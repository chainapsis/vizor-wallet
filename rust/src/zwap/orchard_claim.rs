//! Zwap Orchard claim crypto, vendored from `shielded-zwap/rust/orchard-wasm`.
//!
//! This is the user-side ZEC settlement path for a BTC<>ZEC atomic swap:
//! joint-note trial-decryption, joint unified-address derivation, and the
//! Orchard spend that sweeps the joint note using the reconstructed
//! spend-authorizing key `ask = (k_user + k_b) mod q`.
//!
//! Source upstream uses `wasm-bindgen`; here the three entry points are
//! plain Rust (`Result<String, String>`, JSON in/out) so the wallet's FRB
//! layer can call them directly. Private keys never leave this process.

use serde::{Deserialize, Serialize};
use orchard::{
    builder::{Builder, BundleType},
    bundle::{Authorized, Bundle},
    circuit::ProvingKey,
    keys::{FullViewingKey, PreparedIncomingViewingKey, Scope},
    note::{ExtractedNoteCommitment, Rho, RandomSeed},
    note_encryption::OrchardDomain,
    primitives::redpallas::{self, SpendAuth, VerificationKey},
    tree::{MerkleHashOrchard, MerklePath},
    value::NoteValue,
    Address, Note,
};
use incrementalmerkletree::{Hashable, Position, frontier::CommitmentTree};
use incrementalmerkletree::witness::IncrementalWitness;
use zcash_note_encryption::try_compact_note_decryption;
use rand_core::OsRng;
use ff::{Field, PrimeField};

const NU6_BRANCH_ID: u32 = 0xc8e7_1055;

#[derive(Deserialize)]
struct SpendRequest { ask: String, nk: String, rivk: String, note: NoteData, merkle_path: Vec<String>, dest_raw_address: String, amount: u64, fee: u64, #[serde(default)] branch_id: Option<u32> }

#[derive(Deserialize, Clone)]
struct NoteData { value: u64, rseed: String, rho: String, diversifier: String, pkd: String, position: u32 }

#[derive(Serialize)]
struct SpendResponse { raw_tx_hex: String, txid: String }

#[derive(Deserialize)]
struct DeriveRequest { ak: String, nk: String, rivk: String }

#[derive(Serialize, Deserialize)]
struct DeriveResponse { ivk: String, dk: String, diversifier: String, pkd: String, raw_address: String }

#[derive(Deserialize)]
struct DecryptRequest { ivk: String, diversifier: String, blocks: Vec<CBlock>, nk: Option<String>, ask: Option<String>, rivk: Option<String>, ak: Option<String>, #[serde(default)] frontier_hex: Option<String> }

#[derive(Deserialize)]
struct CBlock { height: u64, txs: Vec<CTx> }

#[derive(Deserialize)]
struct CTx { txid: String, actions: Vec<CAction> }

#[derive(Deserialize)]
struct CAction { nullifier: String, cmx: String, ephemeral_key: String, enc_ciphertext_compact: String }

#[derive(Serialize)]
struct DecryptResponse { notes: Vec<FoundNote>, tree_size: u64 }

#[derive(Serialize, Clone)]
struct FoundNote { value: u64, rseed: String, rho: String, diversifier: String, pkd: String, cmx: String, position: u64, merkle_path: Vec<String>, anchor: String, block_height: u64, txid: String }

fn hex_to_32(h: &str) -> Result<[u8; 32], String> {
    let bytes = hex::decode(h).map_err(|e| format!("bad hex: {}", e))?;
    bytes.try_into().map_err(|v: Vec<u8>| format!("expected 32 bytes, got {}", v.len()))
}

fn ask_from_raw_bytes(bytes: &[u8; 32]) -> Result<redpallas::SigningKey<SpendAuth>, String> {
    let maybe_ask = pasta_curves::pallas::Scalar::from_repr(*bytes);
    if bool::from(maybe_ask.is_none()) {
        return Err("invalid orchard spend authorizing key: scalar parsing failed".into());
    }
    let ask = maybe_ask.unwrap();
    if bool::from(ask.is_zero()) {
        return Err("invalid orchard spend authorizing key: scalar is zero".into());
    }

    let candidate = redpallas::SigningKey::<SpendAuth>::try_from(ask.to_repr())
        .map_err(|_| "invalid orchard spend authorizing key".to_string())?;

    // Match orchard::keys::SpendAuthorizingKey canonicalization: if ak's
    // y-coordinate sign bit is odd, negate ask before using it.
    let ak_bytes = <[u8; 32]>::from(&VerificationKey::<SpendAuth>::from(&candidate));
    if (ak_bytes[31] >> 7) == 1 {
        let neg = -ask;
        redpallas::SigningKey::<SpendAuth>::try_from(neg.to_repr())
            .map_err(|_| "invalid canonical orchard spend authorizing key".to_string())
    } else {
        Ok(candidate)
    }
}

/// Build, prove, sign and serialize the joint-note Orchard sweep.
/// `request_json` is a [`SpendRequest`]; returns a [`SpendResponse`] JSON
/// with `raw_tx_hex` (ready to broadcast) and `txid`.
pub fn orchard_spend(request_json: &str) -> Result<String, String> {
    let req: SpendRequest =
        serde_json::from_str(request_json).map_err(|e| format!("Invalid JSON: {}", e))?;
    handle_spend(req)
}

/// Derive the joint Orchard unified-address material from `ak`/`nk`/`rivk`.
/// `request_json` is a [`DeriveRequest`]; returns a [`DeriveResponse`] JSON.
pub fn orchard_derive(request_json: &str) -> Result<String, String> {
    let req: DeriveRequest =
        serde_json::from_str(request_json).map_err(|e| format!("Invalid JSON: {}", e))?;
    handle_derive(req)
}

/// Trial-decrypt compact blocks against the joint viewing key and return the
/// found note(s) with witness/anchor. `request_json` is a [`DecryptRequest`];
/// returns a [`DecryptResponse`] JSON.
pub fn orchard_trial_decrypt(request_json: &str) -> Result<String, String> {
    let req: DecryptRequest =
        serde_json::from_str(request_json).map_err(|e| format!("Invalid JSON: {}", e))?;
    handle_trial_decrypt(req)
}

fn handle_derive(req: DeriveRequest) -> Result<String, String> {
    let ak_bytes = hex_to_32(&req.ak)?;
    let nk_bytes = hex_to_32(&req.nk)?;
    let rivk_bytes = hex_to_32(&req.rivk)?;
    let mut fvk_bytes = [0u8; 96];
    fvk_bytes[0..32].copy_from_slice(&ak_bytes);
    fvk_bytes[32..64].copy_from_slice(&nk_bytes);
    fvk_bytes[64..96].copy_from_slice(&rivk_bytes);
    let fvk = FullViewingKey::from_bytes(&fvk_bytes).ok_or("Invalid FVK")?;
    let ivk = fvk.to_ivk(Scope::External);
    let ivk_bytes = ivk.to_bytes();
    let addr = fvk.address_at(0u32, Scope::External);
    let raw = addr.to_raw_address_bytes();
    let response = DeriveResponse {
        ivk: hex::encode(&ivk_bytes[32..64]), dk: hex::encode(&ivk_bytes[0..32]),
        diversifier: hex::encode(&raw[0..11]), pkd: hex::encode(&raw[11..43]),
        raw_address: hex::encode(&raw[..]),
    };
    serde_json::to_string(&response).map_err(|e| format!("JSON: {}", e))
}

fn handle_spend(req: SpendRequest) -> Result<String, String> {
    let branch_id = req.branch_id.unwrap_or(NU6_BRANCH_ID);
    let ask_bytes = hex_to_32(&req.ask)?;
    let nk_bytes = hex_to_32(&req.nk)?;
    let rivk_bytes = hex_to_32(&req.rivk)?;
    let signing_key = ask_from_raw_bytes(&ask_bytes)?;
    let ak_bytes = <[u8; 32]>::from(&VerificationKey::<SpendAuth>::from(&signing_key));
    let mut fvk_bytes = [0u8; 96];
    fvk_bytes[0..32].copy_from_slice(&ak_bytes);
    fvk_bytes[32..64].copy_from_slice(&nk_bytes);
    fvk_bytes[64..96].copy_from_slice(&rivk_bytes);
    let fvk = FullViewingKey::from_bytes(&fvk_bytes).ok_or("Invalid FVK")?;

    let rho = Option::from(Rho::from_bytes(&hex_to_32(&req.note.rho)?)).ok_or("Invalid rho")?;
    let rseed = Option::from(RandomSeed::from_bytes(hex_to_32(&req.note.rseed)?, &rho)).ok_or("Invalid rseed")?;
    let div_bytes = hex::decode(&req.note.diversifier).map_err(|e| format!("bad div: {}", e))?;
    let mut div_arr = [0u8; 11];
    if div_bytes.len() != 11 { return Err(format!("diversifier must be 11 bytes")); }
    div_arr.copy_from_slice(&div_bytes);
    let pkd_bytes = hex_to_32(&req.note.pkd)?;
    let mut raw_addr = [0u8; 43];
    raw_addr[0..11].copy_from_slice(&div_arr);
    raw_addr[11..43].copy_from_slice(&pkd_bytes);
    let recipient = Option::from(Address::from_raw_address_bytes(&raw_addr)).ok_or("Invalid recipient")?;
    let note: Note = Option::from(Note::from_parts(recipient, NoteValue::from_raw(req.note.value), rho, rseed)).ok_or("Invalid note")?;

    if req.merkle_path.len() != 32 { return Err(format!("merkle_path must have 32 elements")); }
    let empty = MerkleHashOrchard::empty_leaf();
    let mut auth_path = [empty; 32];
    for (i, h) in req.merkle_path.iter().enumerate() {
        auth_path[i] = Option::from(MerkleHashOrchard::from_bytes(&hex_to_32(h)?)).ok_or(format!("Invalid hash at {}", i))?;
    }
    let merkle_path = MerklePath::from_parts(req.note.position, auth_path);
    let cmx: ExtractedNoteCommitment = note.commitment().into();
    let anchor = merkle_path.root(cmx);

    let dest_bytes = hex::decode(&req.dest_raw_address).map_err(|e| format!("bad dest: {}", e))?;
    if dest_bytes.len() != 43 { return Err(format!("dest must be 43 bytes")); }
    let mut dest_raw = [0u8; 43];
    dest_raw.copy_from_slice(&dest_bytes);
    let dest = Option::from(Address::from_raw_address_bytes(&dest_raw)).ok_or("Invalid dest")?;

    let mut builder = Builder::new(BundleType::DEFAULT, anchor);
    builder.add_spend(fvk.clone(), note, merkle_path).map_err(|e| format!("add_spend: {:?}", e))?;
    let ovk = fvk.to_ovk(Scope::External);
    let empty_memo = [0u8; 512];
    builder.add_output(Some(ovk.clone()), dest, NoteValue::from_raw(req.amount), empty_memo).map_err(|e| format!("add_output: {:?}", e))?;
    let change = req.note.value as i64 - req.amount as i64 - req.fee as i64;
    if change > 0 {
        builder.add_output(Some(ovk), fvk.address_at(0u32, Scope::External), NoteValue::from_raw(change as u64), empty_memo).map_err(|e| format!("change: {:?}", e))?;
    } else if change < 0 { return Err(format!("Insufficient: {} < {} + {}", req.note.value, req.amount, req.fee)); }

    let pk = ProvingKey::build();
    let mut rng = OsRng;
    let (mut pczt_bundle, _) = builder.build_for_pczt(&mut rng).map_err(|e| format!("build: {:?}", e))?;
    pczt_bundle.create_proof(&pk, rng).map_err(|e| format!("proof: {:?}", e))?;
    let effects: Bundle<orchard::bundle::EffectsOnly, i64> = pczt_bundle
        .extract_effects::<i64>()
        .map_err(|e| format!("extract effects: {:?}", e))?
        .ok_or("Empty bundle")?;
    let sighash = compute_zip244_sighash(&effects, branch_id);

    // Sign the real spend action. The Orchard builder shuffles action order,
    // so the real spend may be at any index. Match by rk == ask.randomize(alpha).
    let mut signed = false;
    for action in pczt_bundle.actions_mut().iter_mut() {
        let Some(alpha) = action.spend().alpha() else { continue };
        let rsk = signing_key.randomize(&alpha);
        let rk = VerificationKey::<SpendAuth>::from(&rsk);
        if action.spend().rk() == &rk {
            let signature = rsk.sign(&mut rng, &sighash);
            action.apply_signature(sighash, signature).map_err(|e| format!("sign: {:?}", e))?;
            signed = true;
            break;
        }
    }
    if !signed {
        return Err("sign: no action matched our spend authorizing key".into());
    }
    pczt_bundle.finalize_io(sighash, rng).map_err(|e| format!("finalize_io: {:?}", e))?;
    let unbound: Bundle<orchard::pczt::Unbound, i64> = pczt_bundle
        .extract::<i64>()
        .map_err(|e| format!("extract: {:?}", e))?
        .ok_or("Empty bundle on extract")?;
    let authorized: Bundle<Authorized, i64> = unbound
        .apply_binding_signature(sighash, rng)
        .ok_or("Binding signature did not validate")?;
    let raw_tx = serialize_v5_orchard_only(&authorized, branch_id);
    let mut txid_bytes = sighash;
    txid_bytes.reverse();
    let txid = hex::encode(txid_bytes);
    serde_json::to_string(&SpendResponse { raw_tx_hex: hex::encode(&raw_tx), txid }).map_err(|e| format!("JSON: {}", e))
}

fn read_optional_hash(data: &[u8], pos: &mut usize) -> Result<Option<MerkleHashOrchard>, String> {
    if *pos >= data.len() { return Err("frontier: unexpected EOF reading option tag".into()); }
    match data[*pos] {
        0 => { *pos += 1; Ok(None) }
        1 => {
            *pos += 1;
            if *pos + 32 > data.len() { return Err("frontier: unexpected EOF reading hash".into()); }
            let mut h = [0u8; 32];
            h.copy_from_slice(&data[*pos..*pos + 32]);
            *pos += 32;
            Option::from(MerkleHashOrchard::from_bytes(&h))
                .map(Some)
                .ok_or_else(|| "frontier: non-canonical hash".into())
        }
        t => Err(format!("frontier: invalid option tag {t}"))
    }
}

fn read_compact_size(data: &[u8], pos: &mut usize) -> Result<usize, String> {
    if *pos >= data.len() { return Err("frontier: unexpected EOF reading compact size".into()); }
    let first = data[*pos]; *pos += 1;
    match first {
        0..=252 => Ok(first as usize),
        253 => {
            if *pos + 2 > data.len() { return Err("frontier: unexpected EOF".into()); }
            let v = u16::from_le_bytes([data[*pos], data[*pos + 1]]);
            *pos += 2; Ok(v as usize)
        }
        254 => {
            if *pos + 4 > data.len() { return Err("frontier: unexpected EOF".into()); }
            let v = u32::from_le_bytes(data[*pos..*pos+4].try_into().unwrap());
            *pos += 4; Ok(v as usize)
        }
        _ => Err("frontier: unsupported compact size".into())
    }
}

fn read_hash(data: &[u8], pos: &mut usize) -> Result<MerkleHashOrchard, String> {
    if *pos + 32 > data.len() { return Err("frontier: unexpected EOF reading hash".into()); }
    let mut h = [0u8; 32];
    h.copy_from_slice(&data[*pos..*pos + 32]);
    *pos += 32;
    Option::from(MerkleHashOrchard::from_bytes(&h))
        .ok_or_else(|| "frontier: non-canonical hash".into())
}

fn parse_legacy_commitment_tree(data: &[u8]) -> Result<CommitmentTree<MerkleHashOrchard, 32>, String> {
    let mut pos = 0;
    let left = read_optional_hash(data, &mut pos)?;
    let right = read_optional_hash(data, &mut pos)?;
    let num_parents = read_compact_size(data, &mut pos)?;
    let mut parents = Vec::with_capacity(num_parents);
    for _ in 0..num_parents {
        parents.push(read_optional_hash(data, &mut pos)?);
    }
    CommitmentTree::from_parts(left, right, parents)
        .map_err(|_| "frontier: legacy tree structure invalid".into())
}

fn parse_frontier_v1(data: &[u8]) -> Result<CommitmentTree<MerkleHashOrchard, 32>, String> {
    if data.is_empty() || data[0] == 0 { return Ok(CommitmentTree::empty()); }
    if data[0] != 1 { return Err(format!("frontier v1: bad tag {}", data[0])); }
    let mut pos = 1;
    if pos + 8 > data.len() { return Err("frontier v1: EOF reading position".into()); }
    let position = u64::from_le_bytes(data[pos..pos+8].try_into().unwrap());
    pos += 8;
    let left_hash = read_hash(data, &mut pos)?;
    let right_hash = read_optional_hash(data, &mut pos)?;
    let num_ommers = read_compact_size(data, &mut pos)?;
    let mut ommers: Vec<MerkleHashOrchard> = Vec::with_capacity(num_ommers);
    for _ in 0..num_ommers { ommers.push(read_hash(data, &mut pos)?); }

    let (leaf, all_ommers) = if let Some(right) = right_hash {
        ommers.insert(0, left_hash);
        (right, ommers)
    } else {
        (left_hash, ommers)
    };
    use incrementalmerkletree::frontier::{Frontier, NonEmptyFrontier};
    let nef = NonEmptyFrontier::from_parts(Position::from(position), leaf, all_ommers)
        .map_err(|e| format!("frontier v1: {:?}", e))?;
    let frontier = Frontier::<MerkleHashOrchard, 32>::try_from(nef)
        .map_err(|e| format!("frontier v1 depth: {:?}", e))?;
    Ok(CommitmentTree::from_frontier(&frontier))
}

fn parse_tree_state(data: &[u8]) -> Result<CommitmentTree<MerkleHashOrchard, 32>, String> {
    if data.is_empty() || (data.len() == 1 && data[0] == 0) {
        return Ok(CommitmentTree::empty());
    }
    parse_legacy_commitment_tree(data)
        .or_else(|_| parse_frontier_v1(data))
}

fn handle_trial_decrypt(req: DecryptRequest) -> Result<String, String> {
    // Build FVK from key components:
    //   - ak+nk+rivk: verification-only mode (no spending key)
    //   - ask+nk+rivk: full mode (derive ak from ask)
    let fvk = if let (Some(ak_hex), Some(nk_hex), Some(rivk_hex)) = (&req.ak, &req.nk, &req.rivk) {
        // ak provided directly (verification mode — no spending key needed)
        let mut fvk_bytes = [0u8; 96];
        fvk_bytes[0..32].copy_from_slice(&hex_to_32(ak_hex)?);
        fvk_bytes[32..64].copy_from_slice(&hex_to_32(nk_hex)?);
        fvk_bytes[64..96].copy_from_slice(&hex_to_32(rivk_hex)?);
        FullViewingKey::from_bytes(&fvk_bytes)
    } else if let (Some(ask_hex), Some(nk_hex), Some(rivk_hex)) = (&req.ask, &req.nk, &req.rivk) {
        // ask provided — derive ak from spending key
        let ask = ask_from_raw_bytes(&hex_to_32(ask_hex)?)?;
        let ak_bytes = <[u8; 32]>::from(&VerificationKey::<SpendAuth>::from(&ask));
        let mut fvk_bytes = [0u8; 96];
        fvk_bytes[0..32].copy_from_slice(&ak_bytes);
        fvk_bytes[32..64].copy_from_slice(&hex_to_32(nk_hex)?);
        fvk_bytes[64..96].copy_from_slice(&hex_to_32(rivk_hex)?);
        FullViewingKey::from_bytes(&fvk_bytes)
    } else { None };
    let fvk = fvk.ok_or("Key components required: provide ak+nk+rivk or ask+nk+rivk")?;
    let requested_ivk = hex_to_32(&req.ivk)?;
    let ivk = fvk.to_ivk(Scope::External);
    let ivk_bytes = ivk.to_bytes();
    if ivk_bytes[32..64] != requested_ivk {
        return Err("ivk does not match provided key material".into());
    }
    let div_bytes = hex::decode(&req.diversifier).map_err(|e| format!("bad diversifier: {}", e))?;
    if div_bytes.len() != 11 {
        return Err(format!("diversifier must be 11 bytes, got {}", div_bytes.len()));
    }
    let mut expected_diversifier = [0u8; 11];
    expected_diversifier.copy_from_slice(&div_bytes);
    let prepared_ivk = PreparedIncomingViewingKey::new(&ivk);

    // Seed the commitment tree from the frontier (z_gettreestate at
    // scanFromHeight-1). Without this, positions are local to the scanned
    // range and the anchor won't match any global tree root.
    let mut tree: CommitmentTree<MerkleHashOrchard, 32> = match &req.frontier_hex {
        Some(hex) if !hex.is_empty() => {
            let data = hex::decode(hex).map_err(|e| format!("frontier hex: {e}"))?;
            parse_tree_state(&data)?
        }
        _ => CommitmentTree::empty(),
    };

    let mut witnesses: Vec<(FoundNote, Note, IncrementalWitness<MerkleHashOrchard, 32>)> = Vec::new();
    let mut all_nullifiers: Vec<[u8; 32]> = Vec::new();

    for block in &req.blocks {
        for tx in &block.txs {
            for action in &tx.actions {
                let nf_bytes = hex::decode(&action.nullifier).map_err(|e| format!("bad nf: {}", e))?;
                if nf_bytes.len() == 32 { let mut a = [0u8; 32]; a.copy_from_slice(&nf_bytes); all_nullifiers.push(a); }
                let cmx_bytes = hex_to_32(&action.cmx)?;
                let cmx_hash: MerkleHashOrchard = Option::from(MerkleHashOrchard::from_bytes(&cmx_bytes)).ok_or("Invalid cmx")?;

                tree.append(cmx_hash.clone()).map_err(|_| "commitment tree full")?;
                for (_, _, w) in &mut witnesses {
                    w.append(cmx_hash.clone()).map_err(|_| "witness tree full")?;
                }

                let epk_bytes = hex::decode(&action.ephemeral_key).unwrap_or_default();
                let enc_compact = hex::decode(&action.enc_ciphertext_compact).unwrap_or_default();
                if epk_bytes.len() != 32 || enc_compact.len() < 52 { continue; }
                let mut epk_arr = [0u8; 32]; epk_arr.copy_from_slice(&epk_bytes);
                let mut enc_arr = [0u8; 52]; enc_arr.copy_from_slice(&enc_compact[..52]);
                let mut nf_arr = [0u8; 32]; nf_arr.copy_from_slice(&nf_bytes[..32]);

                let compact_action = orchard::note_encryption::CompactAction::from_parts(
                    Option::from(orchard::note::Nullifier::from_bytes(&nf_arr)).ok_or("Invalid nf")?,
                    Option::from(ExtractedNoteCommitment::from_bytes(&cmx_bytes)).ok_or("Invalid cmx")?,
                    zcash_note_encryption::EphemeralKeyBytes(epk_arr), enc_arr,
                );
                let domain = OrchardDomain::for_compact_action(&compact_action);
                if let Some((note, recipient)) = try_compact_note_decryption(&domain, &prepared_ivk, &compact_action) {
                    let raw_addr = recipient.to_raw_address_bytes();
                    if raw_addr[0..11] != expected_diversifier { continue; }
                    let w = IncrementalWitness::from_tree(tree.clone())
                        .ok_or("empty tree at witness creation")?;
                    let pos = u64::from(w.witnessed_position());
                    witnesses.push((FoundNote {
                        value: note.value().inner(), rseed: hex::encode(note.rseed().as_bytes()),
                        rho: hex::encode(note.rho().to_bytes()), diversifier: hex::encode(&raw_addr[0..11]),
                        pkd: hex::encode(&raw_addr[11..43]), cmx: action.cmx.clone(), position: pos,
                        merkle_path: Vec::new(), anchor: String::new(), block_height: block.height, txid: tx.txid.clone(),
                    }, note, w));
                }
            }
        }
    }

    let tree_size = tree.size() as u64;

    let mut found_notes: Vec<(FoundNote, Note)> = Vec::new();
    for (mut found, note, w) in witnesses {
        if let Some(path) = w.path() {
            found.merkle_path = path.path_elems().iter()
                .map(|h| hex::encode(h.to_bytes()))
                .collect();
            found.position = u64::from(path.position());
            found.anchor = hex::encode(w.root().to_bytes());
        }
        found_notes.push((found, note));
    }

    found_notes.retain(|(_, note)| {
        let nf = note.nullifier(&fvk);
        !all_nullifiers.iter().any(|seen| *seen == nf.to_bytes())
    });

    let notes: Vec<FoundNote> = found_notes.into_iter().map(|(f, _)| f).collect();
    serde_json::to_string(&DecryptResponse { notes, tree_size }).map_err(|e| format!("JSON: {}", e))
}

fn write_compact_size(w: &mut Vec<u8>, n: usize) {
    if n < 253 { w.push(n as u8); }
    else if n <= 0xFFFF { w.push(253); w.extend_from_slice(&(n as u16).to_le_bytes()); }
    else if n <= 0xFFFF_FFFF { w.push(254); w.extend_from_slice(&(n as u32).to_le_bytes()); }
    else { w.push(255); w.extend_from_slice(&(n as u64).to_le_bytes()); }
}

fn compute_zip244_sighash<T: orchard::bundle::Authorization>(bundle: &orchard::Bundle<T, i64>, branch_id: u32) -> [u8; 32] {
    let bb = branch_id.to_le_bytes();
    let header_digest = { let v: u32 = 5; let h: u32 = v|(1<<31); let vg: u32 = 0x26A7_270A;
        let mut s = blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdHeadersHash").to_state();
        s.update(&h.to_le_bytes()); s.update(&vg.to_le_bytes()); s.update(&bb); s.update(&0u32.to_le_bytes()); s.update(&0u32.to_le_bytes());
        let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o };
    let transparent_digest = { let mut o=[0u8;32]; o.copy_from_slice(blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdTranspaHash").to_state().finalize().as_bytes()); o };
    let sapling_digest = { let mut o=[0u8;32]; o.copy_from_slice(blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdSaplingHash").to_state().finalize().as_bytes()); o };
    let orchard_digest = { let actions = bundle.actions();
        let acd = { let mut s = blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdOrcActCHash").to_state();
            for a in actions.iter() { s.update(&a.nullifier().to_bytes()); s.update(&a.cmx().to_bytes()); let e=a.encrypted_note(); s.update(&e.epk_bytes); s.update(&e.enc_ciphertext[0..52]); }
            let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o };
        let amd = { let mut s = blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdOrcActMHash").to_state();
            for a in actions.iter() { s.update(&a.encrypted_note().enc_ciphertext[52..564]); }
            let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o };
        let and = { let mut s = blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdOrcActNHash").to_state();
            for a in actions.iter() { s.update(&a.cv_net().to_bytes()); s.update(&<[u8;32]>::from(a.rk())); let e=a.encrypted_note(); s.update(&e.enc_ciphertext[564..580]); s.update(&e.out_ciphertext); }
            let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o };
        let mut s = blake2b_simd::Params::new().hash_length(32).personal(b"ZTxIdOrchardHash").to_state();
        s.update(&acd); s.update(&amd); s.update(&and); s.update(&[bundle.flags().to_byte()]); s.update(&bundle.value_balance().to_le_bytes()); s.update(&bundle.anchor().to_bytes());
        let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o };
    let mut perso = [0u8;16]; perso[0..12].copy_from_slice(b"ZcashTxHash_"); perso[12..16].copy_from_slice(&bb);
    let mut s = blake2b_simd::Params::new().hash_length(32).personal(&perso).to_state();
    s.update(&header_digest); s.update(&transparent_digest); s.update(&sapling_digest); s.update(&orchard_digest);
    let mut o=[0u8;32]; o.copy_from_slice(s.finalize().as_bytes()); o
}

fn serialize_v5_orchard_only(bundle: &orchard::Bundle<orchard::bundle::Authorized, i64>, branch_id: u32) -> Vec<u8> {
    let mut tx = Vec::with_capacity(4096);
    let v: u32 = 5; tx.extend_from_slice(&(v|(1<<31)).to_le_bytes());
    tx.extend_from_slice(&0x26A7_270Au32.to_le_bytes());
    tx.extend_from_slice(&branch_id.to_le_bytes());
    tx.extend_from_slice(&0u32.to_le_bytes()); tx.extend_from_slice(&0u32.to_le_bytes());
    write_compact_size(&mut tx, 0); write_compact_size(&mut tx, 0);
    write_compact_size(&mut tx, 0); write_compact_size(&mut tx, 0);
    let actions = bundle.actions();
    write_compact_size(&mut tx, actions.len());
    for a in actions.iter() {
        tx.extend_from_slice(&a.cv_net().to_bytes()); tx.extend_from_slice(&a.nullifier().to_bytes());
        tx.extend_from_slice(&<[u8;32]>::from(a.rk())); tx.extend_from_slice(&a.cmx().to_bytes());
        let e = a.encrypted_note(); tx.extend_from_slice(&e.epk_bytes); tx.extend_from_slice(&e.enc_ciphertext); tx.extend_from_slice(&e.out_ciphertext);
    }
    tx.push(bundle.flags().to_byte()); tx.extend_from_slice(&bundle.value_balance().to_le_bytes()); tx.extend_from_slice(&bundle.anchor().to_bytes());
    let proof = bundle.authorization().proof().as_ref(); write_compact_size(&mut tx, proof.len()); tx.extend_from_slice(proof);
    for a in actions.iter() { tx.extend_from_slice(&<[u8;64]>::from(a.authorization())); }
    tx.extend_from_slice(&<[u8;64]>::from(bundle.authorization().binding_signature()));
    tx
}

#[cfg(test)]
mod tests {
    use super::*;
    use orchard::keys::{FullViewingKey as OrchardFvk, SpendAuthorizingKey, SpendingKey};

    fn known_spending_key() -> SpendingKey {
        let mut seed = [0u8; 32];
        loop {
            let candidate = SpendingKey::from_bytes(seed);
            if candidate.is_some().into() {
                break candidate.unwrap();
            }
            seed[0] = seed[0].wrapping_add(1);
        }
    }

    fn ask_raw_scalar_bytes(ask: &SpendAuthorizingKey) -> [u8; 32] {
        let rsk: redpallas::SigningKey<SpendAuth> =
            ask.randomize(&pasta_curves::pallas::Scalar::ZERO);
        rsk.into()
    }

    #[test]
    fn ask_from_raw_bytes_rejects_zero_and_overflow() {
        assert!(ask_from_raw_bytes(&[0u8; 32]).is_err());
        assert!(ask_from_raw_bytes(&[0xffu8; 32]).is_err());
    }

    #[test]
    fn ask_from_raw_bytes_matches_upstream_ak_canonicalization() {
        let sk = known_spending_key();
        let ask = SpendAuthorizingKey::from(&sk);
        let ask_bytes = ask_raw_scalar_bytes(&ask);
        let helper_ask = ask_from_raw_bytes(&ask_bytes).expect("derived ask bytes are valid");

        let upstream_ak = <[u8; 32]>::from(&VerificationKey::<SpendAuth>::from(
            &ask.randomize(&pasta_curves::pallas::Scalar::ZERO),
        ));
        let helper_ak = <[u8; 32]>::from(&VerificationKey::<SpendAuth>::from(&helper_ask));
        assert_eq!(helper_ak, upstream_ak);
    }

    #[test]
    fn derive_round_trips_known_fvk_components() {
        let sk = known_spending_key();
        let fvk: OrchardFvk = (&sk).into();
        let fvk_bytes = fvk.to_bytes();
        let req = DeriveRequest {
            ak: hex::encode(&fvk_bytes[..32]),
            nk: hex::encode(&fvk_bytes[32..64]),
            rivk: hex::encode(&fvk_bytes[64..96]),
        };

        let json = handle_derive(req).expect("derive succeeds");
        let response: DeriveResponse = serde_json::from_str(&json).expect("valid derive JSON");
        let ivk = fvk.to_ivk(Scope::External);
        let ivk_bytes = ivk.to_bytes();
        let address = fvk.address_at(0u32, Scope::External);
        let raw = address.to_raw_address_bytes();

        assert_eq!(response.dk, hex::encode(&ivk_bytes[..32]));
        assert_eq!(response.ivk, hex::encode(&ivk_bytes[32..]));
        assert_eq!(response.diversifier, hex::encode(&raw[..11]));
        assert_eq!(response.pkd, hex::encode(&raw[11..]));
        assert_eq!(response.raw_address, hex::encode(raw));
    }
}
