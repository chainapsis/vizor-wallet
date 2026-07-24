part of '../ironwood_migration_flow_screen.dart';

class IronwoodMigrationFlowScreen extends ConsumerWidget {
  const IronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.previewReviewStage = IronwoodMigrationReviewPreviewStage.review,
    this.onOpenReleaseNotesOverride,
    super.key,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final IronwoodMigrationReviewPreviewStage previewReviewStage;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data =
        previewData ??
        ref.watch(ironwoodMigrationFlowDataProvider) ??
        _fallbackMigrationFlowData();
    return _IronwoodMigrationShell(
      step: step,
      data: data,
      previewPrivatePlan: previewPrivatePlan,
      previewReviewStage: previewReviewStage,
      onOpenReleaseNotesOverride: onOpenReleaseNotesOverride,
    );
  }
}

class IronwoodMigrationEntryScreen extends ConsumerWidget {
  const IronwoodMigrationEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presentationCta = ref.watch(
      ironwoodHomeMigrationPresentationProvider,
    );
    final routeCta = ref.watch(ironwoodMigrationRouteCtaProvider).asData?.value;
    final cta = presentationCta.mode == IronwoodHomeMigrationCtaMode.resume
        ? presentationCta
        : routeCta;
    final target = cta?.mode == IronwoodHomeMigrationCtaMode.resume
        ? '/migration/private/status'
        : '/migration/prepare';
    return _RedirectTo(target);
  }
}

class IronwoodMigrationPrepareScreen extends ConsumerStatefulWidget {
  const IronwoodMigrationPrepareScreen({super.key});

  @override
  ConsumerState<IronwoodMigrationPrepareScreen> createState() =>
      _IronwoodMigrationPrepareScreenState();
}

class _IronwoodMigrationPrepareScreenState
    extends ConsumerState<IronwoodMigrationPrepareScreen> {
  bool _redirectScheduled = false;

  void _go(String location, {String? toast}) {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (toast != null) {
        showAppToast(context, toast, iconName: AppIcons.warning);
      }
      context.go(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inputs = ref.watch(ironwoodMigrationInputsProvider);
    final request = inputs.statusRequest;
    if (!inputs.ironwoodActiveAtTip || request == null) {
      _go('/home', toast: 'Migration is not available for this account.');
      return const _IronwoodMigrationLoadingShell(
        step: IronwoodMigrationFlowStep.prepare,
      );
    }

    if (!inputs.hasAccountScopedData ||
        inputs.isSyncing ||
        inputs.isBackgroundMode) {
      _redirectScheduled = false;
      return const _IronwoodMigrationLoadingShell(
        step: IronwoodMigrationFlowStep.prepare,
      );
    }

    if (inputs.hasSyncFailure) {
      _go(
        '/home',
        toast: 'Sync could not finish. Try again once Vizor is synced.',
      );
      return const _IronwoodMigrationLoadingShell(
        step: IronwoodMigrationFlowStep.prepare,
      );
    }

    final statusAsync = ref.watch(ironwoodMigrationStatusProvider(request));
    return statusAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _IronwoodMigrationLoadingShell(
        step: IronwoodMigrationFlowStep.prepare,
      ),
      error: (_, _) {
        _go('/home', toast: "Couldn't verify migration status.");
        return const _IronwoodMigrationLoadingShell(
          step: IronwoodMigrationFlowStep.prepare,
        );
      },
      data: (status) {
        if (_routeShouldResumeMigration(status)) {
          _go('/migration/private/status');
        } else if (inputs.hasOrchardFunds &&
            _routeShouldStartMigration(status.phase)) {
          _go('/migration/intro');
        } else {
          _go('/home', toast: 'Migration is not needed for this account.');
        }
        return const _IronwoodMigrationLoadingShell(
          step: IronwoodMigrationFlowStep.prepare,
        );
      },
    );
  }
}

class IronwoodMigrationPrivateStatusScreen extends ConsumerWidget {
  const IronwoodMigrationPrivateStatusScreen({this.previewStatus, super.key});

  final rust_sync.MigrationStatus? previewStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewStatus;
    if (preview != null) {
      if (_isEmptyCompletedMigrationStatus(preview)) {
        return const _RedirectTo('/home');
      }
      final previewAccountUuid = ref
          .watch(accountProvider)
          .value
          ?.activeAccountUuid;
      return _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: _IronwoodMigrationPrivateStatusContent(
          status: preview,
          accountUuid: previewAccountUuid,
        ),
      );
    }

    final inputs = ref.watch(ironwoodMigrationInputsProvider);
    final request = inputs.statusRequest;
    if (!inputs.ironwoodActiveAtTip || request == null) {
      return _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: const _IronwoodMigrationPrivateStatusErrorContent(),
      );
    }

    final statusAsync = ref.watch(ironwoodMigrationStatusProvider(request));
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    return statusAsync.when(
      skipLoadingOnReload: true,
      loading: () => _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: const _IronwoodMigrationPrivateStatusErrorContent(),
      ),
      data: (status) {
        final coordinatedStatus = coordinator.statuses[request.accountUuid];
        final effectiveStatus =
            status.activeRunId == null &&
                kIronwoodMigrationStartPhases.contains(status.phase) &&
                coordinatedStatus?.activeRunId != null
            ? coordinatedStatus!
            : status;
        if (_isEmptyCompletedMigrationStatus(effectiveStatus)) {
          return const _RedirectTo('/home');
        }
        if (effectiveStatus.activeRunId == null &&
            kIronwoodMigrationStartPhases.contains(effectiveStatus.phase)) {
          if (coordinator.advancingAccounts.contains(request.accountUuid)) {
            return _IronwoodMigrationFrame(
              toolbar: _privateStatusToolbar(context),
              disableSidebarActions: true,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return _IronwoodMigrationFrame(
            toolbar: _privateStatusToolbar(context),
            disableSidebarActions: true,
            child: const _IronwoodMigrationPrivateStatusErrorContent(),
          );
        }
        return _IronwoodMigrationFrame(
          toolbar: _privateStatusToolbar(context),
          disableSidebarActions: true,
          child: _IronwoodMigrationPrivateStatusContent(
            status: effectiveStatus,
            accountUuid: request.accountUuid,
          ),
        );
      },
    );
  }
}

void _invalidateIronwoodMigrationStatusState(
  WidgetRef ref, {
  IronwoodMigrationStatusRequest? statusRequest,
}) {
  if (statusRequest != null) {
    ref.invalidate(ironwoodMigrationStatusProvider(statusRequest));
  }
  ref.invalidate(ironwoodMigrationRouteCtaProvider);
  ref.invalidate(ironwoodHomeMigrationCtaProvider);
  ref.invalidate(ironwoodMigrationFlowDataProvider);
  ref.invalidate(ironwoodMigrationPrivatePlanProvider);
}
