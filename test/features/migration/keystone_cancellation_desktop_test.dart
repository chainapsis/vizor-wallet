import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/wallet/keystone.dart'
    as rust_keystone_wallet;
import '../../fakes/fake_sync_notifier.dart';

void main() {
  setUpAll(() => RustLib.initMock(api: _SigningApi()));
  tearDownAll(RustLib.dispose);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'Keystone cancel failure retains ownership and permits retry (desktop)',
    (tester) async {
      _useMobileViewport(tester, size: const Size(1440, 900));
      final firstDiscard = Completer<void>();
      final lateProof = Completer<rust_sync.KeystoneMigrationProofStatus>();
      var discardCalls = 0;
      final discardedIds = <String>[];
      var proofCalls = 0;
      final service = _service(
        ios: true,
        onProofStatus: (_) {
          proofCalls++;
          if (proofCalls == 1) return lateProof.future;
          return Future.value(
            const rust_sync.KeystoneMigrationProofStatus(
              readyCount: 1,
              totalCount: 1,
              isReady: true,
              isFailed: false,
            ),
          );
        },
        onDiscardKeystoneRequest: (id) async {
          discardedIds.add(id);
          discardCalls++;
          if (discardCalls == 1) await firstDiscard.future;
        },
      );
      final router = GoRouter(
        initialLocation: '/sign',
        routes: [
          GoRoute(
            path: '/sign',
            builder: (_, _) =>
                const IronwoodMigrationKeystoneCombinedSignScreen(
                  approvedSchedule: [],
                ),
          ),
          GoRoute(
            path: '/migration/private/review',
            builder: (_, _) => const Text('Review route'),
          ),
          GoRoute(
            path: '/migration/options',
            builder: (_, _) => const Text('Review route'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap(hardware: true)),
            syncProvider.overrideWith(FakeSyncNotifier.new),
            ironwoodMigrationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.light, child: child!),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      VoidCallback cancel() => tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Back to review'))
          .onPressed!;
      final staleCancel = cancel();
      staleCancel();
      staleCancel();
      await tester.pump();
      expect(discardCalls, 1);
      expect(find.text('Review route'), findsNothing);
      expect(
        tester
            .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
            .any((p) => p.absorbing),
        isTrue,
      );
      firstDiscard.completeError(StateError('Injected cancellation failure'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Review route'), findsNothing);
      expect(
        find.text('Could not cancel the signing request. Try again.'),
        findsOneWidget,
      );
      expect(
        proofCalls,
        2,
        reason: 'Resume polling for the same owned request after failure',
      );
      lateProof.complete(
        const rust_sync.KeystoneMigrationProofStatus(
          readyCount: 0,
          totalCount: 1,
          isReady: false,
          isFailed: true,
          message: 'Obsolete proof failure',
        ),
      );
      await tester.pump();
      expect(find.text('Obsolete proof failure'), findsNothing);
      expect(proofCalls, 2);
      cancel()();
      await tester.pumpAndSettle();
      expect(discardCalls, 2);
      expect(discardedIds[1], discardedIds[0]);
      expect(find.text('Review route'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        discardCalls,
        2,
        reason: 'Successful cleanup must not run again in dispose',
      );
    },
  );
}

void _useMobileViewport(WidgetTester tester, {required Size size}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

AppBootstrapState _bootstrap({required bool hardware}) => AppBootstrapState(
  initialLocation: '/sign',
  initialAccountState: AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Wallet 1',
        order: 0,
        isHardware: hardware,
      ),
    ],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
IronwoodMigrationService _service({
  required bool ios,
  required Future<rust_sync.KeystoneMigrationProofStatus> Function(String)
  onProofStatus,
  required Future<void> Function(String) onDiscardKeystoneRequest,
}) => IronwoodMigrationService(
  getWalletDbPath: () async => '/tmp/wallet.db',
  getStatus:
      ({required dbPath, required network, required accountUuid}) async =>
          throw StateError('No migration status in isolated signing test'),
  getPrivatePlan:
      ({required dbPath, required network, required accountUuid}) async => null,
  secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
  getEndpoint: () => defaultRpcEndpointConfig('main'),
  getKeystoneProofStatus: ({required requestId}) => onProofStatus(requestId),
  discardKeystoneMigrationRequest: ({required requestId}) =>
      onDiscardKeystoneRequest(requestId),
  prepareKeystoneSingleQrMigration:
      ({
        required dbPath,
        required network,
        required accountUuid,
        required approvedSchedule,
      }) async => rust_sync.KeystoneMigrationSigningRequest(
        requestId: 'cancel-test-request',
        messages: [
          rust_sync.KeystoneMigrationMessage(
            id: 'message',
            redactedPczt: Uint8List.fromList([1]),
            expectedSignatureCount: 1,
          ),
        ],
        signingBatchLimit: 1,
      ),
);

class _SigningApi implements RustLibApi {
  @override
  void crateApiKeystoneResetUrSession() {}
  @override
  Future<List<String>> crateApiKeystoneEncodeZcashSignBatchUrParts({
    required String requestId,
    required List<rust_keystone_wallet.ZcashBatchMessageInput> messages,
    required BigInt maxFragmentLen,
  }) async => ['UR:ZCASH-SIGN-BATCH/$requestId'];
  @override
  Future<Uint32List> crateApiKeystoneZcashSignBatchRoundMessageCounts({
    required String requestId,
    required List<rust_keystone_wallet.ZcashBatchMessageInput> messages,
    required int maxMessages,
  }) async => Uint32List.fromList([messages.length]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
