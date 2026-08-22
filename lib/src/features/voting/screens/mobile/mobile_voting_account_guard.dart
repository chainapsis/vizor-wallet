import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart' show Scaffold, CircularProgressIndicator;

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';

/// Mobile counterpart of the desktop voting guard: holds the voting routes
/// behind account-state readiness. Hardware accounts pass through — Keystone
/// voting is supported on mobile via the same QR flow as desktop.
class MobileVotingAccountGuard extends ConsumerWidget {
  const MobileVotingAccountGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return account.when(
      loading: () => const _MobileVotingGuardScaffold(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _MobileVotingGuardScaffold(
        child: _MobileVotingGuardMessage(
          title: "Couldn't load account",
          message: error.toString(),
        ),
      ),
      data: (_) => child,
    );
  }
}

class _MobileVotingGuardScaffold extends StatelessWidget {
  const _MobileVotingGuardScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Vote',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go('/home');
              },
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileVotingGuardMessage extends StatelessWidget {
  const _MobileVotingGuardMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
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
    );
  }
}
