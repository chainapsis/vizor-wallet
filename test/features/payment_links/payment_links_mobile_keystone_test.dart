@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await loader.load();
  });

  testWidgets(
    'a hardware account reaches the Keystone signing round on mobile',
    (tester) async {
      final hardwareSigning = _FakePaymentLinkHardwareSigningService();
      final operations = _FakePaymentLinkOperations();
      await _pumpMobilePaymentLinks(
        tester,
        operations: operations,
        hardwareSigning: hardwareSigning,
      );

      await _walkToApproveAndCreate(tester);

      // The review CTA must not be left spinning on "Creating..." — the
      // Keystone round trip owns the surface from here.
      expect(
        find.byKey(
          const ValueKey('payment_link_keystone_signing_overlay_surface'),
        ),
        findsOneWidget,
      );
      expect(find.byType(MobileKeystonePcztSigningFlow), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_link_keystone_sign_screen')),
        findsOneWidget,
      );
      expect(hardwareSigning.createdAmounts, [BigInt.from(10000000)]);
      expect(hardwareSigning.createdFromAccounts, ['hardware-account']);
      expect(operations.createdAmounts, isEmpty);
    },
  );

  testWidgets('cancelling the mobile Keystone round returns a usable review', (
    tester,
  ) async {
    final hardwareSigning = _FakePaymentLinkHardwareSigningService();
    await _pumpMobilePaymentLinks(tester, hardwareSigning: hardwareSigning);

    await _walkToApproveAndCreate(tester);
    expect(find.byType(MobileKeystonePcztSigningFlow), findsOneWidget);

    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel('Back').last);
    await tester.pumpAndSettle();
    semantics.dispose();

    expect(find.byType(MobileKeystonePcztSigningFlow), findsNothing);
    expect(hardwareSigning.discardedDrafts, [BigInt.one]);
    final cta = tester.widget<AppButton>(
      find.byKey(const ValueKey('payment_link_mobile_review_continue_button')),
    );
    expect(cta.onPressed, isNotNull);
    expect(find.text('Approve & create'), findsOneWidget);
  });
}

Future<void> _walkToApproveAndCreate(WidgetTester tester) async {
  // Mobile opens on the redeem entry; step back to the Gift Card home first.
  final semantics = tester.ensureSemantics();
  await tester.tap(find.bySemanticsLabel('Back').first);
  await tester.pumpAndSettle();
  semantics.dispose();

  await tester.tap(
    find.byKey(const ValueKey('payment_links_mobile_create_button')),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('payment_link_amount_editor')),
    '0.1',
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();

  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_amount_continue_button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_message_continue_button')),
  );
  await tester.pumpAndSettle();

  expect(find.text('Approve & create'), findsOneWidget);
  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_review_continue_button')),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMobilePaymentLinks(
  WidgetTester tester, {
  _FakePaymentLinkOperations? operations,
  PaymentLinkHardwareSigningService? hardwareSigning,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_hardwareBootstrap),
        paymentLinkOperationsProvider.overrideWithValue(
          operations ?? _FakePaymentLinkOperations(),
        ),
        if (hardwareSigning != null)
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(
            hardwareSigning,
          ),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'hardware-account',
              hasAccountScopedData: true,
              isSyncComplete: true,
              percentage: 1,
              displayTargetPercentage: 1,
              spendableBalance: BigInt.from(14223000000),
              displaySpendableBalance: BigInt.from(14223000000),
            ),
          ),
        ),
        ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
          return const IronwoodHomeMigrationCtaState.hidden();
        }),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
        ironwoodPostMigrationStateProvider.overrideWith((ref) async {
          return const IronwoodPostMigrationState.unavailable();
        }),
        ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
          return const IronwoodMigrationAnnouncementState.hidden();
        }),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          _FakeMigrationCoordinator.new,
        ),
      ],
      child: const ZcashWalletApp(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    if (find
        .byKey(const ValueKey('payment_links_mobile_screen'))
        .evaluate()
        .isNotEmpty) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

const _hardwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'hardware-account',
      name: 'Keystone',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'hardware-account',
  activeAddress: 'u1hardwareaddress',
);

final _hardwareBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: _hardwareAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final _hardwareLink = VizorPaymentLink(
  network: 'main',
  address: 'u1hardwarepaymentlinkaddress',
  amountZatoshi: BigInt.from(10000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
);

class _FakePaymentLinkOperations implements PaymentLinkOperations {
  final List<BigInt> createdAmounts = [];

  @override
  Future<PaymentLinkFundingQuote> quoteMaxFunding({
    required String sourceAccountUuid,
  }) async {
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: BigInt.from(14222980000),
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    throw StateError('Keystone payment links require the hardware flow.');
  }

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) async {}

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async =>
      const [];

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async => const {};

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async =>
      const [];

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async => const [];

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {}
}

class _FakePaymentLinkHardwareSigningService
    implements PaymentLinkHardwareSigningService {
  final createdAmounts = <BigInt>[];
  final createdFromAccounts = <String>[];
  final discardedDrafts = <BigInt>[];

  PaymentLinkHardwarePcztDraft get draft => PaymentLinkHardwarePcztDraft(
    link: _hardwareLink,
    pcztBytes: const [1, 2, 3],
    needsSaplingParams: false,
    feeZatoshi: BigInt.from(10000),
    proposalId: BigInt.one,
    sendFlowId: 'test-payment-link-hardware',
  );

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    return draft;
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => const ['ur:zcash-sign-batch/test'];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [10, 11];

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [7, 8, 9];

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
  }) async {
    return const PaymentLinkHardwareFundingResult(
      txids: 'hardware-funding-txid',
      status: 'broadcasted',
      fundingMetadataSaved: true,
    );
  }
}

class _FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}
