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
  const _MobileMigrationOptions({required this.immediateEnabled});

  final bool immediateEnabled;

  @override
  ConsumerState<_MobileMigrationOptions> createState() =>
      _MobileMigrationOptionsState();
}

class _MobileMigrationOptionsState
    extends ConsumerState<_MobileMigrationOptions> {
  var _selectedOption = _MobileMigrationOption.private;
  var _isContinuing = false;
  String? _continueError;

  void _select(_MobileMigrationOption option) {
    // Continue commits to the selected option: it prepares that plan, saves a
    // draft, and routes on. Switching underneath that would apply one option's
    // work to the other's screen.
    if (_isContinuing) return;
    if (option == _MobileMigrationOption.immediate &&
        !widget.immediateEnabled) {
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
    rust_sync.OrchardMigrationPrivatePlan? plan;
    String? accountUuid;
    try {
      plan = await ref.read(ironwoodMigrationPrivatePlanProvider.future);
      if (!mounted) return;
      if (plan == null) {
        throw StateError('Migration plan is unavailable.');
      }
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      if (accountState.activeAccount?.isHardware ?? false) {
        if (!_keystoneTwoRoundPlanSupported(plan)) {
          throw StateError(
            'This migration needs more transactions than one Keystone '
            'signing request supports.',
          );
        }
      }
    } catch (error) {
      debugPrint('Failed to prepare private migration choice: $error');
      if (!mounted) return;
      setState(() {
        // The lock disables back, both option cards and Continue, so any exit
        // that leaves the user on this screen has to release it. Keeping it
        // held here strands them on an error they cannot retry or leave.
        _isContinuing = false;
        _continueError = "Couldn't prepare the migration plan. Try again.";
      });
      return;
    }

    IronwoodMigrationNotificationAuthorizationStatus authorization;
    try {
      authorization = await ref
          .read(ironwoodMigrationServiceProvider)
          .notificationAuthorizationStatus();
    } catch (_) {
      if (!mounted) return;
      // Permission status is fail-closed: if native status cannot be read,
      // show the explanation screen and keep background work disabled.
      context.go('/migration/private/notifications', extra: plan);
      return;
    }

    var draftSaved = false;
    try {
      if (!mounted) return;
      if (!authorization.allowsBackgroundMigration) {
        context.go('/migration/private/notifications', extra: plan);
        return;
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .savePrivateMigrationDraft(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      draftSaved = true;
      if (!mounted) return;
      await _refreshPrivateMigrationDraftPresentation(ref);
      if (!mounted) return;
      final continuation = await _continuePrivateMigrationAfterNotificationGate(
        ref,
        plan,
      );
      if (!mounted) return;
      _openPrivateMigrationDestination(context, continuation, plan);
    } catch (error) {
      debugPrint('Failed to activate direct-note migration: $error');
      if (!mounted) return;
      if (draftSaved || await _hasDurablePrivateMigrationRun(ref)) {
        if (!mounted) return;
        context.go(
          '/migration/private/status',
          extra: MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
        );
        return;
      }
      setState(() {
        _continueError = "Couldn't start the migration. Try again.";
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
        subtitle:
            'Choose between more privacy over time or a faster migration. '
            'You can review the details before anything moves.',
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
              body:
                  'Splits transactions into multiple parts to minimize '
                  'traceability, but takes longer.',
              selected: privateSelected,
              icon: _MigrationChoiceIcon.private,
              recommended: true,
              onTap: _isContinuing
                  ? null
                  : () => _select(_MobileMigrationOption.private),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MobileMigrationOptionCard(
              key: const ValueKey('mobile_ironwood_immediate_option'),
              title: 'Immediate',
              body: widget.immediateEnabled
                  ? 'Migrates your entire balance in one batch. '
                        'Fast, but less private.'
                  : 'Not available with Keystone.',
              selected: immediateSelected,
              icon: _MigrationChoiceIcon.immediate,
              onTap: widget.immediateEnabled && !_isContinuing
                  ? () => _select(_MobileMigrationOption.immediate)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _refreshPrivateMigrationDraftPresentation(WidgetRef ref) async {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  ref.invalidate(ironwoodHomeMigrationCtaProvider);
  ref.invalidate(ironwoodPostMigrationStateProvider);
  try {
    await ref.read(ironwoodHomeMigrationCtaProvider.future);
  } catch (error) {
    // The durable draft is already saved. Let the destination screen reconcile
    // it rather than trapping the user on the option picker for a stale read.
    debugPrint('Failed to refresh private migration presentation: $error');
  }
}

Future<bool> _hasDurablePrivateMigrationRun(WidgetRef ref) async {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  try {
    final cta = await ref.read(ironwoodMigrationRouteCtaProvider.future);
    return cta.status?.activeRunId != null;
  } catch (_) {
    return false;
  }
}

enum _PrivateMigrationContinuationDestination {
  status,
  keystoneDenominationSigning,
}

void _openPrivateMigrationDestination(
  BuildContext context,
  ({
    _PrivateMigrationContinuationDestination destination,
    MobileIronwoodMigrationKeystoneDenominationSignEntry? keystoneEntry,
  })
  continuation,
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  switch (continuation.destination) {
    case _PrivateMigrationContinuationDestination.status:
      context.go(
        '/migration/private/status',
        extra: MobileIronwoodMigrationStatusEntry(approvedPlan: plan),
      );
      return;
    case _PrivateMigrationContinuationDestination.keystoneDenominationSigning:
      final entry = continuation.keystoneEntry;
      if (entry == null) {
        throw StateError('Keystone signing request is unavailable.');
      }
      context.go(
        '/migration/private/keystone/denominations/sign',
        extra: entry,
      );
      return;
  }
}

Future<
  ({
    _PrivateMigrationContinuationDestination destination,
    MobileIronwoodMigrationKeystoneDenominationSignEntry? keystoneEntry,
  })
>
_continuePrivateMigrationAfterNotificationGate(
  WidgetRef ref,
  rust_sync.OrchardMigrationPrivatePlan plan,
) async {
  final accountState = await ref.read(accountProvider.future);
  final accountUuid = accountState.activeAccountUuid;
  if (accountUuid == null) {
    throw StateError('No active account is selected.');
  }

  if (accountState.activeAccount?.isHardware ?? false) {
    final service = ref.read(ironwoodMigrationServiceProvider);
    final request = await service.prepareKeystoneDenominationPrivateMigration(
      accountUuid: accountUuid,
    );
    if (request.messages.isEmpty) {
      await service.completeKeystoneDenominationPrivateMigration(
        accountUuid: accountUuid,
        requestId: request.requestId,
        signedMessages: const [],
        approvedSchedule: plan.scheduledTransfers,
      );
      _invalidateStartedPrivateMigration(ref);
      return (
        destination: _PrivateMigrationContinuationDestination.status,
        keystoneEntry: null,
      );
    }
    return (
      destination:
          _PrivateMigrationContinuationDestination.keystoneDenominationSigning,
      keystoneEntry: MobileIronwoodMigrationKeystoneDenominationSignEntry(
        approvedSchedule: plan.scheduledTransfers,
        request: request,
        accountUuid: accountUuid,
      ),
    );
  }

  await ref
      .read(ironwoodMigrationCoordinatorProvider.notifier)
      .startSoftwareMigration(
        accountUuid: accountUuid,
        approvedSchedule: plan.scheduledTransfers,
      );

  _invalidateStartedPrivateMigration(ref);
  return (
    destination: _PrivateMigrationContinuationDestination.status,
    keystoneEntry: null,
  );
}

void _invalidateStartedPrivateMigration(WidgetRef ref) {
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  ref.invalidate(ironwoodHomeMigrationCtaProvider);
  ref.invalidate(ironwoodMigrationFlowDataProvider);
  ref.invalidate(ironwoodMigrationPrivatePlanProvider);
}
