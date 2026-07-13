import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Wizard progress row — Figma `1 Amount > 2 Recipient > 3 Review`
/// (PAY wip 5407:149737). Completed steps render a checkmark chip and are
/// tappable to navigate back; the active step renders a filled number chip.
class PayWizardStepper extends StatelessWidget {
  const PayWizardStepper({
    required this.currentIndex,
    this.onStepSelected,
    super.key,
  });

  static const labels = ['Amount', 'Recipient', 'Review'];

  /// 0-based index of the active step.
  final int currentIndex;

  /// Called with the tapped step index; only completed (earlier) steps are
  /// tappable.
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) {
        children
          ..add(const SizedBox(width: AppSpacing.xs))
          ..add(
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: colors.icon.muted,
                ),
              ),
            ),
          )
          ..add(const SizedBox(width: AppSpacing.xs));
      }
      children.add(
        _PayWizardStepChip(
          index: i,
          label: labels[i],
          state: i < currentIndex
              ? _PayWizardStepState.completed
              : i == currentIndex
              ? _PayWizardStepState.active
              : _PayWizardStepState.upcoming,
          onTap: i < currentIndex && onStepSelected != null
              ? () => onStepSelected!(i)
              : null,
        ),
      );
    }
    // scaleDown keeps the row intact on narrow panes (and under the wide
    // Ahem test font) instead of overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        key: const ValueKey('pay_wizard_stepper'),
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

enum _PayWizardStepState { completed, active, upcoming }

class _PayWizardStepChip extends StatelessWidget {
  const _PayWizardStepChip({
    required this.index,
    required this.label,
    required this.state,
    this.onTap,
  });

  final int index;
  final String label;
  final _PayWizardStepState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = state == _PayWizardStepState.active;
    final row = Opacity(
      opacity: active ? 1 : 0.5,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: ValueKey('pay_wizard_step_icon_$index'),
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.raised,
              shape: BoxShape.circle,
            ),
            child: state == _PayWizardStepState.completed
                ? AppIcon(AppIcons.check, size: 16, color: colors.icon.accent)
                : Text(
                    '${index + 1}',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            key: ValueKey('pay_wizard_step_label_$index'),
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('pay_wizard_step_back_$index'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
