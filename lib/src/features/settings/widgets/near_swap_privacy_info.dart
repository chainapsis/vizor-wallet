import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import 'swap_history_check_control.dart';

/// NEAR swap privacy subtitle while it is on.
const kNearSwapPrivacyOnCopy = 'Swaps use one-time Zcash addresses.';

/// NEAR swap privacy subtitle while it is off and could be turned on. Swaps
/// then use a fresh address of the wallet, as hardware accounts always do.
const kNearSwapPrivacyOffCopy = 'Swaps use regular Zcash addresses.';

/// NEAR swap privacy subtitle while a hardware wallet account is active, since
/// only software accounts get one-time swap addresses.
const kNearSwapPrivacyHardwareCopy =
    'Not available for hardware wallet accounts. Their swaps use regular '
    'Zcash addresses.';

/// What Settings shows for NEAR swap privacy on desktop and mobile.
typedef NearSwapPrivacySetting = ({
  bool enabled,
  String description,
  String? transition,
});

/// The NEAR swap privacy option's state, or null when Settings doesn't offer
/// it (see [nearSwapPrivacySettingAvailableProvider]).
final nearSwapPrivacySettingProvider = Provider<NearSwapPrivacySetting?>((ref) {
  if (!ref.watch(nearSwapPrivacySettingAvailableProvider)) return null;
  final enabled = ref.watch(nearSwapPrivacyProvider);
  final hardwareAccount =
      ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false;
  return (
    enabled: enabled,
    description: hardwareAccount
        ? kNearSwapPrivacyHardwareCopy
        : enabled
        ? kNearSwapPrivacyOnCopy
        : kNearSwapPrivacyOffCopy,
    transition: ref.watch(nearSwapPrivacyTransitionProvider),
  );
});

/// Title of the NEAR swap privacy explanation.
const kNearSwapPrivacyInfoTitle = 'NEAR swap privacy';

/// What NEAR swap privacy protects, first in the explanation.
const kNearSwapPrivacyInfoLead =
    'Each swap gives NEAR Intents one-time Zcash addresses for its payout and '
    "refund. Even a future quantum computer can't tie them to this wallet.";

/// The explanation's sections after [kNearSwapPrivacyInfoLead].
const kNearSwapPrivacyInfoSections = [
  (
    title: 'What changes',
    body:
        'Swaps that send ZEC are paid from your Ironwood balance only. The '
        'first swap after you turn this on can take a few minutes to prepare.',
  ),
  (
    title: "What it doesn't cover",
    body:
        "It keeps these addresses from being tied to your wallet; it doesn't "
        'change how your funds are secured. Addresses you enter yourself, '
        'like an Ethereum address you reuse, can still link your swaps. '
        'Hardware wallet accounts use regular addresses.',
  ),
  (
    title: 'When a payout address is shared',
    body:
        'A payout address from a quote that expired unpaid can be used again '
        'for a later quote. Rarely, two devices with the same wallet that '
        'quote at the same moment get the same address. NEAR can see that '
        'those quotes share an address, but still not which wallet it belongs '
        'to.',
  ),
  (
    title: 'After a restore, or while it is off',
    body:
        'After a restore, your wallet finds these payments privately on its '
        'own. Turning this off only gives new swaps regular addresses. Payouts '
        'and refunds to one-time addresses you already used still show up.',
  ),
];

/// Shows the NEAR swap privacy explanation for this binary's form factor: a
/// sheet on mobile, a dialog on desktop.
Future<void> showNearSwapPrivacyInfo(BuildContext context) =>
    kAppFormFactor == AppFormFactor.mobile
    ? showAppMobileSheet<void>(
        context: context,
        builder: (_) => const NearSwapPrivacyInfoSheet(),
      )
    : showDialog<void>(
        context: context,
        builder: (_) => const NearSwapPrivacyInfoDialog(),
      );

/// Desktop NEAR swap privacy explanation.
class NearSwapPrivacyInfoDialog extends StatelessWidget {
  const NearSwapPrivacyInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      key: const ValueKey('near_swap_privacy_info_dialog'),
      backgroundColor: colors.background.ground,
      shape: appModalShape(BorderRadius.circular(AppRadii.medium)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                kNearSwapPrivacyInfoTitle,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: _FadingScrollBody(
                  surface: colors.background.ground,
                  child: const _Body(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('near_swap_privacy_info_close'),
                expand: true,
                variant: AppButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobile NEAR swap privacy explanation.
class NearSwapPrivacyInfoSheet extends ConsumerWidget {
  const NearSwapPrivacyInfoSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return MobileModalScaffold(
      key: const ValueKey('near_swap_privacy_info_sheet'),
      title: kNearSwapPrivacyInfoTitle,
      onClose: () => Navigator.of(context).pop(),
      leading: AppIcon(AppIcons.linkOff, size: 20, color: colors.icon.accent),
      constrainBody: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            // The sheet's card paints the base surface.
            child: _FadingScrollBody(
              surface: colors.background.base,
              child: const _Body(historyCheck: false),
            ),
          ),
          // Where the sheet's buttons go, so it is in reach without scrolling,
          // as far below the text as other sheets keep their buttons.
          if (_showsHistoryCheck(ref)) ...[
            const SizedBox(height: AppSpacing.md),
            const SwapHistoryCheckControl(
              key: ValueKey('near_swap_privacy_history_check'),
              stacked: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether the explanation offers the swap history check: Settings offers
/// NEAR swap privacy and the wallet has a software account, whatever the
/// setting says.
bool _showsHistoryCheck(WidgetRef ref) =>
    ref.watch(nearSwapPrivacySettingAvailableProvider) &&
    (ref
            .watch(accountProvider)
            .value
            ?.accounts
            .any((account) => !account.isHardware) ??
        false);

/// The explanation's scrolling body. It has no scrollbar; instead an edge with
/// more of the body past it fades into the surface, as the endpoint list
/// does, and the fade goes once that end is in view.
class _FadingScrollBody extends StatefulWidget {
  const _FadingScrollBody({required this.surface, required this.child});

  /// The color the body sits on, which the fade ends in.
  final Color surface;
  final Widget child;

  @override
  State<_FadingScrollBody> createState() => _FadingScrollBodyState();
}

class _FadingScrollBodyState extends State<_FadingScrollBody> {
  final _controller = ScrollController();
  var _above = false;
  var _below = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_update);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final above = position.extentBefore > 0.5;
    final below = position.extentAfter > 0.5;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
  }

  Widget _fade({
    required Key key,
    required bool shown,
    required Alignment from,
    required Alignment to,
  }) => IgnorePointer(
    child: AnimatedOpacity(
      key: key,
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: from,
            end: to,
            colors: [widget.surface, widget.surface.withValues(alpha: 0)],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Metrics change on the first layout and whenever the content resizes.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _update();
        return false;
      },
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _controller,
              child: widget.child,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: AppSpacing.base,
            child: _fade(
              key: const ValueKey('near_swap_privacy_info_fade_top'),
              shown: _above,
              from: Alignment.topCenter,
              to: Alignment.bottomCenter,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: AppSpacing.lg,
            child: _fade(
              key: const ValueKey('near_swap_privacy_info_fade_bottom'),
              shown: _below,
              from: Alignment.bottomCenter,
              to: Alignment.topCenter,
            ),
          ),
        ],
      ),
    );
  }
}

/// [kNearSwapPrivacyInfoLead] and [kNearSwapPrivacyInfoSections], then the
/// swap history check when [_showsHistoryCheck].
class _Body extends ConsumerWidget {
  const _Body({this.historyCheck = true});

  /// Whether the history check ends the body, as in the desktop dialog. The
  /// mobile sheet pins it below instead.
  final bool historyCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final showHistoryCheck = historyCheck && _showsHistoryCheck(ref);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kNearSwapPrivacyInfoLead,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
        for (final section in kNearSwapPrivacyInfoSections) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            section.title,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            section.body,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (showHistoryCheck) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: colors.border.subtle),
          const SizedBox(height: AppSpacing.xs),
          // The provider owns the check, so closing the explanation leaves a
          // running or saved one going.
          const SwapHistoryCheckControl(
            key: ValueKey('near_swap_privacy_history_check'),
          ),
        ],
      ],
    );
  }
}
