part of 'mobile_ironwood_migration_flow_screen.dart';

class MobileIronwoodMigrationFlowScreen extends ConsumerWidget {
  const MobileIronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewImmediatePlan,
    this.previewStatus,
    this.previewParts,
    this.previewSurface,
    this.privateMigrationSupported,
    super.key,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final rust_sync.MigrationStatus? previewStatus;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final MobileIronwoodMigrationPreviewSurface? previewSurface;
  final bool? privateMigrationSupported;

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
        previewParts: previewParts,
        privateMigrationSupported: privateMigrationSupported,
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
      previewParts: previewParts,
      privateMigrationSupported: privateMigrationSupported,
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
    required this.previewParts,
    required this.privateMigrationSupported,
    this.status,
  });

  final MobileIronwoodMigrationStep step;
  final IronwoodMigrationFlowData data;
  final bool previewMode;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final rust_sync.OrchardMigrationImmediatePlan? previewImmediatePlan;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final bool? privateMigrationSupported;
  final rust_sync.MigrationStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privateMigrationEnabled =
        privateMigrationSupported ??
        (previewMode || supportsPrivateMobileIronwoodMigration());
    if (!privateMigrationEnabled &&
        switch (step) {
          MobileIronwoodMigrationStep.options ||
          MobileIronwoodMigrationStep.notifications => true,
          _ => false,
        }) {
      return const _MobileMigrationRedirectTo('/migration/fast/review');
    }
    final isHardware =
        !previewMode &&
        (ref.watch(accountProvider).value?.activeAccount?.isHardware ?? false);
    return switch (step) {
      MobileIronwoodMigrationStep.intro => _MobileMigrationIntro(data: data),
      MobileIronwoodMigrationStep.howItWorks =>
        const _MobileMigrationHowItWorks(),
      MobileIronwoodMigrationStep.options => _MobileMigrationOptions(
        immediateEnabled: true,
      ),
      MobileIronwoodMigrationStep.notifications =>
        _MobileMigrationNotificationPermissionScreen(
          privatePlan: previewPrivatePlan,
        ),
      MobileIronwoodMigrationStep.fastReview => _MobileMigrationFastReview(
        data: data,
        previewPlan: previewImmediatePlan,
        privateMigrationEnabled: privateMigrationEnabled,
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

/// Dedicated destination for a finished migration.
///
/// The result used to be reachable only as a branch inside the status screen,
/// so home's completion routing had to send the user to
/// `/migration/private/status`. That screen refreshes its own status on entry
/// and renders its loading/progress surface until the durable phase resolves,
/// which is why a finished migration flashed "in progress" before landing on
/// the result. The status screen keeps its own completion branch so the result
/// still appears when the user is already standing on it; both render the same
/// [_MigrationCompleteSurface], which owns the amount and the seen-marking.
class MobileIronwoodMigrationCompleteScreen extends ConsumerStatefulWidget {
  const MobileIronwoodMigrationCompleteScreen({super.key});

  @override
  ConsumerState<MobileIronwoodMigrationCompleteScreen> createState() =>
      _MobileIronwoodMigrationCompleteScreenState();
}

class _MobileIronwoodMigrationCompleteScreenState
    extends ConsumerState<MobileIronwoodMigrationCompleteScreen> {
  /// The account whose result this screen opened for, held across rebuilds.
  ///
  /// Marking a completion seen invalidates the provider that published it, so
  /// `visible` flips to false moments after this screen appears. Re-deciding
  /// from that provider on every build would redirect home and flash the
  /// result past — the exact behaviour this route exists to remove.
  String? _shownAccountUuid;

  @override
  Widget build(BuildContext context) {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;

    // Switching accounts must not leave another account's result on screen.
    final shownAccountUuid = _shownAccountUuid;
    if (shownAccountUuid != null && shownAccountUuid != accountUuid) {
      return const _MobileMigrationRedirectHome();
    }

    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    final data = ref.watch(ironwoodMigrationFlowDataProvider);
    final status = ctaAsync.value?.status;
    final completedStatus =
        status != null && status.phase == kIronwoodMigrationCompletePhase
        ? status
        : null;

    if (shownAccountUuid == null) {
      final completion = ref.watch(ironwoodMigrationCompletionProvider);
      // Never bounce off this route while either source is still settling;
      // that flicker is what this screen exists to remove.
      if (completion.isLoading || ctaAsync.isLoading) {
        return const _MobileMigrationLoadingScreen();
      }
      final value = completion.value;
      if (value == null ||
          !value.visible ||
          value.accountUuid != accountUuid ||
          completedStatus == null) {
        return const _MobileMigrationRedirectHome();
      }
      _shownAccountUuid = accountUuid;
    }

    // The result headline is built from a real amount or not shown at all, so
    // wait for the flow data rather than rendering a blank total.
    if (completedStatus == null || data == null) {
      return const _MobileMigrationLoadingScreen();
    }
    return _MigrationCompleteSurface(
      status: completedStatus,
      fallbackAmountText: data.amountText,
      onDone: () => context.go('/home'),
    );
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

    // A newly started run invalidates the route CTA before opening this
    // screen. Do not let the previous `start` value redirect back to About
    // while the durable run status is still loading.
    if (ctaAsync.isLoading &&
        ctaAsync.value?.mode == IronwoodHomeMigrationCtaMode.start) {
      return const _MobileMigrationLoadingScreen();
    }

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
        final isHardware =
            ref.watch(accountProvider).value?.activeAccount?.isHardware ??
            false;
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
          isHardware: isHardware,
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
  return phase == kIronwoodMigrationAwaitingPreparationPhase ||
      phase == kIronwoodMigrationAwaitingDenominationSignaturePhase ||
      phase == kIronwoodMigrationWaitingDenomConfirmationsPhase ||
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
