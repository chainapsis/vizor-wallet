import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/native_owned_case.dart';

void main() {
  late Directory directory;
  late Map<String, dynamic> manifest;
  late Map<String, dynamic> context;
  late Map<String, dynamic> data;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-owned-result-');
    manifest = <String, dynamic>{
      'namespace': 'vizor_driver_test_w0_1',
      'context_path': '${directory.path}/native-context.json',
      'scenario_id': 'flutter.macos.import-sync',
    };
    context = <String, dynamic>{
      'schema_version': 1,
      'namespace': manifest['namespace'],
      'pid': 123,
      'support_directory': '${directory.path}/support',
      'secure_store_services': ['test-service', 'test-service.mnemonic'],
      'preferences_prefix': 'test-prefix.',
      'storage_cleanup_completed': false,
      'os_background_scheduling_enabled': false,
    };
    data = <String, dynamic>{
      'case_manifest': Map<String, dynamic>.of(manifest),
      'pid': 123,
      'assertions_completed': true,
      'runtime_context': context,
    };
  });

  tearDown(() async => directory.delete(recursive: true));

  Future<Map<String, Object>> persist() => persistNativeOwnedCaseResult(
    expected: manifest,
    expectedPid: 123,
    data: data,
  );

  test(
    'completed assertions persist context and preserve host result ABI',
    () async {
      expect(await persist(), {'case_manifest': manifest, 'pid': 123});
      expect(
        jsonDecode(await File(manifest['context_path']).readAsString()),
        context,
      );
    },
  );

  test(
    'setup-only successful Driver response is not assertion completion',
    () async {
      data['assertions_completed'] = false;
      await expectLater(persist(), throwsStateError);
      expect(await File(manifest['context_path']).exists(), isFalse);
    },
  );

  test('missing completion marker is rejected', () async {
    data.remove('assertions_completed');
    await expectLater(persist(), throwsStateError);
  });

  test('another app PID is rejected', () async {
    data['pid'] = 124;
    await expectLater(persist(), throwsStateError);
  });

  test('another context PID is rejected', () async {
    context['pid'] = 124;
    await expectLater(persist(), throwsStateError);
  });

  test('another case manifest is rejected', () async {
    (data['case_manifest'] as Map<String, dynamic>)['namespace'] = 'other';
    await expectLater(persist(), throwsStateError);
  });

  test('an observation cannot claim completed cleanup', () async {
    context['storage_cleanup_completed'] = true;
    await expectLater(persist(), throwsStateError);
  });

  test('existing evidence is never overwritten', () async {
    final file = File(manifest['context_path']);
    await file.writeAsString('retained evidence');
    await expectLater(persist(), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), 'retained evidence');
  });

  for (final phase in ['prepare', 'resume']) {
    test(
      'Gift $phase assertions are bound to the original phase and PID',
      () async {
        manifest['scenario_id'] = 'flutter.macos.payment-link-restart';
        data['case_manifest'] = Map<String, dynamic>.of(manifest);
        data['payment_link_phase'] = phase;
        expect(
          await persistNativeOwnedCaseResult(
            expected: manifest,
            expectedPid: 123,
            data: data,
            expectedPaymentLinkPhase: phase,
          ),
          {'case_manifest': manifest, 'pid': 123, 'payment_link_phase': phase},
        );
      },
    );
  }

  test('Gift prepare result cannot satisfy resume', () async {
    manifest['scenario_id'] = 'flutter.macos.payment-link-recovery';
    data['case_manifest'] = Map<String, dynamic>.of(manifest);
    data['payment_link_phase'] = 'prepare';
    await expectLater(
      persistNativeOwnedCaseResult(
        expected: manifest,
        expectedPid: 123,
        data: data,
        expectedPaymentLinkPhase: 'resume',
      ),
      throwsStateError,
    );
    expect(await File(manifest['context_path']).exists(), isFalse);
  });

  test('another scenario cannot supply a Gift phase', () async {
    data['payment_link_phase'] = 'prepare';
    await expectLater(
      persistNativeOwnedCaseResult(
        expected: manifest,
        expectedPid: 123,
        data: data,
        expectedPaymentLinkPhase: 'prepare',
      ),
      throwsStateError,
    );
  });

  test('unsolicited Gift phase is not an ordinary completed result', () async {
    data['payment_link_phase'] = 'prepare';
    await expectLater(persist(), throwsStateError);
  });

  for (final scenario in [
    'flutter.macos.voting',
    'flutter.macos.voting-slow-helper',
  ]) {
    for (final phase in ['setup', 'vote']) {
      test('$scenario $phase result is bound to the original phase', () async {
        manifest['scenario_id'] = scenario;
        data['case_manifest'] = Map<String, dynamic>.of(manifest);
        data['voting_phase'] = phase;
        expect(
          await persistNativeOwnedCaseResult(
            expected: manifest,
            expectedPid: 123,
            data: data,
            expectedVotingPhase: phase,
          ),
          {'case_manifest': manifest, 'pid': 123, 'voting_phase': phase},
        );
      });
    }
  }

  test('voting setup cannot satisfy vote assertions', () async {
    manifest['scenario_id'] = 'flutter.macos.voting';
    data['case_manifest'] = Map<String, dynamic>.of(manifest);
    data['voting_phase'] = 'setup';
    await expectLater(
      persistNativeOwnedCaseResult(
        expected: manifest,
        expectedPid: 123,
        data: data,
        expectedVotingPhase: 'vote',
      ),
      throwsStateError,
    );
    expect(await File(manifest['context_path']).exists(), isFalse);
  });

  test('another scenario cannot supply a voting phase', () async {
    data['voting_phase'] = 'vote';
    await expectLater(
      persistNativeOwnedCaseResult(
        expected: manifest,
        expectedPid: 123,
        data: data,
        expectedVotingPhase: 'vote',
      ),
      throwsStateError,
    );
  });

  test('unsolicited voting phase and mixed phase kinds are rejected', () async {
    data['voting_phase'] = 'setup';
    await expectLater(persist(), throwsStateError);
    manifest['scenario_id'] = 'flutter.macos.voting';
    data['case_manifest'] = Map<String, dynamic>.of(manifest);
    data['payment_link_phase'] = 'prepare';
    await expectLater(
      persistNativeOwnedCaseResult(
        expected: manifest,
        expectedPid: 123,
        data: data,
        expectedVotingPhase: 'setup',
        expectedPaymentLinkPhase: 'prepare',
      ),
      throwsStateError,
    );
  });
}
