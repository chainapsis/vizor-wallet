part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationLoadingScreen extends StatelessWidget {
  const _MobileMigrationLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background.window,
      body: const SafeArea(
        child: Column(
          children: [
            MobileTopNav.steps(
              progress: _migrationProgress,
              showBackButton: false,
            ),
            Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationRedirectTo extends StatefulWidget {
  const _MobileMigrationRedirectTo(this.location);

  final String location;

  @override
  State<_MobileMigrationRedirectTo> createState() =>
      _MobileMigrationRedirectToState();
}

class _MobileMigrationRedirectToState
    extends State<_MobileMigrationRedirectTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const _MobileMigrationLoadingScreen();
}

class _MobileMigrationRedirectHome extends StatefulWidget {
  const _MobileMigrationRedirectHome();

  @override
  State<_MobileMigrationRedirectHome> createState() =>
      _MobileMigrationRedirectHomeState();
}

class _MobileMigrationRedirectHomeState
    extends State<_MobileMigrationRedirectHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) => const _MobileMigrationLoadingScreen();
}

String _compactZec(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(zatoshi).balance.amountText;
}

String _migrationDisplayZec(BigInt zatoshi) {
  final amount = ZecAmount.fromZatoshi(zatoshi)
      .compactBalancePretty(minFractionDigits: 0, maxFractionDigits: 4)
      .amountText;
  final separator = amount.indexOf('.');
  final whole = separator < 0 ? amount : amount.substring(0, separator);
  final fraction = separator < 0 ? '' : amount.substring(separator);
  return '${formatGroupedInteger(int.parse(whole))}$fraction';
}

String _migrationArrivalLabel(rust_sync.OrchardMigrationPrivatePlan plan) {
  return migrationPlanCompletionTimingLabel(plan);
}

Future<void> _openIronwoodReleaseNotes() async {
  await launchUrl(
    Uri.parse(kIronwoodMigrationReleaseNotesUrl),
    mode: LaunchMode.externalApplication,
  );
}
