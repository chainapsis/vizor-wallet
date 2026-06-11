import 'package:flutter/material.dart'
    show Material, showGeneralDialog, showModalBottomSheet;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Shows a mobile modal bottom sheet styled after the Figma mobile
/// modals (e.g. `Accounts Modal`, node 4411:91628): rounded top corners
/// on a ground surface over a scrim barrier.
///
/// This is the mobile counterpart of the desktop pane modal overlay —
/// account switching, pickers, and confirmations present as sheets on
/// mobile.
Future<T?> showAppMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  final colors = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    isScrollControlled: true,
    useSafeArea: true,
    // Root navigator so the sheet and its scrim cover the floating tab
    // bar (the shell's bottomNavigationBar sits outside the branch
    // navigators) — the Figma modals always overlay the nav.
    useRootNavigator: true,
    backgroundColor: colors.background.ground,
    barrierColor: colors.background.neutralScrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.large)),
    ),
    builder: builder,
  );
}

/// Shows a floating rounded card inset from the screen edges and pinned
/// toward the top — the Figma `Add Memo` modal shape, which leaves the
/// lower half free for the software keyboard.
Future<T?> showAppMobileFloatingCard<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  final colors = context.colors;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: isDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: colors.background.neutralScrim,
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (_, animation, _, child) =>
        Opacity(opacity: animation.value, child: child),
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          // Material ancestor: text fields inside the card require one
          // (the bottom-sheet variant gets it from showModalBottomSheet).
          child: Material(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.large),
            child: builder(dialogContext),
          ),
        ),
      ),
    ),
  );
}
