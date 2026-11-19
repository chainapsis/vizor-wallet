import '../../address_book/models/address_book_contact.dart';

/// What happened to a deposit hash the user entered.
enum SwapUserDepositTxHashResult {
  /// NEAR Intents took it; the swap keeps it as the user's hash.
  submitted,

  /// It can't be a transaction hash of the deposit's chain, so it was neither
  /// sent nor saved.
  invalid,

  /// NEAR Intents refused it or could not be reached; nothing was saved.
  failed,
}

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
final _prefixedHex64 = RegExp(r'^0x[0-9a-fA-F]{64}$');
final _base58Signature = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{64,90}$');
final _base58Digest = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
final _tonHash = RegExp(r'^(?:[0-9a-fA-F]{64}|[A-Za-z0-9+/_-]{43}=?)$');
final _starknetHash = RegExp(r'^0x[0-9a-fA-F]{1,64}$');
final _otherHash = RegExp(r'^[0-9A-Za-z_.:-]{16,128}$');

/// The hash the user entered for a deposit on [chainTicker], trimmed, or null
/// when it can't be one of that chain's transaction hashes. Only a hash that
/// passes leaves the device, so a pasted address, note or phrase never reaches
/// NEAR Intents.
String? swapDepositTxHashOrNull(String chainTicker, String input) {
  final hash = input.trim();
  final network = AddressBookNetwork.tryFromChainTicker(chainTicker);
  final pattern = switch (network) {
    final network? when network.isEvm => _prefixedHex64,
    AddressBookNetwork.aptos || AddressBookNetwork.movement => _prefixedHex64,
    AddressBookNetwork.bitcoin ||
    AddressBookNetwork.litecoin ||
    AddressBookNetwork.dogecoin ||
    AddressBookNetwork.bitcoinCash ||
    AddressBookNetwork.dash ||
    AddressBookNetwork.zcash ||
    AddressBookNetwork.tron ||
    AddressBookNetwork.xrp ||
    AddressBookNetwork.stellar ||
    AddressBookNetwork.cardano => _hex64,
    AddressBookNetwork.solana || AddressBookNetwork.fogo => _base58Signature,
    AddressBookNetwork.near || AddressBookNetwork.sui => _base58Digest,
    AddressBookNetwork.ton => _tonHash,
    AddressBookNetwork.starknet => _starknetHash,
    _ => _otherHash,
  };
  return pattern.hasMatch(hash) ? hash : null;
}
