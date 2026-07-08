import '../../../../main.dart' show log;

import '../models/wallet_link_models.dart';
import 'wallet_link_api_client.dart';
import 'wallet_link_completion_crypto.dart';

Future<void> completeWalletLinkPackageBestEffort({
  required String packageId,
  required String completionToken,
  required List<int> keyBytes,
  required int importedAccountCount,
  required int importedContactCount,
}) async {
  final client = WalletLinkApiClient(timeout: const Duration(seconds: 4));
  try {
    final completionEnvelope = await encryptWalletLinkImportSummary(
      summary: WalletLinkImportSummary(
        importedAccountCount: importedAccountCount,
        importedContactCount: importedContactCount,
      ),
      keyBytes: keyBytes,
    );
    await client.completePackage(
      packageId: packageId,
      completionToken: completionToken,
      completionEnvelope: completionEnvelope,
    );
  } catch (error, stackTrace) {
    log('WalletLinkCompletion.completePackage: ERROR: $error\n$stackTrace');
    // The local import already succeeded. Backend completion only updates the
    // desktop confirmation state and must not roll the wallet mutation back.
  } finally {
    client.close(force: true);
  }
}
