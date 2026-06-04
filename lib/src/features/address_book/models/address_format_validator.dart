import 'dart:convert';

import '../../../core/config/network_config.dart';
import '../../../core/crypto/base58check.dart';
import '../../../core/crypto/bech32.dart';
import '../../../core/crypto/keccak256.dart';
import 'address_book_contact.dart';

/// Conservative, best-effort address format check keyed on [network].
///
/// Returns `null` when the address looks plausible for [network], when the
/// address is empty (emptiness is handled by the dedicated non-empty
/// validators), or when [network] has no validator — we never block a chain we
/// do not understand. Returns a short reason otherwise.
///
/// The reason names the address *family*, not the chain: every EVM chain
/// (Ethereum, Base, Arbitrum, …) shares the same 0x hex address, so the message
/// reads "Invalid EVM address" rather than "Invalid Base address".
///
/// Scope: EVM family (0x + 40 hex, with EIP-55 checksum enforced on mixed-case
/// input), Bitcoin, Solana, NEAR, and Zcash. Every other network passes
/// through unchecked. Zcash uses a best-effort prefix/charset check restricted
/// to the active [zcashNetwork] (defaults to the build's network), so a testnet
/// address is rejected on mainnet and vice versa; the authoritative checksum
/// validation lives in the Rust-backed send flow.
String? addressFormatIssue(
  AddressBookNetwork network,
  String address, {
  ZcashNetwork? zcashNetwork,
}) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return null;

  // Every EVM chain shares the same 0x address family, so one check covers all
  // of them (see AddressBookNetwork.isEvm — the single source of truth).
  if (network.isEvm) {
    return _isEvmAddress(trimmed) ? null : 'Invalid EVM address';
  }

  final (ok, kind) = switch (network) {
    AddressBookNetwork.bitcoin => (_isBitcoinAddress(trimmed), 'Bitcoin'),
    AddressBookNetwork.solana => (_isSolanaAddress(trimmed), 'Solana'),
    AddressBookNetwork.near => (_isNearAddress(trimmed), 'NEAR'),
    AddressBookNetwork.zcash => (
      _isZcashAddress(
        trimmed,
        zcashNetwork ?? zcashNetworkFromName(kZcashDefaultNetworkName),
      ),
      'Zcash',
    ),
    _ => (true, ''),
  };

  if (ok) return null;
  return 'Invalid $kind address';
}

final _evm = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
final _btcLegacy = RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$');
final _nearImplicit = RegExp(r'^[0-9a-f]{64}$');
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

bool _isSolanaAddress(String value) =>
    value.length >= 32 && value.length <= 44 && _base58.hasMatch(value);

bool _isNearAddress(String value) {
  if (_nearImplicit.hasMatch(value)) return true;
  return value.length >= 2 && value.length <= 64 && _nearNamed.hasMatch(value);
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
  final tPrefixes = switch (net) {
    ZcashNetwork.mainnet => const ['t1', 't3'],
    ZcashNetwork.testnet || ZcashNetwork.regtest => const ['tm', 't2'],
  };
  for (final prefix in tPrefixes) {
    if (value.startsWith(prefix)) {
      final body = value.substring(prefix.length);
      if (body.length >= 25 && body.length <= 40 && _base58.hasMatch(body)) {
        return true;
      }
    }
  }
  return false;
}
