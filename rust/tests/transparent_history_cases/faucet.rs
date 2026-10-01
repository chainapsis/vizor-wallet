//! Z: zcashd's own wallet as faucet. Coinbase is shielded into several Sapling
//! addresses; every payment is a `z_sendmany` from one of them, as in
//! `scripts/regtest/fund-wallet.sh`. zcashd only spends a note (including a
//! source's change) once it is deep enough for its anchor, so each source
//! rests for `REST_BLOCKS` after a payment and the faucet mines only when
//! every source is resting.

use std::cell::RefCell;

use serde_json::json;

use crate::chain::Chain;

const SOURCES: usize = 12;
const REST_BLOCKS: u64 = 10;

pub struct Faucet {
    /// (zaddr, height from which it may pay again)
    sources: RefCell<Vec<(String, u64)>>,
}

pub fn zec(zatoshis: u64) -> String {
    format!("{}.{:08}", zatoshis / 100_000_000, zatoshis % 100_000_000)
}

impl Faucet {
    pub fn new(chain: &Chain) -> Self {
        let mut sources = Vec::new();
        let mut txids = Vec::new();
        for _ in 0..SOURCES {
            let zaddr = chain
                .rpc_ok("z_getnewaddress", json!(["sapling"]))
                .as_str()
                .unwrap()
                .to_string();
            // 0.001 covers ZIP 317 for 4 transparent inputs + Sapling outputs.
            let result = chain.rpc_ok("z_shieldcoinbase", json!(["*", zaddr, 0.001, 4]));
            txids.push(chain.wait_operation(result["opid"].as_str().unwrap()));
            sources.push((zaddr, 0));
        }
        chain.mine(1);
        for txid in &txids {
            assert!(
                chain.mined_height(txid).is_some(),
                "faucet shielding {txid} was not mined"
            );
        }
        chain.mine(REST_BLOCKS as u32);
        Faucet {
            sources: RefCell::new(sources),
        }
    }

    /// Pays `recipients` in one transaction and returns its txid, unmined.
    pub fn pay(&self, chain: &Chain, recipients: &[(&str, u64)]) -> String {
        let transparent = recipients.iter().any(|(a, _)| a.starts_with('t'));
        let policy = if transparent {
            "AllowRevealedRecipients"
        } else {
            "AllowRevealedAmounts"
        };
        let amounts: Vec<_> = recipients
            .iter()
            .map(|(address, value)| json!({"address": address, "amount": zec(*value)}))
            .collect();
        let source = loop {
            let tip = chain.tip();
            let ready = self
                .sources
                .borrow()
                .iter()
                .position(|(_, ready_at)| *ready_at <= tip);
            match ready {
                Some(index) => break index,
                None => {
                    chain.mine(1);
                }
            }
        };
        let zaddr = self.sources.borrow()[source].0.clone();
        let opid = chain
            .rpc_ok("z_sendmany", json!([zaddr, amounts, 1, null, policy]))
            .as_str()
            .unwrap()
            .to_string();
        let txid = chain.wait_operation(&opid);
        chain.wait_mempool(&txid);
        // Mined at the next block at the earliest; its change needs the rest.
        self.sources.borrow_mut()[source].1 = chain.tip() + 1 + REST_BLOCKS;
        txid
    }
}
