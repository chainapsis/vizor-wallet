import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';

/// Phase 0b placeholder for the mobile send flow entry — pushed over
/// the tab shell as a CupertinoPage so iOS edge-swipe back works.
class MobileSendScreen extends StatelessWidget {
  const MobileSendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: 'Send', onBack: () => context.pop()),
            Expanded(
              child: Center(
                child: Text(
                  'Send flow',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
