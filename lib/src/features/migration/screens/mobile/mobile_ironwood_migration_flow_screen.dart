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
import '../../models/ironwood_migration_presentation.dart';
import '../../providers/ironwood_migration_announcement_provider.dart';
import '../../services/ironwood_migration_service.dart';
import '../../widgets/ironwood_migration_shimmer_text.dart';
import '../../widgets/mobile/mobile_migration_passcode_view.dart';
import '../../widgets/mobile/mobile_migration_progress_indicator.dart';
import '../ironwood_migration_flow_screen.dart';

part 'mobile_ironwood_migration_status_widgets.dart';
part 'mobile_ironwood_migration_step_widgets.dart';

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
        const MobileMigrationPasscodeView(progress: 0.1),
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
                    key: const ValueKey(
                      'mobile_ironwood_intro_continue_button',
                    ),
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
        key: const ValueKey('mobile_ironwood_steps_continue_button'),
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
        key: const ValueKey('mobile_ironwood_options_continue_button'),
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
      key: const ValueKey('mobile_ironwood_migration_status_preparing'),
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
          key: const ValueKey('mobile_ironwood_migration_status_migrating'),
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
                MobileMigrationProgressHero(
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
                                      style: AppTypography.labelLarge.copyWith(
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
                            largeValue: true,
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
