// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/features/donation/screens/donation_screen.dart';
import '../src/features/donation/widgets/donation_views.dart';
import '../src/features/send/widgets/send_review_layout.dart';
import '../src/features/send/widgets/send_status_content_view.dart';
import 'pay_screen_use_cases.dart';
import 'support/wb_layout.dart';

/// One amount corner of the donation composer: the props a figma_compare
/// builder pins. Declared here rather than in the gallery so the knob and the
/// builders cannot drift apart.
class DonationComposeAmountProps {
  const DonationComposeAmountProps({
    this.mode = DonationAmountMode.zec,
    this.amount = '',
    this.selectedPreset,
    this.conversion = r'$ 0',
    this.selectionOffset,
  });

  final DonationAmountMode mode;
  final String amount;
  final String? selectedPreset;
  final String conversion;
  final int? selectionOffset;
}

const donationComposeZecEmptyAmount = DonationComposeAmountProps();

const donationComposeZecPresetAmount = DonationComposeAmountProps(
  amount: '0.02',
  selectedPreset: '0.02',
  conversion: r'$ 16.00',
);

const donationComposeZecMidCursorAmount = DonationComposeAmountProps(
  amount: '123.45',
  selectionOffset: 2,
  conversion: r'$ 98,760.00',
);

const donationComposeUsdPresetAmount = DonationComposeAmountProps(
  mode: DonationAmountMode.usd,
  amount: '15',
  selectedPreset: '15',
  conversion: '0.05 ZEC',
);

// The two USD corners no figma_compare builder pins; the gallery's currency
// and amount knobs are orthogonal, so both halves need all three amounts.
const donationComposeUsdEmptyAmount = DonationComposeAmountProps(
  mode: DonationAmountMode.usd,
  conversion: '0 ZEC',
);

const donationComposeUsdMidCursorAmount = DonationComposeAmountProps(
  mode: DonationAmountMode.usd,
  amount: '123.45',
  selectionOffset: 2,
  conversion: '0.4115 ZEC',
);

/// Desktop donation composer: an [amount] corner plus the axes the screen
/// drives from its own state — a validation error, the submitting CTA, and
/// whether a live ZEC/USD price makes the currency switch usable.
///
/// The preview seeds its controller in `initState`, so the key remounts it
/// whenever a knob changes the amount it should show.
Widget donationComposeFixture(
  DonationComposeAmountProps amount, {
  String? errorText,
  bool isSubmitting = false,
  bool livePrice = true,
}) {
  return _DonationComposePreview(
    key: ValueKey(
      'donation_compose_${amount.mode.name}_${amount.amount}_'
      '${amount.selectedPreset}_${amount.selectionOffset}_'
      '${errorText}_${isSubmitting}_$livePrice',
    ),
    mode: amount.mode,
    amount: amount.amount,
    selectedPreset: amount.selectedPreset,
    conversion: amount.conversion,
    selectionOffset: amount.selectionOffset,
    errorText: errorText,
    isSubmitting: isSubmitting,
    livePrice: livePrice,
  );
}

Widget buildDonationZecEmptyUseCase(BuildContext context) =>
    donationComposeFixture(donationComposeZecEmptyAmount);

Widget buildDonationZecSelectedUseCase(BuildContext context) =>
    donationComposeFixture(donationComposeZecPresetAmount);

Widget buildDonationZecMiddleCursorUseCase(BuildContext context) =>
    donationComposeFixture(donationComposeZecMidCursorAmount);

Widget buildDonationUsdSelectedUseCase(BuildContext context) =>
    donationComposeFixture(donationComposeUsdPresetAmount);

/// Desktop donation review. [confirmEnabled] is the screen's `onConfirm`
/// (null while the donation cannot be submitted) and [showFiat] its optional
/// fiat sub-line.
Widget donationReviewFixture({
  bool confirmEnabled = true,
  bool showFiat = true,
}) {
  return _DonationFrame(
    child: AppPaneScrollScaffold(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(
          label: 'Support Vizor',
          minWidth: 60,
          onTap: () {},
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DonationReviewContentView(
        amountText: '123.12 ZEC',
        fiatText: showFiat ? r'$250.12' : null,
        feeText: '0.012 ZEC',
        confirmLabel: 'Confirm donation',
        confirmIcon: AppIcons.donation,
        onConfirm: confirmEnabled ? () {} : null,
      ),
    ),
  );
}

Widget buildDonationReviewUseCase(BuildContext context) =>
    donationReviewFixture();

/// The review's recipient row on its own; [struckThrough] is how a failed or
/// cancelled donation renders it.
Widget donationRecipientRowFixture({bool struckThrough = false}) {
  return _DonationComponentFrame(
    child: DonationRecipientInfoRow(struckThrough: struckThrough),
  );
}

Widget buildDonationVizorBadgeUseCase(BuildContext context) =>
    const _DonationComponentFrame(child: DonationVizorBadge());

Widget buildDonationSuccessUseCase(BuildContext context) => _DonationFrame(
  background: const DonationSuccessBackground(),
  child: DonationSuccessView(onDone: () {}),
);

Widget buildDonationStatusInProgressUseCase(BuildContext context) =>
    _DonationFrame(
      child: AppPaneScrollScaffold(
        toolbar: AppPaneToolbar(
          leading: AppBackLink(label: 'Home', minWidth: 60, onTap: () {}),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: SendStatusContentView(
          phase: SendStatusPhase.inProgress,
          titleOverride: 'Donation in progress...',
          amountText: '123.12 ZEC',
          fiatText: r'$250.12',
          recipient: const SendReviewAddressRecipient(
            address: 'u1vizordonationaddress',
          ),
          recipientRow: const DonationRecipientInfoRow(),
          timestampText: '25 May, 13:30',
          txIdText: null,
          feeText: '0.012 ZEC',
        ),
      ),
    );

/// The real `DonationScreen`: its own sidebar, toolbar and compose view, with
/// the wallet providers behind the Pay-feature preview shell.
///
/// [livePrice] is the only externally settable axis — without a USD price the
/// ZEC/USD toggle is inert because the screen passes `onToggleMode: null`.
Widget donationScreenFixture({bool livePrice = true}) {
  return payPreviewShellScope(
    zecUsdPrice: livePrice ? 70 : null,
    child: const _DonationScreenHarness(),
  );
}

Widget buildDonationScreenUseCase(BuildContext context) =>
    donationScreenFixture();

Widget buildDonationScreenNoPriceUseCase(BuildContext context) =>
    donationScreenFixture(livePrice: false);

/// `AppMainSidebar` and `AppPaneToolbar` resolve through `GoRouterState.of`,
/// which needs a real matched route.
class _DonationScreenHarness extends StatefulWidget {
  const _DonationScreenHarness();

  @override
  State<_DonationScreenHarness> createState() => _DonationScreenHarnessState();
}

class _DonationScreenHarnessState extends State<_DonationScreenHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/donation',
      routes: [
        GoRoute(path: '/donation', builder: (_, _) => const DonationScreen()),
        GoRoute(path: '/home', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(path: '/settings', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/send/review',
          builder: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IgnorePointer keeps it a static snapshot: sidebar taps leave the route.
    return Center(
      child: WbDesktopWindowBox(
        size: const Size(1080, 720),
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child: IgnorePointer(child: Router.withConfig(config: _router)),
        ),
      ),
    );
  }
}

class _DonationComposePreview extends StatefulWidget {
  const _DonationComposePreview({
    required this.mode,
    this.amount = '',
    this.selectedPreset,
    this.conversion = r'$ 0',
    this.selectionOffset,
    this.errorText,
    this.isSubmitting = false,
    this.livePrice = true,
    super.key,
  });

  final DonationAmountMode mode;
  final String amount;
  final String? selectedPreset;
  final String conversion;
  final int? selectionOffset;
  final String? errorText;
  final bool isSubmitting;

  /// Without a live ZEC/USD price the screen passes no `onToggleMode`, so the
  /// currency switch under the amount is inert.
  final bool livePrice;

  @override
  State<_DonationComposePreview> createState() =>
      _DonationComposePreviewState();
}

class _DonationComposePreviewState extends State<_DonationComposePreview> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.amount);
    final selectionOffset = widget.selectionOffset;
    if (selectionOffset != null) {
      _controller.selection = TextSelection.collapsed(offset: selectionOffset);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DonationFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPaneToolbar(
          leading: AppBackLink(label: 'Settings', minWidth: 60, onTap: () {}),
        ),
        Expanded(
          child: DonationComposeView(
            controller: _controller,
            mode: widget.mode,
            conversionText: widget.conversion,
            selectedPreset: widget.selectedPreset,
            errorText: widget.errorText,
            isSubmitting: widget.isSubmitting,
            onAmountChanged: (_) {},
            onToggleMode: widget.livePrice ? () {} : null,
            onPresetSelected: (_) {},
            onContinue: widget.amount.isEmpty ? null : () {},
          ),
        ),
      ],
    ),
  );
}

/// Plain centred frame for the component previews: the review pane's own
/// content width, without the screen shell around it.
class _DonationComponentFrame extends StatelessWidget {
  const _DonationComponentFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.background.base,
    child: Center(
      child: SizedBox(
        width: AppWindowSizing.contentAreaMaxWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _DonationFrame extends StatelessWidget {
  const _DonationFrame({required this.child, this.background});

  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) => WbDesktopWindowBox(
    child: AppDesktopShell(
      background: background,
      sidebar: const _DonationPreviewSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: child),
    ),
  );
}

class _DonationPreviewSidebar extends StatelessWidget {
  const _DonationPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSidebarItem(label: 'Username', iconName: AppIcons.user),
            const SizedBox(height: AppSpacing.base),
            const AppSidebarItem(label: 'Home', iconName: AppIcons.home),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(label: 'Swap', iconName: AppIcons.swapArrows),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(label: 'Pay', iconName: AppIcons.paid),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(label: 'Vote', iconName: AppIcons.vote),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(label: 'Activity', iconName: AppIcons.history),
            const Spacer(),
            const AppSidebarItem(label: 'Settings', iconName: AppIcons.cog),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(label: 'Sign out', iconName: AppIcons.logOut),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Synced',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
