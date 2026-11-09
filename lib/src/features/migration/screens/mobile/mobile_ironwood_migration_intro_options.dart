part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationIntro extends StatelessWidget {
  const _MobileMigrationIntro({
    required this.data,
    required this.privacyModeEnabled,
  });

  final IronwoodMigrationFlowData data;
  final bool privacyModeEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileIronwoodMigrationBackScope(
      onFallback: () => context.go('/home'),
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Transform.translate(
                offset: const Offset(0, 20),
                child: MobileTopNav.back(
                  title: context.l10n.migrationMobileIntroTitle,
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
                        child: _MobilePoolMigrationHero(
                          data: data,
                          privacyModeEnabled: privacyModeEnabled,
                        ),
                      ),
                      const SizedBox(height: 46),
                      SvgPicture.asset(
                        'assets/illustrations/ironwood_wordmark.svg', // l10n-ignore: asset path
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
                        context.l10n.migrationIntroTagline,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.l10n.migrationMobileIntroBody(
                          hideIfPrivacyMode(
                            data.amountText,
                            privacyModeEnabled: privacyModeEnabled,
                          ),
                        ),
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
                      child: Text(context.l10n.migrationMobileIntroReleaseNote),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    AppButton(
                      key: const ValueKey(
                        'mobile_ironwood_intro_continue_button',
                      ),
                      expand: true,
                      height: 50,
                      onPressed: () => context.go('/migration/how-it-works'),
                      child: Text(context.l10n.onboardingNext),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationHowItWorks extends StatelessWidget {
  const _MobileMigrationHowItWorks();

  @override
  Widget build(BuildContext context) {
    return _MobileIronwoodMigrationBackScope(
      onFallback: () => context.go('/migration/intro'),
      child: _MobileMigrationStepScaffold(
        onBack: () => context.go('/migration/intro'),
        navTitle: context.l10n.migrationMobileHowItWorksNavTitle,
        topGap: 31,
        childGap: 32,
        title: context.l10n.migrationBackHowItWorks,
        bottom: _MobileMigrationPrimaryButton(
          key: const ValueKey('mobile_ironwood_steps_continue_button'),
          label: context.l10n.commonContinue,
          onPressed: () => context.go('/migration/options'),
        ),
        child: const _MobileMigrationProcessCard(),
      ),
    );
  }
}

enum _MobileMigrationOption { private, immediate }

class _MobileMigrationOptions extends ConsumerStatefulWidget {
  const _MobileMigrationOptions({
    required this.data,
    required this.privateEnabled,
    required this.privacyModeEnabled,
    this.privateUnavailableForLedger = false,
    this.movingRest = false,
  });

  final IronwoodMigrationFlowData data;
  final bool privateEnabled;
  final bool privacyModeEnabled;
  final bool privateUnavailableForLedger;
  final bool movingRest;

  @override
  ConsumerState<_MobileMigrationOptions> createState() =>
      _MobileMigrationOptionsState();
}

class _MobileMigrationOptionsState
    extends ConsumerState<_MobileMigrationOptions> {
  late _MobileMigrationOption _selectedOption;
  var _isContinuing = false;
  var _continueFailed = false;

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
      _continueFailed = false;
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
        _continueFailed = true;
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
    final tipHeight = ref.watch(
      syncProvider.select((sync) => sync.asData?.value.chainTipHeight),
    );
    final immediateEstimate = ironwoodImmediateMigrationCompletionEstimate(
      context.l10n,
      ref.watch(blockSpacingProvider).fromTip(tipHeight ?? 0),
    );
    final backLocation = widget.movingRest
        ? '/migration/private/status'
        : '/migration/how-it-works';
    final l10n = context.l10n;
    final restAmount = hideIfPrivacyMode(
      ZecAmount.fromZatoshi(
        widget.data.amountZatoshi,
      ).compactBalance.amountText,
      privacyModeEnabled: widget.privacyModeEnabled,
    );
    return _MobileIronwoodMigrationBackScope(
      // The in-flight step saves a migration draft and then routes on. Leaving
      // in the middle would strand that work on a screen the user has left.
      onFallback: _isContinuing ? null : () => context.go(backLocation),
      child: _MobileMigrationStepScaffold(
        onBack: _isContinuing ? () {} : () => context.go(backLocation),
        navTitle: l10n.migrationMobileOptionsNavTitle,
        topGap: 91,
        childGap: 24,
        title: widget.movingRest
            ? l10n.migrationMobileOptionsTitleRest
            : l10n.migrationMobileOptionsTitle,
        subtitle: widget.privateEnabled
            ? widget.movingRest
                  ? l10n.migrationOptionsBodyMoveRest(restAmount)
                  : l10n.migrationOptionsBody
            : widget.privateUnavailableForLedger
            ? widget.movingRest
                  ? l10n.migrationMobileOptionsSubtitleLedgerRest(restAmount)
                  : l10n.migrationMobileOptionsSubtitleLedger
            : widget.movingRest
            ? l10n.migrationMobileOptionsSubtitleAndroidRest(restAmount)
            : l10n.migrationMobileOptionsSubtitleAndroid,
        bottom: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_continueFailed) ...[
              Text(
                l10n.migrationMobileOptionsOpenError,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
            ],
            _MobileMigrationPrimaryButton(
              key: const ValueKey('mobile_ironwood_options_continue_button'),
              label: l10n.commonContinue,
              busy: _isContinuing,
              onPressed: _isContinuing ? null : _continue,
            ),
          ],
        ),
        child: Column(
          children: [
            _MobileMigrationOptionCard(
              key: const ValueKey('mobile_ironwood_private_option'),
              title: l10n.migrationOptionPrivate,
              body: widget.privateEnabled
                  ? l10n.migrationMobileOptionPrivateBody
                  : widget.privateUnavailableForLedger
                  ? l10n.migrationOptionPrivateLedger
                  : l10n.migrationMobileOptionPrivateUnavailableAndroid,
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
              title: l10n.migrationOptionImmediate,
              body: l10n.migrationMobileOptionImmediateBody(immediateEstimate),
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
