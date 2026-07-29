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
      navTitle: 'About',
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

class _MobileMigrationOptions extends ConsumerStatefulWidget {
  const _MobileMigrationOptions({required this.privateEnabled});

  final bool privateEnabled;

  @override
  ConsumerState<_MobileMigrationOptions> createState() =>
      _MobileMigrationOptionsState();
}

class _MobileMigrationOptionsState
    extends ConsumerState<_MobileMigrationOptions> {
  late _MobileMigrationOption _selectedOption;
  var _isContinuing = false;
  String? _continueError;

  @override
  void initState() {
    super.initState();
    _selectedOption = widget.privateEnabled
        ? _MobileMigrationOption.private
        : _MobileMigrationOption.immediate;
  }

  void _select(_MobileMigrationOption option) {
    // Continue commits to the selected option: it prepares that plan, saves a
    // draft, and routes on. Switching underneath that would apply one option's
    // work to the other's screen.
    if (_isContinuing) return;
    if (option == _MobileMigrationOption.private && !widget.privateEnabled) {
      return;
    }
    if (_selectedOption == option) return;
    setState(() => _selectedOption = option);
  }

  Future<void> _continue() async {
    if (_isContinuing) return;
    if (_selectedOption == _MobileMigrationOption.immediate) {
      context.go('/migration/fast/review');
      return;
    }

    setState(() {
      _isContinuing = true;
      _continueError = null;
    });
    IronwoodMigrationNotificationAuthorizationStatus authorization;
    try {
      authorization = await ref
          .read(ironwoodMigrationServiceProvider)
          .notificationAuthorizationStatus();
    } catch (_) {
      if (!mounted) return;
      // Permission status is fail-closed: if native status cannot be read,
      // show the explanation screen and keep background work disabled.
      context.go('/migration/private/notifications');
      return;
    }

    try {
      if (!mounted) return;
      if (!authorization.allowsBackgroundMigration) {
        context.go('/migration/private/notifications');
        return;
      }
      context.go('/migration/private/start');
    } catch (error) {
      debugPrint('Failed to open private migration preparation: $error');
      if (!mounted) return;
      setState(() {
        _continueError = "Couldn't open migration preparation. Try again.";
      });
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final privateSelected = _selectedOption == _MobileMigrationOption.private;
    final immediateSelected =
        _selectedOption == _MobileMigrationOption.immediate;
    return PopScope(
      // The in-flight step saves a migration draft and then routes on. Leaving
      // in the middle would strand that work on a screen the user has left.
      canPop: !_isContinuing,
      child: _MobileMigrationStepScaffold(
        onBack: _isContinuing
            ? () {}
            : () => context.go('/migration/how-it-works'),
        navTitle: 'How to Migrate',
        topGap: 91,
        childGap: 24,
        title: 'Choose How to Migrate',
        subtitle: widget.privateEnabled
            ? 'Choose between more privacy over time or a faster migration. '
                  'You can review the details before anything moves.'
            : 'Private migration is temporarily unavailable on Android. '
                  'Choose immediate to continue.',
        bottom: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_continueError != null) ...[
              Text(
                _continueError!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
            ],
            _MobileMigrationPrimaryButton(
              key: const ValueKey('mobile_ironwood_options_continue_button'),
              label: 'Continue',
              busy: _isContinuing,
              onPressed: _isContinuing ? null : _continue,
            ),
          ],
        ),
        child: Column(
          children: [
            _MobileMigrationOptionCard(
              key: const ValueKey('mobile_ironwood_private_option'),
              title: 'Private',
              body: widget.privateEnabled
                  ? 'Splits transactions into multiple parts to minimize '
                        'traceability, but takes longer.'
                  : 'Not available on Android.',
              selected: privateSelected,
              icon: _MigrationChoiceIcon.private,
              recommended: widget.privateEnabled,
              onTap: _isContinuing || !widget.privateEnabled
                  ? null
                  : () => _select(_MobileMigrationOption.private),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MobileMigrationOptionCard(
              key: const ValueKey('mobile_ironwood_immediate_option'),
              title: 'Immediate',
              body:
                  'Migrates your entire balance in one batch. '
                  'Fast, but less private.',
              selected: immediateSelected,
              icon: _MigrationChoiceIcon.immediate,
              onTap: _isContinuing
                  ? null
                  : () => _select(_MobileMigrationOption.immediate),
            ),
          ],
        ),
      ),
    );
  }
}
