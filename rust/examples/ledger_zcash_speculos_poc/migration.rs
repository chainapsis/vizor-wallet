//! A synthetic, fully scanned Orchard note for the Immediate migration canary.
//! No chain or real funds are used; the migration plan and PCZT stay real.

use std::convert::Infallible;

use orchard::{
    note::{ExtractedNoteCommitment, NoteVersion, Nullifier, RandomSeed, Rho},
    note_encryption::{OrchardDomain, OrchardNoteEncryption},
    value::NoteValue,
    Note,
};
use rust_lib_zcash_wallet::{
    api::sync::{get_balance, get_orchard_migration_immediate_plan},
    wallet::{
        keys::{import_hardware_account, HardwareSignerKind},
        network::WalletNetwork,
    },
};
use voting_crypto_deps::rand::{rngs::OsRng, Rng};
use zcash_client_backend::{
    data_api::{
        chain::{error::Error, scan_cached_blocks, BlockSource, ChainState},
        WalletWrite,
    },
    proto::compact_formats::{ChainMetadata, CompactBlock, CompactOrchardAction, CompactTx},
};
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_keys::keys::UnifiedFullViewingKey;
use zcash_note_encryption::Domain;
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};
use zip32::Scope;

const NOTE_VALUE: u64 = 1_000_000;
/// The note arrives this many blocks before NU6.3, as a pre-Ironwood Orchard
/// note; the wallet then scans as far past it, where Immediate can migrate it.
const BLOCKS_AROUND_NU6_3: u32 = 20;

pub(super) fn prepare_wallet(
    path: &str,
    ufvk: &str,
    fingerprint: &[u8],
    account_index: u32,
) -> Result<String, String> {
    let network = WalletNetwork::Main;
    let nu6_3 = network
        .activation_height(NetworkUpgrade::Nu6_3)
        .ok_or("Mainnet Ironwood activation is required")?;
    let height = nu6_3 - BLOCKS_AROUND_NU6_3;
    let (account_uuid, _) = import_hardware_account(
        path,
        network,
        "Speculos Ledger Orchard",
        ufvk,
        fingerprint,
        account_index,
        Some(u64::from(u32::from(height))),
        HardwareSignerKind::parse("ledger")?,
    )?;

    let ufvk = UnifiedFullViewingKey::decode(&network, ufvk).map_err(|e| e.to_string())?;
    // The domain reconstructs rho from this revealed nullifier while scanning.
    let nf = Nullifier::from_bytes(&[2; 32]).unwrap();
    let rho = Rho::from_bytes(&nf.to_bytes()).unwrap();
    let rseed = loop {
        let mut bytes = [0; 32];
        OsRng.fill_bytes(&mut bytes);
        if let Some(seed) = Option::from(RandomSeed::from_bytes(bytes, &rho)) {
            break seed;
        }
    };
    let recipient = ufvk
        .orchard()
        .ok_or("Missing Orchard FVK")?
        .address_at(0u32, Scope::External);
    let note = Note::from_parts(
        recipient,
        NoteValue::from_raw(NOTE_VALUE),
        rho,
        rseed,
        NoteVersion::V2,
    )
    .unwrap();
    let encryptor = OrchardNoteEncryption::new(None, note, [0; 512]);
    let action = CompactOrchardAction {
        nullifier: nf.to_bytes().to_vec(),
        cmx: ExtractedNoteCommitment::from(note.commitment())
            .to_bytes()
            .to_vec(),
        ephemeral_key: OrchardDomain::epk_bytes(encryptor.epk()).0.to_vec(),
        ciphertext: encryptor.encrypt_note_plaintext()[..52].to_vec(),
    };
    let count = 2 * BLOCKS_AROUND_NU6_3;
    let blocks = (0..count)
        .map(|index| CompactBlock {
            height: u64::from(u32::from(height) + index),
            hash: block_hash(index + 1),
            prev_hash: block_hash(index),
            time: 1_800_000_000 + index * 75,
            vtx: if index == 0 {
                vec![CompactTx {
                    index: 1,
                    txid: vec![43; 32],
                    actions: vec![action.clone()],
                    ..Default::default()
                }]
            } else {
                vec![]
            },
            chain_metadata: Some(ChainMetadata {
                sapling_commitment_tree_size: 0,
                orchard_commitment_tree_size: 1,
                ironwood_commitment_tree_size: 0,
            }),
            ..Default::default()
        })
        .collect::<Vec<_>>();
    let mut db =
        WalletDb::for_path(path, network, SystemClock, OsRng).map_err(|e| e.to_string())?;
    db.update_chain_tip(height + count - 1)
        .map_err(|e| e.to_string())?;
    scan_cached_blocks(
        &network,
        &FixtureBlocks(blocks),
        &mut db,
        height,
        &ChainState::empty(height - 1, BlockHash([0; 32])),
        count as usize,
    )
    .map_err(|e| format!("Scan Orchard migration fixture: {e}"))?;
    drop(db);

    let balance = get_balance(path.into(), "main".into(), account_uuid.clone())?;
    if balance.spendable != NOTE_VALUE {
        return Err(format!(
            "Orchard migration fixture has unexpected spendable balance: {}",
            balance.spendable
        ));
    }
    get_orchard_migration_immediate_plan(path.into(), "main".into(), account_uuid.clone())?
        .ok_or("Orchard migration fixture has no Immediate migration plan")?;
    println!("orchard_migration_fixture={NOTE_VALUE} spendable Orchard zatoshi");
    Ok(account_uuid)
}

/// Block hashes chain from the zero hash the account birthday records.
fn block_hash(index: u32) -> Vec<u8> {
    let mut hash = vec![0; 32];
    hash[..4].copy_from_slice(&index.to_le_bytes());
    hash
}

struct FixtureBlocks(Vec<CompactBlock>);

impl BlockSource for FixtureBlocks {
    type Error = Infallible;

    fn with_blocks<F, WalletErrT>(
        &self,
        from_height: Option<BlockHeight>,
        limit: Option<usize>,
        mut with_block: F,
    ) -> Result<(), Error<WalletErrT, Self::Error>>
    where
        F: FnMut(CompactBlock) -> Result<(), Error<WalletErrT, Self::Error>>,
    {
        for block in self
            .0
            .iter()
            .filter(|block| {
                from_height.is_none_or(|height| block.height >= u64::from(u32::from(height)))
            })
            .take(limit.unwrap_or(usize::MAX))
        {
            with_block(block.clone())?;
        }
        Ok(())
    }
}
