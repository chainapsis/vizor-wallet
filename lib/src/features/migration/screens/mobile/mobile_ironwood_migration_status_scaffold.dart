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
