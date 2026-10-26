import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../formatting/sync_status_label.dart';
import '../../theme/app_theme.dart';

/// Subtle/slow motion constants for the syncing affordance. One full
/// breath (glow swell) and one shimmer sweep per [period]; both are
/// driven by the same controller so the label and bar feel coordinated.
abstract final class _SyncStatusMotion {
  static const period = Duration(milliseconds: 1400);

  /// Half-width of the shimmer highlight band as a gradient-stop fraction.
  /// Kept narrow for a gentle, low-contrast sparkle.
  static const _bandHalf = 0.18;

  /// Edge-bar glow breathing range (shadow blur radius + alpha). Kept gentle
  /// so the syncing glow stays subtle rather than vibrant.
  static const _minGlowBlur = 8.0;
  static const _maxGlowBlur = 13.0;
  static const _minGlowAlpha = 0.2;
  static const _maxGlowAlpha = 0.45;

  /// 0 → 1 → 0 once per [period].
  static double _breath(double t) => (1 - math.cos(2 * math.pi * t)) / 2;

  static ({double blur, double alpha}) glowFor(double t) {
    final e = _breath(t);
    return (
      blur: _lerp(_minGlowBlur, _maxGlowBlur, e),
      alpha: _lerp(_minGlowAlpha, _maxGlowAlpha, e),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Shared mobile label and glow bar. The sidebar mirrors the header effects.
///
/// While [animated] (the live syncing state, reduced-motion off) a single
/// [AnimationController] drives a bright-green shimmer band sweeping across
/// the label and a slow breathing pulse on the green edge bar, so the two
/// read as one "actively working" affordance. Otherwise — synced, failed,
/// or reduced-motion — it renders the same static label + bar as before.
class MobileSyncStatus extends StatefulWidget {
  const MobileSyncStatus({
    required this.label,
    required this.baseColor,
    required this.highlightColor,
    required this.indicatorColor,
    this.indicatorSize = const Size(6, 50),
    this.leading = false,
    this.wrapLabel = false,
    this.semanticsLabel,
    this.liveRegion = false,
    required this.animated,
    super.key,
  });

  final String label;
  final Color baseColor;
  final Color highlightColor;
  final Color indicatorColor;
  final Size indicatorSize;
  final bool animated;

  /// Physical left edge for the sidebar; the header retains its right edge.
  final bool leading;
  final bool wrapLabel;
  final String? semanticsLabel;
  final bool liveRegion;

  static ({Color label, Color indicator, Color highlight}) colorsFor(
    BuildContext context,
    SyncStatusKind kind,
  ) {
    final colors = context.colors;
    return switch (kind) {
      // A short catch-up keeps the synced look.
      SyncStatusKind.synced || SyncStatusKind.catchingUp => (
        label: colors.sync.text,
        indicator: colors.sync.lightSuccess,
        highlight: colors.sync.text,
      ),
      SyncStatusKind.syncing => (
        label: colors.sync.textSyncing,
        indicator: colors.text.muted,
        highlight: colors.sync.lightSuccess,
      ),
      SyncStatusKind.failed => (
        label: colors.sync.textError,
        indicator: colors.sync.lightError,
        highlight: colors.sync.textError,
      ),
    };
  }

  factory MobileSyncStatus.fromStatus({
    required BuildContext context,
    required SyncStatusLabel status,
    bool leading = false,
    bool wrapLabel = false,
  }) {
    final colors = colorsFor(context, status.kind);
    return MobileSyncStatus(
      label: status.label,
      baseColor: colors.label,
      highlightColor: colors.highlight,
      indicatorColor: colors.indicator,
      animated: status.kind == SyncStatusKind.syncing,
      leading: leading,
      wrapLabel: wrapLabel,
      semanticsLabel: status.semanticsLabel,
      liveRegion: status.kind == SyncStatusKind.failed,
    );
  }

  @override
  State<MobileSyncStatus> createState() => _SyncStatusState();
}

/// The label's style, with tabular figures so a changing percentage keeps its
/// width.
final _labelStyle = withTabularFigures(AppTypography.labelMedium);

class _SyncStatusState extends State<MobileSyncStatus>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  /// The synced label's width at the current text scale. The header's label
  /// slot is at least this wide.
  double _syncedLabelWidth = 0;

  AnimationController get _activeController {
    return _controller ??= AnimationController(
      vsync: this,
      duration: _SyncStatusMotion.period,
    );
  }

  bool get _shouldAnimate {
    if (!widget.animated) {
      return false;
    }
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-evaluate on dependency changes (e.g. the reduce-motion setting).
    _syncAnimation();
    final painter = TextPainter(
      text: TextSpan(text: kSyncStatusSyncedLabel, style: _labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    _syncedLabelWidth = painter.width;
    painter.dispose();
  }

  @override
  void didUpdateWidget(covariant MobileSyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) {
        _activeController.repeat();
      }
    } else {
      final controller = _controller;
      if (controller != null) {
        controller
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _row(double? progress) {
    final glow = progress == null ? null : _SyncStatusMotion.glowFor(progress);
    final text = progress == null
        ? Text(
            widget.label,
            textAlign: widget.leading ? TextAlign.left : null,
            style: _labelStyle.copyWith(color: widget.baseColor),
          )
        : _ShimmerLabel(
            label: widget.label,
            baseColor: widget.baseColor,
            highlightColor: widget.highlightColor,
            leading: widget.leading,
            progress: widget.leading ? 1 - progress : progress,
          );
    // The header's label slot is at least as wide as the synced label, so a
    // shorter one does not move the nav; the label sits at its trailing
    // edge, next to the bar. The sidebar's label is left-aligned and keeps
    // its own width.
    final label = widget.leading
        ? text
        : ConstrainedBox(
            key: const ValueKey('mobile_top_nav_sync_label_slot'),
            constraints: BoxConstraints(minWidth: _syncedLabelWidth),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              widthFactor: 1,
              child: text,
            ),
          );
    final indicator = _SyncEdgeIndicator(
      size: widget.indicatorSize,
      color: widget.indicatorColor,
      leading: widget.leading,
      glowBlur: glow?.blur ?? 12,
      glowAlpha: glow?.alpha ?? 0.6,
    );
    return Semantics(
      label: widget.semanticsLabel,
      excludeSemantics: widget.semanticsLabel != null,
      liveRegion: widget.liveRegion,
      child: Row(
        mainAxisSize: widget.wrapLabel ? MainAxisSize.max : MainAxisSize.min,
        // Mirror the component, never the glyphs or their reading direction.
        textDirection: widget.leading ? TextDirection.ltr : null,
        children: [
          if (widget.leading) ...[
            indicator,
            const SizedBox(width: AppSpacing.s),
          ],
          if (widget.wrapLabel) Expanded(child: label) else label,
          if (!widget.leading) ...[
            const SizedBox(width: AppSpacing.s),
            indicator,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => !_shouldAnimate
      ? _row(null)
      : AnimatedBuilder(
          animation: _activeController,
          builder: (context, _) => _row(_activeController.value),
        );
}

/// The sync label with a bright-green highlight band sweeping across it.
///
/// A [ShaderMask] (`srcIn`) replaces the glyph pixels with a horizontal
/// `base → highlight → base` gradient; sliding the gradient's mapping
/// rect by [progress] travels the band left→right. The band fully exits
/// both edges (pure base) at the loop ends, so the repeat is seamless.
class _ShimmerLabel extends StatelessWidget {
  const _ShimmerLabel({
    required this.label,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    required this.leading,
  });

  final String label;
  final Color baseColor;
  final Color highlightColor;
  final double progress;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final shift = (progress * 2 - 1) * bounds.width;
        final rect = Rect.fromLTWH(
          bounds.left + shift,
          bounds.top,
          bounds.width,
          bounds.height,
        );
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: const [
            0.5 - _SyncStatusMotion._bandHalf,
            0.5,
            0.5 + _SyncStatusMotion._bandHalf,
          ],
          tileMode: TileMode.clamp,
        ).createShader(rect);
      },
      // Solid color so `srcIn` keeps the gradient over the full glyph.
      child: Text(
        label,
        textAlign: leading ? TextAlign.left : null,
        style: _labelStyle.copyWith(color: const Color(0xFFFFFFFF)),
      ),
    );
  }
}

/// The thin glow bar hugging the right screen edge in the account
/// variant — Figma `_Nav Sync Widget > light` (node 4237:92744).
class _SyncEdgeIndicator extends StatelessWidget {
  const _SyncEdgeIndicator({
    required this.size,
    required this.color,
    required this.leading,
    this.glowBlur = 12,
    this.glowAlpha = 0.6,
  });

  final Size size;
  final Color color;
  final bool leading;
  final double glowBlur;
  final double glowAlpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.horizontal(
          left: leading ? Radius.zero : Radius.circular(size.width / 2),
          right: leading ? Radius.circular(size.width / 2) : Radius.zero,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: glowAlpha),
            blurRadius: glowBlur,
          ),
        ],
      ),
    );
  }
}
