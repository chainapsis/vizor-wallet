import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Colors,
        CircularProgressIndicator,
        Dialog,
        Divider,
        LinearProgressIndicator,
        showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/primitives.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../providers/ironwood_migration_announcement_provider.dart';
import '../providers/ironwood_migration_coordinator_provider.dart';
import '../services/ironwood_migration_service.dart';

part 'ironwood_migration_flow/keystone_signing.dart';
part 'ironwood_migration_flow/shell_steps.dart';
part 'ironwood_migration_flow/review_content.dart';
part 'ironwood_migration_flow/migration_batch_chart.dart';
part 'ironwood_migration_flow/status_content.dart';
part 'ironwood_migration_flow/preparing_status.dart';
part 'ironwood_migration_flow/review_plan_cards.dart';
part 'ironwood_migration_flow/transfer_status.dart';
part 'ironwood_migration_flow/shared_components.dart';

enum IronwoodMigrationFlowStep { prepare, intro, howItWorks, options, review }

enum IronwoodMigrationReviewPreviewStage { review, analyzing }

const _privateStatusStartVerificationTimeout = Duration(seconds: 2);
const _defaultMigrationAnalyzingMinimumDuration = Duration(seconds: 6);
const _keystoneMigrationProofPollInterval = Duration(seconds: 1);
const _prepareBroadcastCommitProgress = 0.30;
const _scheduledBlockProgressCap = 0.70;
const _broadcastCommitProgressCap = 0.92;
const _migrationEstimatedSecondsPerBlock = 75;
const _migrationPrepareConfirmationBlocks = 3;
const _migrationPrepareBroadcastBufferBlocks = 1;
const _keystoneMigrationSignBatchResultUrType = 'zcash-batch-sig-result';
const _keystoneMigrationLegacySignResultUrType = 'zcash-sign-result';
const _keystoneMigrationFirmwareUpdateError =
    'Update Keystone firmware to sign Ironwood migrations, then try again.';
const _ironwoodMigrationIntroBannerLightAsset =
    'assets/illustrations/ironwood_migration_intro_banner_light.png';
const _ironwoodMigrationIntroBannerDarkAsset =
    'assets/illustrations/ironwood_migration_intro_banner_dark.png';

final ironwoodMigrationAnalyzingMinimumDurationProvider = Provider<Duration>(
  (_) => _defaultMigrationAnalyzingMinimumDuration,
);

class IronwoodMigrationFlowData {
  const IronwoodMigrationFlowData({
    required this.amountZatoshi,
    required this.accountName,
    required this.profilePictureId,
  });

  final BigInt amountZatoshi;
  final String accountName;
  final String profilePictureId;

  String get amountText =>
      ZecAmount.fromZatoshi(amountZatoshi).balance.amountText;
}

final ironwoodMigrationFlowDataProvider =
    Provider.autoDispose<IronwoodMigrationFlowData?>((ref) {
      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      if (inputs.accountUuid == null) return null;

      final cta = ref.watch(ironwoodHomeMigrationPresentationProvider);
      final status = cta.accountUuid == inputs.accountUuid ? cta.status : null;
      final targetTotal = _sumTargetValues(status);
      final amount = targetTotal > BigInt.zero
          ? targetTotal
          : inputs.orchardBalance + inputs.orchardPendingBalance;

      return IronwoodMigrationFlowData(
        amountZatoshi: amount,
        accountName: inputs.accountName,
        profilePictureId: inputs.profilePictureId,
      );
    });

final ironwoodMigrationPrivatePlanProvider =
    FutureProvider.autoDispose<rust_sync.OrchardMigrationPrivatePlan?>((
      ref,
    ) async {
      final request = ref.watch(
        ironwoodMigrationInputsProvider.select(
          (inputs) => inputs.statusRequest,
        ),
      );
      if (request == null) return null;

      return ref
          .watch(ironwoodMigrationServiceProvider)
          .privatePlan(
            network: request.network,
            accountUuid: request.accountUuid,
          );
    });

BigInt _sumTargetValues(rust_sync.MigrationStatus? status) {
  if (status == null) return BigInt.zero;
  BigInt total = BigInt.zero;
  for (final value in status.targetValuesZatoshi) {
    total += value;
  }
  return total;
}

bool _routeShouldResumeMigration(rust_sync.MigrationStatus status) {
  return status.activeRunId != null ||
      kIronwoodMigrationContinuePhases.contains(status.phase);
}

bool _routeShouldStartMigration(String phase) {
  return kIronwoodMigrationStartPhases.contains(phase);
}

bool _isEmptyCompletedMigrationStatus(rust_sync.MigrationStatus status) {
  return status.phase == kIronwoodMigrationCompletePhase &&
      status.activeRunId == null &&
      status.targetValuesZatoshi.isEmpty &&
      status.parts.isEmpty &&
      status.totalCount == 0;
}

IronwoodMigrationFlowData _fallbackMigrationFlowData() {
  return IronwoodMigrationFlowData(
    amountZatoshi: BigInt.zero,
    accountName: 'Username',
    profilePictureId: kDefaultProfilePictureId,
  );
}

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
