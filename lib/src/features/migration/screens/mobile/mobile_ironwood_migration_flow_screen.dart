import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Divider, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../providers/account_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../providers/ironwood_migration_announcement_provider.dart';
import '../../services/ironwood_migration_service.dart';
import '../ironwood_migration_flow_screen.dart';

enum MobileIronwoodMigrationStep {
  intro,
  howItWorks,
  options,
  privateReview,
  fastReview,
  preparing,
  migrating,
  // The passcode state remains a deterministic design surface until its
  // privacy-lock trigger is specified for migration work.
  passcodeWhileSyncing,
}

const _migrationProgress = 60 / 196;

class MobileIronwoodMigrationFlowScreen extends ConsumerWidget {
  const MobileIronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewArrivalLabel,
    this.previewShowBatchModal = false,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final String? previewArrivalLabel;
  final bool previewShowBatchModal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      return _MobileIronwoodMigrationContent(
        step: step,
        data: preview,
        previewMode: true,
        previewPrivatePlan: previewPrivatePlan,
        previewArrivalLabel: previewArrivalLabel,
        previewShowBatchModal: previewShowBatchModal,
        status: null,
      );
    }

    return ref
        .watch(ironwoodMigrationFlowDataProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => const _MobileMigrationLoadingScreen(),
          error: (_, _) => const _MobileMigrationRedirectHome(),
          data: (data) => data == null
              ? const _MobileMigrationRedirectHome()
              : _MobileIronwoodMigrationContent(
                  step: step,
                  data: data,
                  previewMode: false,
                  previewPrivatePlan: previewPrivatePlan,
                  previewArrivalLabel: previewArrivalLabel,
                  previewShowBatchModal: previewShowBatchModal,
                  status: null,
                ),
        );
  }
}

class _MobileIronwoodMigrationContent extends StatelessWidget {
  const _MobileIronwoodMigrationContent({
    required this.step,
    required this.data,
    required this.previewMode,
    required this.previewPrivatePlan,
    required this.previewArrivalLabel,
    required this.previewShowBatchModal,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final String? previewArrivalLabel;
  final bool previewShowBatchModal;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context) {
    return switch (step) {
      MobileIronwoodMigrationStep.intro => _MobileMigrationIntro(data: data),
      MobileIronwoodMigrationStep.howItWorks => _MobileMigrationHowItWorks(
        data: data,
      ),
      MobileIronwoodMigrationStep.options => _MobileMigrationOptions(
        data: data,
      ),
      MobileIronwoodMigrationStep.privateReview =>
        _MobileMigrationPrivateReview(
          data: data,
          previewPlan: previewPrivatePlan,
          previewArrivalLabel: previewArrivalLabel,
        ),
      MobileIronwoodMigrationStep.fastReview => _MobileMigrationFastReview(
        data: data,
        previewMode: previewMode,
      ),
      MobileIronwoodMigrationStep.preparing => _MobileMigrationPreparing(
        data: data,
        status: status,
      ),
      MobileIronwoodMigrationStep.migrating => _MobileMigrationMigrating(
        data: data,
        status: status,
        initialShowBatchModal: previewShowBatchModal,
      ),
      MobileIronwoodMigrationStep.passcodeWhileSyncing =>
        const _MobileMigrationPasscode(),
    };
  }
}

class MobileIronwoodMigrationPrivateStatusScreen extends ConsumerWidget {
  const MobileIronwoodMigrationPrivateStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    final dataAsync = ref.watch(ironwoodMigrationFlowDataProvider);

    return ctaAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _MobileMigrationLoadingScreen(),
      error: (_, _) => const _MobileMigrationRedirectHome(),
      data: (cta) {
        if (cta.mode == IronwoodHomeMigrationCtaMode.start) {
          return const _MobileMigrationRedirectTo('/migration/intro');
        }
        final status = cta.status;
        final accountUuid = cta.accountUuid;
        if (cta.mode != IronwoodHomeMigrationCtaMode.resume ||
            status == null ||
            accountUuid == null ||
            !_hasMobileMigrationStatusDesign(status.phase)) {
          return const _MobileMigrationRedirectHome();
        }

        return dataAsync.when(
          skipLoadingOnReload: true,
          loading: () => const _MobileMigrationLoadingScreen(),
          error: (_, _) => const _MobileMigrationRedirectHome(),
          data: (data) => data == null
              ? const _MobileMigrationRedirectHome()
              : _MobileMigrationLiveStatus(data: data, status: status),
        );
      },
    );
  }
}

bool _hasMobileMigrationStatusDesign(String phase) {
  return phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
      phase == kIronwoodMigrationReadyToMigratePhase ||
      phase == kIronwoodMigrationBroadcastScheduledPhase ||
      phase == kIronwoodMigrationBroadcastingPhase ||
      phase == kIronwoodMigrationWaitingConfirmationsPhase;
}

class _MobileMigrationLiveStatus extends StatelessWidget {
  const _MobileMigrationLiveStatus({required this.data, required this.status});

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MobileMigrationPreparing(data: data, status: status);
    }
    return _MobileMigrationMigrating(
      data: data,
      status: status,
      initialShowBatchModal: false,
    );
  }
}

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
                titleStyle: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 22),
                    Text(
                      'Ironwood is the latest Zcash shielded pool. It’s '
                      'the first formally verified pool with cutting edge '
                      'cryptography.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                        height: 24 / 16,
                      ),
                    ),
                    const SizedBox(height: 27),
                    Text(
                      'There will be a one-time mandatory upgrade from '
                      'the legacy (orchard) shielded pool. You need to '
                      'transition your ${data.amountText} ZEC from the old '
                      'Orchard pool into the new Ironwood pool.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                        height: 25 / 16,
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
                    height: 44,
                    onPressed: () => _openIronwoodReleaseNotes(),
                    child: const Text('Official release note'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MobileMigrationPrimaryButton(
                    label: 'How the migration works',
                    onPressed: () => context.go('/migration/how-it-works'),
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
  const _MobileMigrationHowItWorks({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/intro'),
      topGap: 31,
      childGap: 30,
      title: 'How Migration Works',
      bottom: _MobileMigrationPrimaryButton(
        label: 'Continue',
        onPressed: () => context.go('/migration/options'),
      ),
      child: _MobileMigrationProcessCard(amount: data.amountText),
    );
  }
}

class _MobileMigrationOptions extends StatelessWidget {
  const _MobileMigrationOptions({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileMigrationStepScaffold(
      onBack: () => context.go('/migration/how-it-works'),
      topGap: 83,
      title: 'Choose How to Migrate\nyour ${data.amountText} ZEC',
      subtitle:
          'Whichever option you choose, your funds will be safely deposited '
          'into the Ironwood pool.',
      bottom: _MobileMigrationPrimaryButton(
        label: 'Continue',
        onPressed: () => context.go('/migration/private/review'),
      ),
      child: Column(
        children: [
          const _MobileMigrationOptionCard(
            title: 'Private',
            body:
                'Sends independent parts over time windows. Slower, harder '
                'to track.',
            selected: true,
            recommended: true,
            icon: _MigrationChoiceIcon.private,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _MobileMigrationOptionCard(
            key: ValueKey('mobile_ironwood_immediate_unavailable'),
            title: 'Immediate',
            body:
                'Sends now in one step. Amount and timing are easier to '
                'associate.',
            selected: false,
            recommended: false,
            icon: _MigrationChoiceIcon.immediate,
            enabled: false,
          ),
          const SizedBox(height: 25),
          Text(
            'Speed vs. correlation exposure. No anchors, cohorts, PCZTs, '
            'or action counts here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
              height: 24 / 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationPrivateReview extends ConsumerStatefulWidget {
  const _MobileMigrationPrivateReview({
    required this.data,
    required this.previewPlan,
    required this.previewArrivalLabel,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final String? previewArrivalLabel;

  @override
  ConsumerState<_MobileMigrationPrivateReview> createState() =>
      _MobileMigrationPrivateReviewState();
}

class _MobileMigrationPrivateReviewState
    extends ConsumerState<_MobileMigrationPrivateReview> {
  bool _isStarting = false;
  String? _startError;

  Future<void> _startMigration() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _startError = null;
    });

    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      final statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      if (accountState.activeAccount?.isHardware ?? false) {
        setState(() {
          _startError =
              'Keystone migration signing is not available on mobile yet.';
        });
        return;
      }

      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(accountUuid: accountUuid);
      if (!mounted) return;
      ref.invalidate(ironwoodMigrationStatusProvider(statusRequest));
      final startedStatus = await ref.read(
        ironwoodMigrationStatusProvider(statusRequest).future,
      );
      if (!mounted) return;
      if (startedStatus.activeRunId == null) {
        throw StateError('Migration did not create an active run.');
      }
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
      context.go('/migration/private/status');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startError = _mobilePrivateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewPlan;
    final planAsync = preview != null
        ? AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(preview)
        : ref.watch(ironwoodMigrationPrivatePlanProvider);
    final plan = planAsync.asData?.value;
    final canStart = plan != null && !_isStarting;

    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      icon: const AppIcon(
        AppIcons.shieldKeyhole,
        size: 28,
        color: Color(0xFF00A460),
      ),
      title: 'Review Migration Plan',
      amount: '${widget.data.amountText} ZEC',
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_startError != null) ...[
            Text(
              _startError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _MobileMigrationPrimaryButton(
            label: _isStarting ? 'Preparing...' : 'Continue',
            onPressed: canStart
                ? preview != null
                      ? () {}
                      : _startMigration
                : null,
          ),
        ],
      ),
      child: planAsync.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const _MobileMigrationUnavailable(),
        data: (plan) => plan == null
            ? const _MobileMigrationUnavailable()
            : _MobilePrivatePlan(
                plan: plan,
                arrivalLabel:
                    widget.previewArrivalLabel ?? _migrationArrivalLabel(plan),
              ),
      ),
    );
  }
}

String _mobilePrivateMigrationStartErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (message.contains('secret storage') ||
      message.contains('unlocked session')) {
    return 'Unlock Vizor before starting migration.';
  }
  if (message.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (message.contains('broadcast') || message.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't start migration. Try again.";
}

class _MobileMigrationFastReview extends StatelessWidget {
  const _MobileMigrationFastReview({
    required this.data,
    required this.previewMode,
  });

  final IronwoodMigrationFlowData data;
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _MobileMigrationReviewScaffold(
      onBack: () => context.go('/migration/options'),
      topGap: 40,
      iconTitleGap: 26,
      icon: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(
          painter: _ImmediateMigrationIconPainter(colors.icon.disabled),
        ),
      ),
      title: 'Review Migration Plan',
      amount: '${data.amountText} ZEC',
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            variant: AppButtonVariant.ghost,
            expand: true,
            height: 44,
            onPressed: () => context.go('/migration/options'),
            leading: const AppIcon(AppIcons.chevronBackward, size: 20),
            child: const Text('Consider another option'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            variant: AppButtonVariant.destructive,
            expand: true,
            height: 50,
            onPressed: previewMode ? () {} : null,
            leading: const AppIcon(AppIcons.warning, size: 20),
            child: const Text('Authorise anyway'),
          ),
        ],
      ),
      child: Column(
        children: [
          _MobileReviewCard(
            child: Column(
              children: [
                _ReviewRow(
                  label: 'Fees (estimate)',
                  value: 'shown before send',
                ),
                const SizedBox(height: AppSpacing.s),
                const _ReviewRow(
                  label: 'Orchard remains',
                  value: '<0.001 ZEC',
                  showInfo: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.homeCard,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    AppIcons.shieldKeyholeOutline,
                    size: 24,
                    color: colors.text.homeCard,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy trade-off',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.homeCard,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text.rich(
                          TextSpan(
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.homeCard,
                              height: 21 / 14,
                              letterSpacing: -0.21,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    'Crosses in one visible step — your '
                                    '${data.amountText} ZEC and timing are ',
                              ),
                              TextSpan(
                                text: 'easier to associate with your wallet',
                                style: TextStyle(
                                  color: colors.text.destructive,
                                ),
                              ),
                              const TextSpan(text: '. '),
                              const TextSpan(
                                text:
                                    'Consider choosing a Private Migration '
                                    'option.',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationPreparing extends StatelessWidget {
  const _MobileMigrationPreparing({required this.data, this.status});

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final splitSubmitted =
        status == null || status!.denominationSplitTotalCount > 0;
    final confirmationsReady =
        status != null &&
        status!.denominationConfirmationTarget > 0 &&
        status!.denominationConfirmationCount >=
            status!.denominationConfirmationTarget;
    return _MobileMigrationStatusScaffold(
      data: data,
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PreparingParticlesPainter(
                      color: colors.border.subtle,
                    ),
                  ),
                ),
                Positioned(
                  top: 80,
                  child: Text(
                    '${data.amountText} ZEC',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Positioned(
                  top: 117,
                  child: Text(
                    'Preparing...',
                    style: AppTypography.displayLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 28,
                  child: Text(
                    'This will take around 10-20m',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 240,
            child: _MobileStatusCard(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _PreparingStatusRow(
                    state: splitSubmitted
                        ? _PreparingStatusState.complete
                        : _PreparingStatusState.waiting,
                    label: 'Transaction splits submitted',
                  ),
                  _PreparingStatusRow(
                    state: confirmationsReady
                        ? _PreparingStatusState.complete
                        : _PreparingStatusState.waiting,
                    label: 'Waiting for confirmation ...',
                  ),
                  const _PreparingStatusRow(
                    state: _PreparingStatusState.pending,
                    label: 'Migration schedule',
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const _MigrationCanLeaveMessage(),
          const SizedBox(height: AppSpacing.s),
          _MobileStatusBackHomeButton(onPressed: () => context.go('/home')),
        ],
      ),
    );
  }
}

class _MobileMigrationMigrating extends StatefulWidget {
  const _MobileMigrationMigrating({
    required this.data,
    required this.initialShowBatchModal,
    this.status,
  });

  final IronwoodMigrationFlowData data;
  final bool initialShowBatchModal;
  final rust_sync.MigrationStatus? status;

  @override
  State<_MobileMigrationMigrating> createState() =>
      _MobileMigrationMigratingState();
}

class _MobileMigrationMigratingState extends State<_MobileMigrationMigrating> {
  late bool _showBatchModal = widget.initialShowBatchModal;

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final plannedBatchCount = _mobilePlannedBatchCount(status);
    final progress = _mobileMigrationProgress(status);
    final currentBatch = _mobileCurrentBatch(status);
    final arrivalLabel = _mobileStatusArrivalLabel(status);
    return Stack(
      children: [
        _MobileMigrationStatusScaffold(
          data: widget.data,
          child: Column(
            children: [
              _MigrationProgressHero(
                amount: widget.data.amountText,
                progress: progress,
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 240,
                child: _MobileStatusCard(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusTextRow(
                        label: '$plannedBatchCount planned batches',
                        value: 'View',
                        trailing: const AppIcon(
                          AppIcons.chevronForward,
                          size: 16,
                        ),
                        onTap: () => setState(() => _showBatchModal = true),
                      ),
                      const Divider(height: 1, thickness: 1),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Current batch'),
                          const SizedBox(height: AppSpacing.xs),
                          _CurrentBatchRow(batch: currentBatch),
                        ],
                      ),
                      const Divider(height: 1, thickness: 1),
                      _StatusTextRow(
                        label: 'Estimated arrival time',
                        value: arrivalLabel,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const _MigrationCanLeaveMessage(),
              const SizedBox(height: AppSpacing.s),
              _MobileStatusBackHomeButton(onPressed: () => context.go('/home')),
            ],
          ),
        ),
        if (_showBatchModal)
          Positioned.fill(
            child: _MigrationBatchModal(
              status: status,
              onClose: () => setState(() => _showBatchModal = false),
            ),
          ),
      ],
    );
  }
}

class _MobileMigrationPasscode extends StatefulWidget {
  const _MobileMigrationPasscode();

  @override
  State<_MobileMigrationPasscode> createState() =>
      _MobileMigrationPasscodeState();
}

class _MobileMigrationPasscodeState extends State<_MobileMigrationPasscode> {
  var _entryLength = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            36,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            children: [
              const _MigrationPasscodeHero(),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 57,
                child: Center(
                  child: PasscodeDots(
                    length: kMobilePasscodeLength,
                    filled: _entryLength,
                  ),
                ),
              ),
              const SizedBox(height: 46),
              PasscodeNumpad(
                onDigit: (_) {
                  if (_entryLength >= kMobilePasscodeLength) return;
                  setState(() => _entryLength += 1);
                },
                onBackspace: () {
                  if (_entryLength == 0) return;
                  setState(() => _entryLength -= 1);
                },
                canDelete: _entryLength > 0,
                onHelp: () {},
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationStatusScaffold extends StatelessWidget {
  const _MobileMigrationStatusScaffold({
    required this.data,
    required this.child,
  });

  final IronwoodMigrationFlowData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.account(
              accountName: data.accountName,
              syncLabel: 'Vizor is synced',
              avatar: AppProfilePicture(
                profilePictureId: data.profilePictureId,
                size: AppProfilePictureSize.navLarge,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  44,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileStatusCard extends StatelessWidget {
  const _MobileStatusCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.md,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

enum _PreparingStatusState { complete, waiting, pending }

class _PreparingStatusRow extends StatelessWidget {
  const _PreparingStatusRow({required this.state, required this.label});

  final _PreparingStatusState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leading = switch (state) {
      _PreparingStatusState.complete => DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF00A460),
          shape: BoxShape.circle,
        ),
        child: const SizedBox.square(
          dimension: 20,
          child: Center(
            child: AppIcon(AppIcons.check, size: 14, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
      _PreparingStatusState.waiting => AppIcon(
        AppIcons.loader,
        size: 20,
        color: colors.icon.accent,
        animated: false,
      ),
      _PreparingStatusState.pending => Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 26,
            child: SizedBox(
              width: 1,
              height: 24,
              child: ColoredBox(color: colors.border.subtle),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.neutralSubtleOpacity,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 20,
              child: Center(
                child: Text(
                  '3',
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    };
    return Row(
      children: [
        leading,
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ),
      ],
    );
  }
}

class _MigrationProgressHero extends StatelessWidget {
  const _MigrationProgressHero({required this.amount, required this.progress});

  final String amount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MigrationArcPainter(
                trackColor: colors.border.subtle,
                progressColor: const Color(0xFF00A460),
                progress: progress,
                rectTop: 0,
              ),
            ),
          ),
          Positioned(
            left: 7,
            top: 61,
            child: Transform.rotate(
              angle: -0.86,
              child: Text(
                '${(progress * 100).round()}% DONE',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 43,
            child: AppIcon(
              AppIcons.shieldKeyhole,
              size: 28,
              color: Color(0xFF00A460),
            ),
          ),
          Positioned(
            top: 80,
            child: Text(
              'Migrating...',
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Positioned(
            top: 117,
            child: Text(
              '$amount ZEC',
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            bottom: 28,
            child: Text(
              'Left to transfer',
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTextRow extends StatelessWidget {
  const _StatusTextRow({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: onTap == null ? 0 : 44),
          child: Align(
            alignment: Alignment.center,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentBatchRow extends StatelessWidget {
  const _CurrentBatchRow({required this.batch});

  final _MobileCurrentBatch batch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          batch.number.toString().padLeft(2, '0'),
          style: AppTypography.codeMedium.copyWith(color: colors.text.muted),
        ),
        const SizedBox(width: AppSpacing.xs),
        const _ZecBatchBadge(),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            batch.amount,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          batch.status,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _MigrationCanLeaveMessage extends StatelessWidget {
  const _MigrationCanLeaveMessage();

  @override
  Widget build(BuildContext context) {
    return Text(
      'You can leave this screen.\nBut keep Vizor open & running.',
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
        height: 20 / 14,
      ),
    );
  }
}

class _MobileStatusBackHomeButton extends StatelessWidget {
  const _MobileStatusBackHomeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      height: 44,
      minWidth: 100,
      onPressed: onPressed,
      child: const Text('Back home'),
    );
  }
}

int _mobilePlannedBatchCount(rust_sync.MigrationStatus? status) {
  if (status == null) return 12;
  if (status.totalCount > 0) return status.totalCount;
  if (status.targetValuesZatoshi.isNotEmpty) {
    return status.targetValuesZatoshi.length;
  }
  return math.max(1, status.preparedNoteCount);
}

double _mobileMigrationProgress(rust_sync.MigrationStatus? status) {
  if (status == null) return 0.1;
  final total = _mobilePlannedBatchCount(status);
  if (total <= 0) return 0.1;
  return (status.confirmedTxCount / total).clamp(0, 1);
}

class _MobileCurrentBatch {
  const _MobileCurrentBatch({
    required this.number,
    required this.amount,
    required this.status,
  });

  final int number;
  final String amount;
  final String status;
}

_MobileCurrentBatch _mobileCurrentBatch(rust_sync.MigrationStatus? status) {
  if (status == null) {
    return const _MobileCurrentBatch(
      number: 4,
      amount: '4.12 ZEC',
      status: 'Confirming...',
    );
  }
  final count = _mobilePlannedBatchCount(status);
  final number = math.min(count, math.max(1, status.confirmedTxCount + 1));
  final values = status.targetValuesZatoshi;
  final amount = number <= values.length
      ? '${ZecAmount.fromZatoshi(values[number - 1]).balance.amountText} ZEC'
      : '${ZecAmount.fromZatoshi(BigInt.zero).balance.amountText} ZEC';
  final label = switch (status.phase) {
    kIronwoodMigrationReadyToMigratePhase => 'Preparing...',
    kIronwoodMigrationBroadcastScheduledPhase => 'Scheduled',
    kIronwoodMigrationBroadcastingPhase => 'Broadcasting...',
    _ => 'Confirming...',
  };
  return _MobileCurrentBatch(number: number, amount: amount, status: label);
}

String _mobileStatusArrivalLabel(rust_sync.MigrationStatus? status) {
  if (status == null) return 'July 18, 12:00';
  final broadcasts = status.scheduledBroadcasts;
  if (broadcasts.isEmpty) return 'Schedule pending';
  var latestMs = broadcasts.first.scheduledAtMs;
  for (final broadcast in broadcasts.skip(1)) {
    latestMs = math.max(latestMs, broadcast.scheduledAtMs);
  }
  return _shortDateTime(DateTime.fromMillisecondsSinceEpoch(latestMs));
}

String _shortDateTime(DateTime dateTime) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${months[dateTime.month - 1]} ${dateTime.day}, '
      '${dateTime.hour}:$minute';
}

class _MigrationBatchModal extends StatefulWidget {
  const _MigrationBatchModal({required this.onClose, this.status});

  final VoidCallback onClose;
  final rust_sync.MigrationStatus? status;

  @override
  State<_MigrationBatchModal> createState() => _MigrationBatchModalState();
}

class _MigrationBatchModalState extends State<_MigrationBatchModal> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batchCount = _mobilePlannedBatchCount(widget.status);
    final targetValues = widget.status?.targetValuesZatoshi;
    final arrivalLabel = _mobileStatusArrivalLabel(widget.status);
    final modalArrivalLabel = arrivalLabel == 'Schedule pending'
        ? 'pending'
        : arrivalLabel.replaceFirst('July', 'Jul');
    return ColoredBox(
      color: colors.background.neutralScrim,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: SizedBox(
            height: 480,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.base,
                borderRadius: BorderRadius.circular(AppRadii.large),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.base + AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$batchCount batches',
                            style: AppTypography.bodyLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          'ETA: $modalArrivalLabel',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Expanded(
                      child: RawScrollbar(
                        key: const ValueKey('migration_batch_scrollbar'),
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        radius: const Radius.circular(AppRadii.full),
                        thickness: 4,
                        mainAxisMargin: 20,
                        padding: EdgeInsets.zero,
                        crossAxisMargin: AppSpacing.xs,
                        thumbColor: colors.background.overlay,
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: ListView.separated(
                              controller: _scrollController,
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: batchCount,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: 1,
                                color: colors.border.subtle,
                              ),
                              itemBuilder: (context, index) {
                                final number = '${index + 1}'.padLeft(2, '0');
                                final eta = _mobileBatchEta(
                                  status: widget.status,
                                  index: index,
                                );
                                return SizedBox(
                                  height: 53,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          number,
                                          style: AppTypography.codeMedium
                                              .copyWith(
                                                color: colors.text.muted,
                                              ),
                                        ),
                                      ),
                                      const _ZecBatchBadge(),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Expanded(
                                        child: Text(
                                          targetValues != null &&
                                                  index < targetValues.length
                                              ? '${ZecAmount.fromZatoshi(targetValues[index]).balance.amountText} ZEC'
                                              : '4.12 ZEC',
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: colors.text.accent,
                                              ),
                                        ),
                                      ),
                                      Text(
                                        eta,
                                        style: AppTypography.labelLarge
                                            .copyWith(
                                              color: colors.text.accent,
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.background.ground,
                          borderRadius: BorderRadius.circular(AppRadii.full),
                        ),
                        child: AppButton(
                          variant: AppButtonVariant.ghost,
                          expand: true,
                          height: 44,
                          onPressed: widget.onClose,
                          child: const Text('Close'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _mobileBatchEta({
  required rust_sync.MigrationStatus? status,
  required int index,
}) {
  if (status == null) {
    return switch (index) {
      0 => '~in 4 hrs',
      1 => '~in 12 hrs',
      2 || 3 || 4 => '~in 24 hrs',
      _ => '~in 30 hrs',
    };
  }
  if (index >= status.scheduledBroadcasts.length) return 'Pending';
  final scheduledAt = DateTime.fromMillisecondsSinceEpoch(
    status.scheduledBroadcasts[index].scheduledAtMs,
  );
  final remaining = scheduledAt.difference(DateTime.now());
  if (remaining <= Duration.zero) return 'Due now';
  final hours = math.max(1, remaining.inMinutes / 60).ceil();
  return '~in $hours hrs';
}

class _ZecBatchBadge extends StatelessWidget {
  const _ZecBatchBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFF6C744),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 16,
        child: Center(
          child: AppIcon(
            AppIcons.zcashCurrency,
            size: 10,
            color: Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

class _MigrationPasscodeHero extends StatelessWidget {
  const _MigrationPasscodeHero();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 194,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MigrationArcPainter(
                trackColor: colors.border.subtle,
                progressColor: const Color(0xFF00A460),
                progress: 0.1,
                rectTop: 14,
              ),
            ),
          ),
          Positioned(
            left: 7,
            top: 75,
            child: Transform.rotate(
              angle: -0.86,
              child: Text(
                '10% DONE',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                  fontSize: 9,
                ),
              ),
            ),
          ),
          Positioned(
            top: 107,
            child: Text(
              'Welcome Back',
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            child: Text(
              'Migrating...',
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparingParticlesPainter extends CustomPainter {
  const _PreparingParticlesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const particles = <(double, double, double)>[
      (0.02, 0.47, 3),
      (0.04, 0.41, 7),
      (0.08, 0.36, 5),
      (0.11, 0.31, 8),
      (0.15, 0.29, 5),
      (0.19, 0.22, 10),
      (0.25, 0.19, 6),
      (0.30, 0.13, 8),
      (0.36, 0.11, 4),
      (0.41, 0.06, 5),
      (0.47, 0.03, 9),
      (0.53, 0.02, 15),
      (0.61, 0.06, 8),
      (0.66, 0.05, 5),
      (0.71, 0.10, 7),
      (0.77, 0.13, 5),
      (0.81, 0.18, 9),
      (0.86, 0.23, 5),
      (0.89, 0.29, 8),
      (0.93, 0.35, 5),
      (0.96, 0.40, 8),
      (0.98, 0.47, 3),
    ];
    final paint = Paint()..color = color;
    for (final particle in particles) {
      canvas.drawCircle(
        Offset(size.width * particle.$1, size.height * particle.$2),
        particle.$3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreparingParticlesPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MigrationArcPainter extends CustomPainter {
  const _MigrationArcPainter({
    required this.trackColor,
    required this.progressColor,
    required this.progress,
    required this.rectTop,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress;
  final double rectTop;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, rectTop, size.width - 20, 250);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MigrationArcPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.progress != progress ||
      oldDelegate.rectTop != rectTop;
}

class _MobileMigrationStepScaffold extends StatelessWidget {
  const _MobileMigrationStepScaffold({
    required this.onBack,
    required this.title,
    required this.child,
    required this.bottom,
    this.subtitle,
    this.topGap = 31,
    this.childGap = 28,
  });

  final VoidCallback onBack;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget bottom;
  final double topGap;
  final double childGap;

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
              child: MobileTopNav.steps(
                progress: _migrationProgress,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topGap,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                          height: 24 / 16,
                        ),
                      ),
                    ],
                    SizedBox(height: childGap),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationReviewScaffold extends StatelessWidget {
  const _MobileMigrationReviewScaffold({
    required this.onBack,
    required this.icon,
    required this.title,
    required this.amount,
    required this.child,
    required this.bottom,
    this.topGap = 29,
    this.iconTitleGap = 36,
  });

  final VoidCallback onBack;
  final Widget icon;
  final String title;
  final String amount;
  final Widget child;
  final Widget bottom;
  final double topGap;
  final double iconTitleGap;

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
              child: MobileTopNav.steps(
                progress: _migrationProgress,
                onBack: onBack,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  topGap,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    icon,
                    SizedBox(height: iconTitleGap),
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      amount,
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 32),
                    child,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.s,
              ),
              child: bottom,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationPrimaryButton extends StatelessWidget {
  const _MobileMigrationPrimaryButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      expand: true,
      constrainContent: true,
      height: 50,
      onPressed: onPressed,
      trailing: const AppIcon(AppIcons.chevronForward, size: 20),
      child: Text(label),
    );
  }
}

class _MobilePoolMigrationHero extends StatelessWidget {
  const _MobilePoolMigrationHero({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = '${data.amountText} $kZcashDefaultCurrencyTicker';
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xLarge),
      child: ColoredBox(
        color: colors.background.ground,
        child: Stack(
          children: [
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Row(
                children: [
                  AppProfilePicture(
                    profilePictureId: data.profilePictureId,
                    size: AppProfilePictureSize.navLarge,
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFB8B8B8), Color(0xFF00A460)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        DecoratedBox(
                          decoration: const ShapeDecoration(
                            color: Color(0xFF00A460),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(6),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(
                                  AppIcons.shieldKeyhole,
                                  size: 20,
                                  color: Color(0xFFEAFEEF),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Text(
                                  'Migration',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: const Color(0xFFEAFEEF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppProfilePicture(
                    profilePictureId: data.profilePictureId,
                    size: AppProfilePictureSize.navLarge,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '(Legacy)',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        Text(
                          'Orchard Pool',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        Text(
                          amount,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Ironwood Pool',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: const Color(0xFF00A460),
                          ),
                        ),
                        Text(
                          amount,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

class _MobileMigrationProcessCard extends StatelessWidget {
  const _MobileMigrationProcessCard({required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    return _MobileReviewCard(
      padding: const EdgeInsets.fromLTRB(20, 29, 16, 42),
      borderRadius: 32,
      child: Column(
        children: [
          _ProcessRow(
            icon: _ProcessIcon.split,
            title: 'Split funds',
            body:
                'Your $amount ZEC balance is divided into several smaller '
                'common notes (10/1/0.1 ZEC). Splitting the balance into '
                'smaller batches mixes your transactions with other users '
                'maximizing privacy.',
          ),
          const Divider(height: 33),
          const _ProcessRow(
            icon: _ProcessIcon.schedule,
            title: 'Schedule',
            body:
                'Transactions dispatch at irregular intervals instead of all '
                'at once.',
          ),
          const Divider(height: 33),
          const _ProcessRow(
            icon: _ProcessIcon.sign,
            title: 'Sign once',
            body:
                'You grant permission at the start, and Vizor executes the '
                'remaining steps.',
          ),
        ],
      ),
    );
  }
}

enum _ProcessIcon { split, schedule, sign }

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final _ProcessIcon icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CustomPaint(
            painter: _ProcessIconPainter(icon, const Color(0xFF00A460)),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                  height: 25 / 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProcessIconPainter extends CustomPainter {
  const _ProcessIconPainter(this.kind, this.color);

  final _ProcessIcon kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case _ProcessIcon.split:
        canvas.drawLine(const Offset(5, 5), const Offset(5, 11), paint);
        canvas.drawLine(const Offset(5, 11), const Offset(12, 11), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(16, 7), paint);
      case _ProcessIcon.schedule:
        canvas.drawCircle(const Offset(10, 10), 6.5, paint);
        canvas.drawLine(const Offset(10, 10), const Offset(10, 6), paint);
        canvas.drawLine(const Offset(10, 10), const Offset(13, 12), paint);
      case _ProcessIcon.sign:
        canvas.drawLine(const Offset(4, 15), const Offset(16, 15), paint);
        canvas.drawLine(const Offset(5, 12), const Offset(8, 6), paint);
        canvas.drawLine(const Offset(8, 6), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 12), const Offset(15, 5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProcessIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

enum _MigrationChoiceIcon { private, immediate }

class _MobileMigrationOptionCard extends StatelessWidget {
  const _MobileMigrationOptionCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.recommended,
    required this.icon,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
  final bool recommended;
  final _MigrationChoiceIcon icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.96,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(24),
          border: selected
              ? Border.all(color: const Color(0xFF00A460), width: 2)
              : null,
          boxShadow: appSurfaceShadow(colors),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: icon == _MigrationChoiceIcon.private
                    ? AppIcon(
                        AppIcons.shieldKeyhole,
                        color: colors.icon.regular,
                      )
                    : CustomPaint(
                        painter: _ImmediateMigrationIconPainter(
                          colors.icon.disabled,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: AppSpacing.xs),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF00C77B),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Text(
                                'Recommended',
                                style: AppTypography.labelLarge.copyWith(
                                  color: const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                        height: 25 / 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? colors.background.inverse
                      : colors.background.overlay,
                ),
                child: selected
                    ? AppIcon(
                        AppIcons.check,
                        size: 16,
                        color: colors.text.inverse,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImmediateMigrationIconPainter extends CustomPainter {
  const _ImmediateMigrationIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.56, 0)
      ..lineTo(size.width * 0.18, size.height * 0.54)
      ..lineTo(size.width * 0.48, size.height * 0.54)
      ..lineTo(size.width * 0.37, size.height)
      ..lineTo(size.width * 0.84, size.height * 0.39)
      ..lineTo(size.width * 0.57, size.height * 0.39)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset.zero,
      Offset(size.width * 0.22, 0),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ImmediateMigrationIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MobilePrivatePlan extends StatelessWidget {
  const _MobilePrivatePlan({required this.plan, required this.arrivalLabel});

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final String arrivalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final perBatchFee = plan.plannedBatchCount <= 0
        ? plan.migrationFeeZatoshi
        : plan.migrationFeeZatoshi ~/ BigInt.from(plan.plannedBatchCount);
    final orchardRemainder = plan.orchardChangeZatoshi ?? BigInt.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: '${plan.plannedBatchCount} planned batches',
                value: 'View  ›',
                strongLabel: true,
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(label: '~ Arrival time', value: arrivalLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: 'Fees (estimate)',
                value: 'Per batch, ~${_compactZec(perBatchFee)} ZEC',
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(
                label: 'Orchard remains',
                value: '<${_compactZec(orchardRemainder)} ZEC',
                showInfo: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Privacy',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Separate windows reduce correlation — the total crossing amount '
          'stays publicly visible. Sending is best effort, not a delivery '
          'time.',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.accent,
            height: 25 / 16,
          ),
        ),
      ],
    );
  }
}

class _MobileReviewCard extends StatelessWidget {
  const _MobileReviewCard({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.strongLabel = false,
    this.showInfo = false,
  });

  final String label;
  final String value;
  final bool strongLabel;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(
          label,
          style:
              (strongLabel
                      ? AppTypography.bodyMediumStrong
                      : AppTypography.bodyMedium)
                  .copyWith(
                    color: strongLabel
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (showInfo) ...[
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(AppIcons.help, size: 14, color: colors.icon.regular),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileMigrationUnavailable extends StatelessWidget {
  const _MobileMigrationUnavailable();

  @override
  Widget build(BuildContext context) {
    return _MobileReviewCard(
      child: Text(
        'Migration review is not available yet. Wait for sync to finish and '
        'try again.',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

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

String _migrationArrivalLabel(rust_sync.OrchardMigrationPrivatePlan plan) {
  final batches = math.max(1, plan.plannedBatchCount);
  final seconds = plan.broadcastWindowSeconds * BigInt.from(batches - 1);
  final duration = Duration(seconds: seconds.toInt());
  final arrival = DateTime.now().add(duration);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final minute = arrival.minute.toString().padLeft(2, '0');
  final days = math.max(1, duration.inHours / 24).ceil();
  return '${months[arrival.month - 1]} ${arrival.day}, '
      '${arrival.hour}:$minute (~$days days)';
}

Future<void> _openIronwoodReleaseNotes() async {
  await launchUrl(
    Uri.parse(kIronwoodMigrationReleaseNotesUrl),
    mode: LaunchMode.externalApplication,
  );
}
