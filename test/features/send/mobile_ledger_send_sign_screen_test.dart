@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/services/sapling_params.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

final _args = SendReviewArgs(
  proposalId: BigInt.one,
  sendFlowId: 'flow-1',
  proposalAccountUuid: 'account-1',
  address: 'u1recipient',
  addressType: 'unified',
  amountZatoshi: BigInt.from(100000),
  feeZatoshi: BigInt.from(10000),
  needsSaplingParams: false,
);

const _params = SaplingParamsStatus(
  spendPath: '/tmp/spend',
  outputPath: '/tmp/output',
  spendExists: true,
  outputExists: true,
);

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
  });

  testWidgets('redacts, proves, signs, and checkpoints before handoff', (
    tester,
  ) async {
    final events = <String>[];
    final operationService = _FakeOperationService(events: events);
    LedgerBroadcastArgs? result;

    await tester.pumpWidget(
      _app(
        operationService: operationService,
        signer: (pczt) async {
          events.add('sign:$pczt');
          return const [4];
        },
        events: events,
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();

    expect(events, [
      'create',
      'redact:[1]',
      'proofs:[1]',
      'sign:[2]',
      'checkpoint:[3]:[4]',
    ]);
    expect(result?.operationId, 'send:account-1:flow-1');
    expect(result?.reviewArgs, same(_args));
  });

  testWidgets('cancel stays on the Ledger path and ignores cancel errors', (
    tester,
  ) async {
    final signing = Completer<List<int>>();
    var cancelCalls = 0;

    await tester.pumpWidget(
      _app(
        operationService: _FakeOperationService(),
        signer: (_) => signing.future,
        canceller: () async {
          cancelCalls++;
          throw StateError('device disconnected');
        },
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_ledger_signing_surface')),
      findsOneWidget,
    );
    expect(find.textContaining('Keystone'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Open signing'), findsOneWidget);
    expect(cancelCalls, 1);
  });

  testWidgets('retrying a failed checkpoint never asks Ledger to sign again', (
    tester,
  ) async {
    final operationService = _FakeOperationService(failCheckpointOnce: true);
    var signCalls = 0;
    LedgerBroadcastArgs? result;

    await tester.pumpWidget(
      _app(
        operationService: operationService,
        signer: (_) async {
          signCalls++;
          return const [4];
        },
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();

    expect(find.text('Signature preserved'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    expect(find.text('Retry saving'), findsOneWidget);

    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();

    expect(signCalls, 1);
    expect(operationService.checkpointCalls, 2);
    expect(result, isNotNull);
  });
}

Widget _app({
  required _FakeOperationService operationService,
  required Future<List<int>> Function(List<int> pcztBytes) signer,
  LedgerOperationCanceller? canceller,
  List<String>? events,
  ValueChanged<LedgerBroadcastArgs>? onResult,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => TextButton(
          onPressed: () async {
            final result = await context.push<LedgerBroadcastArgs>('/sign');
            if (result != null) onResult?.call(result);
          },
          child: const Text('Open signing'),
        ),
      ),
      GoRoute(
        path: '/sign',
        builder: (_, _) => MobileLedgerSendSignScreen(
          args: _args,
          loadWalletDbPath: () async => '/tmp/wallet.db',
          loadSaplingParams: () async => _params,
          createPczt:
              ({
                required dbPath,
                required lightwalletdUrl,
                required network,
                required proposalId,
                required sendFlowId,
              }) async {
                events?.add('create');
                return const [1];
              },
          redactPczt: ({required pcztBytes}) async {
            events?.add('redact:$pcztBytes');
            return const [2];
          },
          addProofs:
              ({required pcztBytes, spendParamsPath, outputParamsPath}) async {
                events?.add('proofs:$pcztBytes');
                return const [3];
              },
          discardProposal: () async {},
        ),
      ),
      GoRoute(path: '/send', builder: (_, _) => const Text('new send')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      ledgerPcztSignerProvider.overrideWithValue(
        (_, pcztBytes) => signer(pcztBytes),
      ),
      ledgerOperationCancellerProvider.overrideWithValue(
        canceller ?? () async {},
      ),
      ledgerSignedOperationServiceProvider.overrideWithValue(operationService),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Ledger',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.ledger,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
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

class _FakeOperationService implements LedgerSignedOperationService {
  _FakeOperationService({this.events, this.failCheckpointOnce = false});

  final List<String>? events;
  final bool failCheckpointOnce;
  var checkpointCalls = 0;

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpointCalls++;
    events?.add('checkpoint:$pcztWithProofsBytes:$pcztWithSignaturesBytes');
    if (failCheckpointOnce && checkpointCalls == 1) {
      throw StateError('temporary storage failure');
    }
  }

  @override
  Future<void> acknowledge(String operationId) async {}

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => throw UnimplementedError();

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => const [];
}
