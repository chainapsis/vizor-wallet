//! Minimal BIP173 bech32 encoder for segwit v0 outputs (P2WSH/P2WPKH).
//!
//! The zwap BTC lock yields a P2WSH `scriptPubKey` (`OP_0 <32-byte hash>`); to
//! display a fundable deposit address we bech32-encode that witness program for
//! the target network. Self-contained (zero deps) so the BTC-address display
//! path adds no crate-version surface — `bitcoin`'s secp256k1 line differs from
//! the one already pinned for DLEq/adaptor work.
//!
//! Witness v0 uses bech32 (not bech32m); only v0 programs are produced here.

const CHARSET: &[u8; 32] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";

fn polymod(values: &[u8]) -> u32 {
    const GEN: [u32; 5] = [0x3b6a_57b2, 0x2650_8e6d, 0x1ea1_19fa, 0x3d42_33dd, 0x2a14_62b3];
    let mut chk: u32 = 1;
    for &v in values {
        let b = (chk >> 25) as u8;
        chk = ((chk & 0x01ff_ffff) << 5) ^ (v as u32);
        for (i, g) in GEN.iter().enumerate() {
            if (b >> i) & 1 == 1 {
                chk ^= g;
            }
        }
    }
    chk
}

fn hrp_expand(hrp: &str) -> Vec<u8> {
    let mut v = Vec::with_capacity(hrp.len() * 2 + 1);
    for b in hrp.bytes() {
        v.push(b >> 5);
    }
    v.push(0);
    for b in hrp.bytes() {
        v.push(b & 0x1f);
    }
    v
}

/// Convert 8-bit bytes to 5-bit groups (no padding control needed for our fixed
/// 20/32-byte witness programs, but the general pad path is implemented).
fn convert_bits(data: &[u8], from: u32, to: u32, pad: bool) -> Option<Vec<u8>> {
    let mut acc: u32 = 0;
    let mut bits: u32 = 0;
    let mut out = Vec::new();
    let maxv: u32 = (1 << to) - 1;
    for &value in data {
        let v = value as u32;
        if (v >> from) != 0 {
            return None;
        }
        acc = (acc << from) | v;
        bits += from;
        while bits >= to {
            bits -= to;
            out.push(((acc >> bits) & maxv) as u8);
        }
    }
    if pad {
        if bits > 0 {
            out.push(((acc << (to - bits)) & maxv) as u8);
        }
    } else if bits >= from || ((acc << (to - bits)) & maxv) != 0 {
        return None;
    }
    Some(out)
}

/// Human-readable part for a network's bech32 addresses.
pub fn hrp_for_network(network: &str) -> &'static str {
    match network {
        "mainnet" | "main" => "bc",
        "testnet" | "test" => "tb",
        _ => "bcrt", // regtest
    }
}

/// Encode a segwit v0 address from `hrp` + 32-byte (P2WSH) or 20-byte (P2WPKH)
/// witness program. Returns `None` on invalid program length.
pub fn encode_segwit_v0(hrp: &str, program: &[u8]) -> Option<String> {
    if program.len() != 20 && program.len() != 32 {
        return None;
    }
    let mut data = vec![0u8]; // witness version 0
    data.extend(convert_bits(program, 8, 5, true)?);

    let mut values = hrp_expand(hrp);
    values.extend_from_slice(&data);
    values.extend_from_slice(&[0, 0, 0, 0, 0, 0]);
    let m = polymod(&values) ^ 1;
    let mut checksum = Vec::with_capacity(6);
    for i in 0..6 {
        checksum.push(((m >> (5 * (5 - i))) & 0x1f) as u8);
    }

    let mut s = String::with_capacity(hrp.len() + 1 + data.len() + 6);
    s.push_str(hrp);
    s.push('1');
    for b in data.iter().chain(checksum.iter()) {
        s.push(CHARSET[*b as usize] as char);
    }
    Some(s)
}

const BECH32_CONST: u32 = 1;
const BECH32M_CONST: u32 = 0x2bc8_30a3;

fn charset_rev(c: u8) -> Option<u8> {
    CHARSET.iter().position(|&x| x == c).map(|i| i as u8)
}

/// Decode a segwit address (bech32 for v0, bech32m for v1+) into its
/// `scriptPubKey`: `<version opcode> <push len> <program>`. Accepts p2wpkh
/// (v0/20B), p2wsh (v0/32B), and p2tr (v1/32B) — the standard payout forms the
/// z2b BTC claim can pay to. Case-insensitive HRP; rejects mixed case, bad
/// checksum, and out-of-range program lengths (BIP173/BIP350).
pub fn segwit_address_to_spk(address: &str) -> Result<Vec<u8>, String> {
    let has_lower = address.chars().any(|c| c.is_ascii_lowercase());
    let has_upper = address.chars().any(|c| c.is_ascii_uppercase());
    if has_lower && has_upper {
        return Err("mixed-case bech32 address".into());
    }
    let addr = address.to_ascii_lowercase();
    let sep = addr.rfind('1').ok_or("bech32: no separator '1'")?;
    if sep == 0 || sep + 7 > addr.len() {
        return Err("bech32: malformed (hrp/data length)".into());
    }
    let hrp = &addr[..sep];
    let data_part = &addr[sep + 1..];
    let mut data = Vec::with_capacity(data_part.len());
    for c in data_part.bytes() {
        data.push(charset_rev(c).ok_or("bech32: invalid data character")?);
    }
    if data.len() < 6 {
        return Err("bech32: data too short for checksum".into());
    }
    // Verify checksum (v0 → bech32, v1+ → bech32m; the witness version is data[0]).
    let mut values = hrp_expand(hrp);
    values.extend_from_slice(&data);
    let witver = data[0];
    let expect = if witver == 0 { BECH32_CONST } else { BECH32M_CONST };
    if polymod(&values) != expect {
        return Err("bech32: bad checksum".into());
    }
    let program = convert_bits(&data[1..data.len() - 6], 5, 8, false)
        .ok_or("bech32: invalid 5→8 bit program")?;
    if witver > 16 {
        return Err("bech32: witness version > 16".into());
    }
    let len_ok = match witver {
        0 => program.len() == 20 || program.len() == 32,
        _ => (2..=40).contains(&program.len()),
    };
    if !len_ok {
        return Err(format!("bech32: bad program length {} for v{witver}", program.len()));
    }
    // scriptPubKey: OP_0 (0x00) for v0, else 0x50 + witver; then push len; then program.
    let ver_opcode = if witver == 0 { 0x00 } else { 0x50 + witver };
    let mut spk = Vec::with_capacity(2 + program.len());
    spk.push(ver_opcode);
    spk.push(program.len() as u8);
    spk.extend_from_slice(&program);
    Ok(spk)
}

/// Encode a P2WSH `scriptPubKey` (`0x00 0x20 <32-byte hash>`) as a bech32
/// address for `network` (`mainnet` | `testnet` | `regtest`).
pub fn p2wsh_address_from_spk(spk: &[u8], network: &str) -> Result<String, String> {
    if spk.len() != 34 || spk[0] != 0x00 || spk[1] != 0x20 {
        return Err("not a 34-byte P2WSH scriptPubKey (0x0020...)".into());
    }
    encode_segwit_v0(hrp_for_network(network), &spk[2..])
        .ok_or_else(|| "bech32 encode failed".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    // BIP173 test vector: a P2WSH for a known program on mainnet.
    #[test]
    fn bip173_p2wpkh_vector() {
        // BIP173: hrp=bc, program = 751e76e8199196d454941c45d1b3a323f1433bd6 → bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
        let prog = hex_to_vec("751e76e8199196d454941c45d1b3a323f1433bd6");
        let addr = encode_segwit_v0("bc", &prog).unwrap();
        assert_eq!(addr, "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
    }

    #[test]
    fn bip173_p2wsh_vector() {
        // BIP173 mainnet P2WSH 32-byte program vector.
        let prog = hex_to_vec("1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262");
        let addr = encode_segwit_v0("bc", &prog).unwrap();
        assert_eq!(
            addr,
            "bc1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3"
        );
    }

    #[test]
    fn p2wsh_spk_roundtrip_regtest() {
        let mut spk = vec![0x00u8, 0x20];
        spk.extend_from_slice(&[0x42u8; 32]);
        let addr = p2wsh_address_from_spk(&spk, "regtest").unwrap();
        assert!(addr.starts_with("bcrt1q"), "regtest P2WSH starts with bcrt1q: {addr}");
    }

    #[test]
    fn decode_p2wpkh_vector() {
        // BIP173 mainnet p2wpkh → spk 0014<20-byte program>.
        let spk = segwit_address_to_spk("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4").unwrap();
        assert_eq!(spk[0], 0x00);
        assert_eq!(spk[1], 0x14);
        assert_eq!(hex_to_vec("751e76e8199196d454941c45d1b3a323f1433bd6"), spk[2..].to_vec());
    }

    #[test]
    fn decode_roundtrips_encode_regtest() {
        let prog = [0x37u8; 20];
        let addr = encode_segwit_v0("bcrt", &prog).unwrap();
        let spk = segwit_address_to_spk(&addr).unwrap();
        assert_eq!(spk, [&[0x00u8, 0x14][..], &prog[..]].concat());
    }

    #[test]
    fn rejects_bad_checksum() {
        assert!(segwit_address_to_spk("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5").is_err());
    }

    fn hex_to_vec(h: &str) -> Vec<u8> {
        (0..h.len()).step_by(2).map(|i| u8::from_str_radix(&h[i..i + 2], 16).unwrap()).collect()
    }
}
