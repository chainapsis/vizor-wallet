/// Shared chrome for the desktop Gift Card surfaces.
///
/// These are the frame pieces — panes, the wizard stepper, help rows, actions,
/// focus rings, the paste drop zone and the loading placeholder — that the step
/// views arrange but do not otherwise depend on. They are kept apart from
/// `payment_link_desktop_views.dart` so a step view can be read without
/// scrolling past 600 lines of chrome, and so the chrome can be reused by any
/// future desktop surface.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_floating_bar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_action.dart';
import 'payment_link_dashed_border_painter.dart';

class PaymentLinkPasteButton extends StatelessWidget {
  const PaymentLinkPasteButton({
    required this.label,
    this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('payment_link_redeem_paste_button'),
      onPressed: onPressed,
      size: AppButtonSize.mediumLarge,
      leading: const AppIcon(AppIcons.paste),
      child: Text(label),
    );
  }
}

class PaymentLinkDashedDropZone extends StatelessWidget {
  const PaymentLinkDashedDropZone({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const ValueKey('payment_link_redeem_drop_zone'),
      painter: PaymentLinkDashedBorderPainter(
        color: context.colors.border.medium,
        radius: AppRadii.large,
        strokeWidth: 3,
      ),
      child: SizedBox(width: 360, height: 225, child: Center(child: child)),
    );
  }
}

class PaymentLinkPane extends StatelessWidget {
  const PaymentLinkPane({
    required this.backLabel,
    required this.onBack,
    required this.child,
    this.actions,
    this.scrollController,
    this.showTopScrollFade = false,
    this.showBottomActionFade = true,
    super.key,
  });

  final String backLabel;
  final VoidCallback onBack;
  final Widget child;
  final Widget? actions;
  final ScrollController? scrollController;
  final bool showTopScrollFade;
  final bool showBottomActionFade;

  @override
  Widget build(BuildContext context) {
    return AppPaneFloatingBar(
      visible: actions != null,
      fadeVisible: showBottomActionFade,
      overlayWidth: 420,
      bar: actions ?? const SizedBox.shrink(),
      builder: (context, bottomReserve) => Stack(
        fit: StackFit.expand,
        children: [
          AppPaneScrollScaffold(
            controller: scrollController,
            toolbar: AppPaneToolbar(
              leading: AppBackLink(
                label: backLabel,
                minWidth: 60,
                onTap: onBack,
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.s,
              bottomReserve,
            ),
            child: child,
          ),
          if (showTopScrollFade)
            Positioned(
              top: AppPaneScrollScaffold.toolbarHeight,
              left: 0,
              right: 0,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: 420,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('payment_link_list_top_fade'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            context.colors.macosUtility.window,
                            context.colors.macosUtility.windowTransparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PaymentLinkWizardPane extends StatelessWidget {
  const PaymentLinkWizardPane({
    required this.title,
    required this.subtitle,
    required this.currentStep,
    required this.backLabel,
    required this.onBack,
    required this.child,
    required this.action,
    this.childSpacing = AppSpacing.lg + AppSpacing.md,
    this.onStepSelected,
    super.key,
  });

  final String title;
  final String subtitle;
  final int currentStep;
  final String backLabel;
  final VoidCallback onBack;
  final Widget child;
  final Widget action;
  final double childSpacing;
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    return PaymentLinkPane(
      backLabel: backLabel,
      onBack: onBack,
      actions: action,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 420,
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PaymentLinkWizardStepper(
                currentStep: currentStep,
                onStepSelected: onStepSelected,
              ),
              SizedBox(height: childSpacing),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentLinkWizardStepper extends StatelessWidget {
  const PaymentLinkWizardStepper({
    required this.currentStep,
    this.onStepSelected,
    super.key,
  });

  final int currentStep;
  final ValueChanged<int>? onStepSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Create', 'Add Message', 'Review'];
    return SizedBox(
      width: 365,
      height: 24,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              PaymentLinkWizardStep(
                index: index,
                label: labels[index],
                currentStep: currentStep,
                onTap: onStepSelected == null
                    ? null
                    : () => onStepSelected!(index),
              ),
              if (index != labels.length - 1) ...[
                const SizedBox(width: AppSpacing.s),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: context.colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.s),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentLinkWizardStep extends StatelessWidget {
  const PaymentLinkWizardStep({
    required this.index,
    required this.label,
    required this.currentStep,
    this.onTap,
    super.key,
  });

  final int index;
  final String label;
  final int currentStep;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final completed = index < currentStep;
    final active = index == currentStep;
    final color = active
        ? context.colors.text.primary
        : context.colors.text.muted;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active || completed
                ? context.colors.background.raised
                : context.colors.background.base,
          ),
          child: completed
              ? AppIcon(AppIcons.check, size: 14, color: color)
              : Text(
                  '${index + 1}',
                  style: AppTypography.labelMedium.copyWith(color: color),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelLarge.copyWith(color: color)),
      ],
    );
    if (onTap == null) return content;
    return PaymentLinkAction(
      onPressed: onTap,
      selected: active,
      builder: (context, hovered, focused) => PaymentLinkActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: content,
        ),
      ),
    );
  }
}

class PaymentLinkHelpStep extends StatelessWidget {
  const PaymentLinkHelpStep({
    required this.icon,
    required this.text,
    super.key,
  });

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: ValueKey('payment_link_help_icon_slot_$icon'),
          width: 32,
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Align(
              alignment: Alignment.topCenter,
              child: AppIcon(
                icon,
                size: AppIconSize.medium,
                color: context.colors.icon.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class PaymentLinkDashedStatusPill extends StatelessWidget {
  const PaymentLinkDashedStatusPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      enabled: false,
      child: CustomPaint(
        painter: PaymentLinkDashedBorderPainter(
          color: context.colors.border.medium,
          radius: AppRadii.full,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 185, minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.time,
                  size: 16,
                  color: context.colors.icon.muted,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentLinkLoadingCard extends StatefulWidget {
  const PaymentLinkLoadingCard({super.key});

  @override
  State<PaymentLinkLoadingCard> createState() => _PaymentLinkLoadingCardState();
}

class _PaymentLinkLoadingCardState extends State<PaymentLinkLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate == _motionEnabled) return;
    _motionEnabled = shouldAnimate;
    if (shouldAnimate) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cardRadius = BorderRadius.all(Radius.circular(AppRadii.large));
    final card = Container(
      key: const ValueKey('payment_link_loading_card'),
      width: 360,
      height: 225,
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: cardRadius,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            key: ValueKey('payment_link_loading_card_gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x0D141818),
                  Color(0x594D5252),
                  Color(0x0D141818),
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: 'Loading gift card',
      container: true,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Stack(
            children: [
              card,
              if (_motionEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _controller,
                      child: Transform.rotate(
                        angle: -0.18,
                        child: const SizedBox(
                          width: 76,
                          height: 320,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0x00FFFFFF),
                                  Color(0x20FFFFFF),
                                  Color(0x00FFFFFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      builder: (context, child) {
                        return Transform.translate(
                          key: const ValueKey('payment_link_loading_shimmer'),
                          offset: Offset(-110 + (590 * _controller.value), 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: child,
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentLinkTabAction extends StatelessWidget {
  const PaymentLinkTabAction({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.text.primary
        : context.colors.text.muted;
    return PaymentLinkAction(
      onPressed: onTap,
      selected: selected,
      role: SemanticsRole.tab,
      builder: (context, hovered, focused) => PaymentLinkActionFocusRing(
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentLinkTextAction extends StatelessWidget {
  const PaymentLinkTextAction({
    required this.label,
    this.onTap,
    this.leading,
    this.trailing,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    final color = active
        ? context.colors.text.secondary
        : context.colors.text.muted;
    return PaymentLinkAction(
      onPressed: active ? onTap : null,
      builder: (context, hovered, focused) => PaymentLinkActionFocusRing(
        key: ValueKey('payment_link_text_action_focus_ring_$label'),
        focused: focused,
        borderRadius: AppRadii.small,
        child: AnimatedOpacity(
          key: ValueKey('payment_link_text_action_hover_$label'),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          opacity: hovered ? 0.72 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  IconTheme(
                    data: IconThemeData(color: color, size: 16),
                    child: leading!,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(color: color),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentLinkActionFocusRing extends StatelessWidget {
  const PaymentLinkActionFocusRing({
    required this.focused,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final bool focused;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: focused
            ? Border.all(
                color: context.colors.state.focusRing,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      child: child,
    );
  }
}
