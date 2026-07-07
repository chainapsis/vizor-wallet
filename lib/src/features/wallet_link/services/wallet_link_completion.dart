import '../../../../main.dart' show log;

import 'wallet_link_api_client.dart';

Future<void> completeWalletLinkPackageBestEffort({
  required String packageId,
  required String completionToken,
}) async {
  final client = WalletLinkApiClient(timeout: const Duration(seconds: 4));
  try {
    await client.completePackage(
      packageId: packageId,
      completionToken: completionToken,
    );
  } catch (error, stackTrace) {
    log('WalletLinkCompletion.completePackage: ERROR: $error\n$stackTrace');
    // The local import already succeeded. Backend completion only updates the
    // desktop confirmation state and must not roll the wallet mutation back.
  } finally {
    client.close(force: true);
  }
}
