import 'package:url_launcher/url_launcher.dart';

const nearIntentsExplorerHost = 'explorer.near-intents.org';

typedef NearIntentsUrlLauncher =
    Future<bool> Function(Uri uri, {required LaunchMode mode});

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

  final intentHash = nearIntentHash?.trim();
  if (intentHash != null && intentHash.isNotEmpty) {
    return nearIntentsExplorerSearchUri(intentHash);
  }

  final txHash = depositTxHash?.trim();
  if (txHash != null && txHash.isNotEmpty) {
    return nearIntentsExplorerSearchUri(txHash);
  }

  return null;
}

Future<bool> launchNearIntentsExplorer({
  String? nearIntentHash,
  String? depositTxHash,
  String? depositAddress,
  NearIntentsUrlLauncher launcher = launchUrl,
}) async {
  final uri = nearIntentsExplorerUri(
    nearIntentHash: nearIntentHash,
    depositTxHash: depositTxHash,
    depositAddress: depositAddress,
  );
  if (uri == null) return false;

  try {
    return await launcher(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
