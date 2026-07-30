import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, PlatformException;
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
    'preparation runtime state parses native handoff states fail-closed',
    () {
      expect(
        IronwoodMigrationPreparationRuntimeState.fromNative('running'),
        IronwoodMigrationPreparationRuntimeState.running,
      );
      expect(
        IronwoodMigrationPreparationRuntimeState.fromNative(
          'foregroundContinuationPending',
        ),
        IronwoodMigrationPreparationRuntimeState.foregroundContinuationPending,
      );
      expect(
        IronwoodMigrationPreparationRuntimeState.fromNative('unknown'),
        IronwoodMigrationPreparationRuntimeState.idle,
      );
      expect(
        IronwoodMigrationPreparationRuntimeState
            .running
            .hasAutomaticBackgroundWork,
        isTrue,
      );
      expect(
        IronwoodMigrationPreparationRuntimeState
            .disabled
            .hasAutomaticBackgroundWork,
        isFalse,
      );
    },
  );

  test('outbox result parses native account scope and retry delay', () {
    final result = IronwoodMigrationOutboxRunResult.fromMap({
      'outcome': 'waiting',
      'nextHeight': 1_000,
      'observedHeight': 1_000,
      'accountUuid': 'account-1',
      'delaySeconds': 60.5,
    });

    expect(result.accountUuid, 'account-1');
    expect(result.retryDelay, const Duration(milliseconds: 60_500));
  });

  test(
    'Android does not read preparation runtime state from a native worker',
    () async {
      var getterCalls = 0;
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
        isIOS: () => false,
        isAndroid: () => true,
        getPreparationRuntimeState:
            ({required network, required accountUuid, required runId}) async {
              getterCalls++;
              expect(network, 'test');
              expect(accountUuid, 'account-1');
              expect(runId, 'run-1');
              return IronwoodMigrationPreparationRuntimeState.scheduled;
            },
      );

      final state = await service.preparationRuntimeState(
        accountUuid: 'account-1',
        runId: 'run-1',
      );

      expect(state, IronwoodMigrationPreparationRuntimeState.idle);
      expect(getterCalls, 0);
    },
  );

  test(
    'Android reports no background preparation tracking capability',
    () async {
      var capabilityCalls = 0;
      final service = _preparationTrackingSupportService(
        isIOS: false,
        isAndroid: true,
        supportsBackgroundPreparationTracking: () async {
          capabilityCalls++;
          return true;
        },
      );

      expect(await service.backgroundPreparationTrackingSupported(), isFalse);
      // There is no Android preparation worker and no Android
      // `background_migration` channel, so the platform gate must answer before
      // any native probe runs.
      expect(capabilityCalls, 0);
    },
  );

  test(
    'background preparation tracking mirrors the native capability',
    () async {
      final unsupported = _preparationTrackingSupportService(
        supportsBackgroundPreparationTracking: () async => false,
      );
      final supported = _preparationTrackingSupportService(
        supportsBackgroundPreparationTracking: () async => true,
      );

      expect(
        await unsupported.backgroundPreparationTrackingSupported(),
        isFalse,
      );
      expect(await supported.backgroundPreparationTrackingSupported(), isTrue);
    },
  );

  test(
    'background preparation tracking capability failure fails closed',
    () async {
      final throwing = _preparationTrackingSupportService(
        supportsBackgroundPreparationTracking: () async =>
            throw PlatformException(code: 'channel_error'),
      );

      // Over-promising a background lane strands the run; under-promising only
      // asks the user to keep Vizor open.
      expect(await throwing.backgroundPreparationTrackingSupported(), isFalse);
    },
  );

  test(
    'an injected preparation runtime source is treated as capable',
    () async {
      // Mirrors the `supportsBackgroundMigration` convention: only the default
      // native runtime-state source is OS-version gated, so a caller that
      // supplies its own source is not described by that gate.
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
        isIOS: () => true,
        isAndroid: () => false,
        getPreparationRuntimeState:
            ({required network, required accountUuid, required runId}) async =>
                IronwoodMigrationPreparationRuntimeState.scheduled,
      );

      expect(await service.backgroundPreparationTrackingSupported(), isTrue);
    },
  );

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

  test('stop drains native work before abandoning the durable run', () async {
    final events = <String>[];
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(activeRunId: 'run-1'),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      quiesceBackgroundMigration: () async => events.add('quiesce'),
      resumeBackgroundMigration: () async => events.add('resume'),
      listMigrationOutboxReceipts: () async {
        events.add('receipts');
        return const [];
      },
      listMigrationOutboxAttemptedTxids:
          ({required network, required accountUuid, required runId}) async {
            expect(network, 'test');
            expect(accountUuid, 'account-1');
            expect(runId, 'run-1');
            return const ['attempted-txid'];
          },
      revokeMigrationAccount: ({required network, required accountUuid}) async {
        events.add('revoke');
      },
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            expect(dbPath, '/tmp/wallet.db');
            expect(lightwalletdUrl, 'https://lwd.example:443');
            expect(network, 'test');
            expect(accountUuid, 'account-1');
            expect(expectedRunId, 'run-1');
            expect(nativeAttemptedTxids, ['attempted-txid']);
            events.add('stop');
          },
    );

    await service.stop(accountUuid: 'account-1', expectedRunId: 'run-1');

    expect(events, ['quiesce', 'receipts', 'stop', 'revoke', 'resume']);
  });

  test(
    'Android stop bypasses unavailable native migration lifecycle',
    () async {
      final events = <String>[];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(activeRunId: 'run-1'),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => false,
        isAndroid: () => true,
        quiesceBackgroundMigration: () async {
          throw StateError('Android native lifecycle must not be called');
        },
        resumeBackgroundMigration: () async {
          throw StateError('Android native lifecycle must not be called');
        },
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              throw StateError('Android native lifecycle must not be called');
            },
        stopMigrationRun:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
              required nativeAttemptedTxids,
            }) async {
              events.add('stop');
            },
      );

      await service.stop(accountUuid: 'account-1', expectedRunId: 'run-1');

      expect(events, ['stop']);
    },
  );

  test('a stale stop never revokes a newer run', () async {
    final events = <String>[];
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(activeRunId: 'run-2'),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      quiesceBackgroundMigration: () async => events.add('quiesce'),
      resumeBackgroundMigration: () async => events.add('resume'),
      listMigrationOutboxReceipts: () async {
        events.add('receipts');
        return const [];
      },
      listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
      revokeMigrationAccount: ({required network, required accountUuid}) async {
        events.add('revoke');
      },
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            expect(expectedRunId, 'run-1');
            events.add('stop');
          },
    );

    await service.stop(accountUuid: 'account-1', expectedRunId: 'run-1');

    expect(events, ['quiesce', 'receipts', 'stop', 'resume']);
  });

  test('a failed durable stop leaves native state untouched', () async {
    final events = <String>[];
    final credentialStore = IronwoodMigrationBackgroundCredentialStore.testing(
      storage: const FlutterSecureStorage(),
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    await credentialStore.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://example.com',
    );
    await credentialStore.bindExpectedRunId(
      network: 'test',
      accountUuid: 'account-1',
      expectedRunId: 'run-1',
    );

    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(activeRunId: 'run-1'),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      backgroundCredentialStore: credentialStore,
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      quiesceBackgroundMigration: () async => events.add('quiesce'),
      resumeBackgroundMigration: () async => events.add('resume'),
      listMigrationOutboxReceipts: () async {
        events.add('receipts');
        return const [];
      },
      listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
      revokeMigrationAccount: ({required network, required accountUuid}) async {
        events.add('revoke');
      },
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            events.add('stop');
            throw StateError('database is busy');
          },
    );

    await expectLater(
      service.stop(accountUuid: 'account-1', expectedRunId: 'run-1'),
      throwsA(isA<StateError>()),
    );

    final untouched = await credentialStore.read(
      network: 'test',
      accountUuid: 'account-1',
    );
    expect(untouched?.expectedRunId, 'run-1');
    expect(events, ['quiesce', 'receipts', 'stop', 'resume']);
  });

  test(
    'a lost revoke response leaves abandoned native work quiesced',
    () async {
      final events = <String>[];
      final credentialStore =
          IronwoodMigrationBackgroundCredentialStore.testing(
            storage: const FlutterSecureStorage(),
            randomBytes: (length) => Uint8List.fromList(
              List<int>.generate(length, (index) => index),
            ),
          );
      await credentialStore.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://example.com',
      );
      await credentialStore.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );

      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(activeRunId: 'run-1'),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: credentialStore,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        quiesceBackgroundMigration: () async => events.add('quiesce'),
        resumeBackgroundMigration: () async => events.add('resume'),
        listMigrationOutboxReceipts: () async => const [],
        listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
              await credentialStore.delete(
                network: network,
                accountUuid: accountUuid,
              );
              throw StateError('native reply was lost');
            },
        stopMigrationRun:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
              required nativeAttemptedTxids,
            }) async {
              events.add('stop');
            },
      );

      await expectLater(
        service.stop(accountUuid: 'account-1', expectedRunId: 'run-1'),
        throwsA(isA<StateError>()),
      );

      final revoked = await credentialStore.read(
        network: 'test',
        accountUuid: 'account-1',
      );
      expect(revoked, isNull);
      expect(events, ['quiesce', 'stop', 'revoke']);
    },
  );

  test(
    'a failed durable stop without a manifest never revokes outbox',
    () async {
      final events = <String>[];
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(activeRunId: 'run-1'),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        quiesceBackgroundMigration: () async => events.add('quiesce'),
        resumeBackgroundMigration: () async => events.add('resume'),
        listMigrationOutboxReceipts: () async => const [],
        listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
            },
        stopMigrationRun:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
              required nativeAttemptedTxids,
            }) async {
              events.add('stop');
              throw StateError('network reconciliation is pending');
            },
      );

      await expectLater(
        service.stop(accountUuid: 'account-1', expectedRunId: 'run-1'),
        throwsA(isA<StateError>()),
      );

      expect(events, ['quiesce', 'stop', 'resume']);
    },
  );

  test(
    'a lost durable stop response still revokes terminal native work',
    () async {
      final events = <String>[];
      var statusReads = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async {
              statusReads++;
              return _migrationStatus(
                activeRunId: statusReads == 1 ? 'run-1' : null,
              );
            },
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        quiesceBackgroundMigration: () async => events.add('quiesce'),
        resumeBackgroundMigration: () async => events.add('resume'),
        listMigrationOutboxReceipts: () async => const [],
        listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
            },
        stopMigrationRun:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
              required nativeAttemptedTxids,
            }) async {
              events.add('stop');
              throw StateError('FFI reply was lost');
            },
      );

      await service.stop(accountUuid: 'account-1', expectedRunId: 'run-1');

      expect(events, ['quiesce', 'stop', 'revoke', 'resume']);
    },
  );

  test('terminal cleanup never resumes when native revoke fails', () async {
    final events = <String>[];
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(activeRunId: null),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      quiesceBackgroundMigration: () async => events.add('quiesce'),
      resumeBackgroundMigration: () async => events.add('resume'),
      listMigrationOutboxReceipts: () async {
        events.add('receipts');
        return const [];
      },
      listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
      revokeMigrationAccount: ({required network, required accountUuid}) async {
        events.add('revoke');
        throw StateError('native storage is busy');
      },
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            events.add('stop');
          },
    );

    await expectLater(
      service.stop(accountUuid: 'account-1', expectedRunId: 'run-1'),
      throwsA(isA<StateError>()),
    );

    expect(events, ['quiesce', 'revoke']);
  });

  test('terminal cleanup revokes before fallible Rust cleanup', () async {
    final events = <String>[];
    final service = IronwoodMigrationService(
      getWalletDbPath: () async => '/tmp/wallet.db',
      getStatus:
          ({required dbPath, required network, required accountUuid}) async =>
              _migrationStatus(activeRunId: null),
      getPrivatePlan:
          ({required dbPath, required network, required accountUuid}) async =>
              null,
      secureStore: AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      ),
      getEndpoint: _testEndpoint,
      isMobile: () => true,
      isIOS: () => true,
      quiesceBackgroundMigration: () async => events.add('quiesce'),
      resumeBackgroundMigration: () async => events.add('resume'),
      listMigrationOutboxReceipts: () async {
        events.add('receipts');
        return const [];
      },
      listMigrationOutboxAttemptedTxids: _noAttemptedOutboxTxids,
      revokeMigrationAccount: ({required network, required accountUuid}) async {
        events.add('revoke');
      },
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            events.add('stop');
            throw StateError('wallet lock cleanup is busy');
          },
    );

    await expectLater(
      service.stop(accountUuid: 'account-1', expectedRunId: 'run-1'),
      throwsA(isA<StateError>()),
    );

    expect(events, ['quiesce', 'revoke', 'stop', 'resume']);
  });

  test(
    'foreground due-outbox recovery runs only native outbox reconciliation',
    () async {
      final events = <String>[];
      var receiptReadCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async {
              events.add('has');
              expect(requiredTxids, ['tx-1']);
              return true;
            },
        listMigrationOutboxReceipts: () async {
          events.add('list');
          receiptReadCount++;
          return receiptReadCount == 1
              ? const []
              : [_outboxReceipt(receiptId: 'receipt-1', txidHex: 'tx-1')];
        },
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
              events.add('receipt');
            },
        acknowledgeMigrationOutboxReceipts: (_) async {
          events.add('ack');
        },
        runMigrationOutboxOnceNow: () async {
          events.add('run');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.accepted,
            observedHeight: 1_000,
          );
        },
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.accepted);
      expect(events, ['list', 'has', 'run', 'list', 'receipt', 'ack']);
    },
  );

  test(
    'foreground recovery allows the global outbox to accept another account',
    () async {
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        listMigrationOutboxReceipts: () async => const [],
        runMigrationOutboxOnceNow: () async =>
            const IronwoodMigrationOutboxRunResult(
              outcome: IronwoodMigrationOutboxRunOutcome.accepted,
              observedHeight: 1_000,
            ),
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.accepted);
    },
  );

  test(
    'foreground recovery rebuilds a missing outbox batch from persisted transactions',
    () async {
      final events = <String>[];
      var receiptReadCount = 0;
      final store = await _boundBackgroundCredentialStore();
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'txid-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'txid-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async {
          events.add('list');
          receiptReadCount++;
          return receiptReadCount == 1
              ? const []
              : [_outboxReceipt(receiptId: 'receipt-1', txidHex: 'txid-1')];
        },
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async {
              events.add('has');
              return false;
            },
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('export');
              expect(dbPath, '/tmp/wallet.db');
              expect(network, 'test');
              expect(accountUuid, 'account-1');
              expect(password, isNotEmpty);
              expect(saltBase64, isNotEmpty);
              return _outboxBatch();
            },
        stageMigrationOutboxBatch: (batch) async {
          events.add('stage');
          expect(batch['batchId'], 'test:account-1:run-1');
          expect(batch['lightwalletdUrl'], 'https://lwd.example:443');
          return const {'txid-1': 'digest-1'};
        },
        armMigrationOutboxBatch:
            ({required batchId, required expectedDigests}) async {
              events.add('arm');
              expect(batchId, 'test:account-1:run-1');
              expect(expectedDigests, const {'txid-1': 'digest-1'});
              return true;
            },
        runMigrationOutboxOnceNow: () async {
          events.add('run');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.accepted,
            observedHeight: 1_000,
          );
        },
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
              events.add('receipt');
            },
        acknowledgeMigrationOutboxReceipts: (_) async {
          events.add('ack');
        },
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.accepted);
      expect(events, [
        'list',
        'has',
        'export',
        'stage',
        'arm',
        'run',
        'list',
        'receipt',
        'ack',
      ]);
    },
  );

  test(
    'an unapplied receipt is reported as recording, not a missing credential',
    () async {
      // The transaction was delivered and a receipt exists, but applying it to
      // the wallet DB failed, so the DB row stays scheduled while the native
      // record has nothing left to send. Labelling that a credential fault
      // sends the user to a repair action that refuses, for a transaction that
      // is already on the network.
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => [
          _outboxReceipt(receiptId: 'receipt-1', txidHex: 'tx-1'),
        ],
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
            }) async => throw StateError('wallet database is busy'),
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        runMigrationOutboxOnceNow: () async =>
            const IronwoodMigrationOutboxRunResult(
              outcome: IronwoodMigrationOutboxRunOutcome.noWork,
              observedHeight: 1_000,
            ),
      );

      await expectLater(
        service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('already submitted'),
              // The marker that routes the UI to the credential-recovery CTA.
              isNot(contains('credential is missing for the active run')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'a malformed receipt from another account does not mask missing recovery',
    () async {
      final otherAccountReceipt =
          _outboxReceipt(receiptId: 'receipt-2', txidHex: 'tx-2')
            ..['accountUuid'] = 'account-2'
            ..['scheduleUpdates'] = 'invalid';
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => [otherAccountReceipt],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        runMigrationOutboxOnceNow: () async =>
            const IronwoodMigrationOutboxRunResult(
              outcome: IronwoodMigrationOutboxRunOutcome.noWork,
              observedHeight: 1_000,
            ),
      );

      await expectLater(
        service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('credential is missing for the active run'),
              isNot(contains('already submitted')),
            ),
          ),
        ),
      );
    },
  );

  test(
    'foreground recovery requests credential recovery without a manifest',
    () async {
      var foregroundRuns = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        runMigrationOutboxOnceNow: () async {
          foregroundRuns++;
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.noWork,
            observedHeight: 1_000,
          );
        },
      );

      await expectLater(
        service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('credential is missing for the active run'),
          ),
        ),
      );
      expect(foregroundRuns, 1);
    },
  );

  test(
    'a stale conflicting batch is revoked and restaged once before broadcast',
    () async {
      // A native record that cannot accept this run's scheduled transactions
      // deadlocks every recovery attempt: staging keeps hitting the same
      // conflict and nothing else can clear the record. While no transaction of
      // the run has been broadcast, that record is stale and may be discarded.
      final events = <String>[];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      var stageCalls = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'txid-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'txid-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => throw PlatformException(
              code: kIronwoodMigrationConflictingOutboxBatchCode,
              message: 'conflictingBatch',
            ),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _outboxBatch(),
        stageMigrationOutboxBatch: (_) async {
          stageCalls++;
          events.add('stage');
          if (stageCalls == 1) {
            throw PlatformException(
              code: kIronwoodMigrationConflictingOutboxBatchCode,
              message: 'conflictingBatch',
            );
          }
          return const {'txid-1': 'digest-1'};
        },
        discardMigrationOutboxBatch: ({required batchId}) async {
          events.add('discard');
          return true;
        },
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
            },
        armMigrationOutboxBatch:
            ({required batchId, required expectedDigests}) async {
              events.add('arm');
              return true;
            },
        runMigrationOutboxOnceNow: () async {
          events.add('run');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.accepted,
            observedHeight: 1_000,
          );
        },
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(events, ['stage', 'discard', 'stage', 'arm', 'run']);
      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.accepted);
    },
  );

  test(
    'a broadcast run keeps a conflicting batch instead of discarding it',
    () async {
      // Once a transaction of the run reached the network, the native record
      // may hold submission state that a rebuild would lose. Such a conflict
      // must surface instead of being cleared automatically.
      final events = <String>[];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  broadcastedTxCount: 1,
                  parts: [_migrationPart(txidHex: 'txid-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'txid-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => throw PlatformException(
              code: kIronwoodMigrationConflictingOutboxBatchCode,
              message: 'conflictingBatch',
            ),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _outboxBatch(),
        stageMigrationOutboxBatch: (_) async {
          events.add('stage');
          throw PlatformException(
            code: kIronwoodMigrationConflictingOutboxBatchCode,
            message: 'conflictingBatch',
          );
        },
        discardMigrationOutboxBatch: ({required batchId}) async {
          events.add('discard');
          return true;
        },
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
            },
      );

      await expectLater(
        service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(events, ['stage']);
    },
  );

  test(
    'a conflicting native batch is repaired instead of failing the retry',
    () async {
      // The native store throws `conflictingBatch` when a batch record exists
      // under this run's batch id but cannot deliver its scheduled
      // transactions (no items, or items that do not cover them). That is the
      // exact state a recovery has to repair, so the inspection call must
      // report "no usable batch" instead of propagating and skipping the
      // restore path entirely.
      final events = <String>[];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'txid-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'txid-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => throw PlatformException(
              code: kIronwoodMigrationConflictingOutboxBatchCode,
              message: 'conflictingBatch',
            ),
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _outboxBatch(),
        stageMigrationOutboxBatch: (_) async {
          events.add('stage');
          return const {'txid-1': 'digest-1'};
        },
        armMigrationOutboxBatch:
            ({required batchId, required expectedDigests}) async {
              events.add('arm');
              return true;
            },
        runMigrationOutboxOnceNow: () async {
          events.add('run');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.accepted,
            observedHeight: 1_000,
          );
        },
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(events, ['stage', 'arm', 'run']);
      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.accepted);
    },
  );

  test(
    'foreground recovery requests credential recovery for an unusable manifest',
    () async {
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => false,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async =>
                throw StateError('Failed to decrypt secure-storage payload'),
      );

      await expectLater(
        service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('credential is missing for the active run'),
          ),
        ),
      );
    },
  );

  test(
    'foreground recovery keeps a usable credential when export re-marks every '
    'scheduled part for re-signing',
    () async {
      final events = <String>[];
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'run-1',
          parts: [_migrationPart(txidHex: 'tx-1')],
          scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
        ),
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'run-1',
          parts: [
            _migrationPart(
              txidHex: 'tx-1',
              state: rust_sync.MigrationPartState.needsInput,
            ),
          ],
        ),
      ];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            statuses.length > 1 ? statuses.removeAt(0) : statuses.first,
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
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => false,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('export');
              return null;
            },
        runMigrationOutboxOnceNow: () async {
          events.add('run');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.needsUserAction,
            observedHeight: 1_000,
          );
        },
      );

      final result = await service.recoverDueMigrationOutbox(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(result.outcome, IronwoodMigrationOutboxRunOutcome.needsUserAction);
      expect(events, ['export', 'run']);
    },
  );

  test(
    'a malformed native outbox reply is not a credential recovery request',
    () async {
      // A channel/payload-shape fault must surface as itself. Reporting it as an
      // unusable credential would offer the user a rebuild that revokes a batch
      // and retires a run over what is only a transport error.
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'tx-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => false,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => throw const IronwoodMigrationOutboxProtocolException(
              'Ironwood migration outbox value is invalid: outcome.',
            ),
      );

      Object? caught;
      try {
        await service.recoverDueMigrationOutbox(
          network: 'test',
          accountUuid: 'account-1',
        );
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<IronwoodMigrationOutboxProtocolException>());
      expect(
        ironwoodMigrationNeedsCredentialRecovery(caught.toString()),
        isFalse,
      );
    },
  );

  test(
    'explicit recovery refuses a run whose native outbox batch is intact',
    () async {
      // Recovery revokes the native outbox before it restages, and a failed
      // restage falls through to run retirement. That window must stay closed
      // for a run whose credential still exports it and whose native batch is
      // already present: there is nothing to recover there.
      final events = <String>[];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(
                  phase: 'broadcast_scheduled',
                  activeRunId: 'run-1',
                  parts: [_migrationPart(txidHex: 'txid-1')],
                  scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'txid-1')],
                ),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getMnemonicBytesForAccount: (_) async =>
            Uint8List.fromList([1, 2, 3, 4]),
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        isHardwareAccount: (_) => false,
        listMigrationOutboxReceipts: () async => const [],
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async => _outboxBatch(),
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke:$accountUuid');
            },
        retireUnbroadcastMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
            }) async {
              events.add('retire:$expectedRunId');
            },
      );

      await expectLater(
        service.recoverSoftwarePrivateMigration(accountUuid: 'account-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('still has a usable credential'),
          ),
        ),
      );
      expect(events, isEmpty);
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
        denominationSplitLayerCount: 1,
        signingBatchLimit: 35,
        scheduleMeanDelayBlocks: 144,
        scheduleMaxDelayBlocks: 576,
        proofReadinessDelayBlocks: 146,
        scheduledTransfers: const [],
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
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
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
    'Android software start does not hand work to background preparation',
    () async {
      var preparationStartCount = 0;
      final service = _notificationAuthorizationService(
        isIOS: false,
        isAndroid: true,
        statuses: [
          _migrationStatus(),
          _migrationStatus(
            phase: 'waiting_denom_confirmations',
            activeRunId: 'run-1',
          ),
        ],
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
      );

      await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(preparationStartCount, 0);
    },
  );

  test(
    'iOS Keystone completion hands confirmation waiting to background preparation',
    () async {
      var preparationStartCount = 0;
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
        isMobile: () => true,
        isIOS: () => true,
        isHardwareAccount: (_) => true,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
        requestNotificationAuthorization: () async => true,
        listMigrationOutboxReceipts: () async => const [],
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
            }) async => _migrationResult(status: 'waiting_denom_confirmations'),
      );

      await service.completeKeystoneDenominationPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: [_signedMigrationMessage()],
        approvedSchedule: const [],
      );

      expect(preparationStartCount, 1);
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
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
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
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
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
    'iOS software migration start never requests notification authorization',
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
      expect(methodCalls, isEmpty);
    },
  );

  test(
    'notification authorization denial keeps migration foreground-only',
    () async {
      var requestCount = 0;
      var preparationStartCount = 0;
      var scheduleCount = 0;
      final service = _notificationAuthorizationService(
        isIOS: true,
        statuses: [
          _migrationStatus(),
          _migrationStatus(
            phase: 'waiting_denom_confirmations',
            activeRunId: 'run-1',
          ),
        ],
        requestNotificationAuthorization: () async {
          requestCount++;
          return false;
        },
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.denied,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
        scheduleBackgroundMigration: () async {
          scheduleCount++;
          return true;
        },
      );

      final result = await service.startSoftwarePrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(result.status, 'broadcasted');
      expect(requestCount, 0);
      expect(preparationStartCount, 0);
      expect(scheduleCount, 0);
    },
  );

  test('notification APIs are available only on iOS', () async {
    var requestCount = 0;
    var statusCount = 0;
    var openSettingsCount = 0;
    final iosService = _notificationAuthorizationService(
      isIOS: true,
      statuses: const [],
      requestNotificationAuthorization: () async {
        requestCount++;
        return true;
      },
      getNotificationAuthorizationStatus: () async {
        statusCount++;
        return IronwoodMigrationNotificationAuthorizationStatus.authorized;
      },
      openNotificationSettings: () async {
        openSettingsCount++;
        return true;
      },
    );
    final androidService = _notificationAuthorizationService(
      isIOS: false,
      isAndroid: true,
      statuses: const [],
      requestNotificationAuthorization: () async {
        requestCount++;
        return true;
      },
      getNotificationAuthorizationStatus: () async {
        statusCount++;
        return IronwoodMigrationNotificationAuthorizationStatus.authorized;
      },
      openNotificationSettings: () async {
        openSettingsCount++;
        return true;
      },
    );

    expect(
      await iosService.notificationAuthorizationStatus(),
      IronwoodMigrationNotificationAuthorizationStatus.authorized,
    );
    expect(
      await iosService.requestNotificationPermission(),
      IronwoodMigrationNotificationAuthorizationStatus.authorized,
    );
    expect(await iosService.openNotificationSystemSettings(), isTrue);
    expect(
      await androidService.notificationAuthorizationStatus(),
      IronwoodMigrationNotificationAuthorizationStatus.denied,
    );
    expect(
      await androidService.requestNotificationPermission(),
      IronwoodMigrationNotificationAuthorizationStatus.denied,
    );
    expect(await androidService.openNotificationSystemSettings(), isFalse);

    expect(requestCount, 1);
    expect(statusCount, 2);
    expect(openSettingsCount, 1);
  });

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
    'iOS software status stays read-only and explicit recovery restores preparation',
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
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
      );

      await service.status(network: 'test', accountUuid: 'account-1');
      expect(preparationStartCount, 0);
      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(preparationStartCount, 1);
    },
  );

  test(
    'Android lifecycle recovery leaves background preparation disabled',
    () async {
      final store = await _boundBackgroundCredentialStore();
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
        isIOS: () => false,
        isAndroid: () => true,
        startBackgroundPreparation: () async {
          preparationStartCount++;
          return true;
        },
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
      );

      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(preparationStartCount, 0);
    },
  );

  test('explicit recovery binds a provisional preparation manifest', () async {
    final store = _backgroundCredentialStore();
    await store.prepare(
      network: 'test',
      accountUuid: 'account-1',
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: 'https://lwd.example:443',
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
      getNotificationAuthorizationStatus: () async =>
          IronwoodMigrationNotificationAuthorizationStatus.authorized,
    );

    await service.resumeBackgroundPreparationIfNeeded(
      network: 'test',
      accountUuid: 'account-1',
    );

    expect(preparationStartCount, 1);
    expect(
      (await store.read(
        network: 'test',
        accountUuid: 'account-1',
      ))?.expectedRunId,
      'run-1',
    );
  });

  test('iOS hardware lifecycle recovery restores preparation', () async {
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
      getNotificationAuthorizationStatus: () async =>
          IronwoodMigrationNotificationAuthorizationStatus.authorized,
    );

    await service.resumeBackgroundPreparationIfNeeded(
      network: 'test',
      accountUuid: 'account-1',
    );

    expect(preparationStartCount, 1);
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
        return Future.value(
          _migrationStatus(phase: 'ready_to_migrate', activeRunId: 'run-1'),
        );
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
    'software continuation does not start another batch after completion',
    () async {
      var macosStartCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                _migrationStatus(phase: 'complete'),
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
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
            }) async => _migrationResult(status: 'ready_to_migrate'),
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
              macosStartCount++;
              return _migrationResult();
            },
      );

      final result = await service.continueSoftwarePrivateMigration(
        accountUuid: 'account-1',
      );

      expect(result.status, 'ready_to_migrate');
      expect(macosStartCount, 0);
    },
  );

  test(
    'prepareKeystoneSingleQrPrivateMigration forwards the approved schedule',
    () async {
      String? seenDbPath;
      String? seenNetwork;
      String? seenAccountUuid;
      List<rust_sync.MigrationScheduledTransfer>? seenSchedule;
      final expected = _keystoneSigningRequest();
      final approvedSchedule = [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(10_000_000),
          blockOffset: 144,
        ),
      ];
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
        prepareKeystoneSingleQrMigration:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required approvedSchedule,
            }) {
              seenDbPath = dbPath;
              seenNetwork = network;
              seenAccountUuid = accountUuid;
              seenSchedule = approvedSchedule;
              return Future.value(expected);
            },
      );

      final request = await service.prepareKeystoneSingleQrPrivateMigration(
        accountUuid: 'account-1',
        approvedSchedule: approvedSchedule,
      );

      expect(request, expected);
      expect(seenDbPath, '/tmp/wallet.db');
      expect(seenNetwork, 'test');
      expect(seenAccountUuid, 'account-1');
      expect(seenSchedule, approvedSchedule);
    },
  );

  test(
    'completeKeystoneSingleQrPrivateMigration reuses pending tx salt',
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
        completeKeystoneSingleQrMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
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

      await service.completeKeystoneSingleQrPrivateMigration(
        accountUuid: 'account-1',
        requestId: 'request-1',
        signedMessages: signedMessages,
      );
      await service.completeKeystoneSingleQrPrivateMigration(
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

  test('Keystone Immediate migration forwards plan and completion', () async {
    final expectedRequest = _keystoneSigningRequest();
    final expectedResult = _migrationResult();
    BigInt? seenAmount;
    BigInt? seenFee;
    BigInt? seenMigrated;
    int? seenNoteCount;
    String? completedRequestId;
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
      prepareKeystoneImmediateMigration:
          ({
            required dbPath,
            required network,
            required accountUuid,
            required approvedTotalInputZatoshi,
            required approvedFeeZatoshi,
            required approvedMigratedZatoshi,
            required approvedInputNoteCount,
          }) async {
            seenAmount = approvedTotalInputZatoshi;
            seenFee = approvedFeeZatoshi;
            seenMigrated = approvedMigratedZatoshi;
            seenNoteCount = approvedInputNoteCount;
            return expectedRequest;
          },
      completeKeystoneImmediateMigration:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required requestId,
            required signedMessages,
          }) async {
            completedRequestId = requestId;
            return expectedResult;
          },
    );
    final plan = rust_sync.OrchardMigrationImmediatePlan(
      totalInputZatoshi: BigInt.from(10_000_000),
      feeZatoshi: BigInt.from(10_000),
      migratedZatoshi: BigInt.from(9_990_000),
      inputNoteCount: 2,
    );

    final request = await service.prepareKeystoneImmediateMigrationRequest(
      accountUuid: 'account-1',
      approvedPlan: plan,
    );
    final result = await service.completeKeystoneImmediateMigrationRequest(
      accountUuid: 'account-1',
      requestId: request.requestId,
      signedMessages: const [],
    );

    expect(request, expectedRequest);
    expect(result, expectedResult);
    expect(seenAmount, plan.totalInputZatoshi);
    expect(seenFee, plan.feeZatoshi);
    expect(seenMigrated, plan.migratedZatoshi);
    expect(seenNoteCount, 2);
    expect(completedRequestId, expectedRequest.requestId);
  });

  test(
    'saved unstarted private draft recreates a missing mobile credential',
    () async {
      final store = _backgroundCredentialStore();
      final status = _migrationStatus(
        phase: 'awaiting_preparation',
        activeRunId: 'draft-run-1',
      );
      var createCount = 0;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus:
            ({required dbPath, required network, required accountUuid}) async =>
                status,
        getPrivatePlan:
            ({required dbPath, required network, required accountUuid}) async =>
                null,
        secureStore: AppSecureStore.testing(
          storage: const FlutterSecureStorage(),
        ),
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        isMobile: () => true,
        isIOS: () => true,
        listMigrationOutboxReceipts: () async => const [],
        createPrivateMigrationDraft:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required approvedSchedule,
            }) async {
              createCount += 1;
              return 'draft-run-1';
            },
      );

      final runId = await service.savePrivateMigrationDraft(
        accountUuid: 'account-1',
        approvedSchedule: const [],
      );

      expect(runId, 'draft-run-1');
      expect(createCount, 1);
      final manifest = await store.read(
        network: 'test',
        accountUuid: 'account-1',
      );
      expect(manifest, isNotNull);
      expect(manifest!.expectedRunId, 'draft-run-1');
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
    'a part the export re-marks for re-signing does not condemn the credential',
    () async {
      // Exporting is not read-only: it first re-marks due parts whose expiry no
      // longer matches the current ZIP 318 window as needs_resign, then exports
      // only the rows still scheduled. Judging the credential against the
      // pre-export snapshot read that ordinary re-sign as "this credential
      // cannot open the run" and revoked, retired and re-planned the migration,
      // discarding signed children and their proofs.
      final events = <String>[];
      final statuses = <rust_sync.MigrationStatus>[
        // Read before the export: the part is still scheduled.
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'run-1',
          scheduledBroadcasts: [_scheduledBroadcast(txidHex: 'tx-a')],
        ),
        // Read after the export: the same part now needs re-signing.
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'run-1',
          parts: [
            _migrationPart(
              txidHex: 'tx-a',
              state: rust_sync.MigrationPartState.needsInput,
            ),
          ],
        ),
      ];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'run-1',
      );
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            statuses.length > 1 ? statuses.removeAt(0) : statuses.first,
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
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2]),
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        isHardwareAccount: (_) => false,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async {
              events.add('export');
              // Rust returns null when this was the final scheduled part and
              // there is no unpromoted proof waiting behind it.
              return null;
            },
        hasMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required expectedTxids,
              required requiredTxids,
            }) async => true,
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke');
            },
        retireUnbroadcastMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
            }) async {
              events.add('retire');
            },
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
              events.add('start');
              return _migrationResult();
            },
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
        requestNotificationAuthorization: () async => true,
      );

      await service.recoverSoftwarePrivateMigration(accountUuid: 'account-1');
      expect(events, ['export']);
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
    'confirmed recovery retires the old run and binds a new credential',
    () async {
      final events = <String>[];
      final mnemonic = Uint8List.fromList([1, 2, 3, 4]);
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'old-run',
          parts: [_migrationPart(txidHex: 'missing-tx')],
        ),
        _migrationStatus(
          phase: 'waiting_denom_confirmations',
          activeRunId: 'new-run',
        ),
      ];
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lightwalletd.test',
      );
      await store.bindExpectedRunId(
        network: 'test',
        accountUuid: 'account-1',
        expectedRunId: 'old-run',
      );
      String? startedPassword;
      String? startedSalt;
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
        backgroundCredentialStore: store,
        getEndpoint: _testEndpoint,
        getMnemonicBytesForAccount: (_) async => mnemonic,
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        isHardwareAccount: (_) => false,
        recoverMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required lightwalletdUrl,
              required expectedTxids,
            }) async => false,
        exportMigrationOutbox:
            ({
              required dbPath,
              required network,
              required accountUuid,
              required password,
              required saltBase64,
            }) async =>
                throw StateError('Failed to decrypt secure-storage payload'),
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {
              events.add('revoke:$network:$accountUuid');
            },
        retireUnbroadcastMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
            }) async {
              events.add('retire:$expectedRunId');
            },
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
              events.add('start');
              startedPassword = password;
              startedSalt = saltBase64;
              expect(mnemonicBytes, [1, 2, 3, 4]);
              expect(approvedSchedule, isEmpty);
              return _migrationResult();
            },
        startBackgroundPreparation: () async {
          events.add('prepare-background');
          return true;
        },
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
        requestNotificationAuthorization: () async => true,
      );

      await service.recoverSoftwarePrivateMigration(accountUuid: 'account-1');

      expect(events, [
        'revoke:test:account-1',
        'retire:old-run',
        'start',
        'prepare-background',
      ]);
      expect(mnemonic, [0, 0, 0, 0]);
      final manifest = await store.read(
        network: 'test',
        accountUuid: 'account-1',
      );
      expect(manifest?.expectedRunId, 'new-run');
      expect(manifest?.credentialHex, startedPassword);
      expect(manifest?.saltBase64, startedSalt);
    },
  );

  test(
    'recovery does not create a new credential when network checks fail',
    () async {
      final store = _backgroundCredentialStore();
      var startCalled = false;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            _migrationStatus(
              phase: 'broadcast_scheduled',
              activeRunId: 'old-run',
              parts: [_migrationPart(txidHex: 'missing-tx')],
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
        getMnemonicBytesForAccount: (_) async => Uint8List.fromList([1, 2]),
        isMobile: () => true,
        isIOS: () => true,
        isMacOS: () => false,
        isHardwareAccount: (_) => false,
        recoverMigrationOutboxBatch:
            ({
              required batchId,
              required network,
              required accountUuid,
              required runId,
              required lightwalletdUrl,
              required expectedTxids,
            }) async => false,
        revokeMigrationAccount:
            ({required network, required accountUuid}) async {},
        retireUnbroadcastMigration:
            ({
              required dbPath,
              required lightwalletdUrl,
              required network,
              required accountUuid,
              required expectedRunId,
            }) async => throw StateError('network verification failed'),
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
              startCalled = true;
              return _migrationResult();
            },
      );

      await expectLater(
        service.recoverSoftwarePrivateMigration(accountUuid: 'account-1'),
        throwsA(isA<StateError>()),
      );
      expect(startCalled, isFalse);
      expect(
        await store.read(network: 'test', accountUuid: 'account-1'),
        isNull,
      );
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

  test(
    'notification denial still stages arms and runs the outbox in foreground',
    () async {
      final store = _backgroundCredentialStore();
      await store.prepare(
        network: 'test',
        accountUuid: 'account-1',
        dbPath: '/tmp/wallet.db',
        lightwalletdUrl: 'https://lwd.example:443',
      );
      var armCalls = 0;
      var stageCalls = 0;
      var foregroundRunCalls = 0;
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
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.denied,
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
        stageMigrationOutboxBatch: (_) async {
          stageCalls++;
          return const {'txid-1': 'digest-1'};
        },
        armMigrationOutboxBatch:
            ({required batchId, required expectedDigests}) async {
              armCalls++;
              return true;
            },
        runMigrationOutboxOnceNow: () async {
          foregroundRunCalls++;
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.waiting,
          );
        },
      );

      expect(
        await service.retryPrivateMigrationInBackground(
          accountUuid: 'account-1',
        ),
        isTrue,
      );
      expect(stageCalls, 1);
      expect(armCalls, 1);
      expect(foregroundRunCalls, 1);
      expect(notificationAuthorizationRequestCount, 0);
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
      expect(notificationAuthorizationRequestCount, 0);
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
    'Keystone preparation and completion never request notifications',
    () async {
      final statuses = <rust_sync.MigrationStatus>[
        _migrationStatus(),
        _migrationStatus(
          phase: 'waiting_denom_confirmations',
          activeRunId: 'keystone-run',
        ),
        _migrationStatus(
          phase: 'ready_to_migrate',
          activeRunId: 'keystone-run',
        ),
        _migrationStatus(
          phase: 'broadcast_scheduled',
          activeRunId: 'keystone-run',
        ),
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
        startBackgroundPreparation: () async => true,
        getNotificationAuthorizationStatus: () async =>
            IronwoodMigrationNotificationAuthorizationStatus.authorized,
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
      expect(notificationAuthorizationRequestCount, 0);
    },
  );

  test(
    'only iOS stages and arms native outbox payload after foreground preparation',
    () async {
      for (final isAndroid in [false, true]) {
        FlutterSecureStorage.setMockInitialValues({});
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
                case 'runOutboxOnceNow':
                  return <String, Object?>{'outcome': 'waiting'};
              }
              throw StateError('Unexpected method ${call.method}');
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final statuses = <rust_sync.MigrationStatus>[
          _migrationStatus(),
          _migrationStatus(activeRunId: 'run-1'),
          _migrationStatus(activeRunId: 'run-1'),
        ];
        final service = IronwoodMigrationService(
          getWalletDbPath: () async => '/tmp/wallet.db',
          getStatus:
              ({required dbPath, required network, required accountUuid}) {
                return Future.value(statuses.removeAt(0));
              },
          getPrivatePlan:
              ({
                required dbPath,
                required network,
                required accountUuid,
              }) async => null,
          secureStore: AppSecureStore.testing(
            storage: const FlutterSecureStorage(),
          ),
          backgroundCredentialStore: _backgroundCredentialStore(),
          getEndpoint: _testEndpoint,
          getSessionPassword: () => throw StateError('session password used'),
          getMnemonicBytesForAccount: (_) async =>
              Uint8List.fromList([1, 2, 3]),
          isMobile: () => true,
          isIOS: () => !isAndroid,
          isAndroid: () => isAndroid,
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

        if (isAndroid) {
          expect(events, ['credentialOperation']);
          expect(stagedPayload, isNull);
          expect(armedPayload, isNull);
          continue;
        }
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
      }
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

  test(
    'status stays read-only and explicit recovery records proof readiness',
    () async {
      final store = await _boundBackgroundCredentialStore();
      final records = <Map<String, Object?>>[];
      var proofReady = true;
      var ios = true;
      var android = false;
      final service = IronwoodMigrationService(
        getWalletDbPath: () async => '/tmp/wallet.db',
        getStatus: ({required dbPath, required network, required accountUuid}) {
          return Future.value(
            _migrationStatus(
              activeRunId: 'run-1',
              proofReady: proofReady,
              nextActionHeight: 288,
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
        isMobile: () => true,
        isIOS: () => ios,
        isAndroid: () => android,
        listMigrationOutboxReceipts: () async => const [],
        recordVerifiedProofReadiness:
            ({
              required network,
              required accountUuid,
              required runId,
              required observedHeight,
            }) async {
              records.add({
                'network': network,
                'accountUuid': accountUuid,
                'runId': runId,
                'observedHeight': observedHeight,
              });
              return true;
            },
      );

      await service.status(network: 'test', accountUuid: 'account-1');
      expect(records, isEmpty);
      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );
      proofReady = false;
      await service.status(network: 'test', accountUuid: 'account-1');
      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );
      ios = false;
      android = true;
      proofReady = true;
      await service.status(network: 'test', accountUuid: 'account-1');
      expect(records, hasLength(1));
      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );
      proofReady = false;
      await service.status(network: 'test', accountUuid: 'account-1');
      await service.resumeBackgroundPreparationIfNeeded(
        network: 'test',
        accountUuid: 'account-1',
      );

      expect(records, [
        {
          'network': 'test',
          'accountUuid': 'account-1',
          'runId': 'run-1',
          'observedHeight': 288,
        },
      ]);
    },
  );
}

rust_sync.MigrationStatus _migrationStatus({
  String phase = 'ready_to_prepare',
  String? activeRunId,
  int broadcastedTxCount = 0,
  bool? proofReady,
  int? nextActionHeight,
  List<rust_sync.MigrationPartStatus> parts = const [],
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
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
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    nextActionHeight: nextActionHeight,
    proofReady: proofReady,
    scheduledBroadcasts: scheduledBroadcasts,
    parts: parts,
  );
}

rust_sync.MigrationScheduledBroadcast _scheduledBroadcast({
  required String txidHex,
}) {
  return rust_sync.MigrationScheduledBroadcast(
    txidHex: txidHex,
    valueZatoshi: BigInt.from(100000),
    scheduledAtMs: 0,
    scheduledHeight: 1_000,
    status: 'scheduled',
  );
}

rust_sync.MigrationPartStatus _migrationPart({
  required String txidHex,
  rust_sync.MigrationPartState state = rust_sync.MigrationPartState.scheduled,
}) {
  return rust_sync.MigrationPartStatus(
    partIndex: 0,
    valueZatoshi: BigInt.from(100000),
    state: state,
    txidHex: txidHex,
    confirmationCount: 0,
    confirmationTarget: 1,
  );
}

RpcEndpointConfig _testEndpoint() => const RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://lwd.example:443',
);

IronwoodMigrationService _preparationTrackingSupportService({
  bool isIOS = true,
  bool isAndroid = false,
  required IronwoodMigrationPreparationTrackingSupportCheck
  supportsBackgroundPreparationTracking,
}) {
  return IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async =>
            _migrationStatus(),
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: _testEndpoint,
    isMacOS: () => false,
    isMobile: () => true,
    isIOS: () => isIOS,
    isAndroid: () => isAndroid,
    supportsBackgroundPreparationTracking:
        supportsBackgroundPreparationTracking,
  );
}

IronwoodMigrationService _notificationAuthorizationService({
  required bool isIOS,
  bool isAndroid = false,
  required List<rust_sync.MigrationStatus> statuses,
  Future<bool> Function()? requestNotificationAuthorization,
  Future<IronwoodMigrationNotificationAuthorizationStatus> Function()?
  getNotificationAuthorizationStatus,
  Future<bool> Function()? openNotificationSettings,
  Future<bool> Function()? startBackgroundPreparation,
  Future<bool> Function()? scheduleBackgroundMigration,
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
    isAndroid: () => isAndroid,
    requestNotificationAuthorization: requestNotificationAuthorization,
    getNotificationAuthorizationStatus:
        getNotificationAuthorizationStatus ??
        () async => IronwoodMigrationNotificationAuthorizationStatus.authorized,
    openNotificationSettings: openNotificationSettings,
    startBackgroundPreparation: startBackgroundPreparation,
    scheduleBackgroundMigration:
        scheduleBackgroundMigration ?? () async => true,
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

rust_sync.MigrationOutboxBatch _outboxBatch({
  String runId = 'run-1',
  List<String>? txids,
}) {
  return rust_sync.MigrationOutboxBatch(
    runId: runId,
    timingMeanBlocks: 144,
    timingMaxBlocks: 576,
    nextProofHeight: 576,
    items: txids != null
        ? [
            for (final (index, txid) in txids.indexed)
              rust_sync.MigrationOutboxItem(
                itemId: txid,
                partIndex: index,
                txidHex: txid,
                rawTransaction: Uint8List.fromList([1, 2, 3, 4]),
                anchorBoundaryHeight: 144,
                scheduledHeight: 288,
                scheduleStartHeight: 288,
                expiryHeight: 34_560,
              ),
          ]
        : [
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

Future<List<String>> _noAttemptedOutboxTxids({
  required String network,
  required String accountUuid,
  required String runId,
}) async => const [];

rust_sync.KeystoneMigrationSigningRequest _keystoneSigningRequest() {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'request-1',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'message-1',
        redactedPczt: Uint8List.fromList([1, 2, 3]),
      ),
    ],
    signingBatchLimit: 35,
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
