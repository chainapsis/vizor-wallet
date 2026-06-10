import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';

const kAccountModalButtonHeight = 36.0;
const kAccountModalButtonMinWidth = 96.0;
const _kAccountModalActionLabelMaxWidth = 156.0;

class AccountModalCard extends StatelessWidget {
  const AccountModalCard({
    required this.child,
    this.bottomPadding = AppSpacing.md,
    super.key,
  });

  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 312,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: accountModalShadow,
      ),
      child: child,
    );
  }
}

const accountModalShadow = [
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
];

class AccountModalActions extends StatelessWidget {
  const AccountModalActions({
    required this.onCancel,
    required this.actionLabel,
    required this.onAction,
    this.cancelLabel = 'Cancel',
    this.actionVariant = AppButtonVariant.primary,
    this.actionMinWidth = kAccountModalButtonMinWidth,
    this.actionLeading,
    super.key,
  });

  final VoidCallback? onCancel;
  final String cancelLabel;
  final String actionLabel;
  final VoidCallback? onAction;
  final AppButtonVariant actionVariant;
  final double actionMinWidth;
  final Widget? actionLeading;

  @override
  Widget build(BuildContext context) {
    Widget buildButton({
      required String label,
      required VoidCallback? onPressed,
      required AppButtonVariant variant,
      required Key key,
      Widget? leading,
    }) {
      return Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth = constraints.hasBoundedWidth
                ? math.max(actionMinWidth, constraints.maxWidth)
                : actionMinWidth;
            final leadingWidth = leading == null ? 0.0 : 20.0;
            final labelMaxWidth = math.max(
              0.0,
              math.min(
                _kAccountModalActionLabelMaxWidth,
                buttonWidth -
                    AppSpacing.xs * 2 -
                    AppSpacing.xxs * 2 -
                    leadingWidth -
                    AppSpacing.xxs,
              ),
            );

            return AppButton(
              key: key,
              onPressed: onPressed,
              variant: variant,
              size: AppButtonSize.medium,
              height: kAccountModalButtonHeight,
              minWidth: buttonWidth,
              leading: leading,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: labelMaxWidth),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),
      );
    }

    return Row(
      children: [
        buildButton(
          key: const ValueKey('account_modal_cancel_button'),
          label: cancelLabel,
          onPressed: onCancel,
          variant: AppButtonVariant.ghost,
        ),
        const SizedBox(width: AppSpacing.s),
        buildButton(
          key: const ValueKey('account_modal_action_button'),
          label: actionLabel,
          onPressed: onAction,
          variant: actionVariant,
          leading: actionLeading,
        ),
      ],
    );
  }
}
