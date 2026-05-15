const nearIntentsExplorerHost = 'explorer.near-intents.org';

Uri nearIntentsExplorerTransactionUri(String depositAddress) {
  return Uri(
    scheme: 'https',
    host: nearIntentsExplorerHost,
    pathSegments: ['transactions', depositAddress.trim()],
  );
}

Uri nearIntentsExplorerSearchUri(String query) {
  return Uri.https(nearIntentsExplorerHost, '/', {'search': query.trim()});
}

Uri? nearIntentsExplorerUri({
  String? nearIntentHash,
  String? depositTxHash,
  String? depositAddress,
}) {
  final address = depositAddress?.trim();
  if (address != null && address.isNotEmpty) {
    return nearIntentsExplorerTransactionUri(address);
  }

  final txHash = depositTxHash?.trim();
  if (txHash != null && txHash.isNotEmpty) {
    return nearIntentsExplorerSearchUri(txHash);
  }

  final intentHash = nearIntentHash?.trim();
  if (intentHash != null && intentHash.isNotEmpty) {
    return nearIntentsExplorerSearchUri(intentHash);
  }

  return null;
}
