import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// A short notice above a list of activity while Private queries is still
/// checking several of its rows, in place of a label on each (see
/// `showsPrivateCheckNotice`).
class PrivateCheckNotice extends StatelessWidget {
  const PrivateCheckNotice({this.centered = false, super.key});

  /// Centres the notice under a centred page title.
  final bool centered;

  static const _iconSize = kAppFormFactor == AppFormFactor.mobile ? 20.0 : 16.0;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.text.secondary;
    final style = AppTypography.bodyMedium.copyWith(color: color);
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale((style.fontSize ?? 14) * (style.height ?? 1.4));
    final text = Text(
      context.l10n.activityPrivateCheckNotice,
      style: style,
      textAlign: centered ? TextAlign.center : TextAlign.start,
    );
    return Row(
      key: const ValueKey('private_check_notice'),
      mainAxisSize: centered ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centred on the first line.
          padding: EdgeInsets.only(
            top: ((lineHeight - _iconSize) / 2).clamp(0.0, double.infinity),
          ),
          // The loader in the line's own tone.
          child: AppIcon(AppIcons.loader, size: _iconSize, color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        if (centered) Flexible(child: text) else Expanded(child: text),
      ],
    );
  }
}

/// Holds a [PrivateCheckNotice] in place so it eases in and out with its
/// spacing instead of moving the list below it in one jump. Shown from the
/// first frame without an entrance, and switched without moving under
/// reduced motion.
class PrivateCheckNoticeSlot extends StatefulWidget {
  const PrivateCheckNoticeSlot({
    required this.checking,
    this.padding = EdgeInsets.zero,
    this.centered = false,
    this.snapWhenScrolled = false,
    super.key,
  });

  /// Whether several rows await the private check.
  final bool checking;

  /// The notice's spacing, which appears and goes with it.
  final EdgeInsets padding;
  final bool centered;

  /// Switches at once when the list has scrolled, for a list whose scroll
  /// anchor keeps the visible rows still instead.
  final bool snapWhenScrolled;

  static const enterDuration = Duration(milliseconds: 240);
  static const exitDuration = Duration(milliseconds: 200);

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
    value: widget.checking ? 1 : 0,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: PrivateCheckNoticeSlot.curve,
    reverseCurve: PrivateCheckNoticeSlot.curve.flipped,
  );

  @override
  void didUpdateWidget(PrivateCheckNoticeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking == widget.checking) return;
    final scrolled =
        widget.snapWhenScrolled &&
        (Scrollable.maybeOf(context)?.position.pixels ?? 0) > 0;
    if (MediaQuery.disableAnimationsOf(context) || scrolled) {
      _controller.value = widget.checking ? 1 : 0;
    } else if (widget.checking) {
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
          child: Padding(
            padding: widget.padding,
            child: PrivateCheckNotice(centered: widget.centered),
          ),
        ),
      ),
    );
  }
}
