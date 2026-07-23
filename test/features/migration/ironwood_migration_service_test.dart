import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_operation_registry.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/rust/api/keystone.dart' as rust_keystone;
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'status resolves wallet db path before calling Rust status API',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          seenDbPath = dbPath;
          seenNetwork = network;
          seenAccountUuid = accountUuid;
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
      );

      await service.status(network: 'test', accountUuid: 'account-1');

      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'privatePlan resolves wallet db path before calling Rust plan API',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = rust_sync.OrchardMigrationPrivatePlan(
        targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
        totalInputZatoshi: BigInt.from(100020000),
        totalMigratableZatoshi: BigInt.from(100000000),
        denominationSplitFeeZatoshi: BigInt.from(10000),
        migrationFeeZatoshi: BigInt.from(10000),
        estimatedTotalFeeZatoshi: BigInt.from(20000),
        plannedBatchCount: 1,
        denominationSplitStageCount: 1,
        signingBatchLimit: 50,
        scheduleMeanDelayBlocks: 144,
        scheduleMaxDelayBlocks: 576,
        scheduledTransfers: const [],
        maxPreparedNotesPerRun: 64,
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              seenDbPath = dbPath;
              seenNetwork = network;
              seenAccountUuid = accountUuid;
              return Future.value(expected);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
      );

      final plan = await service.privatePlan(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(plan, expected);
      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'startSoftwarePrivateMigration reuses pending tx salt and zeroizes mnemonic bytes',
    () async {
      final returnedMnemonicBytes = <Uint8List>[];
      final seenSalts = <String>[];
      final seenMnemonicPayloads = <List<int>>[];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        getMnemonicBytesForAccount: (_) async {
          final bytes = Uint8List.fromList([1, 2, 3, 4]);
          returnedMnemonicBytes.add(bytes);
          return bytes;
        },
        isMacOS: () => false,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) {
              seenSalts.add(saltBase64);
              seenMnemonicPayloads.add(List<int>.from(mnemonicBytes));
              return Future.value(_migrationResult());
            },
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );
      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(seenSalts, hasLength(2));
      expect(seenSalts[1], seenSalts[0]);
      expect(seenMnemonicPayloads, [
        [1, 2, 3, 4],
        [1, 2, 3, 4],
      ]);
      expect(returnedMnemonicBytes, hasLength(2));
      for (final bytes in returnedMnemonicBytes) {
        expect(bytes, everyElement(0));
      }
    },
  );

  test(
    'iOS software start hands confirmation waiting to background preparation',
    () async {
      var preparationStartCount = 0;
      final events = <String>[];
      final statuses = [
        _migrationStatus(),
        _migrationStatus(
          phase: 'waiting_denom_confirmations',
          activeRunId: 'run-1',
        ),
      ];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: _backgroundCredentialStore(),
        getEndpoint: _testEndpoint,
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2, 3]),
        isMacOS: () => false,
        isMobile: () => true,
        isIOS: () => true,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          events.add('startBackgroundPreparation');
          return true;
        },
        requestNotificationAuthorization: () async => true,
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('prepareOutbox');
              return _migrationResult(status: 'ready_to_migrate');
            },
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) async => _migrationResult(status: 'waiting_denom_confirmations'),
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(preparationStartCount, 1);
      expect(events, ['startBackgroundPreparation']);
    },
  );

  test(
    'iOS software start does not start preparation after denomination is ready',
    () async {
      var preparationStartCount = 0;
      final statuses = [
        _migrationStatus(),
        _migrationStatus(phase: 'ready_to_migrate', activeRunId: 'run-1'),
        _migrationStatus(phase: 'ready_to_migrate', activeRunId: 'run-1'),
      ];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: _backgroundCredentialStore(),
        getEndpoint: _testEndpoint,
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2, 3]),
        isMacOS: () => false,
        isMobile: () => true,
        isIOS: () => true,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
        requestNotificationAuthorization: () async => true,
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(status: 'ready_to_migrate'),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) async => _migrationResult(status: 'waiting_denom_confirmations'),
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(preparationStartCount, 0);
    },
  );

  test(
    'iOS software continuation resumes background denomination preparation',
    () async {
      var preparationStartCount = 0;
      final store = await _boundBackgroundCredentialStore();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            _migrationStatus(
              phase: 'waiting_denom_confirmations',
              activeRunId: 'run-1',
            ),
          );
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => 'test-password',
        isHardwareAccount: (_) => false,
        isMacOS: () => false,
        isMobile: () => true,
        isIOS: () => true,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(status: 'waiting_denom_confirmations'),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
      );

      await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');

      expect(preparationStartCount, 1);
    },
  );

  test(
    'explicit iOS software migration start requests notification authorization',
    () async {
      const channel = MethodChannel('com.zcash.wallet/background_migration');
      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methodCalls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = _notificationAuthorizationService(
        isIOS: true,
        statuses: [
          _migrationStatus(),
          _migrationStatus(activeRunId: 'run-1'),
          _migrationStatus(activeRunId: 'run-1'),
        ],
      );

      final result = await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(result.status, 'broadcasted');
      expect(methodCalls, hasLength(1));
      expect(methodCalls.single.method, 'requestNotificationAuthorization');
    },
  );

  test(
    'notification authorization refusal does not fail software migration',
    () async {
      var requestCount = 0;
      final service = _notificationAuthorizationService(
        isIOS: true,
        statuses: [
          _migrationStatus(),
          _migrationStatus(activeRunId: 'run-1'),
          _migrationStatus(activeRunId: 'run-1'),
        ],
        requestNotificationAuthorization: () async {
          requestCount++;
          return false;
        },
      );

      final result = await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(result.status, 'broadcasted');
      expect(requestCount, 1);
    },
  );

  test(
    'notification authorization failure is best effort for software migration',
    () async {
      var requestCount = 0;
      final service = _notificationAuthorizationService(
        isIOS: true,
        statuses: [
          _migrationStatus(),
          _migrationStatus(activeRunId: 'run-1'),
          _migrationStatus(activeRunId: 'run-1'),
        ],
        requestNotificationAuthorization: () async {
          requestCount++;
          throw StateError('authorization unavailable');
        },
      );

      final result = await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(result.status, 'broadcasted');
      expect(requestCount, 1);
    },
  );

  test('non-iOS software migration does not request authorization', () async {
    var requestCount = 0;
    final service = _notificationAuthorizationService(
      isIOS: false,
      statuses: [
        _migrationStatus(),
        _migrationStatus(activeRunId: 'run-1'),
      ],
      requestNotificationAuthorization: () async {
        requestCount++;
        return true;
      },
    );

    final result = await service.startSoftwarePrivateMigration(
      accountUuid: 'account-1',
      approvedSchedule: const [],
    );

    expect(result.status, 'broadcasted');
    expect(requestCount, 0);
  });

  test(
    'software start without an active run does not request authorization',
    () async {
      var requestCount = 0;
      final service = _notificationAuthorizationService(
        isIOS: true,
        statuses: [_migrationStatus(), _migrationStatus()],
        requestNotificationAuthorization: () async {
          requestCount++;
          return true;
        },
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(requestCount, 0);
    },
  );

  test('status polling does not request notification authorization', () async {
    var requestCount = 0;
    final service = _notificationAuthorizationService(
      isIOS: true,
      statuses: [_migrationStatus(activeRunId: 'run-1')],
      requestNotificationAuthorization: () async {
        requestCount++;
        return true;
      },
    );

    await service.status(network: 'test', accountUuid: 'account-1');

    expect(requestCount, 0);
  });

  test(
    'iOS software status restores preparation only for a bound waiting run',
    () async {
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lwd.example:443',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var preparationStartCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'waiting_denom_confirmations',
                  activeRunId: 'run-1',
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        isMobile: () => true,
        isIOS: () => true,
        isHardwareAccount: (_) => false,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
      );

      await service.status(network: 'test', accountUuid: 'account-1');

      expect(preparationStartCount, 1);
    },
  );

  test('iOS hardware status does not restore preparation', () async {
    final store = _backgroundCredentialStore();
    await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );
    await store.bindExpectedRunId(
      network: 'test',
      accountUuid: 'account-1',
      expectedRunId: 'run-1',
    );
    var preparationStartCount = 0;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(
                phase: 'waiting_denom_confirmations',
                activeRunId: 'run-1',
              ),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: store,
      isMobile: () => true,
      isIOS: () => true,
      isHardwareAccount: (_) => true,
      startBackgroundPreparation: () async {
        preparationStartCount++;
        return true;
      },
    );

    await service.status(network: 'test', accountUuid: 'account-1');

    expect(preparationStartCount, 0);
  });

  test('account revocation waits for an in-flight migration start', () async {
    final registry = IronwoodMigrationOperationRegistry();
    final started = Completer<void>();
    final finish = Completer<void>();
    var startCount = 0;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      getSessionPassword: () => 'test-password',
      isMacOS: () => true,
      operationRegistry: registry,
      startMacosSoftwareMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
            required approvedSchedule,
          }) async {
            startCount += 1;
            started.complete();
            await finish.future;
            return _migrationResult();
          },
    );

    final migration = service.startSoftwarePrivateMigration(
      accountUuid: 'account-1',
      approvedSchedule: const [],
    );
    await started.future;

    var revocationCompleted = false;
    final revocationFuture = registry
        .revokeAndWait(network: 'test', accountUuid: 'account-1')
        .then((value) {
          revocationCompleted = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(revocationCompleted, isFalse);

    finish.complete();
    await migration;
    final revocation = await revocationFuture;
    revocation.commit();

    await expectLater(
      service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      ),
      throwsA(isA<IronwoodMigrationAccountRevokedException>()),
    );
    expect(startCount, 1);
  });

  test(
    'startSoftwarePrivateMigration uses macOS stored mnemonic path',
    () async {
      String? seenPassword;
      String? seenSalt;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        getMnemonicBytesForAccount: (_) =>
            throw StateError('mnemonic bytes should not be read on macOS'),
        isMacOS: () => true,
        startMacosSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required password,
              required saltBase64,
            }) {
              seenPassword = password;
              seenSalt = saltBase64;
              return Future.value(_migrationResult());
            },
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) => throw StateError('in-memory mnemonic path should not run'),
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(seenPassword, 'test-password');
      expect(seenSalt, isNotEmpty);
    },
  );

  test('hardware continuation reuses pending tx salt for broadcast', () async {
    final seenSalts = <String>[];
    String? seenPassword;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => const RpcEndpointConfig(
        networkName: 'test',
        lightwalletdUrl: 'https://lwd.example:443',
      ),
      getSessionPassword: () => 'test-password',
      isHardwareAccount: (_) => true,
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            seenPassword = password;
            seenSalts.add(saltBase64);
            return Future.value(_migrationResult());
          },
    );

    await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');
    await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');

    expect(seenPassword, 'test-password');
    expect(seenSalts, hasLength(2));
    expect(seenSalts[1], seenSalts[0]);
  });

  test('software continuation re-enters the macOS signing path', () async {
    List<rust_sync.MigrationScheduledTransfer>? seenSchedule;
    String? seenSalt;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: () => const RpcEndpointConfig(
        networkName: 'test',
        lightwalletdUrl: 'https://lwd.example:443',
      ),
      getSessionPassword: () => 'test-password',
      isHardwareAccount: (_) => false,
      isMacOS: () => true,
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            return Future.value(_migrationResult(status: 'ready_to_migrate'));
          },
      startMacosSoftwareMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
            required approvedSchedule,
          }) {
            seenSchedule = approvedSchedule;
            seenSalt = saltBase64;
            return Future.value(_migrationResult());
          },
    );

    await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');

    expect(seenSchedule, isEmpty);
    expect(seenSalt, isNotEmpty);
  });

  test(
    'prepareKeystoneDenominationPrivateMigration prepares signing request',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = _keystoneSigningRequest();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        prepareKeystoneDenominationMigration:
            ({required dbPath, required network, required accountUuid}) {
              seenDbPath = dbPath;
              seenNetwork = network;
              seenAccountUuid = accountUuid;
              return Future.value(expected);
            },
      );

      final request = await service.prepareKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
      );

      expect(request, expected);
      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'completeKeystoneDenominationPrivateMigration reuses pending tx salt',
    () async {
      final seenSalts = <String>[];
      final seenMessages = <List<rust_sync.KeystoneSignedMigrationMessage>>[];
      final seenSchedules = <List<rust_sync.MigrationScheduledTransfer>>[];
      String? seenRequestId;
      String? seenPassword;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        completeKeystoneDenominationMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
              required approvedSchedule,
            }) {
              seenRequestId = requestId;
              seenPassword = password;
              seenSalts.add(saltBase64);
              seenMessages.add(signedMessages);
              seenSchedules.add(approvedSchedule);
              return Future.value(_migrationResult());
            },
      );
      final signedMessages = [_signedMigrationMessage()];
      final approvedSchedule = [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(10_000_000),
          blockOffset: 144,
        ),
      ];

      await service.completeKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: signedMessages,
        approvedSchedule: approvedSchedule,
      );
      await service.completeKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: signedMessages,
        approvedSchedule: approvedSchedule,
      );

      expect(seenRequestId, 'request-1');
      expect(seenPassword, 'test-password');
      expect(seenMessages, [signedMessages, signedMessages]);
      expect(seenSchedules, [approvedSchedule, approvedSchedule]);
      expect(seenSalts, hasLength(2));
      expect(seenSalts[1], seenSalts[0]);
    },
  );

  test(
    'prepareKeystoneBatchPrivateMigration prepares signing request',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      final expected = _keystoneSigningRequest();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        prepareKeystoneBatchMigration:
            ({required dbPath, required network, required accountUuid}) {
              seenDbPath = dbPath;
              seenNetwork = network;
              seenAccountUuid = accountUuid;
              return Future.value(expected);
            },
      );

      final request = await service.prepareKeystoneBatchPrivateMigration(
        accountUuid: 'account-1',
      );

      expect(request, expected);
      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
    },
  );

  test(
    'completeKeystoneBatchPrivateMigration reuses pending tx salt',
    () async {
      final seenSalts = <String>[];
      final seenMessages = <List<rust_sync.KeystoneSignedMigrationMessage>>[];
      String? seenRequestId;
      String? seenPassword;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: () => const RpcEndpointConfig(
          networkName: 'test',
          lightwalletdUrl: 'https://lwd.example:443',
        ),
        getSessionPassword: () => 'test-password',
        completeKeystoneBatchMigration:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
            }) {
              seenRequestId = requestId;
              seenPassword = password;
              seenSalts.add(saltBase64);
              seenMessages.add(signedMessages);
              return Future.value(_migrationResult());
            },
      );
      final signedMessages = [_signedMigrationMessage()];

      await service.completeKeystoneBatchPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: signedMessages,
      );
      await service.completeKeystoneBatchPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: signedMessages,
      );

      expect(seenRequestId, 'request-1');
      expect(seenPassword, 'test-password');
      expect(seenMessages, [signedMessages, signedMessages]);
      expect(seenSalts, hasLength(2));
      expect(seenSalts[1], seenSalts[0]);
    },
  );

  test('discardKeystonePrivateMigrationRequest discards request id', () async {
    String? seenRequestId;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      discardKeystoneMigrationRequest: ({required requestId}) {
        seenRequestId = requestId;
        return Future.value();
      },
    );

    await service.discardKeystonePrivateMigrationRequest(
      accountUuid: 'account-1',
      requestId: 'request-1',
    );

    expect(seenRequestId, 'request-1');
  });

  test('keystoneProofStatus forwards request id', () async {
    String? seenRequestId;
    const expected = rust_sync.KeystoneMigrationProofStatus(
      readyCount: 1,
      totalCount: 2,
      isReady: false,
      isFailed: false,
    );
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus());
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getKeystoneProofStatus: ({required requestId}) {
        seenRequestId = requestId;
        return Future.value(expected);
      },
    );

    final status = await service.keystoneProofStatus(requestId: 'request-1');

    expect(status, expected);
    expect(seenRequestId, 'request-1');
  });

  test(
    'iOS status recovers a verified outbox when manifest is missing',
    () async {
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(
          activeRunId: 'legacy-run',
          parts: [_migrationPart(txidHex: 'persisted-tx')],
        ),
        _migrationStatus(phase: 'complete'),
      ];
      Map<String, Object?>? recovery;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: _backgroundCredentialStore(),
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        isMobile: () => true,
        isIOS: () => true,
        isHardwareAccount: (_) => true,
        recoverMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required lightwalletdUrl,
              required expectedTxids,
            }) async {
              recovery = {
                'batchId': batchId,
                'network': network,
                'accountUuid': accountUuid,
                'runId': runId,
                'lightwalletdUrl': lightwalletdUrl,
                'expectedTxids': expectedTxids,
              };
              return true;
            },
        runMigrationOutboxOnceNow: () async =>
            const IronwoodMigrationOutboxRunResult(
              outcome: IronwoodMigrationOutboxRunOutcome.noWork,
            ),
        listMigrationOutboxReceipts: () async => const [],
        requestNotificationAuthorization: () async => true,
      );

      final status = await service.status(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(status.phase, 'complete');
      expect(recovery, {
        'batchId': 'test:account-1:legacy-run',
        'network': 'test',
        'accountUuid': 'account-1',
        'runId': 'legacy-run',
        'lightwalletdUrl': 'https://lwd.example:443',
        'expectedTxids': ['persisted-tx'],
      });
    },
  );

  test(
    'active mobile run never falls back to the session credential',
    () async {
      var sessionCredentialRead = false;
      var broadcastCalled = false;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: _backgroundCredentialStore(),
        getEndpoint: _testEndpoint,
        getSessionPassword: () {
          sessionCredentialRead = true;
          return 'session-password';
        },
        isMobile: () => true,
        broadcastDueMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              broadcastCalled = true;
              return _migrationResult();
            },
      );

      await expectLater(
        service.continueSoftwarePrivateMigration(accountUuid: 'account-1'),
        throwsA(isA<StateError>()),
      );
      expect(sessionCredentialRead, isFalse);
      expect(broadcastCalled, isFalse);
    },
  );

  test(
    'mobile new run stores random credential and binds before outbox staging',
    () async {
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(),
        _migrationStatus(activeRunId: 'run-1'),
        _migrationStatus(activeRunId: 'run-1'),
      ];
      final store = _backgroundCredentialStore();
      var scheduledCount = 0;
      String? seenPassword;
      String? seenSalt;
      String? expectedRunIdDuringStart;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2, 3]),
        isMobile: () => true,
        isMacOS: () => false,
        scheduleBackgroundMigration: () async {
          scheduledCount++;
          return true;
        },
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) async {
              expectedRunIdDuringStart = (await store.read(
                network: network,
                accountUuid: accountUuid,
              ))?.expectedRunId;
              seenPassword = password;
              seenSalt = saltBase64;
              return _migrationResult();
            },
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      final manifest = await store.read(
        network: 'test',
        accountUuid: 'account-1',
      );
      expect(expectedRunIdDuringStart, isNull);
      expect(seenPassword, List.filled(32, '01').join());
      expect(seenSalt, 'AQEBAQEBAQEBAQEBAQEBAQ==');
      expect(manifest?.expectedRunId, 'run-1');
      expect(scheduledCount, 0);
    },
  );

  test(
    'mobile status cannot delete a provisional credential while start is in flight',
    () async {
      final store = _backgroundCredentialStore();
      final startEntered = Completer<void>();
      final releaseStart = Completer<void>();
      var runCreated = false;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            _migrationStatus(activeRunId: runCreated ? 'run-1' : null),
          );
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1]),
        isMobile: () => true,
        isMacOS: () => false,
        scheduleBackgroundMigration: () async => true,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) async {
              startEntered.complete();
              await releaseStart.future;
              runCreated = true;
              return _migrationResult();
            },
      );

      final startFuture = service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );
      await startEntered.future;

      final statusFuture = service.status(
        network: 'test',
        accountUuid: 'account-1',
      );
      releaseStart.complete();

      await startFuture;
      await statusFuture;
      expect(
        (await store.read(
          network: 'test',
          accountUuid: 'account-1',
        ))?.expectedRunId,
        'run-1',
      );
    },
  );

  test(
    'mobile status does not schedule a bound manifest without staged outbox work',
    () async {
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lwd.example:443',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var scheduleAttempts = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        isMobile: () => true,
        scheduleBackgroundMigration: () async => ++scheduleAttempts > 1,
      );

      await service.status(network: 'test', accountUuid: 'account-1');
      await service.status(network: 'test', accountUuid: 'account-1');
      await service.status(network: 'test', accountUuid: 'account-1');

      expect(scheduleAttempts, 0);
    },
  );

  test(
    'mobile failed start with no active run deletes provisional manifest',
    () async {
      final store = _backgroundCredentialStore();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus());
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1]),
        isMobile: () => true,
        isMacOS: () => false,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) => Future.error(StateError('start failed')),
      );

      await expectLater(
        service.startSoftwarePrivateMigration(
          accountUuid: 'account-1',
          approvedSchedule: const [],
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNull,
      );
    },
  );

  test(
    'background retry is unavailable on unsupported mobile platforms',
    () async {
      var scheduleCalls = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        supportsBackgroundMigration: () => false,
        scheduleBackgroundMigration: () async {
          scheduleCalls++;
          return true;
        },
      );

      expect(service.supportsBackgroundMigrationRetry, isFalse);
      expect(
        await service.retryPrivateMigrationInBackground(
          accountUuid: 'account-1',
        ),
        isFalse,
      );
      expect(scheduleCalls, 0);
    },
  );

  test('background retry requires a manifest for the active run', () async {
    var scheduleCalls = 0;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus(activeRunId: 'run-1'));
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: _backgroundCredentialStore(),
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      supportsBackgroundMigration: () => true,
      scheduleBackgroundMigration: () async {
        scheduleCalls++;
        return true;
      },
    );

    expect(
      await service.retryPrivateMigrationInBackground(accountUuid: 'account-1'),
      isFalse,
    );
    expect(scheduleCalls, 0);
  });

  test('background retry stages and arms the bound manifest outbox', () async {
    final store = _backgroundCredentialStore();
    await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );
    var armCalls = 0;
    var notificationAuthorizationRequestCount = 0;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus(activeRunId: 'run-1'));
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: store,
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      supportsBackgroundMigration: () => true,
      requestNotificationAuthorization: () async {
        notificationAuthorizationRequestCount++;
        return true;
      },
      listMigrationOutboxReceipts: () async => const [],
      prepareMigrationOutbox:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async => _migrationResult(),
      exportMigrationOutbox:
          ({
            required dbPath,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async => _outboxBatch(),
      stageMigrationOutboxBatch: (_) async => const {'txid-1': 'digest-1'},
      armMigrationOutboxBatch:
          ({required batchId, required expectedDigests}) async {
            armCalls++;
            return true;
          },
      runMigrationOutboxOnceNow: () async =>
          const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.waiting,
          ),
    );

    expect(
      await service.retryPrivateMigrationInBackground(accountUuid: 'account-1'),
      isTrue,
    );
    expect(armCalls, 1);
    expect(notificationAuthorizationRequestCount, 1);
    expect(
      (await store.read(
        network: 'test',
        accountUuid: 'account-1',
      ))?.expectedRunId,
      'run-1',
    );
  });

  test(
    'mobile ambiguous failed start retains and binds its credential',
    () async {
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(),
        _migrationStatus(activeRunId: 'run-after-error'),
      ];
      final store = _backgroundCredentialStore();
      var scheduledCount = 0;
      var notificationAuthorizationRequestCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1]),
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        requestNotificationAuthorization: () async {
          notificationAuthorizationRequestCount++;
          return true;
        },
        scheduleBackgroundMigration: () async {
          scheduledCount++;
          return true;
        },
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required approvedSchedule,
              required mnemonicBytes,
              required password,
              required saltBase64,
            }) => Future.error(StateError('ambiguous failure')),
      );

      await expectLater(
        service.startSoftwarePrivateMigration(
          accountUuid: 'account-1',
          approvedSchedule: const [],
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await store.read(
          network: 'test',
          accountUuid: 'account-1',
        ))?.expectedRunId,
        'run-after-error',
      );
      expect(scheduledCount, 0);
      expect(notificationAuthorizationRequestCount, 1);
    },
  );

  test('mobile active run id mismatch fails closed before Rust call', () async {
    final store = _backgroundCredentialStore();
    await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
    );
    await store.bindExpectedRunId(
      network: 'test',
      accountUuid: 'account-1',
      expectedRunId: 'run-1',
    );
    var rustCalled = false;
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus(activeRunId: 'run-2'));
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) {
            return Future.value(null);
          },
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: store,
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isHardwareAccount: (_) => true,
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) {
            rustCalled = true;
            return Future.value(_migrationResult());
          },
    );

    await expectLater(
      service.continueSoftwarePrivateMigration(accountUuid: 'account-1'),
      throwsA(isA<IronwoodMigrationBackgroundCredentialRunMismatchException>()),
    );
    expect(rustCalled, isFalse);
  });

  test(
    'iOS active run rebinds the same wallet DB after container relocation',
    () async {
      const oldDbPath =
          '/old-container/Application Support/zcash_wallet_abc.db';
      const currentDbPath =
          '/new-container/Application Support/zcash_wallet_abc.db';
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: oldDbPath,
        lightwalletdUrl: 'https://lwd.example:443',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var scheduledCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => currentDbPath,
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        isMobile: () => true,
        isIOS: () => true,
        scheduleBackgroundMigration: () async {
          scheduledCount++;
          return true;
        },
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
      );

      await service.status(network: 'test', accountUuid: 'account-1');

      expect(
        (await store.read(network: 'test', accountUuid: 'account-1'))?.dbPath,
        currentDbPath,
      );
      expect(scheduledCount, 0);
    },
  );

  test(
    'iOS active run rejects a different wallet DB after relocation',
    () async {
      const oldDbPath =
          '/old-container/Application Support/zcash_wallet_abc.db';
      const currentDbPath =
          '/new-container/Application Support/zcash_wallet_other.db';
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: oldDbPath,
        lightwalletdUrl: 'https://lwd.example:443',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var scheduledCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => currentDbPath,
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        isMobile: () => true,
        isIOS: () => true,
        scheduleBackgroundMigration: () async {
          scheduledCount++;
          return true;
        },
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
      );

      await expectLater(
        service.status(network: 'test', accountUuid: 'account-1'),
        throwsA(isA<StateError>()),
      );

      expect(
        (await store.read(network: 'test', accountUuid: 'account-1'))?.dbPath,
        oldDbPath,
      );
      expect(scheduledCount, 0);
    },
  );

  test(
    'Keystone prepare stays silent and completions enroll notifications',
    () async {
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(),
        _migrationStatus(activeRunId: 'keystone-run'),
        _migrationStatus(activeRunId: 'keystone-run'),
        _migrationStatus(activeRunId: 'keystone-run'),
      ];
      final store = _backgroundCredentialStore();
      final credentials = <String>[];
      var scheduledCount = 0;
      var notificationAuthorizationRequestCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        isMobile: () => true,
        isIOS: () => true,
        requestNotificationAuthorization: () async {
          notificationAuthorizationRequestCount++;
          return true;
        },
        scheduleBackgroundMigration: () async {
          scheduledCount++;
          return true;
        },
        listMigrationOutboxReceipts: () async => const [],
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _migrationResult(),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
        prepareKeystoneDenominationMigration:
            ({required dbPath, required network, required accountUuid}) async =>
                _keystoneSigningRequest(),
        completeKeystoneDenominationMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
              required approvedSchedule,
            }) async {
              credentials.add('$password:$saltBase64');
              return _migrationResult();
            },
        prepareKeystoneBatchMigration:
            ({required dbPath, required network, required accountUuid}) async =>
                _keystoneSigningRequest(),
        completeKeystoneBatchMigration:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required requestId,
              required signedMessages,
              required password,
              required saltBase64,
            }) async {
              credentials.add('$password:$saltBase64');
              return _migrationResult();
            },
      );

      await service.prepareKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
      );
      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNull,
      );
      await service.completeKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: [_signedMigrationMessage()],
        approvedSchedule: const [],
      );
      await service.prepareKeystoneBatchPrivateMigration(
        accountUuid: 'account-1',
      );
      await service.completeKeystoneBatchPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-2',
        signedMessages: [_signedMigrationMessage()],
      );

      expect(credentials, hasLength(2));
      expect(credentials[1], credentials[0]);
      expect(scheduledCount, 0);
      expect(notificationAuthorizationRequestCount, 2);
    },
  );

  test(
    'iOS stages and arms typed outbox payload after foreground preparation',
    () async {
      const channel = MethodChannel('com.zcash.wallet/background_migration');
      final events = <String>[];
      Map<Object?, Object?>? stagedPayload;
      Map<Object?, Object?>? armedPayload;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            events.add(call.method);
            switch (call.method) {
              case 'listOutboxReceipts':
                return <Object?>[];
              case 'stageOutboxBatch':
                stagedPayload = call.arguments as Map<Object?, Object?>;
                return <String, String>{'txid-1': 'digest-1'};
              case 'armOutboxBatch':
                armedPayload = call.arguments as Map<Object?, Object?>;
                return true;
              case 'requestNotificationAuthorization':
                return true;
              case 'runOutboxOnceNow':
                return <String, Object?>{'outcome': 'waiting'};
            }
            throw StateError('Unexpected method ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(),
        _migrationStatus(activeRunId: 'run-1'),
        _migrationStatus(activeRunId: 'run-1'),
      ];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(statuses.removeAt(0));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: _backgroundCredentialStore(),
        getEndpoint: _testEndpoint,
        getSessionPassword: () => throw StateError('session password used'),
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2, 3]),
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        startSoftwareMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required mnemonicBytes,
              required password,
              required saltBase64,
              required approvedSchedule,
            }) async {
              events.add('credentialOperation');
              return _migrationResult();
            },
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('prepareOutbox');
              return _migrationResult();
            },
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('exportOutbox');
              return _outboxBatch();
            },
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(events, [
        'listOutboxReceipts',
        'credentialOperation',
        'listOutboxReceipts',
        'prepareOutbox',
        'exportOutbox',
        'stageOutboxBatch',
        'armOutboxBatch',
        'runOutboxOnceNow',
        'listOutboxReceipts',
        'requestNotificationAuthorization',
      ]);
      expect(stagedPayload?['batchId'], 'test:account-1:run-1');
      expect(stagedPayload?['nextProofHeight'], 576);
      final items = stagedPayload?['items'] as List<Object?>;
      final item = items.single as Map<Object?, Object?>;
      expect(item['rawTransaction'], isA<Uint8List>());
      expect(item['rawTransaction'], Uint8List.fromList([1, 2, 3, 4]));
      expect(armedPayload, {
        'batchId': 'test:account-1:run-1',
        'expectedDigests': {'txid-1': 'digest-1'},
      });
    },
  );

  test('iOS surfaces a due outbox transfer that did not submit', () async {
    final store = await _boundBackgroundCredentialStore();
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus(activeRunId: 'run-1'));
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: store,
      getEndpoint: _testEndpoint,
      getSessionPassword: () => 'session-password',
      isMobile: () => true,
      isIOS: () => true,
      isMacOS: () => false,
      listMigrationOutboxReceipts: () async => const [],
      prepareMigrationOutbox:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async => _migrationResult(),
      exportMigrationOutbox:
          ({
            required dbPath,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async => _outboxBatch(),
      stageMigrationOutboxBatch: (_) async => const {'txid-1': 'digest-1'},
      armMigrationOutboxBatch:
          ({required batchId, required expectedDigests}) async => true,
      runMigrationOutboxOnceNow: () async =>
          const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.waiting,
            nextHeight: 288,
            observedHeight: 300,
          ),
    );

    await expectLater(
      service.continueSoftwarePrivateMigration(accountUuid: 'account-1'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Migration broadcast is waiting to retry.',
        ),
      ),
    );
  });

  test(
    'a failed receipt does not block later receipts or outbox recovery',
    () async {
      final events = <String>[];
      List<String>? acknowledgedReceiptIds;
      var receiptsAvailable = true;
      var prepareCount = 0;
      final store = await _boundBackgroundCredentialStore();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(activeRunId: 'run-1'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getSessionPassword: () => 'session-password',
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => receiptsAvailable
            ? [
                _outboxReceipt(receiptId: 'receipt-good', txidHex: 'tx-good'),
                _outboxReceipt(receiptId: 'receipt-bad', txidHex: 'tx-bad'),
                _outboxReceipt(receiptId: 'receipt-later', txidHex: 'tx-later'),
              ]
            : const [],
        reconcileMigrationOutboxReceipt:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required runId,
              required txidHex,
              required outcome,
              required remoteHeight,
              responseMessage,
              required scheduleUpdates,
              acceptedRawTransaction,
            }) async {
              events.add('rust:$txidHex');
              if (txidHex == 'tx-bad') {
                throw StateError('Rust rejected receipt');
              }
            },
        acknowledgeMigrationOutboxReceipts: (receiptIds) async {
          events.add('ack:${receiptIds.join(',')}');
          acknowledgedReceiptIds = receiptIds;
          receiptsAvailable = false;
        },
        prepareMigrationOutbox:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              prepareCount++;
              return _migrationResult();
            },
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => null,
      );

      await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');

      expect(events, [
        'rust:tx-good',
        'rust:tx-bad',
        'rust:tx-later',
        'ack:receipt-good,receipt-later',
      ]);
      expect(acknowledgedReceiptIds, ['receipt-good', 'receipt-later']);
      expect(prepareCount, 1);
    },
  );

  test('iOS continuation never calls the Rust due broadcaster', () async {
    var prepareCount = 0;
    var dueBroadcastCount = 0;
    final store = await _boundBackgroundCredentialStore();
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus: ({required dbPath, required network, required accountUuid}) {
        return Future.value(_migrationStatus(activeRunId: 'run-1'));
      },
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: store,
      getEndpoint: _testEndpoint,
      getSessionPassword: () => 'session-password',
      isMobile: () => true,
      isIOS: () => true,
      listMigrationOutboxReceipts: () async => const [],
      prepareMigrationOutbox:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async {
            prepareCount++;
            return _migrationResult();
          },
      exportMigrationOutbox:
          ({
            required dbPath,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async => null,
      broadcastDueMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required password,
            required saltBase64,
          }) async {
            dueBroadcastCount++;
            return _migrationResult();
          },
    );

    await service.continueSoftwarePrivateMigration(accountUuid: 'account-1');

    expect(prepareCount, 1);
    expect(dueBroadcastCount, 0);
  });

  test(
    'terminal mobile status deletes credential and cancels scheduler',
    () async {
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lwd.example:443',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var cancelledCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(_migrationStatus(phase: 'complete'));
        },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) {
              return Future.value(null);
            },
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        isMobile: () => true,
        cancelBackgroundMigration: () async => cancelledCount++,
      );

      await service.status(network: 'test', accountUuid: 'account-1');

      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNull,
      );
      expect(cancelledCount, 1);
    },
  );
}

rust_sync.MigrationStatus _migrationStatus({
  String phase = 'ready_to_prepare',
  String? activeRunId,
  List<rust_sync.MigrationPartStatus> parts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([]),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
    parts: parts,
  );
}

rust_sync.MigrationPartStatus _migrationPart({required String txidHex}) {
  return rust_sync.MigrationPartStatus(
    partIndex: 0,
    valueZatoshi: BigInt.from(100000),
    state: rust_sync.MigrationPartState.scheduled,
    txidHex: txidHex,
    confirmationCount: 0,
    confirmationTarget: 1,
  );
}

RpcEndpointConfig _testEndpoint() => const RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://lwd.example:443',
);

IronwoodMigrationService _notificationAuthorizationService({
  required bool isIOS,
  required List<rust_sync.MigrationStatus> statuses,
  Future<bool> Function()? requestNotificationAuthorization,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus: ({required dbPath, required network, required accountUuid}) {
      return Future.value(statuses.removeAt(0));
    },
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    backgroundCredentialStore: _backgroundCredentialStore(),
    getEndpoint: _testEndpoint,
    getSessionPassword: () => throw StateError('session password used'),
    getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2, 3]),
    isMacOS: () => false,
    isMobile: () => true,
    isIOS: () => isIOS,
    requestNotificationAuthorization: requestNotificationAuthorization,
    scheduleBackgroundMigration: () async => true,
    listMigrationOutboxReceipts: () async => const [],
    prepareMigrationOutbox:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) async => _migrationResult(),
    exportMigrationOutbox:
        ({
          required dbPath,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) async => null,
    startSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required approvedSchedule,
          required mnemonicBytes,
          required password,
          required saltBase64,
        }) async => _migrationResult(),
  );
}

IronwoodMigrationBackgroundCredentialStore _backgroundCredentialStore() {
  return IronwoodMigrationBackgroundCredentialStore.testing(
    storage: const FlutterSecureStorage(),
    randomBytes: (length) => Uint8List.fromList(List<int>.filled(length, 1)),
  );
}

Future<IronwoodMigrationBackgroundCredentialStore>
_boundBackgroundCredentialStore({String runId = 'run-1'}) async {
  final store = _backgroundCredentialStore();
  await store.prepare(
    network: 'test',
    accountUuid: 'account-1',
    dbPath: '/tmp/wallet.db',
    lightwalletdUrl: 'https://lwd.example:443',
  );
  await store.bindExpectedRunId(
    network: 'test',
    accountUuid: 'account-1',
    expectedRunId: runId,
  );
  return store;
}

rust_sync.IronwoodMigrationResult _migrationResult({
  String status = 'broadcasted',
}) {
  return rust_sync.IronwoodMigrationResult(
    txids: 'txid',
    status: status,
    broadcastedCount: 1,
    totalCount: 1,
    feeZatoshi: BigInt.from(10_000),
    migratedZatoshi: BigInt.from(100_000_000),
  );
}

rust_sync.MigrationOutboxBatch _outboxBatch() {
  return rust_sync.MigrationOutboxBatch(
    runId: 'run-1',
    timingMeanBlocks: 144,
    timingMaxBlocks: 576,
    nextProofHeight: 576,
    items: [
      rust_sync.MigrationOutboxItem(
        itemId: 'txid-1',
        partIndex: 0,
        txidHex: 'txid-1',
        rawTransaction: Uint8List.fromList([1, 2, 3, 4]),
        anchorBoundaryHeight: 144,
        scheduledHeight: 288,
        scheduleStartHeight: 288,
        expiryHeight: 34_560,
      ),
    ],
  );
}

Map<Object?, Object?> _outboxReceipt({
  required String receiptId,
  required String txidHex,
}) {
  return <Object?, Object?>{
    'receiptId': receiptId,
    'batchId': 'test:account-1:run-1',
    'itemId': txidHex,
    'network': 'test',
    'accountUuid': 'account-1',
    'runId': 'run-1',
    'txidHex': txidHex,
    'outcome': 'accepted',
    'remoteHeight': 300,
    'responseCode': 0,
    'responseMessage': null,
    'rawTransaction': Uint8List.fromList([1, 2, 3]),
    'recordedAtMs': 1,
    'scheduleUpdates': <Object?>[],
  };
}

rust_sync.KeystoneMigrationSigningRequest _keystoneSigningRequest() {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'request-1',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'message-1',
        redactedPczt: Uint8List.fromList([1, 2, 3]),
      ),
    ],
    signingBatchLimit: 50,
  );
}

rust_sync.KeystoneSignedMigrationMessage _signedMigrationMessage() {
  return rust_sync.KeystoneSignedMigrationMessage(
    id: 'message-1',
    sigs: [
      rust_keystone.KeystoneActionSig(
        pool: 0,
        actionIndex: 0,
        sig: Uint8List.fromList(List<int>.filled(64, 7)),
      ),
    ],
  );
}
