use orchard::note::Rho;
use orchard::{bundle::BundleVersion, Note, ValuePool};
use zcash_protocol::consensus::BranchId;
fn pczt_with_bundle_type(
    version: BundleVersion,
    memo: &[u8],
    value: u64,
    with_ovk: bool,
    bundle_type: orchard::builder::BundleType,
    fixture_seed: u64,
) -> Vec<u8> {
    use orchard::{
        builder::Builder,
        keys::{FullViewingKey, Scope, SpendingKey},
        note::RandomSeed,
        tree::{MerkleHashOrchard, MerklePath},
        value::NoteValue,
    };
    use pczt::roles::{creator::Creator, io_finalizer::IoFinalizer};
    use rand::{rngs::StdRng, SeedableRng};
    let mut rng = StdRng::seed_from_u64(fixture_seed);
    use zcash_primitives::transaction::{builder::PcztParts, TxVersion};
    use zcash_protocol::consensus::{BlockHeight, MainNetwork};

    let fvk = FullViewingKey::from(&SpendingKey::from_bytes([0x43; 32]).unwrap());
    let rho = Rho::from_bytes(&[1; 32]).into_option().unwrap();
    let rseed = (0u8..=255)
        .find_map(|byte| RandomSeed::from_bytes([byte; 32], &rho).into_option())
        .unwrap();
    let note = Note::from_parts(
        fvk.address_at(0u32, Scope::External),
        NoteValue::from_raw(100_000),
        rho,
        rseed,
        version.note_version(),
    )
    .into_option()
    .unwrap();
    let ironwood = version.value_pool() == ValuePool::Ironwood;
    let branch = if version != BundleVersion::orchard_v2() {
        BranchId::Nu6_3
    } else {
        BranchId::Nu6_2
    };
    let path = MerklePath::from_parts(0, [MerkleHashOrchard::from_bytes(&[0; 32]).unwrap(); 32]);
    let mut builder = Builder::new(
        bundle_type,
        version,
        version.default_flags(),
        path.root(note.commitment().into()),
    )
    .unwrap();
    builder.add_spend(fvk.clone(), note, path).unwrap();
    let mut memo_bytes = [0; 512];
    memo_bytes[..memo.len()].copy_from_slice(memo);
    if version.default_flags().cross_address_enabled() {
        builder
            .add_output(
                with_ovk.then(|| fvk.to_ovk(Scope::External)),
                fvk.address_at(1u32, Scope::External),
                NoteValue::from_raw(value),
                memo_bytes,
            )
            .unwrap();
    } else {
        builder
            .add_change_output(
                fvk.clone(),
                with_ovk.then(|| fvk.to_ovk(Scope::External)),
                fvk.address_at(1u32, Scope::External),
                NoteValue::from_raw(value),
                memo_bytes,
            )
            .unwrap();
    }
    let (mut bundle, metadata) = builder.build_for_pczt(&mut rng).unwrap();
    let derivation = orchard::pczt::Zip32Derivation::parse(
        [0x22; 32],
        vec![0x8000_0020, 0x8000_0085, 0x8000_0000],
    )
    .unwrap();
    bundle
        .update_with(|mut bundle| {
            bundle.update_action_with(metadata.spend_action_index(0).unwrap(), |mut action| {
                action.set_spend_zip32_derivation(derivation);
                Ok(())
            })
        })
        .unwrap();
    let (orchard, ironwood) = if ironwood {
        (None, Some(bundle))
    } else {
        (Some(bundle), None)
    };
    let pczt = Creator::build_from_parts(PcztParts {
        params: MainNetwork,
        version: TxVersion::suggested_for_branch(branch),
        consensus_branch_id: branch,
        lock_time: 0,
        expiry_height: BlockHeight::from_u32(0),
        transparent: None,
        sapling: None,
        orchard,
        ironwood,
    })
    .unwrap();
    IoFinalizer::new(pczt)
        .finalize_io()
        .unwrap()
        .serialize()
        .unwrap()
}

fn main() {
    let hashed: Vec<&[u8]> = vec![
        b"first\nsecond",
        b"first\rsecond",
        b"first\r\nsecond",
        b"\n",
        b"first\tsecond",
        "안녕하세요".as_bytes(),
        "gg 🎉".as_bytes(),
        b"caf\xc3\xa9",
        b"\xffabc",
        b"a\xff",
        b"nul\0inside",
    ];
    let ascii: Vec<&[u8]> = vec![
        b"",
        b"single line",
        br"literal\n",
        b"\xf6",
        b" leading and trailing ",
        br#"~!@#$%^&*()_+-=[]{};':\",.<>/?`|"#,
        &[b'x'; 512],
    ];
    let cases = hashed
        .iter()
        .flat_map(|memo| [(*memo, 0), (*memo, 90_000)])
        .chain(ascii.iter().map(|memo| (*memo, 90_000)));
    let mut fixtures = Vec::new();
    for (index, (memo, value)) in cases.enumerate() {
        let pczt = pczt_with_bundle_type(
            BundleVersion::orchard_v2(),
            memo,
            value,
            true,
            orchard::builder::BundleType::UNPADDED,
            index as u64,
        );
        fixtures.push(serde_json::json!({"memo_hex": hex::encode(memo), "value": value, "pczt_hex": hex::encode(pczt)}));
    }
    println!("{}", serde_json::to_string_pretty(&fixtures).unwrap());
}
