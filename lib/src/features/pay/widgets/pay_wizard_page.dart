import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_floating_bar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import 'pay_wizard_stepper.dart';

/// Shared desktop Pay page anatomy from the Figma PAY flow.
///
/// The 420px content area owns a 396px inner column, a 73px title/stepper
/// block, a 32px section gap, and an optional bottom-pinned action bar. Both
/// production and Widgetbook use this widget so preview parity cannot drift
/// from the live page shell.
class PayWizardPage extends StatelessWidget {
  const PayWizardPage({
    required this.title,
    required this.currentIndex,
    required this.backLabel,
    required this.onBack,
    required this.child,
    this.headingTrailing,
    this.actions,
    this.onStepSelected,
    this.scrollController,
    super.key,
  });

  static const double contentWidth = 420;
  static const double innerWidth = 396;

  final String title;
  final int currentIndex;
  final String backLabel;
  final FutureOr<void> Function() onBack;
  final Widget child;
  final Widget? headingTrailing;
  final Widget? actions;
  final ValueChanged<int>? onStepSelected;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    return AppPaneFloatingBar(
      visible: actions != null,
      overlayWidth: contentWidth,
      // The Pay Figma footer leaves 24px below its 44px CTA. The shared
      // floating bar already supplies 16px, so this finishes the exact inset.
      bar: actions == null
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('pay_wizard_floating_actions'),
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: actions,
            ),
      builder: (context, bottomReserve) => AppPaneScrollScaffold(
        controller: scrollController,
        toolbar: AppPaneToolbar(
          leading: AppBackLink(
            key: const ValueKey('pay_wizard_back_link'),
            label: backLabel,
            minWidth: 60,
            onTap: onBack,
          ),
        ),
        padding: EdgeInsets.only(top: AppSpacing.sm, bottom: bottomReserve),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Column(
                key: const ValueKey('pay_wizard_content_column'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 33,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          title,
                          key: const ValueKey('pay_wizard_title'),
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySmall.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                        if (headingTrailing != null)
                          Positioned(right: 0, child: headingTrailing!),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PayWizardStepper(
                    currentIndex: currentIndex,
                    onStepSelected: onStepSelected,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
