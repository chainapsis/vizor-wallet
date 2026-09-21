@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';

import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_ledger_send_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/services/sapling_params.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

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

final _texArgs = SendReviewArgs(
  proposalId: BigInt.one,
  sendFlowId: 'flow-tex',
  proposalAccountUuid: 'account-1',
  address: 'tex1recipient',
  addressType: 'tex',
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

  testWidgets(
    'direct Ledger signing route rejects a newline before preparation',
    (tester) async {
      var signingCalls = 0;
      final events = <String>[];
      await tester.pumpWidget(
        _app(
          args: SendReviewArgs(
            proposalId: BigInt.one,
            sendFlowId: 'flow-newline',
            proposalAccountUuid: 'account-1',
            address: 'u1recipient',
            addressType: 'unified',
            amountZatoshi: BigInt.from(100000),
            feeZatoshi: BigInt.from(10000),
            needsSaplingParams: false,
            memo: 'first\nsecond',
          ),
          operationService: _FakeOperationService(),
          events: events,
          signer: (_) async {
            signingCalls++;
            return [2];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();
      expect(signingCalls, 0);
      expect(events, isNot(contains('create')));
      expect(
        find.text(
          "Ledger can't sign non-English text yet",
        ),
        findsOneWidget,
      );
    },
  );

  for (final stage in ['connect', 'readiness', 'sign']) {
    for (final kind in [
      LedgerMobileFailure.permissionDenied,
      LedgerMobileFailure.pairingInvalid,
      LedgerMobileFailure.bluetoothOff,
      LedgerMobileFailure.locationDisabled,
    ]) {
      testWidgets('$stage $kind shows recovery and clears it on retry', (
        tester,
      ) async {
        final original = LedgerMobileException(
          kind,
          'permission denied native diagnostic',
        );
        final Object error = switch (stage) {
          'connect' => LedgerConnectionRequiredException(
            'connect wrapper',
            cause: original,
          ),
          'readiness' => LedgerConnectionRequiredException(
            'connect wrapper',
            cause: LedgerAppReadinessException(
              LedgerAppReadinessFailure.unavailable,
              'readiness wrapper',
              cause: original,
            ),
          ),
          _ => original,
        };
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(kLedgerMobileMethodChannel),
          (call) async => call.method == 'bluetoothAccessStatus'
              ? {'permission': 'granted'}
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel(kLedgerMobileMethodChannel),
            null,
          ),
        );
        final accessRecovery = ledgerFailureGuidance(
          original,
        )!.bluetoothRecovery;
        var attempts = 0;
        await tester.pumpWidget(
          _app(
            operationService: _FakeOperationService(),
            signer: (_) async {
              attempts++;
              if (attempts == 1) throw error;
              return [4];
            },
          ),
        );
        await tester.tap(find.text('Open signing'));
        await tester.pumpAndSettle();
        if (ledgerFailureGuidance(original)!.pairingRecovery) {
          expect(
            find.text(
              ledgerFailureGuidance(original)!.pairingInvalid
                  ? 'Pair your Ledger again'
                  : 'Couldn’t connect to your Ledger',
            ),
            findsOneWidget,
          );
          expect(find.text('Find my Ledger'), findsOneWidget);
          expect(attempts, 1);
          return;
        }
        expect(
          find.text(
            accessRecovery
                ? 'Ready to reconnect'
                : ledgerFailureGuidance(original)!.message,
          ),
          findsOneWidget,
        );
        expect(
          find.text('The transaction was rejected on your Ledger.'),
          findsNothing,
        );
        expect(find.text('Open the Zcash app'), findsNothing);
        await tester.tap(find.text(accessRecovery ? 'Reconnect' : 'Try again'));
        await tester.pumpAndSettle();
        expect(attempts, 2);
        expect(
          find.text(
            accessRecovery
                ? 'Ready to reconnect'
                : ledgerFailureGuidance(original)!.message,
          ),
          findsNothing,
        );
      });
    }
  }

  testWidgets('unknown signer error does not diagnose a closed Zcash app', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        operationService: _FakeOperationService(),
        signer: (_) async => throw StateError('unknown diagnostic'),
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Ledger signing could not be completed. Check your device and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open the Zcash app'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final args in [_args, _texArgs]) {
    testWidgets(
      'uses latest fallback after parameter wait for ${args.addressType}',
      (tester) async {
        final route = _Route();
        final params = Completer<SaplingParamsStatus>();
        final urls = <String>[];
        await tester.pumpWidget(
          _app(
            args: args,
            operationService: _FakeOperationService(),
            signer: (_) async => [4],
            route: route,
            paramsLoader: () => params.future,
            onCreate: urls.add,
          ),
        );
        await tester.tap(find.text('Open signing'));
        await tester.pump();
        await tester.pump();
        ProviderScope.containerOf(
          tester.element(find.byType(MobileLedgerSendSignScreen)),
        ).read(rpcEndpointFailoverProvider);
        route.useFallback();
        params.complete(_params);
        await tester.pumpAndSettle();
        expect(urls, ['https://fallback.example:443']);
      },
    );
  }

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

  testWidgets(
    'cancel waits for PCZT creation before returning proposal ownership',
    (tester) async {
      final creation = Completer<void>();
      var discards = 0;
      var signs = 0;
      addTearDown(() {
        if (!creation.isCompleted) creation.complete();
      });
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async {
            signs++;
            return const [4];
          },
          canceller: () async {},
          creationGate: creation.future,
          onDiscard: () async {
            discards++;
            return true;
          },
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Close',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MobileLedgerSendSignScreen), findsOneWidget);
      expect(discards, 0);
      creation.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Open signing'), findsOneWidget);
      expect(discards, 1);
      expect(signs, 0);
    },
  );

  testWidgets(
    'retry stays disabled until pending cancellation returns to review',
    (tester) async {
      final cancellation = Completer<void>();
      var signCalls = 0;
      addTearDown(() {
        if (!cancellation.isCompleted) cancellation.complete();
      });
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async {
            signCalls++;
            throw StateError(_deviceRejected);
          },
          canceller: () => cancellation.future,
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();
      final queuedRetry = tester
          .widget<LedgerSigningModal>(find.byType(LedgerSigningModal))
          .onFailureAction!;
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Close',
        ),
      );
      await tester.pump();
      queuedRetry();
      await tester.pump();
      expect(signCalls, 1);
      expect(
        tester
            .widget<LedgerSigningModal>(find.byType(LedgerSigningModal))
            .onFailureAction,
        isNull,
      );
      cancellation.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open signing'), findsOneWidget);
    },
  );

  testWidgets(
    'Ledger status 0x6a80 asks for a new transaction without blaming the user',
    (tester) async {
      var signCalls = 0;
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async {
            signCalls++;
            throw StateError(
              'ledger_status_6a80: Ledger rejected the PCZT data or key path',
            );
          },
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();

      expect(find.text('Request not accepted'), findsOneWidget);
      expect(find.text(kLedgerHostRequestRejectedMessage), findsOneWidget);
      expect(find.textContaining('rejected on your Ledger'), findsNothing);
      expect(
        find.byKey(const ValueKey('ledger_device_app_prompt_mainnet')),
        findsNothing,
      );
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Create new transaction'), findsOneWidget);
      expect(signCalls, 1);
    },
  );

  testWidgets(
    'new transaction waits for proposal release before opening send',
    (tester) async {
      final release = Completer<bool>();
      var discards = 0;
      addTearDown(() {
        if (!release.isCompleted) release.complete(true);
      });
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async => throw StateError(_hostRejected),
          onDiscard: () {
            discards++;
            return release.future;
          },
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(discards, 1);
      expect(find.text('new send'), findsNothing);
      expect(find.byType(MobileLedgerSendSignScreen), findsOneWidget);
      expect(
        tester
            .widget<LedgerSigningModal>(find.byType(LedgerSigningModal))
            .onFailureAction,
        isNull,
      );

      release.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('new send'), findsOneWidget);
      expect(discards, 1);
    },
  );

  testWidgets(
    'failed proposal release stays on screen and allows another attempt',
    (tester) async {
      final results = [false, true];
      var discards = 0;
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async => throw StateError(_hostRejected),
          onDiscard: () async => results[discards++],
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new transaction'));
      await tester.pumpAndSettle();

      expect(discards, 1);
      expect(find.text('new send'), findsNothing);
      expect(
        find.text('Could not finish cancelling. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Create new transaction'), findsOneWidget);

      await tester.tap(find.text('Create new transaction'));
      await tester.pumpAndSettle();
      expect(discards, 2);
      expect(find.text('new send'), findsOneWidget);
    },
  );

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
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Close',
      ),
    );
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

  testWidgets('Ledger TEX signs two rounds and checkpoints one batch', (
    tester,
  ) async {
    final events = <String>[];
    final operationService = _FakeOperationService(events: events);
    var signCalls = 0;

    await tester.pumpWidget(
      _app(
        args: _texArgs,
        operationService: operationService,
        signer: (pczt) async {
          events.add('sign:$pczt');
          return [++signCalls + 3];
        },
        events: events,
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();

    expect(events, [
      'create-tex',
      'redact:[1]',
      'redact:[5]',
      'proofs:[1]',
      'proofs:[5]',
      'sign:[2]',
      'sign:[6]',
      'checkpoint-batch:[[3], [7]]:[[4], [5]]',
    ]);
    expect(operationService.checkpointCalls, 0);
    expect(operationService.batchCheckpointCalls, 1);
  });

  testWidgets('Ledger TEX round two rejection retries only round two', (
    tester,
  ) async {
    final signedInputs = <List<int>>[];
    final operationService = _FakeOperationService();
    var signCalls = 0;

    await tester.pumpWidget(
      _app(
        args: _texArgs,
        operationService: operationService,
        signer: (pczt) async {
          signedInputs.add(List<int>.of(pczt));
          signCalls++;
          if (signCalls == 2) throw StateError(_deviceRejected);
          return [signCalls + 10];
        },
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();

    expect(
      find.text('The transaction was rejected on your Ledger.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(signedInputs, [
      const [2],
      const [6],
      const [6],
    ]);
    expect(operationService.batchSignatures, [
      const [11],
      const [13],
    ]);
    expect(operationService.batchCheckpointCalls, 1);
  });

  testWidgets(
    'legacy Orchard recovery requires an app update without retrying',
    (tester) async {
      await tester.pumpWidget(
        _app(
          operationService: _FakeOperationService(),
          signer: (_) async => throw StateError(
            '$kLedgerLegacyOrchardRecoveryErrorCode: test fixture',
          ),
        ),
      );
      await tester.tap(find.text('Open signing'));
      await tester.pumpAndSettle();

      expect(find.text('Ledger app update required'), findsOneWidget);
      expect(
        find.text(kLedgerLegacyOrchardRecoveryUnavailableMessage),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets('Ledger TEX round two rejection can cancel the proposal', (
    tester,
  ) async {
    var signCalls = 0;
    var cancelCalls = 0;
    var discardCalls = 0;

    await tester.pumpWidget(
      _app(
        args: _texArgs,
        operationService: _FakeOperationService(),
        signer: (_) async {
          signCalls++;
          if (signCalls == 2) throw StateError(_deviceRejected);
          return const [4];
        },
        canceller: () async => cancelCalls++,
        onDiscard: () async {
          discardCalls++;
          return true;
        },
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Close',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open signing'), findsOneWidget);
    expect(cancelCalls, 1);
    expect(discardCalls, 1);
  });

  testWidgets('Ledger TEX checkpoint retry preserves both signatures', (
    tester,
  ) async {
    final operationService = _FakeOperationService(failCheckpointOnce: true);
    var signCalls = 0;

    await tester.pumpWidget(
      _app(
        args: _texArgs,
        operationService: operationService,
        signer: (_) async => [++signCalls + 3],
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pumpAndSettle();

    expect(find.text('Signature preserved'), findsOneWidget);
    await tester.tap(find.text('Retry saving'));
    await tester.pumpAndSettle();

    expect(signCalls, 2);
    expect(operationService.batchCheckpointCalls, 2);
    expect(operationService.batchSignatures, [
      const [4],
      const [5],
    ]);
  });

  testWidgets('Ledger TEX modal reports each approval round', (tester) async {
    final first = Completer<List<int>>();
    final second = Completer<List<int>>();
    var signCalls = 0;

    await tester.pumpWidget(
      _app(
        args: _texArgs,
        operationService: _FakeOperationService(),
        signer: (_) {
          signCalls++;
          return signCalls == 1 ? first.future : second.future;
        },
      ),
    );
    await tester.tap(find.text('Open signing'));
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LedgerSigningModal)),
    );
    final firstProgress = container
        .read(ledgerSigningProgressProvider.notifier)
        .begin('account-1');
    firstProgress('sending');
    await tester.pump();
    expect(find.text('Processing with Ledger'), findsOneWidget);
    firstProgress('reviewing');
    await tester.pump();
    expect(find.text('Confirm on your Ledger'), findsOneWidget);
    expect(find.text('Transaction 1 of 2'), findsOneWidget);

    first.complete(const [4]);
    await tester.pump();
    await tester.pump();
    final secondProgress = container
        .read(ledgerSigningProgressProvider.notifier)
        .begin('account-1');
    firstProgress('finishing');
    await tester.pump();
    expect(find.text('Preparing transaction'), findsOneWidget);
    secondProgress('reviewing');
    await tester.pump();
    expect(find.text('Confirm on your Ledger'), findsOneWidget);
    expect(find.text('Transaction 2 of 2'), findsOneWidget);

    second.complete(const [8]);
    await tester.pumpAndSettle();
  });
}

Widget _app({
  SendReviewArgs? args,
  required _FakeOperationService operationService,
  required Future<List<int>> Function(List<int> pcztBytes) signer,
  LedgerOperationCanceller? canceller,
  List<String>? events,
  ValueChanged<LedgerBroadcastArgs>? onResult,
  Future<bool> Function()? onDiscard,
  Future<void>? creationGate,
  _Route? route,
  Future<SaplingParamsStatus> Function()? paramsLoader,
  void Function(String)? onCreate,
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
          args: args ?? _args,
          loadWalletDbPath: () async => '/tmp/wallet.db',
          loadSaplingParams: paramsLoader ?? () async => _params,
          createPczt:
              ({
                required dbPath,
                required lightwalletdUrl,
                required network,
                required proposalId,
                required sendFlowId,
              }) async {
                onCreate?.call(lightwalletdUrl);
                events?.add('create');
                if (creationGate != null) await creationGate;
                return const [1];
              },
          createTexPczts:
              ({
                required dbPath,
                required lightwalletdUrl,
                required network,
                required proposalId,
                required sendFlowId,
              }) async {
                onCreate?.call(lightwalletdUrl);
                events?.add('create-tex');
                return rust_sync.TexPcztPairResult(
                  pczts: [
                    Uint8List.fromList([1]),
                    Uint8List.fromList([5]),
                  ],
                  signerPczts: [
                    Uint8List.fromList([8]),
                    Uint8List.fromList([9]),
                  ],
                );
              },
          redactPczt: ({required pcztBytes}) async {
            events?.add('redact:$pcztBytes');
            return [pcztBytes.single + 1];
          },
          addProofs:
              ({required pcztBytes, spendParamsPath, outputParamsPath}) async {
                events?.add('proofs:$pcztBytes');
                return [pcztBytes.single + 2];
              },
          discardProposal: onDiscard ?? () async => true,
        ),
      ),
      GoRoute(path: '/send', builder: (_, _) => const Text('new send')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      if (route != null) rpcEndpointFailoverProvider.overrideWith(() => route),
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

class _FakeOperationService
    implements
        LedgerSignedOperationService,
        LedgerSignedOperationBatchCheckpointService {
  _FakeOperationService({this.events, this.failCheckpointOnce = false});

  final List<String>? events;
  final bool failCheckpointOnce;
  var checkpointCalls = 0;
  var batchCheckpointCalls = 0;
  List<List<int>>? batchProofs;
  List<List<int>>? batchSignatures;

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
  Future<void> checkpointBatch({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<List<int>> pcztsWithProofs,
    required List<List<int>> pcztsWithSignatures,
    String? externalRef,
  }) async {
    batchCheckpointCalls++;
    batchProofs = pcztsWithProofs.map(List<int>.of).toList();
    batchSignatures = pcztsWithSignatures.map(List<int>.of).toList();
    events?.add('checkpoint-batch:$batchProofs:$batchSignatures');
    if (failCheckpointOnce && batchCheckpointCalls == 1) {
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

class _Route extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: defaultRpcEndpointConfig('main'),
    fallbackCandidates: const [],
  );
  void useFallback() {
    state = state.copyWith(
      current: const RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: 'https://fallback.example:443',
      ),
    );
  }
}

const _deviceRejected =
    'ledger_status_6985: Ledger request was rejected or the PCZT was not finalized';

const _hostRejected =
    'ledger_status_6a80: Ledger rejected the PCZT data or key path';
