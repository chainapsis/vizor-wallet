import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/multisig_account_material_provider.dart';
import '../../../providers/multisig_pending_session_provider.dart';
import '../widgets/multisig_onboarding_flow.dart';

class MultisigConnectScreen extends ConsumerWidget {
  const MultisigConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summariesAsync = ref.watch(multisigPendingSessionSummariesProvider);
    final materials = ref.watch(multisigAccountMaterialsProvider).value;
    final materializedSessionStorageIds = materials == null
        ? const <String>{}
        : materializedMultisigSessionStorageIds(materials);

    return MultisigOnboardingTrailingPane(
      backTarget: const OnboardingBackTarget.route(
        label: 'Welcome',
        routePath: '/welcome',
      ),
      bodyPadding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const MultisigOnboardingTitle(
                  title: 'Connect multisig',
                  subtitle: 'Continue a setup or start a new session.',
                  iconName: AppIcons.users,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('multisig_connect_create_button'),
                        onPressed: () => context.go('/multisig/create'),
                        leading: const AppIcon(AppIcons.addNew),
                        child: const Text('Create session'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('multisig_connect_join_button'),
                        onPressed: () => context.go('/multisig/join'),
                        variant: AppButtonVariant.secondary,
                        leading: const AppIcon(AppIcons.link),
                        child: const Text('Join session'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                summariesAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => _InlineError(message: error.toString()),
                  data: (summaries) {
                    final pendingSummaries = summaries
                        .where(
                          (summary) => multisigSessionSummaryNeedsLocalSetup(
                            summary,
                            materializedSessionStorageIds,
                          ),
                        )
                        .toList(growable: false);

                    if (pendingSummaries.isEmpty) {
                      return const _EmptyPendingSessions();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Pending sessions',
                          style: AppTypography.labelLarge.copyWith(
                            color: context.colors.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        for (var i = 0; i < pendingSummaries.length; i++) ...[
                          _PendingSessionTile(summary: pendingSummaries[i]),
                          if (i != pendingSummaries.length - 1)
                            const SizedBox(height: AppSpacing.xs),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingSessionTile extends StatelessWidget {
  const _PendingSessionTile({required this.summary});

  final MultisigPendingSessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(
          '/multisig/session/${Uri.encodeComponent(summary.storageId)}',
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.raised,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
            border: Border.all(color: colors.border.subtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.state.selectedOpacity,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: AppIcon(
                        AppIcons.users,
                        size: 20,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary.displayLabel,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${summary.shortSessionId} · ${_statusLabel(summary.state)}',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 18,
                  color: colors.icon.regular,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(String state) => switch (state) {
    'collecting' => 'Collecting',
    'locked' => 'Locked',
    'ready' => 'Ready',
    _ => state,
  };
}

class _EmptyPendingSessions extends StatelessWidget {
  const _EmptyPendingSessions();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          'No pending multisig sessions',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.destructive,
      ),
    );
  }
}
