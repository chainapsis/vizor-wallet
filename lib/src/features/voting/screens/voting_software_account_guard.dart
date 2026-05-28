import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../providers/account_provider.dart';

class VotingSoftwareAccountGuard extends ConsumerWidget {
  const VotingSoftwareAccountGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return account.when(
      loading: () => const _VotingGuardScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _VotingGuardScaffold(
        child: _VotingGuardMessage(
          title: "Couldn't load account",
          message: error.toString(),
        ),
      ),
      data: (_) => child,
    );
  }
}

class _VotingGuardScaffold extends StatelessWidget {
  const _VotingGuardScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AppRouteBackLink(),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _VotingGuardMessage extends StatelessWidget {
  const _VotingGuardMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
