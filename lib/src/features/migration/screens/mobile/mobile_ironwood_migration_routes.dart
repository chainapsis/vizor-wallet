part of 'mobile_ironwood_migration_flow_screen.dart';

class MobileIronwoodMigrationFlowScreen extends ConsumerWidget {
  const MobileIronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewStatus,
    this.previewReviewStage = MobileIronwoodMigrationReviewPreviewStage.review,
    this.previewParts,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.MigrationStatus? previewStatus;
  final MobileIronwoodMigrationReviewPreviewStage previewReviewStage;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      return _MobileIronwoodMigrationContent(
        step: step,
        data: preview,
        previewMode: true,
        previewPrivatePlan: previewPrivatePlan,
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
    required this.previewReviewStage,
    required this.previewParts,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
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
      MobileIronwoodMigrationStep.options => const _MobileMigrationOptions(),
      MobileIronwoodMigrationStep.privateReview =>
        _MobileMigrationPrivateReview(
          data: data,
          previewPlan: previewPrivatePlan,
          isHardware: isHardware,
          previewStage: previewReviewStage,
        ),
      MobileIronwoodMigrationStep.fastReview => _MobileMigrationFastReview(
        data: data,
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
          approvedPlan: approvedPlan,
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
      phase == kIronwoodMigrationWaitingConfirmationsPhase;
}

class _MobileMigrationLiveStatus extends StatelessWidget {
  const _MobileMigrationLiveStatus({
    required this.data,
    required this.status,
    required this.approvedPlan,
    required this.isHardware,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;
  final rust_sync.OrchardMigrationPrivatePlan? approvedPlan;
  final bool isHardware;

  @override
  Widget build(BuildContext context) {
    if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _MobileMigrationPreparing(
        data: data,
        status: status,
        isHardware: isHardware,
      );
    }
    if (status.phase == kIronwoodMigrationReadyToMigratePhase && isHardware) {
      return _MobileKeystoneMigrationReady(data: data, status: status);
    }
    return _MobileMigrationMigrating(
      data: data,
      status: status,
      previewPlan: approvedPlan,
      previewParts: null,
    );
  }
}
