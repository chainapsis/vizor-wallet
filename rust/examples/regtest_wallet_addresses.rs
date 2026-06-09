use rust_lib_zcash_wallet::api::wallet;
use serde_json::json;
use zcash_address::{ConversionError, ToAddress, TryFromAddress, ZcashAddress};
use zcash_protocol::consensus::NetworkType;

struct P2pkhBytes([u8; 20]);

impl TryFromAddress for P2pkhBytes {
    type Error = &'static str;

    fn try_from_transparent_p2pkh(
        _net: NetworkType,
        data: [u8; 20],
    ) -> Result<Self, ConversionError<Self::Error>> {
        Ok(P2pkhBytes(data))
    }
}

fn main() {
    let mnemonic = std::env::args()
        .nth(1)
        .expect("usage: cargo run --example regtest_wallet_addresses -- <mnemonic>");

    let tempdir = tempfile::tempdir().expect("tempdir");
    let db_path = tempdir.path().join("zcash_wallet.db");
    let db_path = db_path.to_str().expect("utf-8 db path").to_string();

    let result = wallet::import_wallet(
        mnemonic,
        Some(1),
        "regtest".to_string(),
        db_path.clone(),
        Some("E2E Account".to_string()),
    )
    .expect("import regtest wallet");

    let transparent_address = wallet::get_transparent_address(
        db_path,
        "regtest".to_string(),
        Some(result.account_uuid.clone()),
    )
    .expect("transparent address");
    let tex_address = tex_address_for_transparent(&transparent_address);

    println!(
        "{}",
        json!({
            "accountUuid": result.account_uuid,
            "unifiedAddress": result.unified_address,
            "transparentAddress": transparent_address,
            "texAddress": tex_address,
        })
    );
}

fn tex_address_for_transparent(transparent_address: &str) -> String {
    let P2pkhBytes(data) = transparent_address
        .parse::<ZcashAddress>()
        .expect("parse transparent address")
        .convert_if_network(NetworkType::Regtest)
        .expect("regtest transparent P2PKH address");
    ZcashAddress::from_tex(NetworkType::Regtest, data).to_string()
}
