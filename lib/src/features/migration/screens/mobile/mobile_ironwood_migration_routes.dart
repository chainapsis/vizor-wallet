part of 'mobile_ironwood_migration_flow_screen.dart';

class MobileIronwoodMigrationFlowScreen extends ConsumerWidget {
  const MobileIronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewImmediatePlan,
    this.previewStatus,
    this.previewReviewStage = MobileIronwoodMigrationReviewPreviewStage.review,
    this.previewParts,
    this.previewSurface,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final rust_sync.MigrationStatus? previewStatus;
  final MobileIronwoodMigrationReviewPreviewStage previewReviewStage;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final MobileIronwoodMigrationPreviewSurface? previewSurface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      final surface = previewSurface;
      if (surface != null) {
        return _MobileIronwoodMigrationPreviewSurface(
          surface: surface,
          data: preview,
        );
      }
      return _MobileIronwoodMigrationContent(
        step: step,
        data: preview,
        previewMode: true,
        previewPrivatePlan: previewPrivatePlan,
        previewImmediatePlan: previewImmediatePlan,
        previewReviewStage: previewReviewStage,
        previewParts: previewParts,
        status: previewStatus,
      );
    }

    final data = ref.watch(ironwoodMigrationFlowDataProvider);
    if (data == null) return const _MobileMigrationRedirectHome();
    return _MobileIronwoodMigrationContent(
      step: step,
      data: data,
      previewMode: false,
      previewPrivatePlan: previewPrivatePlan,
      previewImmediatePlan: previewImmediatePlan,
      previewReviewStage: previewReviewStage,
      previewParts: previewParts,
      status: null,
    );
  }
}

class _MobileIronwoodMigrationContent extends ConsumerWidget {
  const _MobileIronwoodMigrationContent({
    required this.step,
    required this.data,
    required this.previewMode,
    required this.previewPrivatePlan,
    required this.previewImmediatePlan,
    required this.previewReviewStage,
    required this.previewParts,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final MobileIronwoodMigrationReviewPreviewStage previewReviewStage;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHardware =
        !previewMode &&
        (ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false);
    return switch (step) {
      MobileIronwoodMigrationStep.intro => _MobileMigrationIntro(data: data),
      MobileIronwoodMigrationStep.howItWorks =>
        const _MobileMigrationHowItWorks(),
      MobileIronwoodMigrationStep.options => _MobileMigrationOptions(
        immediateEnabled: !isHardware,
      ),
      MobileIronwoodMigrationStep.notifications =>
        const _MobileMigrationNotificationPermissionScreen(),
      MobileIronwoodMigrationStep.privateReview =>
        _MobileMigrationPrivateReview(
          data: data,
          previewPlan: previewPrivatePlan,
          isHardware: isHardware,
          previewStage: previewReviewStage,
        ),
      MobileIronwoodMigrationStep.fastReview => _MobileMigrationFastReview(
        data: data,
        previewPlan: previewImmediatePlan,
        isHardware: isHardware,
      ),
      MobileIronwoodMigrationStep.preparing => _MobileMigrationPreparing(
        data: data,
        status: status,
        previewPlan: previewPrivatePlan,
        isHardware: isHardware,
      ),
      MobileIronwoodMigrationStep.migrating => _MobileMigrationMigrating(
        data: data,
        status: status,
        previewPlan: previewPrivatePlan,
        previewParts: previewParts,
      ),
    };
  }
}

class MobileIronwoodMigrationPrivateStatusScreen extends ConsumerWidget {
  const MobileIronwoodMigrationPrivateStatusScreen({
    this.approvedPlan,
    super.key,
  });

  final rust_sync.OrchardMigrationPrivatePlan? approvedPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    final data = ref.watch(ironwoodMigrationFlowDataProvider);

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

        if (data == null) return const _MobileMigrationRedirectHome();
        if (!_hasRenderableMobileMigrationStatus(status)) {
          return const _MobileMigrationLoadingScreen();
        }
        return _MobileMigrationLiveStatus(
          data: data,
          status: status,
          isHardware:
              ref.watch(accountProvider).value?.activeAccount?.isHardware ??
              false,
        );
      },
    );
  }
}

bool _hasRenderableMobileMigrationStatus(rust_sync.MigrationStatus status) {
  return status.parts.isNotEmpty ||
      status.scheduledBroadcasts.isNotEmpty ||
      status.targetValuesZatoshi.isNotEmpty;
}

bool _hasMobileMigrationStatusDesign(String phase) {
  return phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
      phase == kIronwoodMigrationReadyToMigratePhase ||
      phase == kIronwoodMigrationBroadcastScheduledPhase ||
      phase == kIronwoodMigrationBroadcastingPhase ||
      phase == kIronwoodMigrationWaitingConfirmationsPhase ||
      phase == kIronwoodMigrationPausedPhase ||
      phase == kIronwoodMigrationFailedRecoverablePhase ||
      phase == kIronwoodMigrationCompletePhase;
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
    return _MobileMigrationRedesignedStatus(
      data: data,
      status: status,
      isHardware: isHardware,
    );
  }
}
