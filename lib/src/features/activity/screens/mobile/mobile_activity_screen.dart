import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';

/// Phase 0b placeholder for the mobile activity tab.
class MobileActivityScreen extends StatelessWidget {
  const MobileActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const MobileTopNav.back(title: 'Activity'),
          Expanded(
            child: Center(
              child: Text(
                'Activity',
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
