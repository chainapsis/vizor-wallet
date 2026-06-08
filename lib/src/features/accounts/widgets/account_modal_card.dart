import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';

const kAccountModalButtonHeight = 36.0;
const kAccountModalButtonMinWidth = 96.0;

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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(
          color: colors.border.subtleOpacity,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
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
