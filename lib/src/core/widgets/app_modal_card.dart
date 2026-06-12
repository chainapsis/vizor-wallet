import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';

const kAppModalCardWidth = 312.0;
const kAppModalButtonHeight = 36.0;
const kAppModalButtonMinWidth = 96.0;
const _kAppModalActionLabelMaxWidth = 156.0;

/// Shared floating modal card used by pane modals (accounts, settings, swap).
///
/// Pane modals render this card centered above an `AppPaneModalOverlay`
/// scrim. Width defaults to the design-system modal width (312) but can be
/// overridden for wider content such as asset pickers.
class AppModalCard extends StatelessWidget {
  const AppModalCard({
    required this.child,
    this.width = kAppModalCardWidth,
    this.bottomPadding = AppSpacing.md,
    super.key,
  });

  final Widget child;
  final double width;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: width,
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
        boxShadow: appModalShadow,
      ),
      child: child,
    );
  }
}

const appModalShadow = [
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
];

/// Cancel + primary action row at the bottom of an [AppModalCard].
class AppModalActions extends StatelessWidget {
  const AppModalActions({
    required this.onCancel,
    required this.actionLabel,
    required this.onAction,
    this.cancelLabel = 'Cancel',
    this.actionVariant = AppButtonVariant.primary,
    this.actionMinWidth = kAppModalButtonMinWidth,
    this.actionLeading,
    this.cancelKey = const ValueKey('modal_cancel_button'),
    this.actionKey = const ValueKey('modal_action_button'),
    super.key,
  });

  final VoidCallback? onCancel;
  final String cancelLabel;
  final String actionLabel;
  final VoidCallback? onAction;
  final AppButtonVariant actionVariant;
  final double actionMinWidth;
  final Widget? actionLeading;
  final Key cancelKey;
  final Key actionKey;

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
            // mediumLarge button padding is AppSpacing.s per side.
            final labelMaxWidth = math.max(
              0.0,
              math.min(
                _kAppModalActionLabelMaxWidth,
                buttonWidth -
                    AppSpacing.s * 2 -
                    AppSpacing.xxs * 2 -
                    leadingWidth -
                    AppSpacing.xxs,
              ),
            );

            return AppButton(
              key: key,
              onPressed: onPressed,
              variant: variant,
              // mediumLarge is the 36px Figma modal button set (Label M).
              size: AppButtonSize.mediumLarge,
              height: kAppModalButtonHeight,
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
          key: cancelKey,
          label: cancelLabel,
          onPressed: onCancel,
          variant: AppButtonVariant.ghost,
        ),
        const SizedBox(width: AppSpacing.s),
        buildButton(
          key: actionKey,
          label: actionLabel,
          onPressed: onAction,
          variant: actionVariant,
          leading: actionLeading,
        ),
      ],
    );
  }
}
