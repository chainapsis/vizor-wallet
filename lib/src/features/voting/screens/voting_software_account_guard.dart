import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingSoftwareAccountGuard extends ConsumerWidget {
  const VotingSoftwareAccountGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return account.when(
      loading: () => const _VotingGuardScaffold(child: VotingPaneLoading()),
      error: (error, _) => _VotingGuardScaffold(
        child: _VotingGuardMessage(
          title: AppLocalizations.of(context).votingAccountLoadError,
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
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: child,
              ),
            ),
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
