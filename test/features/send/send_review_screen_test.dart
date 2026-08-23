// path_provider / plugin platform fakes back the Keystone PCZT preparation
// flow (wallet DB path + Sapling params status).
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart'
    show
        resolveSendReviewRoutePayload,
        resolveSendStatusRoutePayload,
        SendStatusRoutePayloadObserver,
        sendStatusRoutePayloadProvider;
import 'package:zcash_wallet/src/features/send/widgets/send_review_content_view.dart';
import 'package:zcash_wallet/src/features/send/widgets/sapling_params_prompt.dart';
import 'package:zcash_wallet/src/features/send/widgets/verify_address_modal.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' show TexPcztPairResult;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_zec_market_data_cache.dart';

void main() {
  final rustApi = _RustApiFake();

  setUpAll(() {
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() async {
    rustApi.reset();
    FlutterSecureStorage.setMockInitialValues({});
    // Real-IO fakes for the Keystone PCZT preparation flow. Created here
    // because file system futures cannot complete inside the FakeAsync test
    // body.
    final tempDir = await Directory.systemTemp.createTemp('send_review_test');
    addTearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  testWidgets('renders the address-variant review layout', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'unified', memo: _longMemo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review send'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('15.12 ZEC'), findsOneWidget);
    expect(find.text(r'$1.06K'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text(truncatedAddress(_longAddress)), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text(_longMemo), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text('0.00012 ZEC'), findsOneWidget);
    expect(find.text('Confirm & send'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('renders the contact variant for an address-book match', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mike'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SendReviewContentView),
        matching: find.byType(AppProfilePicture),
      ),
      findsOneWidget,
    );
    expect(find.text(truncatedAddress(_longAddress)), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
    expect(find.text('Show full address'), findsOneWidget);
  });

  testWidgets('message expand toggles between truncated and full memo', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'sapling', memo: _veryLongMemo)),
    );
    await tester.pumpAndSettle();

    final collapsedMemo = tester.widget<Text>(find.text(_veryLongMemo));
    expect(collapsedMemo.maxLines, 1);
    expect(find.text('Collapse'), findsNothing);

    await tester.tap(find.text(_veryLongMemo));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsOneWidget);
    final expandedMemo = tester.widget<Text>(find.text(_veryLongMemo));
    expect(expandedMemo.maxLines, isNull);

    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsNothing);
    expect(tester.widget<Text>(find.text(_veryLongMemo)).maxLines, 1);
  });

  testWidgets('confirm pushes the status route without discarding', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(_reviewArgs(addressType: 'unified'), statusExtras: statusExtras),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm & send'));
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    expect(statusExtras.single, isA<SendReviewArgs>());
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('cancel discards the proposal and returns to send', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs(addressType: 'unified')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('send-route'), findsOneWidget);
    expect(rustApi.discardCalls, hasLength(1));
    expect(rustApi.discardCalls.single, (BigInt.one, 'test-send-flow'));
  });

  testWidgets('dispose discards an unconsumed proposal exactly once', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_harness(_reviewArgs(addressType: 'unified')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(rustApi.discardCalls, hasLength(1));
  });

  testWidgets('verify modal shows the full address grid for unknown address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsOneWidget);
    // The add-to-contacts flow is deferred; verification is display-only.
    expect(find.text('Add to contacts'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('verify_address_close_button')));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyAddressModal), findsNothing);
  });

  testWidgets('verify modal marks an unknown transparent address', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'transparent', address: _transparentAddress),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown transparent address'), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
  });

  testWidgets('review marks a TEX recipient distinctly from transparent', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'tex', address: _texAddress),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEX'), findsOneWidget);
    expect(find.text('Transparent'), findsNothing);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('verify modal shows the contact header for a saved address', (
    tester,
  ) async {
    rustApi.previousTransactionCount = 12;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
    // Contact name in the modal header AND on the review screen behind it.
    expect(find.text('Mike'), findsNWidgets(2));
    expect(find.text('12 previous transactions'), findsOneWidget);
  });

  testWidgets('verify modal hides a zero previous transaction count', (
    tester,
  ) async {
    rustApi.previousTransactionCount = 0;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository([
          _contact(id: 'mike', label: 'Mike', address: _longAddress),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Mike'), findsNWidgets(2));
    expect(find.textContaining('previous transaction'), findsNothing);
  });

  testWidgets('verify modal shows own-account header without tx count', (
    tester,
  ) async {
    rustApi
      ..unifiedAddress = _longAddress
      ..previousTransactionCount = 4;
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        addressBookRepository: _FakeAddressBookRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    await _flushRealAsync(tester);
    await tester.pumpAndSettle();

    expect(find.byType(VerifyAddressModal), findsOneWidget);
    expect(find.text('Unknown shielded address'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(VerifyAddressModal),
        matching: find.text('Account 1'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('previous transaction'), findsNothing);
  });

  testWidgets(
    'transparent own-account address resolves to the account header',
    (tester) async {
      rustApi.transparentAddress = _transparentAddress;
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          _reviewArgs(addressType: 'transparent', address: _transparentAddress),
          addressBookRepository: _FakeAddressBookRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();
      await _flushRealAsync(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(VerifyAddressModal),
          matching: find.text('Account 1'),
        ),
        findsOneWidget,
      );
      expect(find.text('Unknown transparent address'), findsNothing);
      expect(find.textContaining('previous transaction'), findsNothing);
    },
  );

  testWidgets('hardware confirm opens the Keystone signing modal', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm with Keystone'), findsOneWidget);
    expect(find.text('Confirm & send'), findsNothing);

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);

    expect(find.byType(KeystoneSigningModal), findsOneWidget);
    // The review confirm button behind the scrim shares the same label, so
    // scope the title assertion to the modal.
    expect(
      find.descendant(
        of: find.byType(KeystoneSigningModal),
        matching: find.text('Confirm with Keystone'),
      ),
      findsOneWidget,
    );
    expect(find.text('Get signature'), findsOneWidget);
    expect(find.text('Scanning issues?'), findsOneWidget);
    expect(find.text('status-route'), findsNothing);
    expect(rustApi.createPcztCalls, 1);
  });

  testWidgets('Keystone handoff carries proofs and signatures to status', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();

    expect(find.text('keystone-scan-route'), findsOneWidget);
    await tester.tap(find.text('keystone-scan-route'));
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    final extra = statusExtras.single;
    expect(extra, isA<KeystoneBroadcastArgs>());
    final keystoneArgs = extra! as KeystoneBroadcastArgs;
    expect(keystoneArgs.pcztWithProofs.single, _fakeProofsBytes);
    expect(keystoneArgs.pcztWithSignatures.single, _fakeSignatureBytes);
    expect(keystoneArgs.reviewArgs.proposalId, BigInt.one);

    // The proposal was consumed by createPcztFromProposal; the handoff must
    // not discard it.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('Keystone TEX advances through two explicit signing rounds', (
    tester,
  ) async {
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'tex'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);
    expect(find.text('Transaction 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('keystone-scan-route'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction 2 of 2'), findsOneWidget);

    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('keystone-scan-route'));
    await tester.pumpAndSettle();

    final handoff = statusExtras.single as KeystoneBroadcastArgs;
    expect(handoff.pcztWithProofs, hasLength(2));
    expect(handoff.pcztWithSignatures, hasLength(2));
  });

  testWidgets('Ledger handoff signs directly and carries the PCZT pair', (
    tester,
  ) async {
    final statusExtras = <Object?>[];
    List<int>? signingRequest;
    final operationService = _FakeLedgerSignedOperationService();

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        statusExtras: statusExtras,
        ledgerOperationService: operationService,
        ledgerSigner: (pcztBytes) async {
          signingRequest = [...pcztBytes];
          return _fakeSignatureBytes;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm with Ledger'), findsOneWidget);
    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);

    expect(find.byType(LedgerSigningModal), findsNothing);
    expect(find.text('status-route'), findsOneWidget);
    expect(signingRequest, const [4, 5, 6]);
    final extra = statusExtras.single as LedgerBroadcastArgs;
    expect(
      extra.operationId,
      'send:test-account:${extra.reviewArgs.sendFlowId}',
    );
    expect(operationService.checkpoints, hasLength(1));
    expect(operationService.checkpoints.single.proofs, _fakeProofsBytes);
    expect(operationService.checkpoints.single.signatures, _fakeSignatureBytes);
  });

  testWidgets(
    'Ledger retry reuses the consumed proposal PCZT and retries only signing',
    (tester) async {
      final statusExtras = <Object?>[];
      final signingRequests = <List<int>>[];

      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          _reviewArgs(addressType: 'unified'),
          bootstrap: _bootstrap(
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
          ),
          statusExtras: statusExtras,
          ledgerSigner: (pcztBytes) async {
            signingRequests.add([...pcztBytes]);
            if (signingRequests.length == 1) {
              throw StateError('Ledger rejected the test PCZT');
            }
            return _fakeSignatureBytes;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm with Ledger'));
      await _flushRealAsync(tester);

      expect(find.text('Ledger signing failed'), findsOneWidget);
      expect(rustApi.createPcztCalls, 1);
      expect(rustApi.redactPcztCalls, 1);
      expect(rustApi.addProofsCalls, 1);

      await tester.tap(find.text('Try again'));
      await _flushRealAsync(tester);

      expect(find.text('status-route'), findsOneWidget);
      expect(rustApi.createPcztCalls, 1);
      expect(rustApi.redactPcztCalls, 1);
      expect(rustApi.addProofsCalls, 1);
      expect(signingRequests, const [
        [4, 5, 6],
        [4, 5, 6],
      ]);
      expect(statusExtras.single, isA<LedgerBroadcastArgs>());
    },
  );

  for (final dismissal in ['button', 'scrim', 'escape', 'back']) {
    testWidgets(
      'Ledger $dismissal dismissal keeps the same review and ignores a late signature',
      (tester) async {
        final signerResult = Completer<List<int>>();
        final operationService = _FakeLedgerSignedOperationService();
        var cancelCount = 0;
        addTearDown(() {
          if (!signerResult.isCompleted) {
            signerResult.complete(_fakeSignatureBytes);
          }
        });

        await _setDesktopViewport(tester);
        await tester.pumpWidget(
          _harness(
            _reviewArgs(addressType: 'unified'),
            bootstrap: _bootstrap(
              isHardware: true,
              hardwareSignerKind: HardwareSignerKind.ledger,
            ),
            ledgerOperationService: operationService,
            ledgerSigner: (_) => signerResult.future,
            ledgerCanceller: () async => cancelCount++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Confirm with Ledger'));
        await _flushRealAsync(tester);
        expect(find.text('Review on your Ledger'), findsOneWidget);

        switch (dismissal) {
          case 'button':
            await tester.tap(
              find.descendant(
                of: find.byType(LedgerSigningModal),
                matching: find.text('Cancel'),
              ),
            );
          case 'scrim':
            final overlayRect = tester.getRect(
              find.byType(AppPaneModalOverlay),
            );
            await tester.tapAt(overlayRect.topLeft + const Offset(8, 8));
          case 'escape':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'back':
            await tester.binding.handlePopRoute();
        }
        await _flushRealAsync(tester);

        expect(find.byType(LedgerSigningModal), findsNothing);
        expect(find.byType(SendReviewScreen), findsOneWidget);
        expect(find.text('Confirm with Ledger'), findsOneWidget);
        expect(find.text('15.12 ZEC'), findsOneWidget);
        expect(find.text(truncatedAddress(_longAddress)), findsOneWidget);
        expect(cancelCount, 1);
        expect(rustApi.discardCalls, isEmpty);
        expect(operationService.checkpoints, isEmpty);

        signerResult.complete(_fakeSignatureBytes);
        await _flushRealAsync(tester);

        expect(find.byType(SendReviewScreen), findsOneWidget);
        expect(find.text('status-route'), findsNothing);
        expect(operationService.checkpoints, isEmpty);
        expect(rustApi.discardCalls, isEmpty);
      },
    );
  }

  testWidgets('Ledger cancellation generation cannot affect the next request', (
    tester,
  ) async {
    final firstSignerResult = Completer<List<int>>();
    final secondSignerResult = Completer<List<int>>();
    final operationService = _FakeLedgerSignedOperationService();
    var signerCalls = 0;
    var cancelCount = 0;
    addTearDown(() {
      if (!firstSignerResult.isCompleted) {
        firstSignerResult.complete(_fakeSignatureBytes);
      }
      if (!secondSignerResult.isCompleted) {
        secondSignerResult.complete(_fakeSignatureBytes);
      }
    });

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerOperationService: operationService,
        ledgerSigner: (_) {
          signerCalls++;
          return signerCalls == 1
              ? firstSignerResult.future
              : secondSignerResult.future;
        },
        ledgerCanceller: () async => cancelCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(LedgerSigningModal),
        matching: find.text('Cancel'),
      ),
    );
    await _flushRealAsync(tester);

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(signerCalls, 2);

    firstSignerResult.complete(_fakeSignatureBytes);
    await _flushRealAsync(tester);
    expect(find.text('Review on your Ledger'), findsOneWidget);
    expect(operationService.checkpoints, isEmpty);

    secondSignerResult.complete(_fakeSignatureBytes);
    await _flushRealAsync(tester);
    expect(find.text('status-route'), findsOneWidget);
    expect(operationService.checkpoints, hasLength(1));
    expect(cancelCount, 1);
  });

  testWidgets('Ledger retry reuses an in-flight consumed proposal PCZT', (
    tester,
  ) async {
    final creationGate = Completer<void>();
    var cancelCount = 0;
    rustApi.createPcztGate = creationGate;
    addTearDown(() {
      if (!creationGate.isCompleted) creationGate.complete();
    });

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerSigner: (_) async => _fakeSignatureBytes,
        ledgerCanceller: () async => cancelCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(rustApi.createPcztCalls, 1);

    await tester.tap(
      find.descendant(
        of: find.byType(LedgerSigningModal),
        matching: find.text('Cancel'),
      ),
    );
    await _flushRealAsync(tester);
    expect(find.byType(SendReviewScreen), findsOneWidget);

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(rustApi.createPcztCalls, 1);

    creationGate.complete();
    await _flushRealAsync(tester);

    expect(find.text('status-route'), findsOneWidget);
    expect(rustApi.createPcztCalls, 1);
    expect(cancelCount, 1);
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('Ledger expired proposal requires a new transaction', (
    tester,
  ) async {
    final operationService = _FakeLedgerSignedOperationService();
    var signerCalls = 0;
    rustApi.createPcztError = StateError('proposal not found');

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerOperationService: operationService,
        ledgerSigner: (_) async {
          signerCalls++;
          return _fakeSignatureBytes;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);

    expect(find.text('Transaction expired'), findsOneWidget);
    expect(find.text('Create new transaction'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(signerCalls, 0);
    expect(operationService.checkpoints, isEmpty);

    await tester.tap(find.text('Create new transaction'));
    await tester.pumpAndSettle();

    expect(find.text('send-route'), findsOneWidget);
    expect(rustApi.discardCalls, [(BigInt.one, 'test-send-flow')]);
  });

  testWidgets('Ledger checkpoint retry preserves bytes without re-signing', (
    tester,
  ) async {
    final operationService = _FakeLedgerSignedOperationService()
      ..failuresRemaining = 1;
    var signerCalls = 0;

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerOperationService: operationService,
        ledgerSigner: (_) async {
          signerCalls++;
          return _fakeSignatureBytes;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);

    expect(find.text('Could not save signed transaction'), findsOneWidget);
    expect(find.text('Retry saving'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LedgerSigningModal),
        matching: find.text('Cancel'),
      ),
      findsNothing,
    );
    expect(signerCalls, 1);
    expect(operationService.checkpoints, hasLength(1));

    await tester.tap(find.text('Retry saving'));
    await _flushRealAsync(tester);

    expect(find.text('status-route'), findsOneWidget);
    expect(signerCalls, 1);
    expect(rustApi.createPcztCalls, 1);
    expect(rustApi.redactPcztCalls, 1);
    expect(rustApi.addProofsCalls, 1);
    expect(operationService.checkpoints, hasLength(2));
    expect(
      operationService.checkpoints.map((checkpoint) => checkpoint.operationId),
      everyElement('send:test-account:test-send-flow'),
    );
    expect(
      operationService.checkpoints.map((checkpoint) => checkpoint.accountUuid),
      everyElement('test-account'),
    );
    expect(
      operationService.checkpoints.map((checkpoint) => checkpoint.kind),
      everyElement(LedgerSignedOperationKind.send),
    );
    expect(
      operationService.checkpoints.map((checkpoint) => checkpoint.proofs),
      everyElement(_fakeProofsBytes),
    );
    expect(
      operationService.checkpoints.map((checkpoint) => checkpoint.signatures),
      everyElement(_fakeSignatureBytes),
    );
  });

  testWidgets('Ledger checkpoint integrity failure blocks every retry', (
    tester,
  ) async {
    final operationService = _FakeLedgerSignedOperationService()
      ..failuresRemaining = 1
      ..checkpointError = StateError(
        'Ledger signed operation cannot be retried with different data',
      );
    var signerCalls = 0;

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerOperationService: operationService,
        ledgerSigner: (_) async {
          signerCalls++;
          return _fakeSignatureBytes;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);

    expect(find.text('Signed transaction needs attention'), findsOneWidget);
    expect(find.text('Retry saving'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(LedgerSigningModal),
        matching: find.text('Cancel'),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Signed transaction needs attention'), findsOneWidget);
    expect(signerCalls, 1);
    expect(operationService.checkpoints, hasLength(1));
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('Ledger saving state cannot be dismissed after signature', (
    tester,
  ) async {
    final checkpointGate = Completer<void>();
    final operationService = _FakeLedgerSignedOperationService()
      ..checkpointGate = checkpointGate;
    var cancelCount = 0;
    addTearDown(() {
      if (!checkpointGate.isCompleted) checkpointGate.complete();
    });

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerOperationService: operationService,
        ledgerSigner: (_) async => _fakeSignatureBytes,
        ledgerCanceller: () async => cancelCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(find.text('Saving signed transaction'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LedgerSigningModal),
        matching: find.text('Cancel'),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    final overlayRect = tester.getRect(find.byType(AppPaneModalOverlay));
    await tester.tapAt(overlayRect.topLeft + const Offset(8, 8));
    await tester.pump();

    expect(find.text('Saving signed transaction'), findsOneWidget);
    expect(find.text('send-route'), findsNothing);
    expect(cancelCount, 0);
    expect(rustApi.discardCalls, isEmpty);

    checkpointGate.complete();
    await _flushRealAsync(tester);
    expect(find.text('status-route'), findsOneWidget);
  });

  testWidgets('Ledger Sapling parameter cancellation returns to review', (
    tester,
  ) async {
    var signerCalls = 0;

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified', needsSaplingParams: true),
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        ledgerSigner: (_) async {
          signerCalls++;
          return _fakeSignatureBytes;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(find.byType(SaplingParamsPrompt), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SaplingParamsPrompt),
        matching: find.text('Cancel'),
      ),
    );
    await _flushRealAsync(tester);

    expect(find.byType(SaplingParamsPrompt), findsNothing);
    expect(find.byType(LedgerSigningModal), findsNothing);
    expect(find.byType(SendReviewScreen), findsOneWidget);
    expect(find.text('Confirm with Ledger'), findsOneWidget);
    expect(signerCalls, 0);
    expect(rustApi.discardCalls, isEmpty);
  });

  testWidgets('Ledger review survives route replay while signing waits', (
    tester,
  ) async {
    final args = _reviewArgs(addressType: 'unified');
    final statusExtras = <Object?>[];
    final signerResult = Completer<List<int>>();
    addTearDown(() {
      if (!signerResult.isCompleted) {
        signerResult.complete(_fakeSignatureBytes);
      }
    });

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        args,
        bootstrap: _bootstrap(
          isHardware: true,
          hardwareSignerKind: HardwareSignerKind.ledger,
        ),
        statusExtras: statusExtras,
        ledgerSigner: (_) => signerResult.future,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Ledger'));
    await _flushRealAsync(tester);
    expect(find.byType(LedgerSigningModal), findsOneWidget);

    final reviewContext = tester.element(find.byType(SendReviewScreen));
    ProviderScope.containerOf(
      reviewContext,
    ).read(sendStatusRoutePayloadProvider.notifier).retain(args);
    GoRouter.of(
      reviewContext,
    ).go('/send/review?flow=${args.sendFlowId}&replayed=1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SendReviewScreen), findsOneWidget);
    expect(find.byType(LedgerSigningModal), findsOneWidget);
    expect(find.text('send-route'), findsNothing);

    signerResult.complete(_fakeSignatureBytes);
    await _flushRealAsync(tester);

    expect(find.text('status-route'), findsOneWidget);
    expect(statusExtras.single, isA<LedgerBroadcastArgs>());
  });

  testWidgets('Keystone status survives a router refresh after handoff', (
    tester,
  ) async {
    final routerRefresh = ChangeNotifier();
    addTearDown(routerRefresh.dispose);
    final statusExtras = <Object?>[];

    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
        statusExtras: statusExtras,
        routerRefresh: routerRefresh,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm with Keystone'));
    await _flushRealAsync(tester);
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('keystone-scan-route'));
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    expect(statusExtras.last, isA<KeystoneBroadcastArgs>());

    routerRefresh.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('status-route'), findsOneWidget);
    expect(find.text('send-route'), findsNothing);
    expect(statusExtras.last, isA<KeystoneBroadcastArgs>());
  });

  test('retained status payload cannot restore a different send flow', () {
    final reviewArgs = _reviewArgs(addressType: 'unified');
    final retained = KeystoneBroadcastArgs(
      reviewArgs: reviewArgs,
      pcztWithProofs: [_fakeProofsBytes],
      pcztWithSignatures: [_fakeSignatureBytes],
    );

    expect(
      resolveSendStatusRoutePayload(
        routePayload: null,
        retainedPayload: retained,
        sendFlowId: 'different-send-flow',
      ),
      isNull,
    );
  });

  test('retained review payload restores only its matching send flow', () {
    final reviewArgs = _reviewArgs(addressType: 'unified');

    expect(
      resolveSendReviewRoutePayload(
        routePayload: null,
        retainedPayload: reviewArgs,
        sendFlowId: reviewArgs.sendFlowId,
      ),
      same(reviewArgs),
    );
    expect(
      resolveSendReviewRoutePayload(
        routePayload: null,
        retainedPayload: reviewArgs,
        sendFlowId: 'different-send-flow',
      ),
      isNull,
    );
  });

  test('retained Ledger payload restores only its matching send flow', () {
    final reviewArgs = _reviewArgs(addressType: 'unified');
    final retained = LedgerBroadcastArgs(
      reviewArgs: reviewArgs,
      operationId: 'send:test-account:${reviewArgs.sendFlowId}',
    );

    expect(
      resolveSendStatusRoutePayload(
        routePayload: null,
        retainedPayload: retained,
        sendFlowId: reviewArgs.sendFlowId,
      ),
      same(retained),
    );
    expect(
      resolveSendStatusRoutePayload(
        routePayload: null,
        retainedPayload: retained,
        sendFlowId: 'different-send-flow',
      ),
      isNull,
    );
  });

  test('status route observer clears payload when the route is removed', () {
    var clearCount = 0;
    final observer = SendStatusRoutePayloadObserver(
      onLeaveStatus: () => clearCount++,
    );
    final statusRoute = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/send/status'),
      builder: (_) => const SizedBox.shrink(),
    );

    observer.didRemove(statusRoute, null);

    expect(clearCount, 1);
  });

  testWidgets('status payload cleanup waits until navigation finishes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sendStatusRoutePayloadProvider.notifier);
    final payload = _reviewArgs(addressType: 'unified');
    notifier.retain(payload);

    notifier.clearAfterNavigation();

    expect(container.read(sendStatusRoutePayloadProvider), same(payload));
    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(sendStatusRoutePayloadProvider), isNull);
  });

  testWidgets('deferred cleanup preserves a newer send flow', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sendStatusRoutePayloadProvider.notifier);
    final previousPayload = _reviewArgs(addressType: 'unified');
    final nextPayload = _reviewArgs(addressType: 'transparent');
    notifier.retain(previousPayload);

    notifier.clearAfterNavigation();
    notifier.retain(nextPayload);
    await tester.pump(const Duration(milliseconds: 1));

    expect(container.read(sendStatusRoutePayloadProvider), same(nextPayload));
  });

  testWidgets('status back navigation clears payload without a build error', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sendStatusRoutePayloadProvider.notifier);
    final payload = _reviewArgs(addressType: 'unified');
    notifier.retain(payload);
    final router = GoRouter(
      initialLocation: '/send/status?flow=${payload.sendFlowId}',
      observers: [
        SendStatusRoutePayloadObserver(
          onLeaveStatus: notifier.clearAfterNavigation,
        ),
      ],
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home-route')),
        GoRoute(
          path: '/send/status',
          builder: (context, _) => TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('back-home'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('back-home'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('home-route'), findsOneWidget);
    expect(container.read(sendStatusRoutePayloadProvider), isNull);
  });

  test(
    'status route observer preserves payload for same-route replacement',
    () {
      var clearCount = 0;
      final observer = SendStatusRoutePayloadObserver(
        onLeaveStatus: () => clearCount++,
      );
      MaterialPageRoute<void> statusRoute() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/send/status'),
        builder: (_) => const SizedBox.shrink(),
      );

      observer.didReplace(oldRoute: statusRoute(), newRoute: statusRoute());

      expect(clearCount, 0);
    },
  );

  testWidgets('Keystone reject while preparing discards the proposal', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        _reviewArgs(addressType: 'unified'),
        bootstrap: _bootstrap(isHardware: true),
      ),
    );
    await tester.pumpAndSettle();

    // Cancel before the PCZT preparation consumed the proposal (real-IO
    // futures are still pending at this point). The review screen behind the
    // scrim has its own Cancel, so scope the tap to the modal.
    await tester.tap(find.text('Confirm with Keystone'));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(KeystoneSigningModal),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('send-route'), findsOneWidget);
    expect(rustApi.discardCalls, hasLength(1));
    expect(rustApi.createPcztCalls, 0);
  });

  testWidgets(
    'Keystone reject after PCZT creation releases the retained input lock',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _harness(
          _reviewArgs(addressType: 'unified'),
          bootstrap: _bootstrap(isHardware: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm with Keystone'));
      await _flushRealAsync(tester);
      expect(rustApi.createPcztCalls, 1);

      await tester.tap(
        find.descendant(
          of: find.byType(KeystoneSigningModal),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('send-route'), findsOneWidget);
      // createPcztFromProposal consumes the replayable proposal but retains
      // its owner-scoped DB input lock until the hardware flow finishes.
      expect(rustApi.discardCalls, [(BigInt.one, 'test-send-flow')]);
    },
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

/// Lets real-IO futures (wallet DB path, Sapling params status) resolve —
/// they cannot complete inside the FakeAsync test zone on their own.
/// Several rounds because the chain interleaves real-IO awaits with
/// fake-zone microtasks that only run during pump; bounded pumps because
/// repeating loader animations would hang pumpAndSettle.
Future<void> _flushRealAsync(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Widget _harness(
  SendReviewArgs args, {
  AppBootstrapState? bootstrap,
  AddressBookRepository? addressBookRepository,
  List<Object?>? statusExtras,
  Listenable? routerRefresh,
  Future<List<int>> Function(List<int> pcztBytes)? ledgerSigner,
  LedgerOperationCanceller? ledgerCanceller,
  LedgerSignedOperationService? ledgerOperationService,
}) {
  final router = GoRouter(
    initialLocation: '/send/review?flow=${args.sendFlowId}',
    initialExtra: args,
    refreshListenable: routerRefresh,
    routes: [
      GoRoute(path: '/send', builder: (_, _) => const Text('send-route')),
      GoRoute(
        path: '/send/review',
        builder: (context, state) => switch (resolveSendReviewRoutePayload(
          routePayload: state.extra,
          retainedPayload: ProviderScope.containerOf(
            context,
          ).read(sendStatusRoutePayloadProvider),
          sendFlowId: state.uri.queryParameters['flow'],
        )) {
          SendReviewArgs resolved => SendReviewScreen(args: resolved),
          _ => const Text('send-route'),
        },
      ),
      GoRoute(
        path: '/send/keystone/scan',
        builder: (context, _) => GestureDetector(
          onTap: () => context.pop(Uint8List.fromList(_fakeSignatureBytes)),
          child: const Text('keystone-scan-route'),
        ),
      ),
      GoRoute(
        path: '/send/status',
        builder: (context, state) {
          final resolved = resolveSendStatusRoutePayload(
            routePayload: state.extra,
            retainedPayload: ProviderScope.containerOf(
              context,
            ).read(sendStatusRoutePayloadProvider),
            sendFlowId: state.uri.queryParameters['flow'],
          );
          statusExtras?.add(resolved);
          if (resolved is! SendReviewArgs &&
              resolved is! KeystoneBroadcastArgs &&
              resolved is! LedgerBroadcastArgs) {
            return const Text('send-route');
          }
          return const Text('status-route');
        },
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(bootstrap ?? _bootstrap()),
      zecMarketDataSourceProvider.overrideWithValue(
        const _FakeMarketDataSource(),
      ),
      zecMarketDataCacheProvider.overrideWithValue(FakeZecMarketDataCache()),
      addressBookRepositoryProvider.overrideWithValue(
        addressBookRepository ?? _FakeAddressBookRepository(),
      ),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
      if (ledgerSigner != null)
        ledgerPcztSignerProvider.overrideWithValue(
          (_, pcztBytes) => ledgerSigner(pcztBytes),
        ),
      if (ledgerCanceller != null)
        ledgerOperationCancellerProvider.overrideWithValue(ledgerCanceller),
      ledgerSignedOperationServiceProvider.overrideWithValue(
        ledgerOperationService ?? _FakeLedgerSignedOperationService(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _LedgerCheckpoint {
  const _LedgerCheckpoint({
    required this.operationId,
    required this.accountUuid,
    required this.kind,
    required this.proofs,
    required this.signatures,
  });

  final String operationId;
  final String accountUuid;
  final LedgerSignedOperationKind kind;
  final List<int> proofs;
  final List<int> signatures;
}

class _FakeLedgerSignedOperationService
    implements LedgerSignedOperationService {
  final checkpoints = <_LedgerCheckpoint>[];
  int failuresRemaining = 0;
  Object checkpointError = StateError('checkpoint failed');
  Completer<void>? checkpointGate;

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpoints.add(
      _LedgerCheckpoint(
        operationId: operationId,
        accountUuid: accountUuid,
        kind: kind,
        proofs: [...pcztWithProofsBytes],
        signatures: [...pcztWithSignaturesBytes],
      ),
    );
    final gate = checkpointGate;
    if (gate != null) await gate.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw checkpointError;
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

AppBootstrapState _bootstrap({
  bool isHardware = false,
  HardwareSignerKind? hardwareSignerKind,
}) {
  return AppBootstrapState(
    initialLocation: '/send/review',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: 'test-account',
          name: 'Account 1',
          order: 0,
          isHardware: isHardware,
          hardwareSignerKind: hardwareSignerKind,
        ),
      ],
      activeAccountUuid: 'test-account',
      activeAddress: 'u1activeaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

AddressBookContact _contact({
  required String id,
  required String label,
  required String address,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: AddressBookNetwork.zcash,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts
      ..clear()
      ..addAll(contacts);
  }
}

SendReviewArgs _reviewArgs({
  required String addressType,
  String? memo,
  String address = _longAddress,
  BigInt? amountZatoshi,
  bool needsSaplingParams = false,
}) {
  return SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'test-send-flow',
    proposalAccountUuid: 'test-account',
    address: address,
    addressType: addressType,
    amountZatoshi: amountZatoshi ?? BigInt.from(1512000000),
    feeZatoshi: BigInt.from(12000),
    needsSaplingParams: needsSaplingParams,
    memo: memo,
  );
}

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return const ZecMarketData(usdPrice: 70);
  }
}

const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs.';

const _longAddress =
    'u1tvg4akwn3gk64h6dfe0000000000000000005j3eds7qfhzek6scgcn8fh5';

const _transparentAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

const _texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';

const _veryLongMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin. This message should be visible after '
    'the preview expands.';

const _fakeProofsBytes = <int>[3, 3, 3];
const _fakeSignatureBytes = <int>[9, 9];

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'test-account',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(500000000),
    totalBalance: BigInt.from(500000000),
  );
}

class _RustApiFake implements RustLibApi {
  final discardCalls = <(BigInt, String)>[];
  int createPcztCalls = 0;
  int redactPcztCalls = 0;
  int addProofsCalls = 0;
  Object? createPcztError;
  Completer<void>? createPcztGate;
  int previousTransactionCount = 0;
  String unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
  String transparentAddress = 't1ownaccountaddressnotmatchingrecipient';

  void reset() {
    discardCalls.clear();
    createPcztCalls = 0;
    redactPcztCalls = 0;
    addProofsCalls = 0;
    createPcztError = null;
    createPcztGate = null;
    previousTransactionCount = 0;
    unifiedAddress = 'u1ownaccountaddressnotmatchingrecipient';
    transparentAddress = 't1ownaccountaddressnotmatchingrecipient';
  }

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add((proposalId, sendFlowId));
  }

  @override
  Future<int> crateApiSyncGetPreviousTransactionCountForAddress({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String address,
  }) async {
    return previousTransactionCount;
  }

  @override
  Future<String> crateApiWalletGetUnifiedAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return unifiedAddress;
  }

  @override
  Future<String> crateApiWalletGetTransparentReceiveAddress({
    required String dbPath,
    required String network,
    String? accountUuid,
  }) async {
    return transparentAddress;
  }

  @override
  Future<List<String>> crateApiWalletGetRecentTransparentReceiveAddresses({
    required String dbPath,
    required String network,
    String? accountUuid,
    required int limit,
  }) async {
    return [transparentAddress];
  }

  @override
  Future<Uint8List> crateApiSyncCreatePcztFromProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    createPcztCalls++;
    final gate = createPcztGate;
    if (gate != null) await gate.future;
    final error = createPcztError;
    if (error != null) throw error;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<TexPcztPairResult> crateApiSyncCreateTexPcztsFromProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    createPcztCalls++;
    return TexPcztPairResult(
      pczts: [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ],
      signerPczts: [
        Uint8List.fromList([4]),
        Uint8List.fromList([5]),
      ],
    );
  }

  @override
  Future<Uint8List> crateApiSyncRedactPcztForSigner({
    required List<int> pcztBytes,
  }) async {
    redactPcztCalls++;
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async {
    return const ['UR:ZCASH-PCZT/TESTPART'];
  }

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    addProofsCalls++;
    return Uint8List.fromList(_fakeProofsBytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
