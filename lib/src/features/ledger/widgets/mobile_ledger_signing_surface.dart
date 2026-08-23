import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';

class MobileLedgerSigningSurface extends StatelessWidget {
  const MobileLedgerSigningSurface({
    required this.child,
    required this.onBack,
    required this.canLeave,
    this.title = 'Ledger',
    super.key,
  });

  final Widget child;
  final VoidCallback onBack;
  final bool canLeave;
  final String title;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canLeave) onBack();
      },
      child: Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.back(title: title, onBack: canLeave ? onBack : null),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Center(child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
