import 'package:flutter/material.dart';

import '../../../core/widgets/app_icon.dart';

const votingAutoAdvanceDelay = Duration(milliseconds: 600);

/// A single countdown before advancing, rather than an indeterminate loader.
class VotingAutoAdvanceIndicator extends StatelessWidget {
  const VotingAutoAdvanceIndicator({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Moving to the next unanswered question',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reducedMotion ? Duration.zero : votingAutoAdvanceDelay,
            builder: (context, progress, child) => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 1.5,
                    color: color,
                    backgroundColor: color.withValues(alpha: .16),
                  ),
                ),
                child!,
              ],
            ),
            child: AppIcon(AppIcons.arrowDownward, size: 12, color: color),
          ),
        ),
      ),
    );
  }
}
