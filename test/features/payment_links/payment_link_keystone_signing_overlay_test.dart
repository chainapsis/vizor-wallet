import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  testWidgets('scans a Keystone signature and broadcasts Gift Card funding', (
    tester,
  ) async {
    final service = _FakeHardwareSigningService();
    VizorPaymentLink? completedLink;
    String? completedStatus;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, _) => PaymentLinkKeystoneSigningOverlay(
                amountZatoshi: BigInt.from(10000000),
                sourceAccountUuid: 'hardware-account',
                onCancel: () {},
                onFundingBroadcast: (link, status, _) async {
                  completedLink = link;
                  completedStatus = status;
                },
              ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder:
              (context, _) => Center(
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
          builder:
              (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
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
      const [4, 5, 6],
    ]);
    expect(completedLink, _link);
    expect(completedStatus, 'broadcasted');
  });

  testWidgets('does not expose the Gift Card after an unknown broadcast', (
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
          builder:
              (_, _) => PaymentLinkKeystoneSigningOverlay(
                amountZatoshi: BigInt.from(10000000),
                sourceAccountUuid: 'hardware-account',
                onCancel: () {},
                onFundingBroadcast: (_, _, _) async => completed = true,
              ),
        ),
        GoRoute(
          path: '/send/keystone/scan',
          builder:
              (context, _) => Center(
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
          builder:
              (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
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

    expect(completed, isFalse);
    expect(
      find.text('Broadcast timed out before confirmation.'),
      findsOneWidget,
    );
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
  });

  final String broadcastStatus;
  final String? broadcastMessage;
  final createdAmounts = <BigInt>[];
  final createdFromAccounts = <String>[];
  final proofDrafts = <BigInt>[];
  final broadcastSignatures = <List<int>>[];

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    String? artworkId,
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
  }) async => const ['ur:zcash-pczt/test'];

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
  }) async {}

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcastSignatures.add(pcztWithSignaturesBytes);
    return rust_sync.ExtractAndBroadcastPcztResult(
      txid: 'hardware-funding-txid',
      status: broadcastStatus,
      message: broadcastMessage,
    );
  }
}
