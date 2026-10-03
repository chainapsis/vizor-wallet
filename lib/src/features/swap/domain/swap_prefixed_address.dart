/// Result of recognizing a `<prefix>:<address>` recipient string.
class SwapPrefixedAddressMatch {
  const SwapPrefixedAddressMatch({
    required this.symbol,
    required this.chainTicker,
    required this.address,
  });

  /// Asset symbol the prefix identifies, e.g. `USDT`.
  final String symbol;

  /// Chain ticker the prefix identifies, e.g. `tron`. Matched against
  /// [SwapAsset.chainTicker] (see `swap_asset.dart`) case-insensitively.
  final String chainTicker;

  /// The address with the prefix and separator stripped.
  final String address;
}

/// Prefixes some exchanges/wallets embed ahead of a raw chain address in
/// withdrawal QR codes (e.g. `usdttron:T9y...` for TRC-20 USDT), mapped to
/// the (symbol, chain) pair Vizor should switch the swap/pay composer to.
/// Keys are lowercase and matched case-insensitively.
const _swapAddressPrefixes = <String, (String symbol, String chainTicker)>{
  'usdttron': ('USDT', 'tron'),
};

/// Detects a `<prefix>:<address>` recipient string and returns the asset it
/// identifies plus the bare address, or `null` when [input] doesn't start
/// with a recognized prefix.
SwapPrefixedAddressMatch? detectSwapPrefixedAddress(String input) {
  final trimmed = input.trim();
  final separatorIndex = trimmed.indexOf(':');
  if (separatorIndex <= 0) return null;
  final prefix = trimmed.substring(0, separatorIndex).toLowerCase();
  final mapped = _swapAddressPrefixes[prefix];
  if (mapped == null) return null;
  final address = trimmed.substring(separatorIndex + 1).trim();
  if (address.isEmpty) return null;
  return SwapPrefixedAddressMatch(
    symbol: mapped.$1,
    chainTicker: mapped.$2,
    address: address,
  );
}
