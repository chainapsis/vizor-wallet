import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

class LedgerStep {
  const LedgerStep(
    this.label, {
    this.message,
    this.note,
    this.detail,
    this.busy = false,
    this.requiresDeviceAction = false,
  });
  final String label;
  final String? message;
  final String? note;
  final String? detail;
  final bool busy;
  final bool requiresDeviceAction;
}

/// One procedure for account setup and transaction approval. Only the current
/// step expands; its ordinal and first text baseline remain stable while busy.
class LedgerProcedure extends StatefulWidget {
  const LedgerProcedure({
    required this.steps,
    required this.currentStep,
    this.topPadding = AppSpacing.md,
    super.key,
  });
  final List<LedgerStep> steps;
  final int currentStep;
  final double topPadding;

  @override
  State<LedgerProcedure> createState() => _LedgerProcedureState();
}

class _LedgerProcedureState extends State<LedgerProcedure> {
  final _stepKeys = <int, GlobalKey>{};
  String? _layout;

  void _reveal(String layout, {bool afterExpansion = false}) {
    if (afterExpansion ? _layout != layout : _layout == layout) return;
    _layout = layout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layout != layout) return;
      final targetContext = _stepKeys[widget.currentStep]?.currentContext;
      final target = targetContext?.findRenderObject();
      if (targetContext == null || target is! RenderBox) return;
      final position = Scrollable.maybeOf(targetContext)?.position;
      if (position == null || position.maxScrollExtent <= 0) return;
      position.ensureVisible(
        target,
        duration:
            afterExpansion && !MediaQuery.disableAnimationsOf(targetContext)
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        alignmentPolicy: target.size.height > position.viewportDimension
            ? ScrollPositionAlignmentPolicy.explicit
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = context.colors;
      final style = AppTypography.bodyMediumStrong;
      final scale =
          MediaQuery.textScalerOf(context).scale(style.fontSize!) /
          style.fontSize!;
      final lineHeight = style.fontSize! * style.height! * scale;
      final markerSize = 24.0 * scale;
      final current = widget.steps[widget.currentStep];
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      final layout =
          '${constraints.maxWidth}:${MediaQuery.sizeOf(context).height}:$scale:$reducedMotion:${widget.currentStep}:${current.message}:${current.note}:${current.detail}:${current.requiresDeviceAction}';
      _reveal(layout);
      return Padding(
        padding: EdgeInsets.only(top: widget.topPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < widget.steps.length; index++) ...[
              if (index > 0) const SizedBox(height: 20),
              Semantics(
                key: _stepKeys.putIfAbsent(index, GlobalKey.new),
                container: true,
                liveRegion: index == widget.currentStep,
                label: index < widget.currentStep
                    ? 'Step ${index + 1} of ${widget.steps.length}, complete'
                    : 'Step ${index + 1} of ${widget.steps.length}',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox(
                        width: markerSize,
                        height: lineHeight,
                        child: Center(
                          child: index < widget.currentStep
                              ? AppIcon(
                                  AppIcons.check,
                                  size: 20,
                                  color: colors.icon.regular,
                                )
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (index == widget.currentStep)
                                      Container(
                                        width: markerSize,
                                        height: markerSize,
                                        decoration: BoxDecoration(
                                          color: colors.button.primary.bg,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    Text(
                                      '${index + 1}',
                                      style: style.copyWith(
                                        color: index == widget.currentStep
                                            ? colors.button.primary.label
                                            : colors.text.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.steps[index].label,
                                  style: style.copyWith(
                                    color: index == widget.currentStep
                                        ? colors.text.accent
                                        : colors.text.secondary,
                                  ),
                                ),
                              ),
                              if (index == widget.currentStep &&
                                  current.busy) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: (lineHeight - 20) / 2,
                                  ),
                                  child: AppIcon(
                                    AppIcons.loader,
                                    animated: true,
                                    size: 20,
                                    color: colors.icon.regular,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          _LedgerStepBody(
                            step: widget.steps[index],
                            expanded: index == widget.currentStep,
                            onExpanded: () =>
                                _reveal(layout, afterExpansion: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Retain the outgoing instruction only while it folds away. Keeping each row
/// mounted lets a rapid stage change reverse from its current visible height.
class _LedgerStepBody extends StatefulWidget {
  const _LedgerStepBody({
    required this.step,
    required this.expanded,
    required this.onExpanded,
  });
  final LedgerStep step;
  final bool expanded;
  final VoidCallback onExpanded;

  @override
  State<_LedgerStepBody> createState() => _LedgerStepBodyState();
}

class _LedgerStepBodyState extends State<_LedgerStepBody> {
  LedgerStep? _content;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    if (widget.expanded) _content = widget.step;
  }

  @override
  void didUpdateWidget(covariant _LedgerStepBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded) _content = widget.step;
    if (oldWidget.expanded != widget.expanded) _moving = true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = _content;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 250);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (content?.detail != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              content!.detail!,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        if (content?.message != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              content!.message!,
              style: content.requiresDeviceAction
                  ? AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    )
                  : AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
            ),
          ),
        if (content?.note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: Text(
              content!.note!,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
      ],
    );
    return ExcludeSemantics(
      excluding: !widget.expanded,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(reducedMotion),
        tween: Tween(
          begin: widget.expanded ? 1 : 0,
          end: widget.expanded ? 1 : 0,
        ),
        duration: duration,
        curve: Curves.easeOutCubic,
        onEnd: () {
          if (!_moving) return;
          _moving = false;
          if (widget.expanded) widget.onExpanded();
        },
        builder: (context, fraction, child) => fraction == 0
            ? const SizedBox.shrink()
            : ClipRect(
                child: Align(
                  alignment: Alignment.topLeft,
                  heightFactor: fraction,
                  child: Opacity(opacity: fraction, child: child),
                ),
              ),
        // Reset size interpolation on a step change: the fold already owns it.
        // Within an open step, copy changes can still resize the sheet gently.
        child: reducedMotion
            ? body
            : AnimatedSize(
                key: ValueKey(widget.expanded),
                alignment: Alignment.topLeft,
                duration: duration,
                curve: Curves.easeOutCubic,
                onEnd: () {
                  if (widget.expanded) widget.onExpanded();
                },
                child: body,
              ),
      ),
    );
  }
}
