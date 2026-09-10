// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_secret_operation_guard.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/providers/wallet_link_provider.dart';
import 'package:zcash_wallet/src/features/wallet_link/services/wallet_link_api_client.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart'
    show AccountExportMetadata;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _accountUuid = 'account-1';
const _accounts = AccountState(
  accounts: [AccountInfo(uuid: _accountUuid, name: 'Test', order: 0)],
  activeAccountUuid: _accountUuid,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rust = _ConsumerRustFake();
  late AppSecureStore store;
  late LinuxKeyringCoordinator coordinator;
  late _DelayedAccountNotifier accounts;
  late ProviderContainer container;

  setUpAll(() => RustLib.initMock(api: rust));
  tearDownAll(RustLib.dispose);
  setUp(() async {
    rust.reset();
    FlutterSecureStorage.setMockInitialValues({
      kWalletDbNameKey: 'zcash_wallet_consumer_test.db',
    });
    store = AppSecureStore.testing(
      storage: const FlutterSecureStorage(),
      enforceSessionGeneration: true,
    )..setSessionPassword('Testpass1!');
    coordinator = LinuxKeyringCoordinator.testing();
    accounts = _DelayedAccountNotifier();
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        linuxSecretOperationStoreProvider.overrideWithValue(store),
        linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
        accountProvider.overrideWith(() => accounts),
        syncProvider.overrideWith(_ConsumerSyncNotifier.new),
      ],
    );
    await container.read(accountProvider.future);
    await container.read(syncProvider.future);
    final directory = await Directory.systemTemp.createTemp('linux-consumers-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() async {
      PathProviderPlatform.instance = oldPaths;
      await directory.delete(recursive: true);
      container.dispose();
      coordinator.dispose();
    });
  });

  Future<WidgetRef> mountConsumer(WidgetTester tester) async {
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            widgetRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );
    return widgetRef;
  }

  for (final flow in ['send', 'shield', 'swap']) {
    for (final interruption in [
      'lock and unlock',
      'account removal',
      'mutation before account state publication',
      'dispose',
    ]) {
      testWidgets('Linux $flow discards credentials after $interruption', (
        tester,
      ) async {
        final ref = await mountConsumer(tester);
        Future<Object?>? completion;
        await tester.runAsync(() async {
          final operation = switch (flow) {
            'send' => runSendBroadcast(
              ref: ref,
              args: _sendArgs(),
              confirmSaplingParamsDownload: () async => false,
              shouldAbort: () async => !ref.context.mounted,
            ),
            'shield' => shieldTransparentSoftwareBalance(
              ref: ref,
              accountUuid: _accountUuid,
            ),
            _ =>
              container
                  .read(swapDepositSenderProvider)
                  .sendZecDeposit(accountUuid: _accountUuid, quote: _quote()),
          };
          completion = operation.then<Object?>(
            (value) => value,
            onError: (Object error) => error,
          );
          await accounts.started.future.timeout(const Duration(seconds: 3));
        });

        Completer<void>? mutationRelease;
        Future<void>? mutation;
        switch (interruption) {
          case 'lock and unlock':
            store.clearSessionPassword();
            store.setSessionPassword('Testpass1!');
          case 'account removal':
            accounts.removeAll();
          case 'mutation before account state publication':
            mutationRelease = Completer<void>();
            mutation = coordinator.runMutation(() => mutationRelease!.future);
          case 'dispose':
            if (flow == 'swap') container.dispose();
            await tester.pumpWidget(const SizedBox());
        }

        Object? outcome;
        await tester.runAsync(() async {
          accounts.release();
          outcome = await completion;
        });

        expect(rust.executeCalls, 0);
        expect(rust.shieldCalls, 0);
        expect(accounts.bytes, everyElement(0));
        if (flow == 'send') {
          expect(
            (outcome as SendBroadcastOutcome).phase,
            anyOf(SendBroadcastPhase.failed, SendBroadcastPhase.aborted),
          );
        } else {
          expect(outcome, isA<SecureStorageSessionChangedException>());
        }
        expect(rust.discardCalls, flow == 'shield' ? 0 : 1);
        mutationRelease?.complete();
        await mutation;
      });
    }

    testWidgets(
      'Linux $flow proceeds when its pending request is still current',
      (tester) async {
        final ref = await mountConsumer(tester);
        await tester.runAsync(() async {
          final operation = switch (flow) {
            'send' => runSendBroadcast(
              ref: ref,
              args: _sendArgs(),
              confirmSaplingParamsDownload: () async => false,
            ),
            'shield' => shieldTransparentSoftwareBalance(
              ref: ref,
              accountUuid: _accountUuid,
            ),
            _ =>
              container
                  .read(swapDepositSenderProvider)
                  .sendZecDeposit(accountUuid: _accountUuid, quote: _quote()),
          };
          await accounts.started.future.timeout(const Duration(seconds: 3));
          accounts.release();
          await operation;
        });
        expect(rust.executeCalls + rust.shieldCalls, 1);
        expect(rust.discardCalls, 0);
        expect(accounts.bytes, everyElement(0));
      },
    );
  }

  test(
    'Linux swap rechecks the existing quote deadline before signing',
    () async {
      final send = container
          .read(swapDepositSenderProvider)
          .sendZecDeposit(
            accountUuid: _accountUuid,
            quote: _quote(expired: true),
          );
      final failed = expectLater(send, throwsA(isA<StateError>()));
      await accounts.started.future.timeout(const Duration(seconds: 3));
      accounts.release();
      await failed;
      expect(rust.executeCalls, 0);
      expect(rust.discardCalls, 1);
      expect(accounts.bytes, everyElement(0));
    },
  );

  for (final interruption in [
    'lock and unlock',
    'account removal',
    'expire',
    'dispose',
    'none',
    'lock during upload',
  ]) {
    test(
      'Linux wallet link validates its delayed request: $interruption',
      () async {
        final client = _RecordingLinkClient(
          delayUpload: interruption == 'lock during upload',
        );
        final linkContainer = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            linuxSecretOperationStoreProvider.overrideWithValue(store),
            linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
            accountProvider.overrideWith(
              () => accounts = _DelayedAccountNotifier(),
            ),
            walletLinkApiClientProvider.overrideWithValue(client),
          ],
        );
        addTearDown(linkContainer.dispose);
        addTearDown(() => client.close(force: true));
        await linkContainer.read(accountProvider.future);
        final subscription = linkContainer.listen(
          walletLinkControllerProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        final controller = linkContainer.read(
          walletLinkControllerProvider.notifier,
        );
        final operation = controller.start();
        await accounts.started.future.timeout(const Duration(seconds: 3));

        if (interruption == 'lock during upload') {
          accounts.release();
          await client.uploadStarted.future;
        }
        switch (interruption) {
          case 'lock during upload':
          case 'lock and unlock':
            store.clearSessionPassword();
            store.setSessionPassword('Testpass1!');
          case 'account removal':
            accounts.removeAll();
          case 'expire':
            controller.expire();
          case 'dispose':
            linkContainer.dispose();
          case 'none':
            break;
        }
        if (interruption != 'lock during upload') accounts.release();
        client.uploadRelease?.complete();
        await operation;
        expect(
          client.uploads,
          interruption == 'none' || interruption == 'lock during upload'
              ? 1
              : 0,
        );
        if (interruption == 'none') {
          expect(
            linkContainer.read(walletLinkControllerProvider).phase,
            WalletLinkPhase.ready,
          );
        } else if (interruption == 'lock during upload') {
          expect(
            linkContainer.read(walletLinkControllerProvider).phase,
            WalletLinkPhase.error,
          );
          expect(
            linkContainer.read(walletLinkControllerProvider).qrPayload,
            isNull,
          );
        }
      },
    );
  }
}

SendReviewArgs _sendArgs() => SendReviewArgs(
  proposalId: BigInt.one,
  sendFlowId: 'linux-consumer',
  proposalAccountUuid: _accountUuid,
  address: 'u1recipient',
  addressType: 'unified',
  amountZatoshi: BigInt.from(100000000),
  feeZatoshi: BigInt.from(10000),
  needsSaplingParams: false,
);

SwapQuote _quote({bool expired = false}) => SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  sellAmount: 1,
  sellAmountBaseUnits: BigInt.from(100000000),
  receiveAmount: 50,
  minimumReceiveAmount: 49,
  providerLabel: 'Test',
  feeLabel: 'Included',
  expiryLabel: '01:00',
  quoteExpiresAt: expired ? DateTime.utc(2000) : null,
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 'u1deposit',
    expiresInLabel: '01:00',
    reuseWarning: '',
  ),
);

class _DelayedAccountNotifier extends AccountNotifier {
  final started = Completer<void>();
  final _released = Completer<void>();
  final bytes = Uint8List.fromList([1, 2, 3]);
  @override
  FutureOr<AccountState> build() => _accounts;

  void removeAll() => state = const AsyncData(AccountState());
  void release() => _released.complete();

  Future<void> _wait() async {
    started.complete();
    await _released.future;
  }

  @override
  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) async {
    await _wait();
    return bytes;
  }

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async {
    await _wait();
    return const SoftwareWalletSecret(mnemonic: 'test recovery material');
  }
}

class _ConsumerSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _accountUuid,
    hasAccountScopedData: true,
    canShieldTransparentBalance: true,
  );
  @override
  Future<T> runWithAuthoritativeSpendable<T>({
    required String accountUuid,
    required Future<T> Function() operation,
  }) => operation();
  @override
  Future<void> refreshAfterSend() async {}
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _ConsumerRustFake implements RustLibApi {
  int executeCalls = 0;
  int shieldCalls = 0;
  int discardCalls = 0;
  void reset() {
    executeCalls = 0;
    shieldCalls = 0;
    discardCalls = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #crateApiSyncExecuteProposal:
        executeCalls++;
        return Future.value(
          const ExecuteProposalResult(
            txids: 'test-txid',
            status: 'broadcasted',
            broadcastedCount: 1,
            totalCount: 1,
          ),
        );
      case #crateApiSyncShieldTransparentBalance:
        shieldCalls++;
        return Future.value(
          ShieldTransparentResult(
            txids: 'test-txid',
            status: 'broadcasted',
            broadcastedCount: 1,
            totalCount: 1,
            feeZatoshi: BigInt.one,
            shieldedZatoshi: BigInt.from(100000000),
          ),
        );
      case #crateApiSyncDiscardProposal:
        discardCalls++;
        return Future<void>.value();
      case #crateApiSyncProposeSend:
        return Future.value(
          ProposalResult(
            proposalId: BigInt.one,
            needsSaplingParams: false,
            feeZatoshi: BigInt.from(10000),
          ),
        );
      case #crateApiSyncGetExportBirthdayHeight:
        return Future.value(BigInt.from(1));
      case #crateApiWalletGetAccountExportMetadata:
        return Future.value(const AccountExportMetadata(zip32AccountIndex: 0));
      default:
        return super.noSuchMethod(invocation);
    }
  }
}

class _RecordingLinkClient extends WalletLinkApiClient {
  _RecordingLinkClient({bool delayUpload = false})
    : uploadRelease = delayUpload ? Completer<void>() : null;

  final uploadStarted = Completer<void>();
  final Completer<void>? uploadRelease;
  int uploads = 0;

  @override
  Future<WalletLinkCreatePackageResponse> createPackage(
    WalletLinkCreatePackageRequest input,
  ) async {
    uploads++;
    uploadStarted.complete();
    await uploadRelease?.future;
    return WalletLinkCreatePackageResponse(
      id: input.id,
      expiresAt: 9999999999,
      ttlSeconds: 60,
    );
  }

  @override
  Future<WalletLinkPackageStatus> getPackageStatus(String packageId) async =>
      WalletLinkPackageStatus(
        id: packageId,
        status: WalletLinkPackageCompletionStatus.pending,
        expiresAt: 9999999999,
      );

  @override
  Future<void> revokePackage(String packageId) async {}
}
