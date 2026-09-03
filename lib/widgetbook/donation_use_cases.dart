// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/features/donation/widgets/donation_views.dart';
import '../src/features/send/widgets/send_review_layout.dart';
import '../src/features/send/widgets/send_status_content_view.dart';

Widget buildDonationZecEmptyUseCase(BuildContext context) =>
    const _DonationComposePreview(mode: DonationAmountMode.zec);

Widget buildDonationZecSelectedUseCase(BuildContext context) =>
    const _DonationComposePreview(
      mode: DonationAmountMode.zec,
      amount: '0.02',
      selectedPreset: '0.02',
      conversion: r'$ 16.00',
    );

Widget buildDonationUsdSelectedUseCase(BuildContext context) =>
    const _DonationComposePreview(
      mode: DonationAmountMode.usd,
      amount: '15',
      selectedPreset: '15',
      conversion: '0.05 ZEC',
    );

Widget buildDonationReviewUseCase(BuildContext context) => _DonationFrame(
  child: AppPaneScrollScaffold(
    toolbar: AppPaneToolbar(
      leading: AppBackLink(label: 'Support Vizor', minWidth: 60, onTap: () {}),
    ),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: DonationReviewContentView(
      amountText: '123.12 ZEC',
      fiatText: r'$250.12',
      feeText: '0.012 ZEC',
      confirmLabel: 'Confirm donation',
      confirmIcon: AppIcons.donation,
      onConfirm: () {},
    ),
  ),
);

Widget buildDonationSuccessUseCase(BuildContext context) => _DonationFrame(
  background: const DonationSuccessBackground(),
  child: DonationSuccessView(onDone: () {}),
);

Widget buildDonationStatusInProgressUseCase(BuildContext context) =>
    _DonationFrame(
      child: AppPaneScrollScaffold(
        toolbar: AppPaneToolbar(
          leading: AppBackLink(label: 'Send', minWidth: 60, onTap: () {}),
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

class _DonationComposePreview extends StatefulWidget {
  const _DonationComposePreview({
    required this.mode,
    this.amount = '',
    this.selectedPreset,
    this.conversion = r'$ 0',
  });

  final DonationAmountMode mode;
  final String amount;
  final String? selectedPreset;
  final String conversion;

  @override
  State<_DonationComposePreview> createState() =>
      _DonationComposePreviewState();
}

class _DonationComposePreviewState extends State<_DonationComposePreview> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.amount,
  );

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
            onAmountChanged: (_) {},
            onToggleMode: () {},
            onPresetSelected: (_) {},
            onContinue: widget.amount.isEmpty ? null : () {},
          ),
        ),
      ],
    ),
  );
}

class _DonationFrame extends StatelessWidget {
  const _DonationFrame({required this.child, this.background});

  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) => AppDesktopShell(
    background: background,
    sidebar: const _DonationPreviewSidebar(),
    pane: AppDesktopPane(padding: EdgeInsets.zero, child: child),
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
