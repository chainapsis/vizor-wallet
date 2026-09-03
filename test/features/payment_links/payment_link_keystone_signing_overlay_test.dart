import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/features/send/screens/keystone_send_scan_screen.dart';

void main() {
  testWidgets('scans a Keystone signature and broadcasts Gift Card funding', (
    tester,
  ) async {
    final service = _FakeHardwareSigningService();
    VizorPaymentLink? completedLink;
    String? completedStatus;
    KeystoneSendScanArgs? scanArgs;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PaymentLinkKeystoneSigningOverlay(
            amountZatoshi: BigInt.from(10000000),
            sourceAccountUuid: 'hardware-account',
            onCancel: () {},
            onFundingBroadcast: (link, result) async {
              completedLink = link;
              completedStatus = result.status;
            },
          ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder: (context, state) {
            scanArgs = state.extra as KeystoneSendScanArgs?;
            return Center(
              child: TextButton(
                key: const ValueKey('fake_keystone_signature_done'),
                onPressed: () => context.pop<List<int>>(const [4, 5, 6]),
                child: const Text('Return signature'),
              ),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
    addTearDown(router.dispose);

    for (var i = 0; i < 20 && service.proofDrafts.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sign Gift Card on Keystone'), findsOneWidget);
    expect(service.createdAmounts, [BigInt.from(10000000)]);
    expect(service.createdFromAccounts, ['hardware-account']);

    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('fake_keystone_signature_done')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('fake_keystone_signature_done')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.broadcastSignatures, [
      const [10, 11],
    ]);
    expect(scanArgs?.expectedUrType, 'zcash-batch-sig-result');
    expect(scanArgs?.decodePcztResponse, isFalse);
    expect(service.decodedResponses, [
      const [4, 5, 6],
    ]);
    expect(completedLink, _link);
    expect(completedStatus, 'broadcasted');
  });

  testWidgets('hands an unknown broadcast with a txid to the preparing flow', (
    tester,
  ) async {
    final service = _FakeHardwareSigningService(
      broadcastStatus: 'broadcast_unknown',
      broadcastMessage: 'Broadcast timed out before confirmation.',
    );
    var completed = false;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PaymentLinkKeystoneSigningOverlay(
            amountZatoshi: BigInt.from(10000000),
            sourceAccountUuid: 'hardware-account',
            onCancel: () {},
            onFundingBroadcast: (_, _) async => completed = true,
          ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('fake_keystone_signature_done'),
              onPressed: () => context.pop<List<int>>(const [4, 5, 6]),
              child: const Text('Return signature'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
    addTearDown(router.dispose);

    for (var i = 0; i < 20 && service.proofDrafts.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fake_keystone_signature_done')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(completed, isTrue);
    expect(find.text('Broadcast timed out before confirmation.'), findsNothing);
    expect(find.text('Back to Gift Card'), findsNothing);
  });

  testWidgets('discards the prepared draft when broadcast fails', (
    tester,
  ) async {
    final service = _FakeHardwareSigningService(
      broadcastError: StateError('Keystone signature preflight failed'),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PaymentLinkKeystoneSigningOverlay(
            amountZatoshi: BigInt.from(10000000),
            sourceAccountUuid: 'hardware-account',
            onCancel: () {},
            onFundingBroadcast: (_, _) async {},
          ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('fake_keystone_signature_done'),
              onPressed: () => context.pop<List<int>>(const [4, 5, 6]),
              child: const Text('Return signature'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
    addTearDown(router.dispose);

    for (var i = 0; i < 20 && service.proofDrafts.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fake_keystone_signature_done')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.discardedDrafts, [BigInt.one]);
    expect(
      find.text('Keystone signature could not be applied.'),
      findsOneWidget,
    );
    expect(find.text('Back to Gift Card'), findsOneWidget);
  });
  testWidgets('keeps the draft when broadcast fails after submission', (
    tester,
  ) async {
    final service = _FakeHardwareSigningService(
      broadcastError: StateError('Storing the funding transaction failed'),
      throwAfterSubmissionStarted: true,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => PaymentLinkKeystoneSigningOverlay(
            amountZatoshi: BigInt.from(10000000),
            sourceAccountUuid: 'hardware-account',
            onCancel: () {},
            onFundingBroadcast: (_, _) async {},
          ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('fake_keystone_signature_done'),
              onPressed: () => context.pop<List<int>>(const [4, 5, 6]),
              child: const Text('Return signature'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
    addTearDown(router.dispose);

    for (var i = 0; i < 20 && service.proofDrafts.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Get signature'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('fake_keystone_signature_done')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.submissionStartedCount, 1);
    // The network may already hold the funding transaction, so the draft and
    // its prepared txid stay for the recovery reconciler to settle.
    expect(service.discardedDrafts, isEmpty);
    expect(find.text('Back to Gift Card'), findsOneWidget);
  });
}

final _link = VizorPaymentLink(
  network: 'main',
  address: 'u1paymentlinkaddress',
  amountZatoshi: BigInt.from(10000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
);

class _FakeHardwareSigningService implements PaymentLinkHardwareSigningService {
  _FakeHardwareSigningService({
    this.broadcastStatus = 'broadcasted',
    this.broadcastMessage,
    this.broadcastError,
    this.throwAfterSubmissionStarted = false,
  });

  final String broadcastStatus;
  final String? broadcastMessage;
  final Object? broadcastError;

  /// When true the fake reports the transaction as handed to the network
  /// before it throws, the way a store failure behind a successful broadcast
  /// does.
  final bool throwAfterSubmissionStarted;
  var submissionStartedCount = 0;
  final createdAmounts = <BigInt>[];
  final createdFromAccounts = <String>[];
  final proofDrafts = <BigInt>[];
  final discardedDrafts = <BigInt>[];
  final decodedResponses = <List<int>>[];
  final broadcastSignatures = <List<int>>[];

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    return PaymentLinkHardwarePcztDraft(
      link: _link,
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
      proposalId: BigInt.one,
      sendFlowId: 'test-payment-link-hardware',
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => const ['ur:zcash-sign-batch/test'];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async {
    decodedResponses.add(responseCbor);
    return const [10, 11];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    proofDrafts.add(draft.proposalId);
    return const [7, 8, 9];
  }

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    discardedDrafts.add(draft.proposalId);
  }

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
    void Function()? onSubmissionStarted,
  }) async {
    broadcastSignatures.add(pcztWithSignaturesBytes);
    if (throwAfterSubmissionStarted) {
      submissionStartedCount += 1;
      onSubmissionStarted?.call();
    }
    final error = broadcastError;
    if (error != null) throw error;
    submissionStartedCount += 1;
    onSubmissionStarted?.call();
    return PaymentLinkHardwareFundingResult(
      txids: 'hardware-funding-txid',
      status: broadcastStatus,
      message: broadcastMessage,
      fundingMetadataSaved: true,
    );
  }
}
