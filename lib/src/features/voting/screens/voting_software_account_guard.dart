import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
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
      data: (state) {
        if (state.activeAccount?.isHardware == true) {
          return const _VotingGuardScaffold(child: _HardwareVotingComingSoon());
        }
        return child;
      },
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

class _HardwareVotingComingSoon extends StatelessWidget {
  const _HardwareVotingComingSoon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _VotingGuardMessage(
        title: 'Hardware Accounts Coming Soon',
        message:
            'Coinholder polling for Keystone and other hardware accounts is coming soon. Switch to a software account to view and submit polls.',
        action: AppButton(
          onPressed: () => context.go('/accounts'),
          variant: AppButtonVariant.primary,
          minWidth: 220,
          child: const Text('Switch Account'),
        ),
      ),
    );
  }
}

class _VotingGuardMessage extends StatelessWidget {
  const _VotingGuardMessage({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

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
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
