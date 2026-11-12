import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_shape.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/swap_past_swaps_check_provider.dart';
import 'swap_history_check_control.dart';

/// Which subtitle the NEAR swap privacy option shows.
enum NearSwapPrivacyDescription {
  /// The setting is on.
  on,

  /// The setting is off and could be turned on. Swaps then use a fresh address
  /// of the wallet, as hardware accounts always do.
  off,

  /// The saved choice couldn't be read.
  unknown,

  /// A hardware wallet account is active, and only software accounts get
  /// one-time swap addresses.
  hardware;

  /// The subtitle in the display language.
  String text(AppLocalizations l10n) => switch (this) {
    NearSwapPrivacyDescription.on => l10n.settingsNearSwapPrivacyOn,
    NearSwapPrivacyDescription.off => l10n.settingsNearSwapPrivacyOff,
    NearSwapPrivacyDescription.unknown => l10n.settingsNearSwapPrivacyUnknown,
    NearSwapPrivacyDescription.hardware => l10n.settingsNearSwapPrivacyHardware,
  };
}

/// What Settings shows for NEAR swap privacy on desktop and mobile.
/// [available] is false for a hardware wallet account, which shows "Not
/// available" instead of a switch. [checkingPastSwaps] shows
/// [NearSwapPrivacyCheckingPastSwaps].
typedef NearSwapPrivacySetting = ({
  bool enabled,
  bool available,
  NearSwapPrivacyDescription description,
  EnhancePirTransition? transition,
  bool checkingPastSwaps,
});

/// The NEAR swap privacy option's state, or null when Settings doesn't offer
/// it (see [nearSwapPrivacySettingAvailableProvider]).
final nearSwapPrivacySettingProvider = Provider<NearSwapPrivacySetting?>((ref) {
  if (!ref.watch(nearSwapPrivacySettingAvailableProvider)) return null;
  final enabled = ref.watch(nearSwapPrivacyProvider);
  final hardwareAccount =
      ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false;
  return (
    enabled: enabled ?? false,
    available: !hardwareAccount,
    description: enabled == null
        ? NearSwapPrivacyDescription.unknown
        : hardwareAccount
        ? NearSwapPrivacyDescription.hardware
        : enabled
        ? NearSwapPrivacyDescription.on
        : NearSwapPrivacyDescription.off,
    transition: ref.watch(nearSwapPrivacyTransitionProvider),
    checkingPastSwaps:
        enabled == true &&
        !hardwareAccount &&
        ref.watch(swapPastSwapsCheckProvider),
  );
});

/// The NEAR swap privacy explanation's sections after its lead.
List<({String title, String body})> nearSwapPrivacyInfoSections(
  AppLocalizations l10n,
) => [
  (
    title: l10n.settingsNearSwapPrivacyInfoChangesTitle,
    body: l10n.settingsNearSwapPrivacyInfoChangesBody,
  ),
  (
    title: l10n.settingsNearSwapPrivacyInfoLimitsTitle,
    body: l10n.settingsNearSwapPrivacyInfoLimitsBody,
  ),
  (
    title: l10n.settingsNearSwapPrivacyInfoReuseTitle,
    body: l10n.settingsNearSwapPrivacyInfoReuse,
  ),
  (
    title: l10n.settingsNearSwapPrivacyInfoRestoreTitle,
    body: l10n.settingsNearSwapPrivacyInfoRestore,
  ),
];

/// The "Learn more" button under the NEAR swap privacy description, which
/// opens [showNearSwapPrivacyInfo]. Its icon lines up with the text above.
class NearSwapPrivacyLearnMore extends StatelessWidget {
  const NearSwapPrivacyLearnMore({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    void open() => unawaited(showNearSwapPrivacyInfo(context));
    return Semantics(
      container: true,
      button: true,
      label: context.l10n.settingsNearSwapPrivacyLearnMoreSemantics,
      onTap: open,
      excludeSemantics: true,
      child: AppButton(
        key: const ValueKey('near_swap_privacy_learn_more'),
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.small,
        leading: AppIcon(AppIcons.help, color: colors.icon.muted),
        onPressed: open,
        child: Text(context.l10n.settingsNearSwapPrivacyLearnMore),
      ),
    );
  }
}

/// "Checking past swaps" with a loader, read out as it appears and goes.
class NearSwapPrivacyCheckingPastSwaps extends StatelessWidget {
  const NearSwapPrivacyCheckingPastSwaps({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        key: const ValueKey('near_swap_privacy_checking_past_swaps'),
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.muted),
          const SizedBox(width: AppSpacing.xxs),
          // Wraps at narrow widths and large text sizes.
          Flexible(
            child: Text(
              context.l10n.settingsNearSwapPrivacyCheckingPastSwaps,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                context.l10n.settingsNearSwapPrivacyLabel,
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
                child: Text(context.l10n.commonClose),
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
      title: context.l10n.settingsNearSwapPrivacyLabel,
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

/// The explanation's lead and [nearSwapPrivacyInfoSections], then the
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
          context.l10n.settingsNearSwapPrivacyInfoLead,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
        for (final section in nearSwapPrivacyInfoSections(context.l10n)) ...[
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
