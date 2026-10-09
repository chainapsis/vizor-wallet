import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Connects only to the parent's original app VM; never launches another app.
Future<void> main() async {
  final expected = jsonDecode(
    Platform.environment['VIZOR_E2E_CASE_MANIFEST'] ??
        (throw StateError('The original case manifest is missing.')),
  );
  final expectedPid = int.parse(
    Platform.environment['VIZOR_E2E_APP_PID'] ??
        (throw StateError('The original app PID is missing.')),
  );
  await integrationDriver(
    responseDataCallback: (data) async {
      final result = await persistNativeOwnedCaseResult(
        expected: expected,
        expectedPid: expectedPid,
        expectedPaymentLinkPhase:
            Platform.environment['VIZOR_E2E_PAYMENT_LINK_PHASE'],
        expectedVotingPhase: Platform.environment['VIZOR_E2E_VOTING_PHASE'],
        expectedIosPhase: Platform.environment['VIZOR_E2E_IOS_PHASE'],
        data: data,
      );
      stdout.writeln('VIZOR_E2E_RESULT=${jsonEncode(result)}');
    },
  );
}

/// Validates real assertion completion before persisting an app observation.
/// This file never authorizes deletion; the original host owner checks it again.
Future<Map<String, Object>> persistNativeOwnedCaseResult({
  required Object? expected,
  required int expectedPid,
  required Map<String, dynamic>? data,
  String? expectedPaymentLinkPhase,
  String? expectedVotingPhase,
  String? expectedIosPhase,
}) async {
  final actual = data?['case_manifest'];
  final context = data?['runtime_context'];
  final phaseCount = [
    expectedPaymentLinkPhase,
    expectedVotingPhase,
    expectedIosPhase,
  ].whereType<String>().length;
  if (expected is! Map<String, dynamic> ||
      actual is! Map<String, dynamic> ||
      phaseCount > 1 ||
      data!.length != 4 + phaseCount ||
      (expectedPaymentLinkPhase != null &&
          (!const {'prepare', 'resume'}.contains(expectedPaymentLinkPhase) ||
              !const {
                'flutter.macos.payment-link-restart',
                'flutter.macos.payment-link-recovery',
              }.contains(expected['scenario_id']) ||
              data['payment_link_phase'] != expectedPaymentLinkPhase)) ||
      (expectedVotingPhase != null &&
          (!const {'setup', 'vote'}.contains(expectedVotingPhase) ||
              !const {
                'flutter.macos.voting',
                'flutter.macos.voting-slow-helper',
              }.contains(expected['scenario_id']) ||
              data['voting_phase'] != expectedVotingPhase)) ||
      (expectedIosPhase != null &&
          (!const {'prepare', 'resume'}.contains(expectedIosPhase) ||
              !const {
                'flutter.ios.ironwood-migration-restart',
                'flutter.ios.ironwood-background-restart',
              }.contains(expected['scenario_id']) ||
              data['ios_phase'] != expectedIosPhase)) ||
      data['pid'] is! int ||
      data['pid'] != expectedPid ||
      data['assertions_completed'] != true ||
      actual.length != expected.length ||
      expected.entries.any(
        (entry) =>
            actual[entry.key] != entry.value ||
            actual[entry.key].runtimeType != entry.value.runtimeType,
      ) ||
      context is! Map<String, dynamic> ||
      context['schema_version'] != 1 ||
      context['namespace'] != expected['namespace'] ||
      context['pid'] is! int ||
      context['pid'] != expectedPid ||
      context['storage_cleanup_completed'] != false ||
      context['os_background_scheduling_enabled'] != false) {
    throw StateError('The original app/case did not complete its assertions.');
  }
  final path = expected['context_path'];
  if (path == 'app-support' &&
      expected['scenario_id'] is String &&
      (expected['scenario_id'] as String).startsWith('flutter.ios.')) {
    // iOS already published its context inside its owned Simulator container.
    // Never interpret app-support as a host path or overwrite native evidence.
    return <String, Object>{
      'case_manifest': actual,
      'pid': expectedPid,
      'ios_phase': ?expectedIosPhase,
    };
  }
  if (path is! String || !File(path).isAbsolute) {
    throw StateError('The original host context path must be absolute.');
  }
  final encoded = jsonEncode(context);
  if (utf8.encode(encoded).length > 8192) {
    throw StateError('The native context exceeds its host observation limit.');
  }
  // Never truncate/adopt an existing case observation or create new parents.
  final file = await File(path).create(exclusive: true);
  await file.writeAsString(encoded, flush: true);
  return <String, Object>{
    'case_manifest': actual,
    'pid': expectedPid,
    'payment_link_phase': ?expectedPaymentLinkPhase,
    'voting_phase': ?expectedVotingPhase,
  };
}
