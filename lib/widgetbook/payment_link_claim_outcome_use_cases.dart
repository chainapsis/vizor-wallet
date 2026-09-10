import 'package:flutter/widgets.dart';
import '../src/features/payment_links/widgets/payment_link_archive_header.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/payment_links/widgets/payment_link_desktop_views.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import '../src/features/payment_links/widgets/payment_link_claim_outcome_view.dart';

Widget buildClaimNoBalanceUseCase(BuildContext context) =>
    _outcome(PaymentLinkAvailability.noBalance);
Widget buildClaimedElsewhereUseCase(BuildContext context) =>
    _outcome(PaymentLinkAvailability.claimedElsewhere);
Widget buildClaimFailedUseCase(BuildContext context) =>
    _outcome(PaymentLinkAvailability.failed);
Widget buildClaimCheckingUseCase(BuildContext context) =>
    _outcome(PaymentLinkAvailability.checking);
Widget _outcome(PaymentLinkAvailability availability) {
  final view = PaymentLinkClaimOutcomeView(
    availability: availability,
    onBack: () {},
    onCheck: () {},
    onArchive:
        availability == PaymentLinkAvailability.checking ||
            availability == PaymentLinkAvailability.rejected
        ? null
        : () {},
  );
  return _wrapOutcome(view);
}

Widget buildClaimRejectedUseCase(BuildContext context) =>
    _outcome(PaymentLinkAvailability.rejected);
Widget buildClaimBusyUseCase(BuildContext context) => _wrapOutcome(
  PaymentLinkClaimOutcomeView(
    availability: PaymentLinkAvailability.checking,
    busy: true,
    onBack: () {},
    onCheck: () {},
  ),
);
Widget buildClaimArchivedUseCase(BuildContext context) => _wrapOutcome(
  PaymentLinkClaimOutcomeView(
    availability: PaymentLinkAvailability.claimedElsewhere,
    archived: true,
    onBack: () {},
    onCheck: () {},
    onArchive: () {},
  ),
);
Widget _wrapOutcome(Widget view) => Builder(
  builder: (context) => ColoredBox(
    color: context.colors.background.window,
    child: kAppFormFactor == AppFormFactor.mobile
        ? SizedBox.expand(child: view)
        : AppDesktopPane(padding: EdgeInsets.zero, child: view),
  ),
);

Widget buildClaimOutcomeListUseCase(BuildContext context) => _outcomeList();
Widget buildClaimArchiveClosedUseCase(BuildContext context) =>
    _outcomeList(archive: true);
Widget buildClaimArchiveOpenUseCase(BuildContext context) =>
    _outcomeList(archive: true, expanded: true);

Widget _outcomeList({bool archive = false, bool expanded = false}) {
  Widget row(String label, String action, {bool loading = false}) {
    final image = Image.asset(
      PaymentLinkCardArtwork.ruby.assetPath,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
    );
    return kAppFormFactor == AppFormFactor.mobile
        ? PaymentLinkCardListMobileRow(
            thumbnail: image,
            amountText: '0.10 ZEC',
            dateText: 'September 9',
            statusText: label,
            actionLabel: action,
            showLoader: loading,
            onAction: () {},
          )
        : PaymentLinkCardListRow(
            thumbnail: image,
            amountText: '0.10 ZEC',
            dateText: 'September 9',
            statusText: label,
            actionLabel: action,
            showLoader: loading,
            onAction: () {},
          );
  }

  final sections = [
    PaymentLinkCardsSection(
      label: 'Received',
      cards: [
        row('Checking result', 'Check status', loading: true),
        if (!archive) ...[
          row('Claim failed', 'Check status'),
          row('Already claimed', 'View card'),
          row('No balance', 'Check status'),
        ],
      ],
    ),
    if (archive)
      PaymentLinkCardsSection(
        label: 'Archived',
        header: PaymentLinkArchiveHeader(
          count: 1,
          expanded: expanded,
          onToggle: () {},
        ),
        cards: [if (expanded) row('Already claimed', 'View card')],
      ),
  ];
  return _wrapOutcome(
    kAppFormFactor == AppFormFactor.mobile
        ? PaymentLinkCardsMobileView(
            sections: sections,
            activeTab: PaymentLinkCardsTab.received,
            onTabSelected: (_) {},
            onBack: () {},
            onCreate: () {},
            onRedeem: () {},
          )
        : PaymentLinkCardsDesktopView(
            sections: sections,
            activeTab: PaymentLinkCardsTab.received,
            onTabSelected: (_) {},
            onBack: () {},
            onCreate: () {},
            onRedeem: () {},
          ),
  );
}
