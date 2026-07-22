part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationIntro extends StatelessWidget {
  const _MobileMigrationIntro({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Transform.translate(
              offset: const Offset(0, 20),
              child: MobileTopNav.back(
                title: 'Zcash Network Update',
                titleStyle: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
                onBack: () => context.go('/home'),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  30,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 172,
                      child: _MobilePoolMigrationHero(data: data),
                    ),
                    const SizedBox(height: 46),
                    SvgPicture.asset(
                      'assets/illustrations/ironwood_wordmark.svg',
                      key: const ValueKey('mobile_ironwood_wordmark'),
                      width: 273,
                      height: 37,
                      colorFilter: ColorFilter.mode(
                        colors.text.accent,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'A new shielded pool for Zcash.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Your ${data.amountText} ZEC is currently in Orchard. '
                      'To keep using these funds for shielded payments, '
                      "you'll need to move them to Ironwood. You'll review "
                      'the migration plan before any funds move.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.muted,
                        height: 24 / 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    height: 50,
                    onPressed: () => _openIronwoodReleaseNotes(),
                    leading: const AppIcon(AppIcons.link, size: 18),
                    child: const Text('Official release note'),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    key: const ValueKey(
                      'mobile_ironwood_intro_continue_button',
                    ),
                    expand: true,
                    height: 50,
                    onPressed: () => context.go('/migration/how-it-works'),
                    child: const Text('Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationHowItWorks extends StatelessWidget {
  const _MobileMigrationHowItWorks();

  @override
  Widget build(BuildContext context) {
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/intro'),
      stepLabel: 'Step 1/3',
      topGap: 31,
      childGap: 32,
      title: 'How Migration Works',
      bottom: _MobileMigrationPrimaryButton(
        key: const ValueKey('mobile_ironwood_steps_continue_button'),
        label: 'Continue',
        onPressed: () => context.go('/migration/options'),
      ),
      child: const _MobileMigrationProcessCard(),
    );
  }
}

enum _MobileMigrationOption { private, immediate }

class _MobileMigrationOptions extends StatefulWidget {
  const _MobileMigrationOptions();

  @override
  State<_MobileMigrationOptions> createState() =>
      _MobileMigrationOptionsState();
}

class _MobileMigrationOptionsState extends State<_MobileMigrationOptions> {
  var _selectedOption = _MobileMigrationOption.private;

  void _select(_MobileMigrationOption option) {
    if (_selectedOption == option) return;
    setState(() => _selectedOption = option);
  }

  @override
  Widget build(BuildContext context) {
    final privateSelected = _selectedOption == _MobileMigrationOption.private;
    final immediateSelected =
        _selectedOption == _MobileMigrationOption.immediate;
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/how-it-works'),
      stepLabel: 'Step 2/3',
      topGap: 91,
      childGap: 24,
      title: 'Choose How to Migrate',
      subtitle:
          'Choose between more privacy over time or a faster migration. '
          'You can review the details before anything moves.',
      bottom: _MobileMigrationPrimaryButton(
        key: const ValueKey('mobile_ironwood_options_continue_button'),
        label: 'Continue',
        onPressed: () => context.go(
          privateSelected
              ? '/migration/private/review'
              : '/migration/fast/review',
        ),
      ),
      child: Column(
        children: [
          _MobileMigrationOptionCard(
            key: const ValueKey('mobile_ironwood_private_option'),
            title: 'Private',
            body: 'Sends independent parts over time',
            selected: privateSelected,
            icon: _MigrationChoiceIcon.private,
            recommended: true,
            onTap: () => _select(_MobileMigrationOption.private),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobileMigrationOptionCard(
            key: const ValueKey('mobile_ironwood_immediate_option'),
            title: 'Immediate',
            body: 'Sends now in one step.',
            selected: immediateSelected,
            icon: _MigrationChoiceIcon.immediate,
            onTap: () => _select(_MobileMigrationOption.immediate),
          ),
        ],
      ),
    );
  }
}
