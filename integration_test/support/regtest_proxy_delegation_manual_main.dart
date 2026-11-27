// Vizor for testing proxy delegation by hand on the local stack:
//
//   scripts/e2e/flutter-macos-regtest-proxy-delegation.sh up
//   scripts/e2e/flutter-macos-regtest-proxy-delegation.sh app
//
// `app` runs this entrypoint with the stack's defines; it trusts the dev
// stack's CA and pins the vote chain's anchor as the integration test does
// (see proxy_delegation_regtest.dart). Never part of a shipped build.

import 'package:flutter/widgets.dart';
import 'package:zcash_wallet/app.dart';

import 'proxy_delegation_regtest.dart';

/// Starts Vizor against the proxy delegation regtest stack.
Future<void> main() async {
  await initializeZcashWalletRuntime();
  await prepareProxyDelegationRegtest();
  runApp(
    await buildBootstrappedZcashWalletApp(
      overrides: proxyDelegationRegtestOverrides(),
    ),
  );
}
