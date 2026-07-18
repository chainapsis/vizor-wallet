import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Divider, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/sync_status_label.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../models/ironwood_migration_presentation.dart';
import '../../providers/ironwood_migration_announcement_provider.dart';
import '../../services/ironwood_migration_service.dart';
import '../../widgets/ironwood_migration_shimmer_text.dart';
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
    this.previewShowBatchModal = false,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
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
        previewShowBatchModal: previewShowBatchModal,
        status: null,
      );
    }

    return ref.watch(ironwoodMigrationFlowDataProvider).when(
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
                  previewShowBatchModal: previewShowBatchModal,
                  status: null,
                ),
        );
  }
}

class _MobileIronwoodMigrationContent extends ConsumerWidget {
  const _MobileIronwoodMigrationContent({
    required this.step,
    required this.data,
    required this.previewMode,
    required this.previewPrivatePlan,
    required this.previewShowBatchModal,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final bool previewShowBatchModal;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHardware = !previewMode &&
        (ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false);
    final shouldLoadPlan = !previewMode &&
        (step == MobileIronwoodMigrationStep.howItWorks ||
            step == MobileIronwoodMigrationStep.options);
    final plan = previewPrivatePlan ??
        (shouldLoadPlan
            ? ref.watch(ironwoodMigrationPrivatePlanProvider).asData?.value
            : null);
    return switch (step) {
      MobileIronwoodMigrationStep.intro => _MobileMigrationIntro(data: data),
      MobileIronwoodMigrationStep.howItWorks => _MobileMigrationHowItWorks(
          data: data,
          plan: plan,
          isHardware: isHardware,
        ),
      MobileIronwoodMigrationStep.options => _MobileMigrationOptions(
          data: data,
          plan: plan,
        ),
      MobileIronwoodMigrationStep.privateReview =>
        _MobileMigrationPrivateReview(
          data: data,
          previewPlan: previewPrivatePlan,
          isHardware: isHardware,
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
          previewPlan: previewPrivatePlan,
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
              : _MobileMigrationLiveStatus(
                  data: data,
                  status: status,
                  isHardware: ref
                          .watch(accountProvider)
                          .value
                          ?.activeAccount
                          ?.isHardware ??
                      false,
                ),
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
  const _MobileMigrationLiveStatus({
    required this.data,
    required this.status,
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;
  final bool isHardware;

  @override
  Widget build(BuildContext context) {
    if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MobileMigrationPreparing(data: data, status: status);
    }
    if (status.phase == kIronwoodMigrationReadyToMigratePhase && isHardware) {
      return _MobileKeystoneMigrationReady(data: data, status: status);
    }
    return _MobileMigrationMigrating(
      data: data,
      status: status,
      previewPlan: null,
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
  const _MobileMigrationHowItWorks({
    required this.data,
    required this.plan,
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? plan;
  final bool isHardware;

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
      child: _MobileMigrationProcessCard(
        amount: data.amountText,
        plan: plan,
        isHardware: isHardware,
      ),
    );
  }
}

class _MobileMigrationOptions extends StatelessWidget {
  const _MobileMigrationOptions({required this.data, required this.plan});

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? plan;

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
          _MobileMigrationOptionCard(
            title: 'Private',
            body: plan == null
                ? 'Prepares separate migration transactions and spreads their '
                    'sends when the plan allows it.'
                : privateMigrationMethodDescription(plan!),
            selected: true,
            icon: _MigrationChoiceIcon.private,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _MobileMigrationOptionCard(
            key: ValueKey('mobile_ironwood_immediate_unavailable'),
            title: 'Immediate',
            body: 'Sends now in one step. Amount and timing are easier to '
                'associate.',
            selected: false,
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
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool isHardware;

  @override
  ConsumerState<_MobileMigrationPrivateReview> createState() =>
      _MobileMigrationPrivateReviewState();
}

class _MobileMigrationPrivateReviewState
    extends ConsumerState<_MobileMigrationPrivateReview> {
  bool _isStarting = false;
  String? _startError;

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
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
        context.go(
          '/migration/private/keystone/denominations/sign',
          extra: plan.scheduledTransfers,
        );
        return;
      }

      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
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
    final keystonePlanSupported = !widget.isHardware ||
        plan == null ||
        _keystoneTwoRoundPlanSupported(plan);
    final canStart = plan != null && !_isStarting && keystonePlanSupported;

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
          if (!keystonePlanSupported) ...[
            Text(
              'This migration needs more transactions than one Keystone '
              'signing request supports.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _MobileMigrationPrimaryButton(
            key: const ValueKey('mobile_ironwood_authorize_start_button'),
            label: _isStarting
                ? 'Preparing...'
                : widget.isHardware
                    ? 'Continue with Keystone'
                    : 'Continue',
            onPressed: canStart
                ? preview != null
                    ? () {}
                    : () => _startMigration(plan)
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
                arrivalLabel: _migrationArrivalLabel(plan),
              ),
      ),
    );
  }
}

bool _keystoneTwoRoundPlanSupported(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final limit = plan.signingBatchLimit;
  if (limit <= 0) return false;
  return plan.denominationSplitStageCount <= limit &&
      plan.plannedBatchCount <= limit;
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
                  value: 'Calculated before send',
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
                                text: 'Crosses in one visible step — your '
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
                                text: 'Consider choosing a Private Migration '
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
    final confirmationsReady = status != null &&
        status!.denominationConfirmationTarget > 0 &&
        status!.denominationConfirmationCount >=
            status!.denominationConfirmationTarget;
    return _MobileMigrationStatusScaffold(
      data: data,
      topNavSpacing: AppSpacing.s,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        18,
        AppSpacing.sm,
        0,
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
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
                    top: 97,
                    child: Text(
                      '${data.amountText} ZEC',
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 131,
                    child: IronwoodMigrationShimmerText(
                      key: const ValueKey(
                        'mobile_ironwood_migration_preparing_title',
                      ),
                      text: 'Preparing...',
                      style: AppTypography.displayLarge.copyWith(
                        letterSpacing: 0,
                      ),
                      baseColor: colors.text.secondary,
                      highlightColor: colors.text.accent,
                    ),
                  ),
                  Positioned(
                    top: 183,
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Text(
                      status == null
                          ? 'This will take around 10-20m'
                          : migrationPreparationProgressLabel(status!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              height: 240,
              child: _MobileStatusCard(
                child: Center(
                  child: SizedBox(
                    height: 140,
                    child: Column(
                      children: [
                        const _PreparingStatusRow(
                          state: _PreparingStatusState.complete,
                          label: 'Transaction splits submitted',
                          showConnector: true,
                        ),
                        _PreparingStatusRow(
                          state: confirmationsReady
                              ? _PreparingStatusState.complete
                              : _PreparingStatusState.waiting,
                          label: 'Waiting for confirmation...',
                          showConnector: true,
                        ),
                        const _PreparingStatusRow(
                          state: _PreparingStatusState.pending,
                          label: 'Migration schedule',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            const _MigrationCanLeaveMessage(),
            const SizedBox(height: AppSpacing.base),
            _MobileStatusBackHomeButton(
              key: const ValueKey('mobile_ironwood_status_back_home_button'),
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileKeystoneMigrationReady extends StatelessWidget {
  const _MobileKeystoneMigrationReady({
    required this.data,
    required this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batchCount = _mobilePlannedBatchCount(status);
    final transactionLabel = batchCount == 1
        ? '1 migration transaction'
        : '$batchCount migration transactions';
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_keystone_ready'),
      data: data,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.s),
                const AppIcon(AppIcons.qr, size: 40),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Ready for Keystone',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'The split transactions are confirmed. Use Keystone again to '
                  'approve the Ironwood migration transactions.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                _MobileStatusCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF00A460),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(
                              dimension: 20,
                              child: Center(
                                child: AppIcon(
                                  AppIcons.check,
                                  size: 14,
                                  color: Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          const Expanded(
                            child: Text('Split transactions confirmed'),
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.lg),
                      Text(
                        'Keystone approval',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$transactionLabel ready to sign',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_keystone_batch_sign_button',
                  ),
                  expand: true,
                  onPressed: () =>
                      context.go('/migration/private/keystone/batch/sign'),
                  child: const Text('Continue'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _MobileStatusBackHomeButton(
                    onPressed: () => context.go('/home')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationMigrating extends StatefulWidget {
  const _MobileMigrationMigrating({
    required this.data,
    required this.initialShowBatchModal,
    required this.previewPlan,
    this.status,
  });

  final IronwoodMigrationFlowData data;
  final bool initialShowBatchModal;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
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
    final plannedBatchCount = _mobilePlannedBatchCount(
      status,
      previewPlan: widget.previewPlan,
    );
    final progress = _mobileMigrationProgress(
      status,
      previewPlan: widget.previewPlan,
    );
    final currentBatch = _mobileCurrentBatch(
      status,
      previewPlan: widget.previewPlan,
    );
    final arrivalLabel = _mobileStatusArrivalLabel(
      status,
      previewPlan: widget.previewPlan,
    );
    final timingLabel = _mobileStatusTimingLabel(status);
    final remainingAmount = _mobileRemainingAmountText(
      status,
      fallback: widget.data.amountText,
    );
    return Stack(
      children: [
        _MobileMigrationStatusScaffold(
          data: widget.data,
          topNavSpacing: AppSpacing.s,
          contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            18,
            AppSpacing.sm,
            0,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              children: [
                _MigrationProgressHero(
                  amount: remainingAmount,
                  progress: progress,
                ),
                const SizedBox(height: AppSpacing.base),
                SizedBox(
                  height: 240,
                  child: _MobileStatusCard(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          height: 32,
                          child: _StatusTextRow(
                            label:
                                plannedMigrationBatchesLabel(plannedBatchCount),
                            value: 'View',
                            emphasizeLabel: true,
                            trailing: const AppIcon(
                              AppIcons.chevronForward,
                              size: 20,
                            ),
                            onTap: () =>
                                setState(() => _showBatchModal = true),
                          ),
                        ),
                        const Divider(height: 1, thickness: 1),
                        SizedBox(
                          height: 63,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 25,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(left: AppSpacing.xxs),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Current batch',
                                      style: AppTypography.labelMedium.copyWith(
                                        color: context.colors.text.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              SizedBox(
                                height: 30,
                                child: _CurrentBatchRow(batch: currentBatch),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 1),
                        SizedBox(
                          height: 32,
                          child: _StatusTextRow(
                            label: timingLabel,
                            value: arrivalLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                const _MigrationCanLeaveMessage(),
                const SizedBox(height: AppSpacing.base),
                _MobileStatusBackHomeButton(
                  key:
                      const ValueKey('mobile_ironwood_status_back_home_button'),
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ),
        if (_showBatchModal)
          Positioned.fill(
            child: _MigrationBatchModal(
              status: status,
              previewPlan: widget.previewPlan,
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

class _MobileMigrationStatusScaffold extends ConsumerWidget {
  const _MobileMigrationStatusScaffold({
    required this.data,
    required this.child,
    this.topNavSpacing = 0,
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
  final double topNavSpacing;
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
            if (topNavSpacing > 0) SizedBox(height: topNavSpacing),
            MobileTopNav.account(
              accountName: data.accountName,
              syncLabel: syncLabel,
              avatar: AppProfilePicture(
                profilePictureId: data.profilePictureId,
                size: AppProfilePictureSize.navLarge,
              ),
            ),
            Expanded(
              child: Padding(
                padding: contentPadding,
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
  const _MobileStatusCard({required this.child});

  final Widget child;

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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: child,
        ),
      ),
    );
  }
}

enum _PreparingStatusState { complete, waiting, pending }

class _PreparingStatusRow extends StatelessWidget {
  const _PreparingStatusRow({
    required this.state,
    required this.label,
    this.showConnector = false,
  });

  final _PreparingStatusState state;
  final String label;
  final bool showConnector;

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
            dimension: 24,
            child: Center(
              child:
                  AppIcon(AppIcons.check, size: 16, color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      _PreparingStatusState.waiting => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: AppIcon(
                AppIcons.loader,
                size: 16,
                color: colors.icon.inverse,
                animated: false,
              ),
            ),
          ),
        ),
      _PreparingStatusState.pending => DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.raised,
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Text(
                '3',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
        ),
    };
    return SizedBox(
      height: showConnector ? 58 : 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                leading,
                if (showConnector)
                  SizedBox(
                    width: 24,
                    height: 34,
                    child: Center(
                      child: SizedBox(
                        width: 1,
                        height: 18,
                        child: ColoredBox(color: colors.border.subtle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ),
        ],
      ),
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
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _MigrationArcPainter(
                trackColor: colors.border.subtle,
                progressColor: const Color(0xFF00A460),
                progress: progress,
                rectTop: 8,
                horizontalInset: 8,
                rectHeight: 195,
                trackWidth: 8,
                progressWidth: 8,
              ),
            ),
          ),
          Positioned(
            left: -3,
            top: 86,
            child: Transform.rotate(
              angle: -0.84,
              alignment: Alignment.bottomLeft,
              child: Text(
                '${(progress * 100).round()}% DONE',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                  fontSize: 12,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const Positioned(
            top: 49,
            child: AppIcon(
              AppIcons.shieldKeyhole,
              size: 32,
              color: Color(0xFF00A460),
            ),
          ),
          Positioned(
            top: 97,
            child: Text(
              'Migrating...',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            top: 131,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            height: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                key: const ValueKey('mobile_ironwood_remaining_amount'),
                TextSpan(
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                    fontSize: 40,
                    height: 1,
                    letterSpacing: 0,
                  ),
                  children: [
                    TextSpan(text: '$amount '),
                    TextSpan(
                      text: 'ZEC',
                      style: AppTypography.displayLarge.copyWith(
                        color: colors.text.accent,
                        fontSize: 32,
                        height: 33 / 32,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 183,
            child: Text(
              'Left to transfer',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.secondary,
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
    this.emphasizeLabel = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool emphasizeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: Alignment.center,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xxs),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.accent,
                      fontWeight:
                          emphasizeLabel ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.accent,
                  ),
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
        const SizedBox(width: AppSpacing.xxs),
        const _ZecBatchBadge(),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            batch.amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
        Text(
          batch.status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.accent,
          ),
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
    return SizedBox(
      height: 50,
      child: Center(
        child: AppButton(
          height: 44,
          minWidth: 100,
          onPressed: onPressed,
          child: const Text('Back home'),
        ),
      ),
    );
  }
}

int _mobilePlannedBatchCount(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) return previewPlan?.plannedBatchCount ?? 0;
  if (status.totalCount > 0) return status.totalCount;
  if (status.targetValuesZatoshi.isNotEmpty) {
    return status.targetValuesZatoshi.length;
  }
  return math.max(1, status.preparedNoteCount);
}

double _mobileMigrationProgress(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) return previewPlan == null ? 0 : 0.1;
  final total = _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  if (total <= 0) return 0;
  return (status.confirmedTxCount / total).clamp(0, 1);
}

String _mobileRemainingAmountText(
  rust_sync.MigrationStatus? status, {
  required String fallback,
}) {
  if (status == null || status.targetValuesZatoshi.isEmpty) return fallback;

  final values = status.targetValuesZatoshi;
  final total = values.fold<BigInt>(
    BigInt.zero,
    (sum, value) => sum + value,
  );
  if (total <= BigInt.zero) return fallback;

  final completed = math.min(values.length, status.confirmedTxCount);
  final BigInt remaining;
  if (status.totalCount > 0 && values.length == status.totalCount) {
    remaining = values.skip(completed).fold<BigInt>(
          BigInt.zero,
          (sum, value) => sum + value,
        );
  } else {
    final progress = _mobileMigrationProgress(status);
    final scaledProgress = BigInt.from((progress * 10000).round());
    remaining = total - (total * scaledProgress) ~/ BigInt.from(10000);
  }

  return ZecAmount.fromZatoshi(
    remaining > BigInt.zero ? remaining : BigInt.zero,
  ).balance.amountText;
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

_MobileCurrentBatch _mobileCurrentBatch(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) {
    final values = previewPlan?.targetValuesZatoshi;
    return _MobileCurrentBatch(
      number: values?.isNotEmpty ?? false ? 1 : 0,
      amount: values?.isNotEmpty ?? false
          ? '${ZecAmount.fromZatoshi(values!.first).balance.amountText} ZEC'
          : 'Amount pending',
      status: 'Not started',
    );
  }
  final count = _mobilePlannedBatchCount(status, previewPlan: previewPlan);
  final number = math.min(count, math.max(1, status.confirmedTxCount + 1));
  final values = status.targetValuesZatoshi;
  final amount = number <= values.length
      ? '${ZecAmount.fromZatoshi(values[number - 1]).balance.amountText} ZEC'
      : 'Amount pending';
  final label = switch (status.phase) {
    kIronwoodMigrationReadyToMigratePhase => 'Preparing...',
    kIronwoodMigrationBroadcastScheduledPhase => 'Scheduled',
    kIronwoodMigrationBroadcastingPhase => 'Broadcasting...',
    _ => 'Confirming...',
  };
  return _MobileCurrentBatch(number: number, amount: amount, status: label);
}

String _mobileStatusArrivalLabel(
  rust_sync.MigrationStatus? status, {
  rust_sync.OrchardMigrationPrivatePlan? previewPlan,
}) {
  if (status == null) {
    return previewPlan == null
        ? 'Schedule pending'
        : migrationDispatchWindowLabel(previewPlan.broadcastWindowSeconds);
  }
  return migrationDispatchTimingLabel(status);
}

String _mobileStatusTimingLabel(rust_sync.MigrationStatus? status) {
  if (status?.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return 'Migration status';
  }
  return 'Estimated arrival time';
}

class _MigrationBatchModal extends StatefulWidget {
  const _MigrationBatchModal({
    required this.onClose,
    required this.previewPlan,
    this.status,
  });

  final VoidCallback onClose;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
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
    final batchCount = _mobilePlannedBatchCount(
      widget.status,
      previewPlan: widget.previewPlan,
    );
    final targetValues = widget.status?.targetValuesZatoshi ??
        widget.previewPlan?.targetValuesZatoshi;
    final arrivalLabel = _mobileStatusArrivalLabel(
      widget.status,
      previewPlan: widget.previewPlan,
    );
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          migrationBatchesLabel(batchCount),
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Schedule: $arrivalLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                                final dispatchLabel = _mobileBatchDispatchLabel(
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
                                          style:
                                              AppTypography.codeMedium.copyWith(
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
                                              : 'Amount pending',
                                          style:
                                              AppTypography.labelLarge.copyWith(
                                            color: colors.text.accent,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        dispatchLabel,
                                        style:
                                            AppTypography.labelLarge.copyWith(
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

String _mobileBatchDispatchLabel({
  required rust_sync.MigrationStatus? status,
  required int index,
}) {
  if (status == null) return 'Pending';
  if (index >= status.scheduledBroadcasts.length) return 'Pending';
  return migrationScheduledBroadcastLabel(status.scheduledBroadcasts[index]);
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
        dimension: 19,
        child: Center(
          child: AppIcon(
            AppIcons.zcashCurrency,
            size: 11,
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
    // Figma node 6533:120710 uses a fixed 353 x 120 particle field inside
    // the 361 px title area. Scale the deterministic coordinates as a group
    // so compact widths keep the same arc rather than reflowing randomly.
    const particles = <(double, double, double)>[
      (268, 36, 19),
      (327, 84, 16),
      (4, 99, 13),
      (103, 37, 13),
      (56, 52, 13),
      (344, 97, 13),
      (22, 95, 11),
      (209, 13, 19),
      (135, 15, 20),
      (291, 55, 15),
      (316, 62, 15),
      (54, 72, 15),
      (33, 76, 15),
      (37, 57, 11),
      (234, 30, 11),
      (249, 17, 13),
      (202, 5, 6),
      (309, 80, 6),
      (255, 40, 6),
      (279, 60, 6),
      (120, 26, 6),
      (89, 62, 6),
      (75, 63, 6),
      (126, 15, 6),
      (152, 35, 10),
      (232, 14, 10),
      (5, 118, 6),
      (351, 118, 6),
      (335, 76, 6),
      (299, 45, 6),
      (13, 84, 6),
      (106, 24, 6),
      (164, 4, 37),
      (74, 34, 21),
    ];
    final paint = Paint()..color = color;
    final scale = size.width / 361;
    for (final particle in particles) {
      final diameter = particle.$3 * scale;
      canvas.drawCircle(
        Offset(
          (4 + particle.$1 + particle.$3 / 2) * scale,
          (4 + particle.$2 + particle.$3 / 2) * scale,
        ),
        diameter / 2,
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
    this.horizontalInset = 10,
    this.rectHeight = 250,
    this.trackWidth = 4,
    this.progressWidth = 6,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress;
  final double rectTop;
  final double horizontalInset;
  final double rectHeight;
  final double trackWidth;
  final double progressWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      horizontalInset,
      rectTop,
      size.width - horizontalInset * 2,
      rectHeight,
    );
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackWidth
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = progressWidth
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
      oldDelegate.rectTop != rectTop ||
      oldDelegate.horizontalInset != horizontalInset ||
      oldDelegate.rectHeight != rectHeight ||
      oldDelegate.trackWidth != trackWidth ||
      oldDelegate.progressWidth != progressWidth;
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
  const _MobileMigrationProcessCard({
    required this.amount,
    required this.plan,
    required this.isHardware,
  });

  final String amount;
  final rust_sync.OrchardMigrationPrivatePlan? plan;
  final bool isHardware;

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
            body: plan == null
                ? 'Vizor will calculate the split transactions and migration '
                    'batches from your current Orchard notes.'
                : migrationPlanPreparationDescription(
                    plan: plan!,
                    amountText: amount,
                  ),
          ),
          const Divider(height: 33),
          const _ProcessRow(
            icon: _ProcessIcon.schedule,
            title: 'Schedule',
            body: 'Transactions dispatch at irregular intervals instead of all '
                'at once.',
          ),
          const Divider(height: 33),
          _ProcessRow(
            icon: _ProcessIcon.sign,
            title: isHardware ? 'Sign with Keystone twice' : 'Sign once',
            body: isHardware
                ? 'First approve the split transactions. After they confirm, '
                    'return to approve the Ironwood migration transactions.'
                : 'You grant permission at the start, and Vizor executes the '
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
    required this.icon,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String body;
  final bool selected;
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
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
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
    final orchardRemainder = plan.orchardChangeZatoshi ?? BigInt.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: plannedMigrationBatchesLabel(plan.plannedBatchCount),
                value: 'View  ›',
                strongLabel: true,
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(label: 'Dispatch window', value: arrivalLabel),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MobileReviewCard(
          child: Column(
            children: [
              _ReviewRow(
                label: 'Fees (estimate)',
                value:
                    'Total, ~${_compactZec(plan.estimatedTotalFeeZatoshi)} ZEC',
              ),
              const SizedBox(height: AppSpacing.s),
              _ReviewRow(
                label: 'Orchard remains',
                value: '${_compactZec(orchardRemainder)} ZEC',
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
          'Transactions are scheduled across the shown window instead of all '
          'at once. Amounts and timing remain visible, so this is not a '
          'privacy guarantee.',
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
          style: (strongLabel
                  ? AppTypography.bodyMediumStrong
                  : AppTypography.bodyMedium)
              .copyWith(
            color: strongLabel ? colors.text.accent : colors.text.secondary,
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
  return migrationDispatchWindowLabel(plan.broadcastWindowSeconds);
}

Future<void> _openIronwoodReleaseNotes() async {
  await launchUrl(
    Uri.parse(kIronwoodMigrationReleaseNotesUrl),
    mode: LaunchMode.externalApplication,
  );
}
