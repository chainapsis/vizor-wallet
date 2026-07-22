part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationStatusScaffold extends ConsumerWidget {
  const _MobileMigrationStatusScaffold({
    required this.data,
    required this.child,
    this.showAccountNav = true,
    this.contentPadding = const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      44,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    super.key,
  });

  final IronwoodMigrationFlowData data;
  final Widget child;
  final bool showAccountNav;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final syncLabel = SyncStatusLabel.from(sync).label;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            if (showAccountNav) ...[
              MobileTopNav.account(
                accountName: data.accountName,
                syncLabel: syncLabel,
                avatar: AppProfilePicture(
                  profilePictureId: data.profilePictureId,
                  size: AppProfilePictureSize.navLarge,
                ),
              ),
            ],
            Expanded(
              child: Padding(padding: contentPadding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatusCard extends StatelessWidget {
  const _MobileStatusCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
          child: child,
        ),
      ),
    );
  }
}

class _MobileMigrationRecoveryCard extends StatelessWidget {
  const _MobileMigrationRecoveryCard({
    required this.sending,
    required this.schedulingBackground,
    required this.backgroundRetryScheduled,
    required this.supportsBackgroundRetry,
    required this.error,
    required this.onSendOne,
    required this.onRetryInBackground,
  });

  final bool sending;
  final bool schedulingBackground;
  final bool backgroundRetryScheduled;
  final bool supportsBackgroundRetry;
  final String? error;
  final VoidCallback onSendOne;
  final VoidCallback onRetryInBackground;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = sending || schedulingBackground;
    return _MobileStatusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(AppIcons.warning, size: 20, color: colors.icon.warning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Transfer ready',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            supportsBackgroundRetry
                ? 'A scheduled transfer is still waiting. Send one now, or '
                      'let Vizor try again in the background.'
                : 'A scheduled transfer is still waiting. Send the next '
                      'transfer now to continue.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sending now can link this transfer more closely to your current '
            'app activity.',
            style: AppTypography.labelMedium.copyWith(color: colors.text.muted),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              error!,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const ValueKey('mobile_ironwood_send_one_due_button'),
            expand: true,
            constrainContent: true,
            height: 44,
            onPressed: busy ? null : onSendOne,
            child: Text(
              sending ? 'Sending...' : 'Send one now',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (supportsBackgroundRetry) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              key: const ValueKey('mobile_ironwood_retry_background_button'),
              variant: AppButtonVariant.secondary,
              expand: true,
              constrainContent: true,
              height: 44,
              onPressed: busy ? null : onRetryInBackground,
              child: Text(
                schedulingBackground
                    ? 'Scheduling...'
                    : backgroundRetryScheduled
                    ? 'Background retry scheduled'
                    : 'Retry in background',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
