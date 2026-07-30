import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

class IronwoodMigrationAnalyzingProgressBar extends StatefulWidget {
  const IronwoodMigrationAnalyzingProgressBar({super.key});

  @override
  State<IronwoodMigrationAnalyzingProgressBar> createState() =>
      _IronwoodMigrationAnalyzingProgressBarState();
}

class _IronwoodMigrationAnalyzingProgressBarState
    extends State<IronwoodMigrationAnalyzingProgressBar>
    with SingleTickerProviderStateMixin {
  static const _barWidth = 196.0;
  static const _segmentWidth = 72.0;
  static const _initialProgress = _segmentWidth / (_barWidth + _segmentWidth);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _controller.value = _initialProgress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = _initialProgress;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('ironwood_migration_analyzing_progress_bar'),
      width: _barWidth,
      height: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.overlay),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _shouldAnimate
                  ? _controller.value
                  : _initialProgress;
              final left =
                  -_segmentWidth + progress * (_barWidth + _segmentWidth);
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: _segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
