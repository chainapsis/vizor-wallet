import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';

/// Phase 0b placeholder for the mobile home tab — proves the tab shell
/// and the push navigation into the send/receive flows. Replaced by the
/// real mobile home screen in the next phase.
class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const MobileTopNav.account(accountName: 'Account'),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Home',
                    style: AppTypography.headlineMedium.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    onPressed: () => context.push('/send'),
                    child: const Text('Send'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push('/receive'),
                    child: const Text('Receive'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
