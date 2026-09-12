const MAX_PAYMENT_URI_BYTES: usize = 16 * 1024;

/// Parses a cross-chain payment URI into the parser's versioned JSON contract.
///
/// This only validates protocol syntax. The caller must resolve supported
/// networks and assets, preserve required payment conditions, and obtain user
/// approval before creating a payment. No endpoint in the request is fetched.
pub fn parse_cross_chain_payment_uri(uri: String) -> Result<String, String> {
    if uri.len() > MAX_PAYMENT_URI_BYTES {
        return Err("Payment request is too long.".to_owned());
    }

    let uri = lowercase_uppercase_bech32_address(&uri);
    let parsed = payment_uri::PaymentRequest::parse(&uri).map_err(sanitized_payment_uri_error)?;
    if let payment_uri::PaymentRequest::Ethereum(request) = &parsed {
        let raw = request.as_raw();
        // The upstream ERC-20 JSON maps an overflowing chain ID to null. That
        // must not turn an invalid explicit network into a user-selectable one.
        if raw
            .chain_id
            .as_ref()
            .is_some_and(|chain_id| chain_id.as_u64().is_err())
        {
            return Err("Invalid Ethereum payment request chain ID.".to_owned());
        }

        // ERC-20 JSON only carries the two transfer ABI parameters. A native
        // value or gas parameter would be lost, changing the requested call.
        // Keep those requests blocked until their full conditions are handled.
        if request.as_erc20().is_some()
            && raw
                .parameters
                .iter()
                .flat_map(|parameters| parameters.iter())
                .count()
                != 2
        {
            return Err("Payment request requires unsupported transaction parameters.".to_owned());
        }
    }

    // Upstream currently exposes JSON serialization through parsing only. Use
    // that versioned contract after validating conditions it does not retain.
    payment_uri::parse_to_json(&uri).map_err(sanitized_payment_uri_error)
}

/// BIP-173 allows an all-uppercase bech32 address so QR encoders can use the
/// smaller alphanumeric mode, and merchant QR codes use that form. The parser
/// compares the HRP case-sensitively, so lowercase such an address first.
/// Base58 addresses are mixed case and never match; parameters are untouched.
fn lowercase_uppercase_bech32_address(uri: &str) -> String {
    const BECH32_PREFIXES: [&str; 6] = ["bc1", "tb1", "bcrt1", "ltc1", "tltc1", "rltc1"];
    let Some((scheme, rest)) = uri.split_once(':') else {
        return uri.to_owned();
    };
    if !(scheme.eq_ignore_ascii_case("bitcoin") || scheme.eq_ignore_ascii_case("litecoin")) {
        return uri.to_owned();
    }
    let address_len = rest.find('?').unwrap_or(rest.len());
    let (address, query) = rest.split_at(address_len);
    let is_uppercase_bech32 = address.is_ascii()
        && !address.bytes().any(|byte| byte.is_ascii_lowercase())
        && BECH32_PREFIXES.iter().any(|prefix| {
            address.len() > prefix.len() && address[..prefix.len()].eq_ignore_ascii_case(prefix)
        });
    if !is_uppercase_bech32 {
        return uri.to_owned();
    }
    format!("{scheme}:{}{query}", address.to_ascii_lowercase())
}

fn sanitized_payment_uri_error(error: payment_uri::Error) -> String {
    // Upstream Display errors can contain the recipient, amount, or URI.
    // Never send those untrusted values into Dart exception logging.
    let message = match error {
        payment_uri::Error::MissingScheme => "Payment request is missing its URI scheme.",
        payment_uri::Error::UnsupportedScheme(_) => "Unsupported payment request protocol.",
        payment_uri::Error::MissingRecipient => "Payment request is missing its recipient.",
        payment_uri::Error::InvalidAddress(_) => "Invalid payment request address.",
        payment_uri::Error::InvalidAmount(_) => "Invalid payment request amount.",
        payment_uri::Error::DuplicateParameter(_) => "Payment request has duplicate parameters.",
        payment_uri::Error::UnsupportedRequiredParameter(_) => {
            "Payment request requires an unsupported parameter."
        }
        payment_uri::Error::InvalidEncoding(_) => "Invalid payment request encoding.",
        payment_uri::Error::InvalidTransactionLink(_) => "Invalid payment transaction link.",
        payment_uri::Error::Ethereum(_) => "Invalid Ethereum payment request.",
        _ => "Invalid payment request.",
    };
    message.to_owned()
}

#[cfg(test)]
mod tests {
    use super::{parse_cross_chain_payment_uri, MAX_PAYMENT_URI_BYTES};
    use serde_json::{json, Value};

    const BITCOIN: &str = "1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo";
    const LITECOIN: &str = "LT2KVaAy1ppRuxRgrS5RNU3vBsy7RibPeA";
    const EVM_RECIPIENT: &str = "0x1111111111111111111111111111111111111111";
    const USDC_BASE: &str = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
    const SOLANA: &str = "mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN";
    const USDC_SOLANA: &str = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

    fn parse(uri: String) -> Value {
        serde_json::from_str(&parse_cross_chain_payment_uri(uri).unwrap()).unwrap()
    }

    #[test]
    fn bitcoin_preserves_exact_amount_and_request_description() {
        assert_eq!(
            parse(format!(
                "bitcoin:{BITCOIN}?amount=0.00000001&label=Coffee%20shop&message=Order%20123"
            )),
            json!({
                "version": 1,
                "type": "bitcoin",
                "address": BITCOIN,
                "network": "mainnet",
                "amount": "0.00000001",
                "label": "Coffee shop",
                "message": "Order 123",
            })
        );
    }

    #[test]
    fn uppercase_bech32_qr_form_parses_like_lowercase() {
        let lowercase = parse(
            "bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4?amount=0.001&label=Coffee%20Shop"
                .to_owned(),
        );
        let uppercase = parse(
            "BITCOIN:BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4?amount=0.001&label=Coffee%20Shop"
                .to_owned(),
        );
        assert_eq!(uppercase, lowercase);
        assert_eq!(uppercase["label"], "Coffee Shop");
        // Base58 and mixed-case bech32 are left to the parser untouched.
        assert!(parse_cross_chain_payment_uri(format!("BITCOIN:{BITCOIN}")).is_ok());
        assert!(parse_cross_chain_payment_uri(
            "bitcoin:bc1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4".to_owned()
        )
        .is_err());
    }

    #[test]
    fn litecoin_keeps_protocol_and_eight_decimal_precision() {
        let request = parse(format!("litecoin:{LITECOIN}?amount=1.23456789"));
        assert_eq!(request["type"], "litecoin");
        assert_eq!(request["network"], "mainnet");
        assert_eq!(request["amount"], "1.23456789");
    }

    #[test]
    fn ethereum_native_preserves_atomic_values_above_float_precision() {
        let request = parse(format!(
            "ethereum:{EVM_RECIPIENT}@8453?value=9007199254740993"
        ));
        assert_eq!(request["type"], "ethereum_native");
        assert_eq!(request["chain_id"], "8453");
        assert_eq!(request["recipient_address"], EVM_RECIPIENT);
        assert_eq!(request["value_hex"], "0x20000000000001");
    }

    #[test]
    fn ethereum_erc20_keeps_contract_separate_from_payment_recipient() {
        let request = parse(format!(
            "ethereum:{USDC_BASE}@8453/transfer?address={EVM_RECIPIENT}&uint256=2500000"
        ));
        assert_eq!(request["type"], "ethereum_erc20");
        assert_eq!(request["chain_id"], "8453");
        assert_eq!(request["token_contract_address"], USDC_BASE);
        assert_eq!(request["recipient_address"], EVM_RECIPIENT);
        assert_eq!(request["value_hex"], "0x2625a0");
    }

    #[test]
    fn ethereum_missing_chain_and_amount_stay_unresolved() {
        let request = parse(format!("ethereum:{EVM_RECIPIENT}"));
        assert!(request["chain_id"].is_null());
        assert!(request["value_hex"].is_null());
    }

    #[test]
    fn ethereum_explicit_overflowing_chain_id_is_not_treated_as_missing() {
        for payload in [
            format!("{EVM_RECIPIENT}@18446744073709551616?value=1"),
            format!(
                "{USDC_BASE}@18446744073709551616/transfer?address={EVM_RECIPIENT}&uint256=2500000"
            ),
        ] {
            assert_eq!(
                parse_cross_chain_payment_uri(format!("ethereum:{payload}")),
                Err("Invalid Ethereum payment request chain ID.".to_owned())
            );
        }
    }

    #[test]
    fn ethereum_erc20_transaction_parameters_cannot_be_silently_discarded() {
        for parameter in [
            "value=0",
            "value=1000000000000000000",
            "gas=21000",
            "gasLimit=21000",
            "gasPrice=1",
        ] {
            assert_eq!(
                parse_cross_chain_payment_uri(format!(
                    "ethereum:{USDC_BASE}@8453/transfer?address={EVM_RECIPIENT}&uint256=2500000&{parameter}"
                )),
                Err("Payment request requires unsupported transaction parameters.".to_owned())
            );
        }
    }

    #[test]
    fn solana_native_preserves_lamport_precision() {
        let request = parse(format!("solana:{SOLANA}?amount=0.000000001"));
        assert_eq!(request["type"], "solana_transfer");
        assert_eq!(request["amount"], "0.000000001");
        assert!(request["spl_token"].is_null());
    }

    #[test]
    fn solana_token_precision_and_transaction_conditions_are_not_discarded() {
        let request = parse(format!(
            "solana:{SOLANA}?amount=0.12345678901234567890&spl-token={USDC_SOLANA}&reference={SOLANA}&memo=order%20123&label=Coffee&message=Thank%20you"
        ));
        assert_eq!(request["amount"], "0.12345678901234567890");
        assert_eq!(request["spl_token"], USDC_SOLANA);
        assert_eq!(request["references"], json!([SOLANA]));
        assert_eq!(request["memo"], "order 123");
        assert_eq!(request["label"], "Coffee");
        assert_eq!(request["message"], "Thank you");
    }

    #[test]
    fn interactive_solana_requests_are_classified_without_fetching() {
        assert_eq!(
            parse("solana:https://example.com/payment-request".to_owned()),
            json!({
                "version": 1,
                "type": "solana_transaction",
                "link": "https://example.com/payment-request",
            })
        );
    }

    #[test]
    fn arbitrary_evm_methods_are_not_classified_as_transfers() {
        let request = parse(format!(
            "ethereum:{USDC_BASE}@8453/approve?address={EVM_RECIPIENT}&uint256=2500000"
        ));
        assert_eq!(request["type"], "ethereum_unrecognised");
    }

    #[test]
    fn malformed_requests_fail_without_echoing_private_request_data() {
        for uri in [
            "bitcoin:private-recipient".to_owned(),
            format!("bitcoin:{BITCOIN}?amount=0.000000001"),
            format!("bitcoin:{BITCOIN}?amount=1&amount=2"),
            format!("bitcoin:{BITCOIN}?req-private-extension=1"),
            format!("bitcoin:{BITCOIN}?label=private%ZZ"),
            "ethereum:private-recipient?value=1".to_owned(),
            format!("solana:{SOLANA}?amount=0.0000000001"),
            format!("solana:{SOLANA}?reference=private-reference"),
        ] {
            let error = parse_cross_chain_payment_uri(uri.clone()).unwrap_err();
            assert!(!error.contains(&uri));
            assert!(!error.contains("private"));
            assert!(!error.contains(BITCOIN));
            assert!(!error.contains(SOLANA));
        }
    }

    #[test]
    fn oversized_uri_is_rejected_before_protocol_parsing() {
        assert_eq!(
            parse_cross_chain_payment_uri("x".repeat(MAX_PAYMENT_URI_BYTES + 1)),
            Err("Payment request is too long.".to_owned())
        );
    }
}
