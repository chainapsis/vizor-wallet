//! Synthetic Ironwood funds shared by hardware signer fixtures.

use std::convert::Infallible;

use orchard::{
    note::{ExtractedNoteCommitment, NoteVersion, Nullifier, RandomSeed, Rho},
    note_encryption::{IronwoodDomain, IronwoodNoteEncryption},
    value::NoteValue,
    Note,
};
use rust_lib_zcash_wallet::{api::sync::get_balance, wallet::network::WalletNetwork};
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

pub fn funding_height() -> Result<BlockHeight, String> {
    let network = WalletNetwork::Main;
    let height = network
        .activation_height(NetworkUpgrade::Nu6_3)
        .ok_or("Mainnet Ironwood activation is required")?
        + 100;
    Ok(height)
}

pub fn fund_wallet(
    path: &str,
    ufvk: &UnifiedFullViewingKey,
    account_uuid: &str,
    height: BlockHeight,
) -> Result<(), String> {
    let network = WalletNetwork::Main;
    let prior = ChainState::empty(height - 1, BlockHash([0; 32]));
    let mut db =
        WalletDb::for_path(path, network, SystemClock, OsRng).map_err(|e| e.to_string())?;
    // The domain reconstructs rho from this revealed nullifier while scanning.
    let nf = Nullifier::from_bytes(&[1; 32]).unwrap();
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
        NoteValue::from_raw(5_000_000),
        rho,
        rseed,
        NoteVersion::V3,
    )
    .unwrap();
    let encryptor = IronwoodNoteEncryption::new(None, note, [0; 512]);
    let action = CompactOrchardAction {
        nullifier: nf.to_bytes().to_vec(),
        cmx: ExtractedNoteCommitment::from(note.commitment())
            .to_bytes()
            .to_vec(),
        ephemeral_key: IronwoodDomain::epk_bytes(encryptor.epk()).0.to_vec(),
        ciphertext: encryptor.encrypt_note_plaintext()[..52].to_vec(),
    };
    let mut blocks = Vec::new();
    for index in 0..12u8 {
        blocks.push(CompactBlock {
            height: u64::from(u32::from(height)) + u64::from(index),
            hash: vec![index + 1; 32],
            prev_hash: vec![index; 32],
            time: 1_800_000_000 + u32::from(index) * 75,
            vtx: if index == 0 {
                vec![CompactTx {
                    index: 1,
                    txid: vec![42; 32],
                    ironwood_actions: vec![action.clone()],
                    ..Default::default()
                }]
            } else {
                vec![]
            },
            chain_metadata: Some(ChainMetadata {
                sapling_commitment_tree_size: 0,
                orchard_commitment_tree_size: 0,
                ironwood_commitment_tree_size: 1,
            }),
            ..Default::default()
        });
    }
    db.update_chain_tip(height + 11)
        .map_err(|e| e.to_string())?;
    scan_cached_blocks(
        &network,
        &FixtureBlocks(blocks),
        &mut db,
        height,
        &prior,
        12,
    )
    .map_err(|e| format!("Scan Ironwood fixture: {e}"))?;
    drop(db);
    let balance = get_balance(path.into(), "main".into(), account_uuid.into())?;
    if balance.spendable != 5_000_000 {
        return Err(format!(
            "Ironwood fixture has unexpected spendable balance: {}",
            balance.spendable
        ));
    }
    Ok(())
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
