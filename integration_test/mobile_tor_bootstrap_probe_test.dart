import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/rust/api/network_privacy.dart'
    as rust_network_privacy;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/network_privacy.dart' as rust_types;

/// Bootstraps Tor from the app's own support directory on a mobile OS.
///
/// A bootstrap failure surfaces from inside fail-closed mode — every request
/// blocked while Tor never becomes ready — so no host test can catch it. This
/// talks to the live Tor network and is not part of any automated lane; run it
/// by hand against a booted simulator or device.
///
/// What it does not settle: whether arti's filesystem permission checks need
/// the mobile exemption. The iOS simulator passes this with the exemption
/// compiled out, because a simulator container is an ordinary directory in the
/// host filesystem. Only a real device answers that.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tor bootstraps from the mobile app sandbox', (tester) async {
    await RustLib.init();
    final torDirectory = await getTorDataDirectoryPath();

    rust_network_privacy.beginNetworkPrivacyEnable();
    final status = await rust_network_privacy.configureNetworkPrivacy(
      enabled: true,
      torDirectory: torDirectory,
    );

    expect(
      status,
      rust_types.NetworkPrivacyStatus.ready,
      reason: 'bootstrap from $torDirectory did not reach ready',
    );
    expect(rust_network_privacy.isTorEnabled(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
