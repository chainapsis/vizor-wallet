//! Decoder for Zodl's native gift links. No network or wallet database access.
//! Wire compatibility is pinned in docs/zodl-gift-links.md.

use bech32::{primitives::decode::CheckedHrpstring, Bech32m};
use zcash_protocol::consensus::{NetworkUpgrade, Parameters};
use zeroize::Zeroizing;

use super::{keys, network::WalletNetwork};

pub(crate) struct DecodedGift {
    pub network: String,
    pub mnemonic: String,
    pub birthday_height: u32,
    pub stated_amount_zatoshi: Option<u64>,
    pub description: Option<String>,
}

const INVALID: &str = "Gift card link is invalid or unsupported.";

pub(crate) fn decode(raw: &str) -> Result<DecodedGift, String> {
    let invalid = || INVALID.to_owned();
    let raw = raw.trim();
    if raw.len() > 16 * 1024 {
        return Err(invalid());
    }
    let (base, fragment) = raw.split_once('#').ok_or_else(invalid)?;
    // Keep the bearer key out of the URL parser's owned allocations.
    let uri = url::Url::parse(base).map_err(|_| invalid())?;
    if uri.scheme() != "https" || uri.host_str() != Some("gift.zodl.com")
        || uri.path() != "/" || uri.port().is_some() || !uri.username().is_empty()
        || uri.password().is_some() || uri.query().is_some()
        // Url normalizes an explicit default port. Reject it before normalization too.
        || base.split('/').nth(2).unwrap_or("").contains(':')
    {
        return Err(invalid());
    }
    let mut values: [Option<&str>; 5] = [None; 5];
    let mut counts = [0u32; 5];
    for pair in fragment.split('&').filter(|p| !p.is_empty()) {
        let (name, value) = pair.split_once('=').unwrap_or((pair, ""));
        let index = match name {
            "v" => 0,
            "key" => 1,
            "height" => 2,
            "amount" => 3,
            "desc" => 4,
            _ => continue,
        };
        counts[index] += 1;
        values[index] = Some(value);
    }
    if counts[..3] != [1, 1, 1] || values[0] != Some("1") {
        return Err(invalid());
    }
    let key =
        CheckedHrpstring::new::<Bech32m>(values[1].ok_or_else(invalid)?).map_err(|_| invalid())?;
    key.validate_segwit_padding().map_err(|_| invalid())?;
    let (network_name, network) = match key.hrp().to_lowercase().as_str() {
        "zgift" => ("main", WalletNetwork::Main),
        "zgifttest" => ("test", WalletNetwork::Test),
        "zgiftregtest" => ("regtest", WalletNetwork::Regtest),
        _ => return Err(invalid()),
    };
    let entropy = Zeroizing::new(key.byte_iter().collect::<Vec<_>>());
    if entropy.len() != 32 {
        return Err(invalid());
    }
    let height_text = values[2].ok_or_else(invalid)?;
    if height_text.starts_with('0')
        || height_text.is_empty()
        || !height_text.bytes().all(|b| b.is_ascii_digit())
    {
        return Err(invalid());
    }
    let birthday_height = height_text.parse::<u32>().map_err(|_| invalid())?;
    let minimum = if network_name == "regtest" {
        1
    } else {
        u32::from(
            network
                .activation_height(NetworkUpgrade::Nu5)
                .ok_or_else(invalid)?,
        )
    };
    if birthday_height < minimum {
        return Err(invalid());
    }
    let stated_amount_zatoshi = if counts[3] == 1 {
        values[3].and_then(parse_amount)
    } else {
        None
    };
    let description = if counts[4] == 1 {
        values[4].and_then(parse_description)
    } else {
        None
    };
    Ok(DecodedGift {
        network: network_name.into(),
        mnemonic: keys::mnemonic_from_entropy(entropy.to_vec()).map_err(|_| invalid())?,
        birthday_height,
        stated_amount_zatoshi,
        description,
    })
}

fn parse_amount(text: &str) -> Option<u64> {
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    if whole.is_empty()
        || !whole.bytes().all(|b| b.is_ascii_digit())
        || !fraction.bytes().all(|b| b.is_ascii_digit())
        || fraction.len() > 8
        || (text.contains('.') && fraction.is_empty())
    {
        return None;
    }
    let whole = whole.parse::<u64>().ok()?;
    let fraction = format!("{fraction:0<8}").parse::<u64>().ok()?;
    let amount = whole.checked_mul(100_000_000)?.checked_add(fraction)?;
    (amount > 0 && amount <= 21_000_000 * 100_000_000).then_some(amount)
}

fn parse_description(text: &str) -> Option<String> {
    // Fragment values are percent encoded, not HTML form encoded: '+' stays '+'.
    let mut bytes = Vec::with_capacity(text.len());
    let mut input = text.bytes();
    while let Some(byte) = input.next() {
        bytes.push(if byte == b'%' {
            let high = (input.next()? as char).to_digit(16)?;
            let low = (input.next()? as char).to_digit(16)?;
            (high * 16 + low) as u8
        } else {
            byte
        });
    }
    if bytes.len() > 512 {
        return None;
    }
    let text = String::from_utf8(bytes).ok()?;
    let clean: String = text
        .chars()
        .filter_map(|c| {
            if matches!(
                c,
                '\t' | '\n' | '\r' | '\u{b}' | '\u{c}' | '\u{85}' | '\u{2028}' | '\u{2029}'
            ) {
                Some(' ')
            } else if c.is_control()
                || matches!(c, '\u{61c}' | '\u{200b}' | '\u{200e}' | '\u{200f}'
            | '\u{202a}'..='\u{202e}' | '\u{2060}'..='\u{2064}' | '\u{2066}'..='\u{206f}'
            | '\u{feff}' | '\u{fff9}'..='\u{fffb}')
            {
                None
            } else {
                Some(c)
            }
        })
        .collect();
    (!clean.trim().is_empty()).then_some(clean)
}

#[cfg(test)]
mod tests {
    use super::*;
    use bech32::Hrp;

    // Public, never-funded interoperability vector from the target SDK's encoder test.
    const KEY: &str = "zgift15kj6tfd95kj6tfd95kj6tfd95kj6tfd95kj6tfd95kj6tfd95kjsuax7hg";
    fn link(extra: &str) -> String {
        format!("https://gift.zodl.com/#v=1&key={KEY}&height=3500000{extra}")
    }
    #[test]
    fn decodes_independently_encoded_zodl_vector() {
        let gift = decode(&link(
            "&amount=1.5&desc=Hi%20from%20Zcash%21%20%F0%9F%9B%A1%EF%B8%8F%20100%25%20~_.-%2B%2F",
        ))
        .unwrap();
        assert_eq!(gift.network, "main");
        assert_eq!(gift.birthday_height, 3_500_000);
        assert_eq!(gift.stated_amount_zatoshi, Some(150_000_000));
        assert_eq!(
            gift.description.as_deref(),
            Some("Hi from Zcash! 🛡️ 100% ~_.-+/")
        );
        let expected = keys::mnemonic_from_entropy(vec![0xa5; 32]).unwrap();
        assert_eq!(gift.mnemonic, expected);
    }
    #[test]
    fn informational_fields_do_not_make_funded_cards_unreadable() {
        for extra in [
            "",
            "&amount=bad&desc=%FF",
            "&amount=1&amount=2&desc=a&desc=b",
            "&amount=21000001",
            "&amount=0",
            "&amount=1.000000001",
        ] {
            let gift = decode(&link(extra)).unwrap();
            assert_eq!(gift.stated_amount_zatoshi, None);
            assert_eq!(gift.description, None);
        }
        assert_eq!(
            decode(&link("&desc=a+b%0A%E2%80%AEc"))
                .unwrap()
                .description
                .as_deref(),
            Some("a+b c")
        );
        assert_eq!(
            decode(&link(&format!("&desc={}", "a".repeat(513))))
                .unwrap()
                .description,
            None
        );
    }
    #[test]
    fn rejects_bad_required_fields_without_echoing_secrets() {
        for raw in [
            link("&v=1"),
            link("&height=3500000"),
            link("&key=x"),
            link("").replace("height=3500000", "height=03400000"),
            link("").replace("height=3500000", "height=1"),
            link("").replace("height=3500000", "height=4294967296"),
            link("").replace("v=1", "v=2"),
            link("").replace("https:", "http:"),
            link("").replace("gift.zodl.com", "gift.zodl.com.evil"),
            link("").replace("gift.zodl.com/", "gift.zodl.com:443/"),
            link("").replace("/#", "/?x=1#"),
            link("").replace(KEY, &KEY[..KEY.len() - 1]),
        ] {
            assert_eq!(decode(&raw).err().as_deref(), Some(INVALID));
        }
        let short = bech32::encode::<Bech32m>(Hrp::parse("zgift").unwrap(), &[0; 16]).unwrap();
        assert!(decode(&link("").replace(KEY, &short)).is_err());
        let old_checksum =
            bech32::encode::<bech32::Bech32>(Hrp::parse("zgift").unwrap(), &[0xa5; 32]).unwrap();
        assert!(decode(&link("").replace(KEY, &old_checksum)).is_err());
        assert!(decode(&link("").replace(KEY, &format!("Z{}", &KEY[1..]))).is_err());
    }
    #[test]
    fn network_comes_from_the_key_and_uppercase_qr_keys_work() {
        assert!(decode(&link("").replace(KEY, &KEY.to_uppercase())).is_ok());
        for (hrp, network, height) in [
            ("zgifttest", "test", 3_000_000),
            ("zgiftregtest", "regtest", 1),
        ] {
            let key = bech32::encode::<Bech32m>(Hrp::parse(hrp).unwrap(), &[0; 32]).unwrap();
            let raw = format!("https://gift.zodl.com#v=1&key={key}&height={height}");
            assert_eq!(decode(&raw).unwrap().network, network);
        }
    }
}
