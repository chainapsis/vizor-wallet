// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_toast.dart';

Widget buildToastUseCase(BuildContext context) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          AppToast(message: 'Address Copied'),
          SizedBox(height: AppSpacing.sm),
          AppToast(message: 'Transaction Hash Copied'),
        ],
      ),
    ),
  );
}
