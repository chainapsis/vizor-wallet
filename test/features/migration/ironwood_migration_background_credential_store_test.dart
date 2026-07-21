import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('manifest round-trips through scoped secure storage', () async {
    final store = IronwoodMigrationBackgroundCredentialStore.testing(
      storage: const FlutterSecureStorage(),
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );

    final prepared = await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );

    expect(
      IronwoodMigrationBackgroundCredentialStore.storageKey(
        network: 'test',
        accountUuid: 'account-1',
      ),
      'test:account-1',
    );
    expect(prepared.version, 1);
    expect(
      prepared.credentialHex,
      '000102030405060708090a0b0c0d0e0f'
      '101112131415161718191a1b1c1d1e1f',
    );
    expect(prepared.saltBase64, base64Encode(List<int>.generate(16, (i) => i)));
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
  });

  test('manifest decoding rejects non-strict or invalid values', () {
    final valid = <String, Object?>{
      'version': 1,
      'network': 'main',
      'accountUuid': 'account-1',
      'dbPath': '/tmp/wallet.db',
      'lightwalletdUrl': 'https://lwd.example:443',
      'credentialHex': List.filled(32, 'ab').join(),
      'saltBase64': base64Encode(List<int>.filled(16, 7)),
      'expectedRunId': null,
    };

    expect(
      IronwoodMigrationBackgroundCredentialManifest.decode(
        jsonEncode(valid),
      ).encode(),
      jsonEncode(valid),
    );

    final invalidManifests = <Object?>[
      {...valid, 'extra': true},
      {...valid}..remove('dbPath'),
      {...valid, 'version': '1'},
      {...valid, 'network': 'unknown'},
      {...valid, 'accountUuid': ''},
      {...valid, 'credentialHex': List.filled(32, 'AB').join()},
      {...valid, 'credentialHex': List.filled(31, 'ab').join()},
      {...valid, 'saltBase64': base64Encode(List<int>.filled(15, 7))},
      {...valid, 'saltBase64': 'not-base64'},
      {...valid, 'expectedRunId': ''},
      {...valid, 'expectedRunId': 7},
      const <Object?>[],
    ];

    for (final invalid in invalidManifests) {
      expect(
        () => IronwoodMigrationBackgroundCredentialManifest.decode(
          jsonEncode(invalid),
        ),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test('stored manifest must match its network and account scope', () async {
    final raw = IronwoodMigrationBackgroundCredentialManifest(
      version: 1,
      network: 'main',
      accountUuid: 'account-2',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
      credentialHex: List.filled(32, 'ab').join(),
      saltBase64: base64Encode(List<int>.filled(16, 7)),
      expectedRunId: null,
    ).encode();
    FlutterSecureStorage.setMockInitialValues({'test:account-1': raw});
    final store = IronwoodMigrationBackgroundCredentialStore.testing(
      storage: const FlutterSecureStorage(),
      randomBytes: (length) => Uint8List(length),
    );

    expect(
      () => store.read(network: 'test', accountUuid: 'account-1'),
      throwsFormatException,
    );
  });

  test('binding a different run id fails closed', () async {
    final store = IronwoodMigrationBackgroundCredentialStore.testing(
      storage: const FlutterSecureStorage(),
      randomBytes: (length) => Uint8List(length),
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
      throwsA(isA<IronwoodMigrationBackgroundCredentialRunMismatchException>()),
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
    await lifecycle.resumeAfterFailedMutation();

    expect(calls.map((call) => call.method), ['quiesce', 'resume']);
  });

  test('Android quiesce retains the credential until revocation commits', () async {
    final storage = FlutterSecureStorage();
    final store = IronwoodMigrationBackgroundCredentialStore.testing(
      storage: storage,
      randomBytes: (length) => Uint8List(length),
    );
    final lifecycle = IronwoodMigrationBackgroundLifecycle(
      credentialStore: store,
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

    await lifecycle.revokeAccount(
      network: 'test',
      accountUuid: 'account-1',
    );
    expect(
      await store.read(network: 'test', accountUuid: 'account-1'),
      isNull,
    );
  });

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
