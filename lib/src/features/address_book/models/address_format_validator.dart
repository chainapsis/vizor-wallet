import 'dart:convert';

import '../../../core/config/network_config.dart';
import '../../../core/crypto/base58check.dart';
import '../../../core/crypto/bech32.dart';
import '../../../core/crypto/keccak256.dart';
import 'address_book_contact.dart';

/// Severity of an address-format finding.
///
/// [error] means the address cannot be valid for the network and is safe to
/// hard-block. [warning] means the address is syntactically valid but unusual
/// enough to deserve a second look (surface it, never block on it).
enum AddressFormatSeverity { error, warning }

/// A format finding for an address, carrying a short user-facing [message]
/// and its [severity].
class AddressFormatFinding {
  const AddressFormatFinding.error(this.message)
    : severity = AddressFormatSeverity.error;

  const AddressFormatFinding.warning(this.message)
    : severity = AddressFormatSeverity.warning;

  final String message;
  final AddressFormatSeverity severity;
}

/// Conservative, best-effort address format check keyed on [network].
///
/// Returns `null` when the address looks plausible for [network], when the
/// address is empty (emptiness is handled by the dedicated non-empty
/// validators), or when [network] has no validator — we never block a chain we
/// do not understand. Otherwise returns a finding whose severity separates
/// "cannot be valid" ([AddressFormatSeverity.error]) from "valid but worth a
/// second look" ([AddressFormatSeverity.warning]).
///
/// The reason names the address *family*, not the chain: every EVM chain
/// (Ethereum, Base, Arbitrum, …) shares the same 0x hex address, so the message
/// reads "Invalid EVM address" rather than "Invalid Base address".
///
/// Scope: EVM family (0x + 40 hex, with EIP-55 checksum enforced on mixed-case
/// input), Bitcoin, Solana, NEAR, and Zcash. Every other network passes
/// through unchecked. Zcash transparent addresses are fully Base58Check
/// verified; unified/Sapling addresses use a best-effort prefix/charset check
/// restricted to the active [zcashNetwork] (defaults to the build's network),
/// so a testnet address is rejected on mainnet and vice versa, with the
/// authoritative bech32m checksum validation living in the Rust-backed send
/// flow. NEAR bare top-level names (no dot, not implicit) are syntactically
/// valid but warn: only the protocol registrar can create them, so a typical
/// user input like `alice` is almost always a missing `.near`.
AddressFormatFinding? addressFormatCheck(
  AddressBookNetwork network,
  String address, {
  ZcashNetwork? zcashNetwork,
}) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return null;

  // Every EVM chain shares the same 0x address family, so one check covers all
  // of them (see AddressBookNetwork.isEvm — the single source of truth).
  if (network.isEvm) {
    return _isEvmAddress(trimmed)
        ? null
        : const AddressFormatFinding.error('Invalid EVM address');
  }

  switch (network) {
    case AddressBookNetwork.bitcoin:
      return _isBitcoinAddress(trimmed)
          ? null
          : const AddressFormatFinding.error('Invalid Bitcoin address');
    case AddressBookNetwork.solana:
      return _isSolanaAddress(trimmed)
          ? null
          : const AddressFormatFinding.error('Invalid Solana address');
    case AddressBookNetwork.near:
      return _nearFinding(trimmed);
    case AddressBookNetwork.zcash:
      return _isZcashAddress(
            trimmed,
            zcashNetwork ?? zcashNetworkFromName(kZcashDefaultNetworkName),
          )
          ? null
          : const AddressFormatFinding.error('Invalid Zcash address');
    default:
      return null;
  }
}

/// Hard-gate view of [addressFormatCheck]: only error-severity messages.
///
/// Returns `null` for valid addresses *and* for warning-severity findings, so
/// callers that block submission (the swap review/destination paths) never
/// reject a syntactically valid address. Callers that can display advisory
/// text should use [addressFormatCheck] directly.
String? addressFormatIssue(
  AddressBookNetwork network,
  String address, {
  ZcashNetwork? zcashNetwork,
}) {
  final finding = addressFormatCheck(
    network,
    address,
    zcashNetwork: zcashNetwork,
  );
  if (finding == null) return null;
  return finding.severity == AddressFormatSeverity.error
      ? finding.message
      : null;
}

final _evm = RegExp(r'^0[xX][0-9a-fA-F]{40}$');
final _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
final _btcLegacy = RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$');
final _nearImplicit = RegExp(r'^[0-9a-f]{64}$');
// NEAR eth-implicit accounts: 0x + 40 lowercase hex (account IDs are
// lowercase-only, so no uppercase variant exists).
final _nearEthImplicit = RegExp(r'^0x[0-9a-f]{40}$');
// Named accounts: lowercase alphanumeric runs joined by single separators
// (`.`, `-`, `_`); no leading/trailing/consecutive separators.
final _nearNamed = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
final _bech32Body = RegExp(r'^[a-z0-9]+$');

bool _isEvmAddress(String value) {
  if (!_evm.hasMatch(value)) return false;
  final body = value.substring(2);
  // All-lowercase / all-uppercase carry no checksum information, so they can
  // only be format-checked. Mixed case must satisfy the EIP-55 checksum.
  if (body == body.toLowerCase() || body == body.toUpperCase()) return true;
  return _isEip55Checksummed(body);
}

bool _isEip55Checksummed(String body) {
  final hash = keccak256(ascii.encode(body.toLowerCase()));
  for (var i = 0; i < 40; i++) {
    final ch = body.codeUnitAt(i);
    final isUpper = ch >= 0x41 && ch <= 0x46; // A-F
    final isLower = ch >= 0x61 && ch <= 0x66; // a-f
    if (!isUpper && !isLower) continue; // digits are case-agnostic
    final hashByte = hash[i >> 1];
    final nibble = (i & 1) == 0 ? (hashByte >> 4) : (hashByte & 0x0f);
    final shouldBeUpper = nibble >= 8;
    if (shouldBeUpper != isUpper) return false;
  }
  return true;
}

bool _isBitcoinAddress(String value) {
  // Legacy P2PKH/P2SH: base58 format gate + base58check (double-SHA256) checksum.
  if (_btcLegacy.hasMatch(value)) return base58CheckDecode(value) != null;
  // Native SegWit (bech32/bech32m): full checksum verification.
  if (value.toLowerCase().startsWith('bc1')) {
    return decodeSegwitAddress(value) != null;
  }
  return false;
}

bool _isSolanaAddress(String value) {
  // Fast-path gate (charset + plausible length), then the authoritative
  // check: a Solana address is an Ed25519 public key, so the base58 payload
  // must decode to exactly 32 bytes.
  if (value.length < 32 || value.length > 44 || !_base58.hasMatch(value)) {
    return false;
  }
  return base58Decode(value)?.length == 32;
}

AddressFormatFinding? _nearFinding(String value) {
  if (_nearImplicit.hasMatch(value)) return null;
  if (_nearEthImplicit.hasMatch(value)) return null;
  final isNamed =
      value.length >= 2 && value.length <= 64 && _nearNamed.hasMatch(value);
  if (!isNamed) {
    return const AddressFormatFinding.error('Invalid NEAR address');
  }
  // Bare top-level names (`alice`) are syntactically valid, but on mainnet
  // only the protocol registrar can create them — real ones (`aurora`,
  // `sweat`) are rare, so the common case is a user dropping the `.near`
  // suffix. Warn without blocking.
  if (!value.contains('.')) {
    return const AddressFormatFinding.warning(
      'NEAR accounts usually end in .near — double-check this address',
    );
  }
  return null;
}

bool _isZcashAddress(String value, ZcashNetwork net) {
  final lower = value.toLowerCase();
  // Bech32(m): unified + sapling addresses for this network only.
  final bechPrefixes = [net.uaPrefix, '${net.saplingPrefix}1'];
  for (final prefix in bechPrefixes) {
    if (lower.startsWith(prefix)) {
      return value.length >= 8 && _bech32Body.hasMatch(lower);
    }
  }
  // Transparent base58check: P2PKH + P2SH prefixes for this network only.
  // Full Base58Check verification — a real t-addr decodes to a 22-byte
  // payload (2-byte version prefix + 20-byte hash) with a valid checksum.
  final tPrefixes = switch (net) {
    ZcashNetwork.mainnet => const ['t1', 't3'],
    ZcashNetwork.testnet || ZcashNetwork.regtest => const ['tm', 't2'],
  };
  for (final prefix in tPrefixes) {
    if (value.startsWith(prefix)) {
      final payload = base58CheckDecode(value);
      return payload != null && payload.length == 22;
    }
  }
  return false;
}
