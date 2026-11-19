import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../transaction_completeness.dart';

/// A short notice above a list of activity about the private check of its
/// rows, in place of a label on each (see `privateCheckNotice`): still
/// checking, or stopped and why, with a way to the Private queries setting
/// when only the user can clear the stop.
class PrivateCheckNotice extends StatelessWidget {
  const PrivateCheckNotice({required this.state, super.key});

  final PrivateCheckNoticeState state;

  /// The Settings button under a stop's reason, with the gap above it.
  static const settingsHeight = AppSpacing.xxs + 32.0;

  static const _iconSize = kAppFormFactor == AppFormFactor.mobile ? 20.0 : 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final stop = state.stop;
    final style = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((style.fontSize ?? 14) * (style.height ?? 1.4));
    final message = switch (stop) {
      null => l10n.activityPrivateCheckNotice,
      // What happened; the setting's own turn-off prompt says what turning
      // it off does, as Home's longer hint does here.
      rust_sync.TransparentStopReason.quarantined =>
        l10n.activityPrivateCheckStopQuarantined,
      rust_sync.TransparentStopReason.legacyDiscrepancy =>
        l10n.activityPrivateCheckStopLegacyDiscrepancy,
      rust_sync.TransparentStopReason.optOutUnfinished =>
        l10n.activityPrivateCheckStopOptOutUnfinished,
      rust_sync.TransparentStopReason.withdrawn ||
      rust_sync.TransparentStopReason.stalled => transparentStopHint(
        l10n,
        stop,
      ),
    };
    final icon = stop == null
        // The loader in the line's own tone.
        ? AppIcon(AppIcons.loader, size: _iconSize, color: style.color)
        // As Home warns about Private queries.
        : AppIcon(
            AppIcons.warning,
            size: _iconSize,
            color: colors.text.warning,
          );
    final line = Row(
      key: const ValueKey('private_check_notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centred on the first line.
          padding: EdgeInsets.only(
            top: ((lineHeight - _iconSize) / 2).clamp(0.0, double.infinity),
          ),
          child: icon,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(message, style: style)),
      ],
    );
    if (stop == null || !transparentStopNeedsSettings(stop)) return line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        const SizedBox(height: AppSpacing.xxs),
        Padding(
          // Under the text, past the icon.
          padding: const EdgeInsetsDirectional.only(
            start: _iconSize + AppSpacing.xs,
          ),
          child: AppButton(
            key: const ValueKey('private_check_notice_settings'),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            height: settingsHeight - AppSpacing.xxs,
            contentPadding: EdgeInsets.zero,
            iconGap: AppSpacing.xxs,
            // As Home's "See all".
            trailing: const AppIcon(AppIcons.chevronForward, size: 16),
            onPressed: () => context.go('/settings'),
            // Named for the setting it leads to.
            child: Text(
              l10n.settingsPrivateQueriesLabel,
              style: AppTypography.labelLarge,
            ),
          ),
        ),
      ],
    );
  }
}

/// Holds a [PrivateCheckNotice] in place so it eases in and out with its
/// spacing instead of moving the list below it in one jump, and cross-fades
/// between checking and stopped in place, so only finishing folds it away.
/// Shown from the first frame without an entrance, and switched without
/// moving under reduced motion.
class PrivateCheckNoticeSlot extends StatefulWidget {
  const PrivateCheckNoticeSlot({
    required this.notice,
    this.padding = EdgeInsets.zero,
    this.snapWhenScrolled = false,
    super.key,
  });

  /// The notice to show, or null for none.
  final PrivateCheckNoticeState? notice;

  /// The notice's spacing, which appears and goes with it.
  final EdgeInsets padding;

  /// Switches at once when the list has scrolled, for a list whose scroll
  /// anchor keeps the visible rows still instead.
  final bool snapWhenScrolled;

  static const enterDuration = Duration(milliseconds: 240);
  static const exitDuration = Duration(milliseconds: 200);

  /// A switch between checking and stopped fades through: the old notice
  /// fades out over the first [_swapOutEnd] of it, and the new one eases in
  /// over the rest, so neither overlaps the other nor pops in.
  static const swapDuration = Duration(milliseconds: 300);
  static const _swapOutEnd = 0.35;

  /// The app's entrance curve; the exit runs it backwards, so it slows to a
  /// stop as well.
  static const curve = Cubic(0.23, 1, 0.32, 1);

  @override
  State<PrivateCheckNoticeSlot> createState() => _PrivateCheckNoticeSlotState();
}

class _PrivateCheckNoticeSlotState extends State<PrivateCheckNoticeSlot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: PrivateCheckNoticeSlot.enterDuration,
    reverseDuration: PrivateCheckNoticeSlot.exitDuration,
    value: widget.notice != null ? 1 : 0,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: PrivateCheckNoticeSlot.curve,
    reverseCurve: PrivateCheckNoticeSlot.curve.flipped,
  );

  /// The last notice shown, which stays while the slot eases out.
  late PrivateCheckNoticeState? _shown = widget.notice;

  /// A switch that happened at once, for the frame it lands in.
  bool _snapped = false;

  @override
  void didUpdateWidget(PrivateCheckNoticeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final notice = widget.notice;
    if (oldWidget.notice == notice) return;
    final scrolled =
        widget.snapWhenScrolled &&
        (Scrollable.maybeOf(context)?.position.pixels ?? 0) > 0;
    final snap = MediaQuery.disableAnimationsOf(context) || scrolled;
    if (notice != null) {
      _shown = notice;
      if (snap && !_snapped) {
        _snapped = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _snapped = false);
        });
      }
    }
    if ((oldWidget.notice != null) == (notice != null)) return;
    if (snap) {
      _controller.value = notice != null ? 1 : 0;
    } else if (notice != null) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    Widget content = shown == null
        ? const SizedBox(width: double.infinity)
        : PrivateCheckNotice(key: ValueKey(shown), state: shown);
    if (!_snapped && !MediaQuery.disableAnimationsOf(context)) {
      content = AnimatedSize(
        duration: PrivateCheckNoticeSlot.swapDuration,
        curve: PrivateCheckNoticeSlot.curve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: PrivateCheckNoticeSlot.swapDuration,
          // A gentle ease: the entrance curve would pop text in.
          switchInCurve: const Interval(
            PrivateCheckNoticeSlot._swapOutEnd,
            1,
            curve: Curves.easeOut,
          ),
          // Runs backwards, so it covers the start.
          switchOutCurve: const Interval(
            1 - PrivateCheckNoticeSlot._swapOutEnd,
            1,
          ),
          // Sized by the incoming notice; the outgoing one fades over it.
          layoutBuilder: (current, previous) => SizedBox(
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                for (final child in previous)
                  Positioned(top: 0, left: 0, right: 0, child: child),
                ?current,
              ],
            ),
          ),
          child: content,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      // Nothing is built while hidden, so its loader does not keep ticking.
      builder: (context, child) => _controller.value == 0
          ? const SizedBox(width: double.infinity)
          : child!,
      child: SizeTransition(
        sizeFactor: _curve,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _curve,
          child: Padding(padding: widget.padding, child: content),
        ),
      ),
    );
  }
}
