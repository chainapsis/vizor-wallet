import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart' show e2eRuntimeContext;
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';

import 'regtest_import_sync_test.dart' as import_sync;

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
    default:
      throw StateError(
        'This cohort does not implement ${manifest.scenarioId}.',
      );
  }
}
