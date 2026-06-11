/// Converts a chain-facing ZEC txid (1Click status hashes and our broadcast
/// results use the display byte order, optionally 0x-prefixed) into the
/// wallet's internal-order lowercase `txidHex` so the two can be compared
/// with string equality.
///
/// Returns null when the input is not a 32-byte hex string — callers must
/// not match on malformed hashes.
String? swapChainTxidToWalletTxidHex(String? chainTxid) {
  var hex = chainTxid?.trim() ?? '';
  if (hex.startsWith('0x') || hex.startsWith('0X')) {
    hex = hex.substring(2);
  }
  if (hex.length != 64) return null;
  if (!_hex64.hasMatch(hex)) return null;
  final lower = hex.toLowerCase();
  final buffer = StringBuffer();
  for (var i = 62; i >= 0; i -= 2) {
    buffer.write(lower.substring(i, i + 2));
  }
  return buffer.toString();
}

final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
