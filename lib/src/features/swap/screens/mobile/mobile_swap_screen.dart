import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';

/// Phase 0b placeholder for the mobile swap tab.
class MobileSwapScreen extends StatelessWidget {
  const MobileSwapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const MobileTopNav.back(title: 'Swap'),
          Expanded(
            child: Center(
              child: Text(
                'Swap',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
