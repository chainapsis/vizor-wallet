//! Offline public-API integration: native link -> real compact-block scan ->
//! SQLite note selection -> external-card max-spend proposal. No RPC or proofs.

use std::convert::Infallible;

use orchard::{
    note::{ExtractedNoteCommitment, NoteVersion, RandomSeed, Rho},
    note_encryption::OrchardDomain,
    tree::MerkleHashOrchard,
    value::NoteValue,
};
use rust_lib_zcash_wallet::{
    api::{sync as sync_api, wallet as wallet_api},
    wallet::{keys, network::WalletNetwork},
};
use secrecy::{ExposeSecret, SecretVec};
use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::{
    data_api::{
        anchor_retention::AnchorRetentionInterval,
        chain::{self, BlockSource, ChainState},
        WalletWrite,
    },
    proto::compact_formats::{ChainMetadata, CompactBlock, CompactOrchardAction, CompactTx},
};
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_note_encryption::{Domain, NoteEncryption};
use zcash_primitives::block::BlockHash;
use zcash_protocol::consensus::{BlockHeight, NetworkUpgrade, Parameters};

// Public, never-funded A5-entropy vector from the target Zodl SDK encoder test.
const KEY: &str = "zgift15kj6tfd95kj6tfd95kj6tfd95kj6tfd95kj6tfd95kj6tfd95kjsuax7hg";
const NETWORK: WalletNetwork = WalletNetwork::Main;

struct Blocks(Vec<CompactBlock>);

impl BlockSource for Blocks {
    type Error = Infallible;

    fn with_blocks<F, E>(
        &self,
        from: Option<BlockHeight>,
        limit: Option<usize>,
        mut visit: F,
    ) -> Result<(), chain::error::Error<E, Self::Error>>
    where
        F: FnMut(CompactBlock) -> Result<(), chain::error::Error<E, Self::Error>>,
    {
        for block in self
            .0
            .iter()
            .filter(|block| from.is_none_or(|height| block.height >= u64::from(u32::from(height))))
            .take(limit.unwrap_or(usize::MAX))
        {
            visit(block.clone())?;
        }
        Ok(())
    }
}

struct Card {
    _directory: tempfile::TempDir,
    path: String,
    account: String,
    recipient: String,
    usk: UnifiedSpendingKey,
    state: ChainState,
}

impl Card {
    fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let path = directory
            .path()
            .join("card.db")
            .to_str()
            .unwrap()
            .to_owned();
        // An older Orchard card exercises the ordinary scan/selection path,
        // independently of Vizor's Ironwood-only funding observer.
        let height = NETWORK.activation_height(NetworkUpgrade::Nu5).unwrap() + 100;
        let decoded = wallet_api::decode_zodl_gift_link(format!(
            "https://gift.zodl.com/#v=1&key={KEY}&height={height}&amount=0.001"
        ))
        .unwrap();
        assert_eq!(decoded.network, "main");
        assert_eq!(decoded.stated_amount_zatoshi, Some(100_000));
        assert_eq!(
            wallet_api::gift_mnemonic_to_entropy(decoded.mnemonic.clone()).unwrap(),
            vec![0xa5; 32]
        );
        let imported = wallet_api::import_wallet(
            decoded.mnemonic.clone(),
            String::new(),
            Some(u64::from(decoded.birthday_height)),
            decoded.network,
            path.clone(),
            Some("Native card".into()),
        )
        .unwrap();
        let seed = keys::mnemonic_to_seed(&decoded.mnemonic).unwrap();
        let usk =
            UnifiedSpendingKey::from_seed(&NETWORK, seed.expose_secret(), zip32::AccountId::ZERO)
                .unwrap();
        wallet_api::validate_gift_address(
            decoded.mnemonic,
            "main".into(),
            imported.unified_address,
        )
        .unwrap();
        let recipient =
            keys::derive_gift_address(NETWORK, &SecretVec::new(vec![9; 32]), 0).unwrap();
        Self {
            _directory: directory,
            path,
            account: imported.account_uuid,
            recipient,
            usk,
            state: ChainState::empty(height - 1, BlockHash([0; 32])),
        }
    }

    fn scan_block(&mut self, deposits: &[u64]) {
        let height = self.state.block_height() + 1;
        let mut hash = [0; 32];
        hash[..4].copy_from_slice(&u32::from(height).to_le_bytes());
        let mut tree = self.state.final_orchard_tree().clone();
        let receiver = self
            .usk
            .to_unified_full_viewing_key()
            .orchard()
            .unwrap()
            .address_at(0u32, zip32::Scope::External);
        let transactions = deposits
            .iter()
            .enumerate()
            .map(|(index, value)| {
                let mut rho_bytes = hash;
                rho_bytes[4] = (index + 1) as u8;
                let rho = Rho::from_bytes(&rho_bytes).unwrap();
                let note = orchard::Note::from_parts(
                    receiver,
                    NoteValue::from_raw(*value),
                    rho,
                    RandomSeed::from_bytes([3; 32], &rho).unwrap(),
                    NoteVersion::V2,
                )
                .unwrap();
                let cmx = ExtractedNoteCommitment::from(note.commitment());
                assert!(tree.append(MerkleHashOrchard::from_cmx(&cmx)));
                let encryption = NoteEncryption::<OrchardDomain>::new(None, note, [0; 512]);
                CompactTx {
                    index: (index + 1) as u64,
                    txid: rho_bytes.to_vec(),
                    actions: vec![CompactOrchardAction {
                        nullifier: rho_bytes.to_vec(),
                        cmx: cmx.to_bytes().to_vec(),
                        ephemeral_key: OrchardDomain::epk_bytes(encryption.epk()).0.to_vec(),
                        ciphertext: encryption.encrypt_note_plaintext()[..52].to_vec(),
                    }],
                    ..Default::default()
                }
            })
            .collect();
        let block = CompactBlock {
            height: u64::from(u32::from(height)),
            hash: hash.to_vec(),
            prev_hash: self.state.block_hash().0.to_vec(),
            time: 1_700_000_000 + u32::from(height),
            vtx: transactions,
            chain_metadata: Some(ChainMetadata {
                orchard_commitment_tree_size: tree.tree_size() as u32,
                ..Default::default()
            }),
            ..Default::default()
        };
        let mut db = WalletDb::for_path(&self.path, NETWORK, SystemClock, OsRng).unwrap();
        db.set_anchor_retention_interval(AnchorRetentionInterval::custom(
            std::num::NonZeroU32::new(1).unwrap(),
        ));
        db.update_chain_tip(height).unwrap();
        chain::scan_cached_blocks(
            &NETWORK,
            &Blocks(vec![block]),
            &mut db,
            height,
            &self.state,
            1,
        )
        .unwrap();
        self.state = ChainState::new(
            height,
            BlockHash(hash),
            self.state.final_sapling_tree().clone(),
            tree,
            self.state.final_ironwood_tree().clone(),
        );
    }

    fn confirm(&mut self, empty_blocks: usize) {
        for _ in 0..empty_blocks {
            self.scan_block(&[]);
        }
    }

    fn quote(&self) -> Result<sync_api::SendMaxEstimateResult, String> {
        sync_api::estimate_external_gift_claim_max(
            self.path.clone(),
            "main".into(),
            self.account.clone(),
            self.recipient.clone(),
        )
    }

    fn propose(&self, amount: u64) -> Result<sync_api::ProposalResult, String> {
        sync_api::propose_external_gift_claim(
            self.path.clone(),
            "main".into(),
            self.account.clone(),
            "native-claim".into(),
            self.recipient.clone(),
            amount,
        )
    }
}

#[test]
fn native_card_uses_six_confirmations_and_the_actual_multi_deposit_max() {
    let mut card = Card::new();
    card.scan_block(&[1_000_000, 2_000_000, 3_000_000]);
    card.confirm(4);
    let balance =
        sync_api::get_balance(card.path.clone(), "main".into(), card.account.clone()).unwrap();
    assert_eq!(balance.total, 6_000_000);
    assert!(card
        .quote()
        .err()
        .expect("External funding must wait for six confirmations")
        .to_lowercase()
        .contains("insufficient"));
    assert!(card.propose(5_985_000).is_err());
    // The same DB can quote a Vizor card under its shorter policy.
    assert!(sync_api::estimate_payment_link_claim_max(
        card.path.clone(),
        "main".into(),
        card.account.clone(),
        card.recipient.clone(),
    )
    .is_ok());

    card.confirm(1);
    let quote = card.quote().unwrap();
    assert_eq!(quote.fee_zatoshi, 15_000); // Three Orchard inputs, ZIP-317.
    assert_eq!(quote.amount_zatoshi, 6_000_000 - quote.fee_zatoshi);
    assert!(!quote.needs_sapling_params);
    assert_eq!(
        card.propose(100_000)
            .err()
            .expect("The advertised amount must not authorize the claim"),
        "Gift card balance changed. Check the card again."
    );
    let proposal = card.propose(quote.amount_zatoshi).unwrap();
    assert_eq!(proposal.fee_zatoshi, quote.fee_zatoshi);
    assert!(!proposal.needs_sapling_params);
    assert!(
        card.quote().is_err(),
        "The proposal must reserve its inputs"
    );

    // The stored native proposal retains Discard OVK and cannot escape through
    // hardware PCZT creation, which always uses the sender OVK. Rejection is
    // local and releases its real SQLite input locks before any RPC.
    let error = sync_api::create_pczt_from_proposal(
        card.path.clone(),
        "http://127.0.0.1:1".into(),
        "main".into(),
        proposal.proposal_id,
        "native-claim".into(),
    )
    .unwrap_err();
    assert_eq!(
        error,
        "Gift Card claim proposals cannot be signed as a PCZT"
    );
    assert_eq!(card.quote().unwrap().amount_zatoshi, quote.amount_zatoshi);
}

#[test]
fn a_new_mature_deposit_invalidates_the_reviewed_amount_before_locking_inputs() {
    let mut card = Card::new();
    card.scan_block(&[1_000_000, 2_000_000, 3_000_000]);
    card.confirm(5);
    let reviewed = card.quote().unwrap();
    card.scan_block(&[4_000_000]);
    card.confirm(4);
    assert_eq!(
        card.quote().unwrap().amount_zatoshi,
        reviewed.amount_zatoshi
    );
    card.confirm(1);
    let current = card.quote().unwrap();
    assert_eq!(current.fee_zatoshi, 20_000);
    assert_eq!(current.amount_zatoshi, 10_000_000 - current.fee_zatoshi);
    assert_eq!(
        card.propose(reviewed.amount_zatoshi)
            .err()
            .expect("The stale review must not authorize the claim"),
        "Gift card balance changed. Check the card again."
    );
    let proposal = card.propose(current.amount_zatoshi).unwrap();
    assert_eq!(proposal.fee_zatoshi, current.fee_zatoshi);
    assert!(
        card.quote().is_err(),
        "The proposal must reserve its inputs"
    );
    sync_api::discard_proposal(proposal.proposal_id, "native-claim".into()).unwrap();
    assert_eq!(card.quote().unwrap().amount_zatoshi, current.amount_zatoshi);
}
