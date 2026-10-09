import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart' show e2eRuntimeContext;
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';

import 'regtest_import_sync_test.dart' as import_sync;
import 'regtest_fallback_endpoint_test.dart' as fallback_endpoint;
import 'regtest_custom_endpoint_no_fallback_test.dart' as custom_endpoint;
import 'regtest_slow_height_fallback_test.dart' as slow_height;
import 'regtest_sync_startup_stall_recovery_test.dart' as startup_recovery;
import 'regtest_shield_transparent_test.dart' as shield;
import 'regtest_shield_transparent_retry_test.dart' as shield_retry;
import 'regtest_multi_account_send_test.dart' as multi_account;
import 'regtest_tex_send_test.dart' as tex;
import 'regtest_payment_uri_send_test.dart' as payment_uri;
import 'regtest_payment_uri_locked_send_test.dart' as locked_uri;
import 'regtest_payment_request_round_trip_test.dart' as payment_request;

/// One binary, with case identity supplied only by the existing runtime contract.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      installE2eRuntimeCaseManifest(
        isDebug: kDebugMode,
        isIos: Platform.isIOS,
        isMacos: Platform.isMacOS,
        defaultNetworkName: kZcashDefaultNetworkName,
      ) ??
      (throw StateError('The native E2E cohort profile is not enabled.'));
  binding.reportData = <String, Object?>{
    'case_manifest': manifest.toJson(),
    'pid': pid,
    'assertions_completed': false,
    'runtime_context': null,
  };
  tearDownAll(() {
    binding.reportData!['runtime_context'] = e2eRuntimeContext;
  });
  switch (manifest.scenarioId) {
    case 'flutter.macos.import-sync':
      import_sync.main();
      return;
    case 'flutter.macos.fallback-endpoint':
      fallback_endpoint.main();
      return;
    case 'flutter.macos.custom-endpoint-no-fallback':
      custom_endpoint.main();
      return;
    case 'flutter.macos.slow-height-fallback':
      slow_height.main();
      return;
    case 'flutter.macos.sync-startup-stall-recovery':
      startup_recovery.main();
      return;
    case 'flutter.macos.shield-transparent':
      shield.main();
      return;
    case 'flutter.macos.shield-transparent-retry':
      shield_retry.main();
      return;
    case 'flutter.macos.multi-account-send':
      multi_account.main();
      return;
    case 'flutter.macos.tex-send':
      tex.main();
      return;
    case 'flutter.macos.payment-uri-send':
      payment_uri.main();
      return;
    case 'flutter.macos.payment-uri-locked-send':
      locked_uri.main();
      return;
    case 'flutter.macos.payment-request-round-trip':
      payment_request.main();
      return;
    default:
      throw StateError(
        'This cohort does not implement ${manifest.scenarioId}.',
      );
  }
}
