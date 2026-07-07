import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal_card.dart';

const kAccountModalButtonHeight = kAppModalButtonHeight;
const kAccountModalButtonMinWidth = kAppModalButtonMinWidth;

const accountModalShadow = appModalShadow;

/// Accounts/settings-facing alias for the shared [AppModalCard].
///
/// Kept so existing callers and tests (which assert on the
/// `account_modal_*_button` keys) stay stable; new features should use
/// [AppModalCard] / [AppModalActions] from `core/widgets` directly.
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
    return AppModalCard(bottomPadding: bottomPadding, child: child);
  }
}

class AccountModalActions extends StatelessWidget {
  const AccountModalActions({
    required this.onCancel,
    required this.actionLabel,
    required this.onAction,
    this.cancelLabel,
    this.actionVariant = AppButtonVariant.primary,
    this.actionMinWidth = kAccountModalButtonMinWidth,
    this.actionLeading,
    super.key,
  });

  final VoidCallback? onCancel;

  /// Defaults to the localized "Cancel" when null.
  final String? cancelLabel;
  final String actionLabel;
  final VoidCallback? onAction;
  final AppButtonVariant actionVariant;
  final double actionMinWidth;
  final Widget? actionLeading;

  @override
  Widget build(BuildContext context) {
    return AppModalActions(
      onCancel: onCancel,
      cancelLabel: cancelLabel,
      actionLabel: actionLabel,
      onAction: onAction,
      actionVariant: actionVariant,
      actionMinWidth: actionMinWidth,
      actionLeading: actionLeading,
      cancelKey: const ValueKey('account_modal_cancel_button'),
      actionKey: const ValueKey('account_modal_action_button'),
    );
  }
}
