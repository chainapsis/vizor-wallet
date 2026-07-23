import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_manifest_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('manifest round-trips through scoped secure storage', () async {
    final store = IronwoodMigrationBackgroundManifestStore.testing(
      storage: const FlutterSecureStorage(),
    );

    final prepared = await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );

    expect(
      IronwoodMigrationBackgroundManifestStore.storageKey(
        network: 'test',
        accountUuid: 'account-1',
      ),
      'test:account-1',
    );
    expect(prepared.version, 1);
    expect(prepared.expectedRunId, isNull);
    expect(
      await store.read(network: 'test', accountUuid: 'account-1'),
      prepared,
    );

    expect(
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      ),
      isTrue,
    );
    expect(
      (await store.read(
        network: 'test',
        accountUuid: 'account-1',
      ))?.expectedRunId,
      'run-1',
    );
    expect(
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      ),
      isFalse,
    );

    final relocated = await store.replaceDbPath(
      network: 'test',
      accountUuid: 'account-1',
      expectedDbPath: '/tmp/wallet.db',
      dbPath: '/new-container/wallet.db',
    );
    expect(relocated.dbPath, '/new-container/wallet.db');
    expect(relocated.expectedRunId, 'run-1');
  });

  test('manifest decoding rejects non-strict or invalid values', () {
    final valid = <String, Object?>{
      'version': 1,
      'network': 'main',
      'accountUuid': 'account-1',
      'dbPath': '/tmp/wallet.db',
      'lightwalletdUrl': 'https://lwd.example:443',
      'expectedRunId': null,
    };

    expect(
      IronwoodMigrationBackgroundManifest.decode(jsonEncode(valid)).encode(),
      jsonEncode(valid),
    );

    final invalidManifests = <Object?>[
      {...valid, 'extra': true},
      {...valid}..remove('dbPath'),
      {...valid, 'version': '1'},
      {...valid, 'network': 'unknown'},
      {...valid, 'accountUuid': ''},
      {...valid, 'expectedRunId': ''},
      {...valid, 'expectedRunId': 7},
      const <Object?>[],
    ];

    for (final invalid in invalidManifests) {
      expect(
        () => IronwoodMigrationBackgroundManifest.decode(jsonEncode(invalid)),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test('stored manifest must match its network and account scope', () async {
    final raw = IronwoodMigrationBackgroundManifest(
      version: 1,
      network: 'main',
      accountUuid: 'account-2',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
      expectedRunId: null,
    ).encode();
    FlutterSecureStorage.setMockInitialValues({'test:account-1': raw});
    final store = IronwoodMigrationBackgroundManifestStore.testing(
      storage: const FlutterSecureStorage(),
    );

    expect(
      () => store.read(network: 'test', accountUuid: 'account-1'),
      throwsFormatException,
    );
  });

  test('binding a different run id fails closed', () async {
    final store = IronwoodMigrationBackgroundManifestStore.testing(
      storage: const FlutterSecureStorage(),
    );
    await store.prepare(
      network: 'main',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );
    await store.bindExpectedRunId(
      network: 'main',
      accountUuid: 'account-1',
      expectedRunId: 'run-1',
    );

    expect(
      () => store.bindExpectedRunId(
        network: 'main',
        accountUuid: 'account-1',
        expectedRunId: 'run-2',
      ),
      throwsA(isA<IronwoodMigrationBackgroundManifestRunMismatchException>()),
    );
  });

  test(
    'iOS account revocation waits for native lifecycle completion',
    () async {
      const channel = MethodChannel('test/background_migration/revoke_account');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final lifecycle = IronwoodMigrationBackgroundLifecycle(
        channel: channel,
        isIOS: true,
        isAndroid: false,
      );

      await lifecycle.revokeAccount(network: 'test', accountUuid: 'account-1');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'revokeAccount');
      expect(calls.single.arguments, {
        'network': 'test',
        'accountUuid': 'account-1',
      });
    },
  );

  test('iOS quiesce and resume use separate native lifecycle steps', () async {
    const channel = MethodChannel('test/background_migration/quiesce');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      channel: channel,
      isIOS: true,
      isAndroid: false,
    );

    await lifecycle.quiesce();
    await lifecycle.resumeAfterMutation();

    expect(calls.map((call) => call.method), ['quiesce', 'resume']);
  });

  test('iOS migration resume retries a transient channel failure', () async {
    const channel = MethodChannel('test/background_migration/resume_retry');
    var resumeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'resume') return true;
          resumeCalls += 1;
          if (resumeCalls == 1) {
            throw PlatformException(code: 'temporarily_unavailable');
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      channel: channel,
      isIOS: true,
      isAndroid: false,
      resumeRetryDelays: const [Duration.zero, Duration.zero],
    );

    await lifecycle.resumeAfterMutation();

    expect(resumeCalls, 2);
  });

  test('caller-managed quiescence stays scoped to its async action', () async {
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      isIOS: false,
      isAndroid: false,
    );

    expect(lifecycle.isQuiescenceManagedByCaller, isFalse);
    await lifecycle.runWithCallerManagedQuiescence(() async {
      expect(lifecycle.isQuiescenceManagedByCaller, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(lifecycle.isQuiescenceManagedByCaller, isTrue);
    });
    expect(lifecycle.isQuiescenceManagedByCaller, isFalse);
  });

  test(
    'Android quiesce retains the manifest until revocation commits',
    () async {
      final storage = FlutterSecureStorage();
      final store = IronwoodMigrationBackgroundManifestStore.testing(
        storage: storage,
      );
      final lifecycle = IronwoodMigrationBackgroundLifecycle(
        manifestStore: store,
        isIOS: false,
        isAndroid: true,
      );
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lwd.example:443',
      );

      await lifecycle.quiesce();
      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNotNull,
      );

      await lifecycle.revokeAccount(network: 'test', accountUuid: 'account-1');
      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNull,
      );
    },
  );

  test('iOS wallet reset fails closed when native revocation fails', () async {
    const channel = MethodChannel('test/background_migration/revoke_all');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      channel: channel,
      isIOS: true,
      isAndroid: false,
    );

    await expectLater(lifecycle.revokeAll(), throwsStateError);
  });
}
