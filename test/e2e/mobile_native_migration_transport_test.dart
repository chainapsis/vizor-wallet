import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/mobile_background_migration_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zcash.wallet/background_migration');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Set<String> leases;
  late bool quiesceResult;
  late bool resumeResult;
  setUp(() {
    calls = [];
    leases = {'sibling-lease'};
    quiesceResult = resumeResult = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'quiesce' || call.method == 'resume') {
        final args = call.arguments as Map;
        final id = args['leaseId'] as String;
        expect(id, startsWith('e2e-native-outbox-tick:'));
        if (call.method == 'quiesce') {
          leases.add(id);
          return quiesceResult;
        }
        leases.remove(id);
        return resumeResult;
      }
      if (call.method == 'resumeWithoutSchedulingForTesting') {
        // Current AppDelegate API takes no lease and cannot release one.
        expect(call.arguments, isNull);
        return true;
      }
      if (call.method == 'runOutboxOnceNow') return {'outcome': 'accepted'};
      throw StateError('Unexpected native method ${call.method}');
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'unique hold releases its own production admission lease before debug resume',
    () async {
      expect(
        await withNativeMigrationTransportHeld(() async {
          expect(leases, hasLength(2));
          return 'observed';
        }),
        'observed',
      );
      expect(calls.map((call) => call.method), [
        'quiesce',
        'resume',
        'resumeWithoutSchedulingForTesting',
      ]);
      expect(calls[0].arguments, calls[1].arguments);
      expect(leases, {'sibling-lease'});
    },
  );

  test('action failure still releases only this lease', () async {
    final primary = StateError('financial assertion failed');
    await expectLater(
      withNativeMigrationTransportHeld(() async => throw primary),
      throwsA(same(primary)),
    );
    expect(leases, {'sibling-lease'});
    expect(calls[0].arguments, calls[1].arguments);
  });

  test(
    'unproven quiescence performs no scenario action but attempts exact release',
    () async {
      quiesceResult = false;
      var actions = 0;
      await expectLater(
        withNativeMigrationTransportHeld(() async => actions++),
        throwsA(isA<TestFailure>()),
      );
      expect(actions, 0);
      expect(leases, {'sibling-lease'});
    },
  );

  test(
    'false production resume outside isolated profile cannot credit debug readiness',
    () async {
      resumeResult = false;
      await expectLater(
        withNativeMigrationTransportHeld(() async {}),
        throwsA(isA<TestFailure>()),
      );
      expect(calls.map((call) => call.method), ['quiesce', 'resume']);
    },
  );

  test(
    'native transport tick invokes production outbox, not the background manager',
    () async {
      expect(await runNativeMigrationOutboxTick(), {'outcome': 'accepted'});
      expect(calls.map((call) => call.method), ['runOutboxOnceNow']);
    },
  );
}
