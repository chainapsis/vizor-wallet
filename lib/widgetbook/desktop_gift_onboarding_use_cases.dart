import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/features/onboarding/create/customise_account_screen.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/providers/gift_card_entry_price_provider.dart';
import '../src/features/payment_links/providers/gift_claim_flow_provider.dart';
import '../src/features/payment_links/screens/desktop_gift_password_screen.dart';
import '../src/features/payment_links/screens/gift_claim_screen.dart';
import '../src/features/payment_links/services/payment_link_service.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart'
    show PaymentLinkAvailability;
import '../src/providers/account_provider.dart';

final _link = VizorPaymentLink(
  network: 'main',
  address: 'u1previewgift',
  amountZatoshi: BigInt.from(10_000_000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3_000_000,
  label: 'Welcome gift',
  createdAt: DateTime.utc(2026, 9, 1),
);
final _inspection = PaymentLinkClaimInspection(
  link: _link,
  directory: Directory.systemTemp,
  dbPath: '/preview-only/claim.db',
  accountUuid: 'preview-gift',
  totalZatoshi: BigInt.from(10_010_000),
  claimableZatoshi: _link.amountZatoshi,
  feeZatoshi: BigInt.from(10_000),
  fundingConfirmationCount: 2,
  waitingForFundingConfirmations: false,
  availability: PaymentLinkAvailability.available,
);

Widget buildDesktopGiftEntryUseCase(BuildContext context) =>
    const _Capture(screen: GiftClaimScreen());
Widget buildDesktopGiftAdditionalEntryUseCase(BuildContext context) =>
    const _Capture(screen: GiftClaimScreen(addingAccount: true));
Widget buildDesktopGiftCheckingUseCase(BuildContext context) =>
    const _Capture(screen: GiftClaimScreen(), phase: GiftClaimPhase.checking);
Widget buildDesktopGiftInspectedUseCase(BuildContext context) =>
    const _Capture(screen: GiftClaimScreen(), phase: GiftClaimPhase.inspected);
Widget buildDesktopGiftPasswordUseCase(BuildContext context) => const _Capture(
  screen: DesktopGiftPasswordScreen(),
  phase: GiftClaimPhase.inspected,
);
Widget buildDesktopGiftCustomiseUseCase(BuildContext context) => _Capture(
  screen: CustomiseAccountScreen.gift(
    configuresPassword: true,
    onFinish: (_, _) async {},
    random: Random(1234),
  ),
);
Widget buildDesktopGiftAdditionalCustomiseUseCase(BuildContext context) =>
    _Capture(
      screen: CustomiseAccountScreen.gift(
        configuresPassword: false,
        onFinish: (_, _) async {},
        random: Random(1234),
      ),
    );
Widget buildDesktopGiftCheckErrorUseCase(BuildContext context) =>
    const _Capture(screen: GiftClaimScreen(), phase: GiftClaimPhase.failed);
Widget buildDesktopGiftLongScanUseCase(BuildContext context) => const _Capture(
  screen: GiftClaimScreen(),
  phase: GiftClaimPhase.longSyncConfirmation,
);

/// Read-only scenarios use only route memory and local fixtures.
class _Capture extends StatefulWidget {
  const _Capture({required this.screen, this.phase});
  final Widget screen;
  final GiftClaimPhase? phase;
  @override
  State<_Capture> createState() => _CaptureState();
}

class _CaptureState extends State<_Capture> {
  late final _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => IgnorePointer(child: widget.screen),
      ),
    ],
  );
  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(_EmptyAccounts.new),
      giftClaimFlowProvider.overrideWith(() => _GiftFlow(widget.phase)),
      giftCardEntryPriceProvider.overrideWith((_) async => 31.9618),
    ],
    child: Router(
      routerDelegate: _router.routerDelegate,
      routeInformationParser: _router.routeInformationParser,
      routeInformationProvider: _router.routeInformationProvider,
    ),
  );
}

class _EmptyAccounts extends AccountNotifier {
  @override
  AccountState build() => const AccountState();
}

class _GiftFlow extends GiftClaimFlowNotifier {
  _GiftFlow(this.phase);
  final GiftClaimPhase? phase;
  @override
  GiftClaimFlowState? build() => phase == null
      ? null
      : GiftClaimFlowState(
          link: _link,
          phase: phase!,
          failure: phase == GiftClaimPhase.failed
              ? GiftClaimFailure.network
              : null,
          inspection: phase == GiftClaimPhase.inspected ? _inspection : null,
        );
}
