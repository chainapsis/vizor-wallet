import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../settings/widgets/network_privacy_control.dart' show PrivacyToggle;
import '../models/swap_models.dart';

/// Quote failure above the primary recovery action, in the composer's
/// existing quote-error style.
class SwapQuoteUnavailableStatus extends StatelessWidget {
  const SwapQuoteUnavailableStatus({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      key: const ValueKey('swap_quote_feedback'),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.destructive,
      ),
    ),
  );
}

/// Confidential route setting at the top of the swap and Pay settings modal.
/// The mode is a quote parameter like slippage, so it is chosen there and the
/// composer only marks the settings button while it is on.
class SwapConfidentialSetting extends StatelessWidget {
  const SwapConfidentialSetting({
    required this.confidential,
    required this.onChanged,
    super.key,
  });

  final bool confidential;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_confidential_setting'),
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SwapConfidentialIcon(),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      context.l10n.swapConfidentialLabel,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                context.l10n.swapConfidentialSettingDescription,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        // The Settings privacy toggle, so privacy switches look alike. Its own
        // node carries no tap action, so this one lets screen readers flip it.
        Semantics(
          container: true,
          button: true,
          enabled: true,
          toggled: confidential,
          label: context.l10n.swapConfidentialLabel,
          onTap: () => onChanged(!confidential),
          excludeSemantics: true,
          child: PrivacyToggle(
            enabled: confidential,
            trackKey: const ValueKey('swap_confidential_switch'),
            semanticsLabel: context.l10n.swapConfidentialLabel,
            onToggle: () => onChanged(!confidential),
          ),
        ),
      ],
    );
  }
}

/// Counts turns to confidential for [SwapConfidentialSeamReveal] and the
/// mark. A turn made inside the settings waits for them to close, so the
/// reveal plays where it can be seen; turning it back off first cancels it.
class SwapConfidentialRevealCounter {
  int _value = 0;
  bool _pending = false;

  int get value => _value;

  /// Returns whether [value] changed.
  bool turnedOn({required bool settingsOpen}) {
    if (settingsOpen) {
      _pending = true;
      return false;
    }
    _value++;
    return true;
  }

  /// Returns whether [value] changed.
  bool settingsClosed({required bool confidential}) {
    final play = _pending && confidential;
    _pending = false;
    if (play) _value++;
    return play;
  }
}

/// One play of turning confidential on: the seam flips first, then the mark
/// lands beside the settings button.
const kSwapConfidentialRevealDuration = Duration(milliseconds: 900);

/// The confidential mark: on the settings button while the mode is on, and
/// beside the setting itself.
class SwapConfidentialIcon extends StatelessWidget {
  const SwapConfidentialIcon({
    this.alpha = 1,
    this.reveal = 0,
    this.labeled = false,
    super.key,
  });

  final double alpha;

  /// Raised each time confidential turns on, landing the mark once after the
  /// seam flip. 0 shows it still.
  final int reveal;

  /// Names the mark for screen readers where no visible label sits beside it.
  final bool labeled;

  @override
  Widget build(BuildContext context) {
    final mark = _mark(context);
    return labeled
        ? Semantics(label: context.l10n.swapConfidentialLabel, child: mark)
        : mark;
  }

  Widget _mark(BuildContext context) {
    final color = context.colors.icon.brandCrimson;
    final icon = AppIcon(
      AppIcons.incognito,
      size: 16,
      color: color.withValues(alpha: alpha),
    );
    if (reveal == 0 || MediaQuery.disableAnimationsOf(context)) return icon;
    return TweenAnimationBuilder<double>(
      key: ValueKey(reveal),
      tween: Tween(begin: 0, end: 1),
      duration: kSwapConfidentialRevealDuration,
      child: icon,
      builder: (context, t, child) {
        final land = const Interval(
          0.55,
          0.95,
          curve: Curves.easeOutBack,
        ).transform(t);
        return CustomPaint(
          painter: _MarkGlowPainter(
            color: color,
            progress: const Interval(0.75, 1).transform(t),
          ),
          child: Opacity(
            opacity: const Interval(0.55, 0.7).transform(t),
            child: Transform.scale(scale: 2 - land, child: child),
          ),
        );
      },
    );
  }
}

/// Turns the swap direction button over to the confidential mark and back
/// under a crimson ring, once each time [reveal] rises: the seam between pay
/// and receive is what confidential hides. 0 shows [child] still.
class SwapConfidentialSeamReveal extends StatelessWidget {
  const SwapConfidentialSeamReveal({
    required this.reveal,
    required this.size,
    required this.radius,
    required this.child,
    this.faceBorder,
    super.key,
  });

  final int reveal;

  /// The button's side, corner radius and any outer ring, which the mark face
  /// matches.
  final double size;
  final double radius;
  final BoxBorder? faceBorder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reveal == 0 || MediaQuery.disableAnimationsOf(context)) return child;
    final colors = context.colors;
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.background.brandCrimsonStrong,
        borderRadius: BorderRadius.circular(radius),
        border: faceBorder,
      ),
      child: const AppIcon(
        AppIcons.incognito,
        size: 20,
        color: Color(0xFFFFFFFF),
      ),
    );
    return TweenAnimationBuilder<double>(
      key: ValueKey(reveal),
      tween: Tween(begin: 0, end: 1),
      duration: kSwapConfidentialRevealDuration,
      child: child,
      builder: (context, t, child) {
        // Out, the mark in and held, out again, the button back.
        final showFace = t >= 0.15 && t < 0.75;
        final turn = t < 0.15
            ? 1 - Curves.easeIn.transform(t / 0.15)
            : t < 0.3
            ? Curves.easeOut.transform((t - 0.15) / 0.15)
            : t < 0.62
            ? 1.0
            : t < 0.75
            ? 1 - Curves.easeIn.transform((t - 0.62) / 0.13)
            : t < 0.9
            ? Curves.easeOut.transform((t - 0.75) / 0.15)
            : 1.0;
        return CustomPaint(
          painter: _SeamRingPainter(
            color: colors.icon.brandCrimson,
            radius: radius,
            progress: const Interval(
              0.15,
              0.7,
              curve: Curves.easeOut,
            ).transform(t),
          ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(turn, 1, 1),
            // The button stays mounted under the face, so a tap mid-flip
            // still reaches it.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(opacity: showFace ? 0 : 1, child: child),
                if (showFace) IgnorePointer(child: face),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SeamRingPainter extends CustomPainter {
  const _SeamRingPainter({
    required this.color,
    required this.radius,
    required this.progress,
  });

  final Color color;
  final double radius;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final spread = 14 * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(spread),
        Radius.circular(radius + spread),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.8 * (1 - progress)),
    );
  }

  @override
  bool shouldRepaint(_SeamRingPainter old) =>
      old.color != color || old.radius != radius || old.progress != progress;
}

class _MarkGlowPainter extends CustomPainter {
  const _MarkGlowPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    canvas.drawCircle(
      size.center(Offset.zero),
      8 + 8 * progress,
      Paint()..color = color.withValues(alpha: 0.35 * (1 - progress)),
    );
  }

  @override
  bool shouldRepaint(_MarkGlowPainter old) =>
      old.color != color || old.progress != progress;
}

/// Whether a confidential route is moving funds: every status that still
/// reads as in progress, short of an incomplete deposit waiting on the user.
bool swapConfidentialRouteFlows(SwapIntentStatus status) =>
    !status.isTerminal && status != SwapIntentStatus.incompleteDeposit;

/// Review and status connector between the paying and receiving rows: a
/// dashed route with the mark, in place of the flow arrow. The line runs from
/// the icon slot of the row above to the icon slot of the row below, read
/// from where those rows are laid out. The mark explains itself on hover or
/// tap.
class SwapConfidentialRouteConnector extends StatelessWidget {
  /// Between the swap review and status asset rows.
  const SwapConfidentialRouteConnector.swap({this.flowing = false, super.key})
    : height = 24;

  /// Between the pay amount and recipient rows. Mobile status keeps the taller
  /// arrow row it replaces.
  const SwapConfidentialRouteConnector.pay({
    required bool review,
    this.flowing = false,
    super.key,
  }) : height = kAppFormFactor == AppFormFactor.mobile && !review ? 40 : 24;

  /// Height of the arrow row this replaces.
  final double height;

  /// Dashes run from pay toward receive while the swap is in progress.
  final bool flowing;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.icon.brandCrimson;
    final badge = Semantics(
      label: context.l10n.swapConfidentialLabel,
      child: AppTooltip(
        message: context.l10n.swapConfidentialRouteTooltip,
        tapToShow: true,
        child: const _RouteBadge(size: 22),
      ),
    );
    return SizedBox(
      key: const ValueKey('swap_confidential_route'),
      height: height,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          // The icon column the route runs down.
          width: AppAssetSize.size,
          height: height,
          child: flowing && !MediaQuery.disableAnimationsOf(context)
              ? _FlowingRoute(
                  key: const ValueKey('swap_confidential_route_flowing'),
                  color: color,
                  child: badge,
                )
              : _RouteLine(
                  color: color,
                  child: Center(child: badge),
                ),
        ),
      ),
    );
  }
}

class _FlowingRoute extends StatefulWidget {
  const _FlowingRoute({required this.color, required this.child, super.key});

  final Color color;
  final Widget child;

  @override
  State<_FlowingRoute> createState() => _FlowingRouteState();
}

class _FlowingRouteState extends State<_FlowingRoute>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RouteLine(
    color: widget.color,
    phase: _controller,
    child: Center(child: widget.child),
  );
}

/// The same solid crimson and white mark the composer's seam turns over to,
/// so review and status show what the user saw switch on.
class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.colors.background.brandCrimsonStrong,
      shape: BoxShape.circle,
    ),
    child: AppIcon(
      AppIcons.incognito,
      size: size * 0.6,
      color: const Color(0xFFFFFFFF),
    ),
  );
}

/// Paints the dashed route behind [child]. [phase] slides the dashes down by
/// up to one period.
class _RouteLine extends SingleChildRenderObjectWidget {
  const _RouteLine({required this.color, this.phase, super.child});

  final Color color;
  final Animation<double>? phase;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRouteLine(color: color, phase: phase);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderRouteLine renderObject,
  ) {
    renderObject
      ..color = color
      ..phase = phase;
  }
}

class _RenderRouteLine extends RenderProxyBox {
  _RenderRouteLine({required Color color, Animation<double>? phase})
    : _color = color,
      _phase = phase;

  static const _period = 6.0;
  static const _dash = 3.0;

  /// Space left between the line and each icon slot.
  static const _gap = 2.0;

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  Animation<double>? _phase;
  set phase(Animation<double>? value) {
    if (value == _phase) return;
    if (attached) _phase?.removeListener(markNeedsPaint);
    _phase = value;
    if (attached) _phase?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _phase?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _phase?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// The line's ends in this box's coordinates: the facing edges of the icon
  /// slots in the rows above and below. Both rows centre their icon slot, so
  /// the edges follow from where the rows sit, whatever their height. Falls
  /// back to this box's own height outside a column.
  (double, double) _span() {
    RenderObject node = this;
    while (node.parent != null && node.parent is! RenderFlex) {
      node = node.parent!;
    }
    final flex = node.parent;
    final data = node.parentData;
    if (flex is! RenderFlex ||
        flex.direction != Axis.vertical ||
        data is! FlexParentData) {
      return (0, size.height);
    }
    final above = data.previousSibling;
    final below = data.nextSibling;
    final aboveData = above?.parentData;
    final belowData = below?.parentData;
    if (above == null ||
        below == null ||
        aboveData is! FlexParentData ||
        belowData is! FlexParentData) {
      return (0, size.height);
    }
    final origin = MatrixUtils.transformPoint(
      getTransformTo(flex),
      Offset.zero,
    ).dy;
    const slot = AppAssetSize.size;
    final top = aboveData.offset.dy + (above.size.height + slot) / 2 + _gap;
    final bottom = belowData.offset.dy + (below.size.height - slot) / 2 - _gap;
    return (top - origin, bottom - origin);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..color = _color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final (start, end) = _span();
    final x = offset.dx + size.width / 2;
    final shift = (_phase?.value ?? 0) * _period;
    for (var y = start - _period + shift; y < end; y += _period) {
      final from = y < start ? start : y;
      final to = y + _dash > end ? end : y + _dash;
      if (to > from) {
        context.canvas.drawLine(
          Offset(x, offset.dy + from),
          Offset(x, offset.dy + to),
          paint,
        );
      }
    }
    super.paint(context, offset);
  }
}
