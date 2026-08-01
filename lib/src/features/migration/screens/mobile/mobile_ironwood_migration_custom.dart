part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationCustom extends StatelessWidget {
  const _MobileMigrationCustom({required this.data, this.previewPlan});

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;

  @override
  Widget build(BuildContext context) {
    return _MobileIronwoodMigrationBackScope(
      onFallback: () => context.go('/migration/options'),
      child: Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform.translate(
                offset: const Offset(0, 20),
                child: MobileTopNav.back(
                  title: 'Migration Options',
                  titleStyle: AppTypography.headlineSmall,
                  onBack: () => context.go('/migration/options'),
                ),
              ),
              Expanded(
                child: IronwoodMigrationCustomContent(
                  data: data,
                  previewPlan: previewPlan,
                  mobileLayout: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
