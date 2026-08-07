@Tags(['live-tor'])
library;

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
/// blocked while Tor never becomes ready — so no host test can catch it.
///
/// This talks to the live Tor network and is not part of any automated lane.
/// The `live-tor` tag is what keeps it out of one: `dart_test.yaml` skips that
/// tag, so `fvm flutter test integration_test/` — which would otherwise pick
/// this file up, spend five minutes on a network nobody controls, and leave the
/// process Tor-enabled and fail-closed for whatever shares the binary — reports
/// it as skipped instead. Run it by hand against a booted simulator or device:
///
/// ```sh
/// fvm flutter test --tags live-tor --run-skipped \
///   integration_test/mobile_tor_bootstrap_probe_test.dart \
///   -d <device> --dart-define=VIZOR_FORM_FACTOR=mobile
/// ```
///
/// The define is what this probe is run with, and every mobile-targeted
/// invocation carries it — the test binary is compiled per lane like any other
/// build. Omitting it here compiles the probe against desktop tokens on a
/// phone, which is the mismatch `lib/main.dart` asserts against.
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
