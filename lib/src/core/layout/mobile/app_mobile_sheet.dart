import 'package:flutter/material.dart' show showModalBottomSheet;
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
    backgroundColor: colors.background.ground,
    barrierColor: colors.background.neutralScrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.large)),
    ),
    builder: builder,
  );
}
