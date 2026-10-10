@Tags(['mobile'])
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart' show e2eRuntimeContext;
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart'
    show kPaymentLinkRegtestEnabled;

import 'regtest_mobile_create_sync_test.dart' as create;
import 'regtest_mobile_import_sync_test.dart' as import_sync;
import 'regtest_mobile_account_management_test.dart' as accounts;
import 'regtest_mobile_multi_account_send_test.dart' as send;
import 'regtest_mobile_mempool_receive_test.dart' as mempool;
import 'regtest_mobile_fallback_endpoint_test.dart' as fallback;
import 'regtest_mobile_slow_height_fallback_test.dart' as slow_height;
import 'regtest_mobile_payment_link_round_trip_test.dart' as gift;
import 'regtest_mobile_payment_uri_send_test.dart' as payment_uri;
import 'regtest_mobile_gift_onboarding_test.dart' as gift_onboarding;
import 'regtest_mobile_ironwood_pre_migration_send_test.dart' as pre_migration;
import 'regtest_mobile_ironwood_migration_test.dart' as migration;
import 'regtest_mobile_ironwood_migration_many_notes_test.dart' as many_notes;
import 'regtest_mobile_ironwood_migration_multi_account_test.dart'
    as migration_accounts;
import 'regtest_mobile_ironwood_migration_reorg_test.dart' as migration_reorg;
import 'regtest_mobile_ironwood_migration_network_recovery_test.dart'
    as migration_network;
import 'regtest_mobile_ironwood_migration_account_reimport_test.dart'
    as migration_reimport;
import 'regtest_mobile_ironwood_migration_restart_prepare_test.dart'
    as restart_prepare;
import 'regtest_mobile_ironwood_migration_restart_resume_test.dart'
    as restart_resume;
import 'regtest_mobile_ironwood_background_migration_test.dart' as background;
import 'regtest_mobile_ironwood_background_restart_prepare_test.dart'
    as background_prepare;
import 'regtest_mobile_ironwood_background_restart_resume_test.dart'
    as background_resume;

/// One mobile binary; original scenarios retain all financial/UI assertions.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      installE2eRuntimeCaseManifest(
        isDebug: kDebugMode,
        isIos: Platform.isIOS,
        isMacos: Platform.isMacOS,
        defaultNetworkName: kZcashDefaultNetworkName,
      ) ??
      (throw StateError('The iOS E2E cohort profile is not enabled.'));
  if (!Platform.isIOS ||
      !kVizorE2eIosCohort ||
      kAppFormFactor != AppFormFactor.mobile ||
      !kPaymentLinkRegtestEnabled) {
    throw StateError('The iOS cohort requires the mobile regtest/Gift build.');
  }
  binding.reportData = <String, Object?>{
    'case_manifest': manifest.toJson(),
    'pid': pid,
    'assertions_completed': false,
    'runtime_context': null,
  };
  final phaseBytes = readE2eNativeEnvironmentBytes('VIZOR_E2E_IOS_PHASE', 16);
  final phase = phaseBytes == null ? null : ascii.decode(phaseBytes);
  final isRestart = const {
    'flutter.ios.ironwood-migration-restart',
    'flutter.ios.ironwood-background-restart',
  }.contains(manifest.scenarioId);
  if (isRestart
      ? !const {'prepare', 'resume'}.contains(phase)
      : phase != null) {
    throw StateError('The original iOS restart phase is missing or invalid.');
  }
  if (phase != null) binding.reportData!['ios_phase'] = phase;
  tearDownAll(() {
    binding.reportData!['runtime_context'] = e2eRuntimeContext;
  });
  switch (manifest.scenarioId) {
    case 'flutter.ios.create-sync':
      create.main();
    case 'flutter.ios.import-sync':
      import_sync.main();
    case 'flutter.ios.account-management':
      accounts.main();
    case 'flutter.ios.multi-account-send':
      send.main();
    case 'flutter.ios.mempool-receive':
      mempool.main();
    case 'flutter.ios.fallback-endpoint':
      fallback.main();
    case 'flutter.ios.slow-height-fallback':
      slow_height.main();
    case 'flutter.ios.payment-link-round-trip':
      gift.main();
    case 'flutter.ios.payment-uri-send':
      payment_uri.main();
    case 'flutter.ios.gift-onboarding':
      gift_onboarding.main();
    case 'flutter.ios.ironwood-pre-migration-send':
      pre_migration.main();
    case 'flutter.ios.ironwood-migration':
      migration.main();
    case 'flutter.ios.ironwood-migration-many-notes':
    case 'flutter.ios.ironwood-migration-500-notes':
      many_notes.main();
    case 'flutter.ios.ironwood-migration-multi-account':
      migration_accounts.main();
    case 'flutter.ios.ironwood-migration-reorg':
      migration_reorg.main();
    case 'flutter.ios.ironwood-migration-network-recovery':
      migration_network.main();
    case 'flutter.ios.ironwood-migration-account-reimport':
      migration_reimport.main();
    case 'flutter.ios.ironwood-migration-restart':
      (phase == 'prepare' ? restart_prepare.main : restart_resume.main)();
    case 'flutter.ios.ironwood-background-migration':
      background.main();
    case 'flutter.ios.ironwood-background-restart':
      (phase == 'prepare' ? background_prepare.main : background_resume.main)();
    default:
      throw StateError(
        'The mobile cohort does not implement ${manifest.scenarioId}.',
      );
  }
}
