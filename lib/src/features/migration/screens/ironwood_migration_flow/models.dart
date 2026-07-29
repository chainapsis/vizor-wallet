part of '../ironwood_migration_flow_screen.dart';

enum IronwoodMigrationFlowStep {
  prepare,
  intro,
  howItWorks,
  whatToExpect,
  options,
  review,
  immediateReview,
}

enum IronwoodMigrationReviewPreviewStage { review, analyzing }

const _privateStatusStartVerificationTimeout = Duration(seconds: 2);
const _defaultMigrationAnalyzingMinimumDuration = Duration(seconds: 6);
const _keystoneMigrationProofPollInterval = Duration(seconds: 1);
const _scheduledBlockProgressCap = 0.70;
const _migrationEstimatedSecondsPerBlock = 75;
const _migrationPrepareConfirmationBlocks = 3;
const _keystoneMigrationSignBatchResultUrType = 'zcash-batch-sig-result';
const _keystoneMigrationLegacySignResultUrType = 'zcash-sign-result';
const _keystoneMigrationFirmwareUpdateError =
    'Update Keystone firmware to sign Ironwood migrations, then try again.';
const _ironwoodMigrationIntroBannerLightAsset =
    'assets/illustrations/ironwood_migration_intro_banner_light.png';
const _ironwoodMigrationIntroBannerDarkAsset =
    'assets/illustrations/ironwood_migration_intro_banner_dark.png';
const _ironwoodMigrationHowStepAssets = [
  'assets/illustrations/ironwood_migration_how_step_1.png',
  'assets/illustrations/ironwood_migration_how_step_2.png',
  'assets/illustrations/ironwood_migration_how_step_3.png',
];
const _ironwoodMigrationExpectationRunningAsset =
    'assets/illustrations/ironwood_migration_expect_running.png';
const _ironwoodMigrationExpectationAssets = [
  'assets/illustrations/ironwood_migration_expect_time.png',
  'assets/illustrations/ironwood_migration_expect_spend.png',
  'assets/illustrations/ironwood_migration_expect_privacy.png',
  _ironwoodMigrationExpectationRunningAsset,
];

final ironwoodMigrationAnalyzingMinimumDurationProvider = Provider<Duration>(
  (_) => _defaultMigrationAnalyzingMinimumDuration,
);
// Keystone encodes firmware 2.5.1 as [12, 5, 1]. This is the batch-signing
// protocol floor; raise it if the first stable Ironwood release requires more.
const _keystoneIronwoodBatchMinimumFirmwareVersion = [12, 5, 1];

@visibleForTesting
bool ironwoodMigrationKeystoneFirmwareSupportsBatch(List<int> version) {
  if (version.length < _keystoneIronwoodBatchMinimumFirmwareVersion.length) {
    return false;
  }
  for (
    var i = 0;
    i < _keystoneIronwoodBatchMinimumFirmwareVersion.length;
    i++
  ) {
    final actual = version[i];
    final minimum = _keystoneIronwoodBatchMinimumFirmwareVersion[i];
    if (actual != minimum) return actual > minimum;
  }
  return true;
}

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

final ironwoodMigrationImmediatePlanProvider =
    FutureProvider.autoDispose<rust_sync.OrchardMigrationImmediatePlan?>((
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
          .immediatePlan(
            network: request.network,
            accountUuid: request.accountUuid,
          );
    });

typedef IronwoodActiveMigrationImmediatePlanRequest = ({
  String network,
  String accountUuid,
  String runId,
  int observedHeight,
  String revision,
});

IronwoodActiveMigrationImmediatePlanRequest
ironwoodActiveMigrationImmediatePlanRequest({
  required String network,
  required String accountUuid,
  required rust_sync.MigrationStatus status,
  required int observedHeight,
}) {
  return (
    network: network,
    accountUuid: accountUuid,
    runId: status.activeRunId ?? '',
    observedHeight: observedHeight,
    revision: [
      status.phase,
      status.denominationConfirmationCount,
      status.denominationSplitCompletedCount,
      status.pendingTxCount,
      status.broadcastedTxCount,
      status.confirmedTxCount,
      for (final broadcast in status.scheduledBroadcasts)
        '${broadcast.txidHex}:${broadcast.status}',
      for (final part in status.parts)
        '${part.partIndex}:${part.state.name}:${part.txidHex}:'
            '${part.confirmationCount}',
    ].join('|'),
  );
}

/// Re-evaluates Immediate conversion availability for the current active-run
/// snapshot.
///
/// This is intentionally separate from [ironwoodMigrationImmediatePlanProvider]:
/// the review provider can retain a plan calculated before the private run
/// locked or spent its inputs. The run progress revision makes meaningful
/// coordinator/status changes re-check the run-scoped spendable notes without
/// keying on an unstable FFI object identity.
final ironwoodActiveMigrationImmediatePlanProvider = FutureProvider.autoDispose
    .family<
      rust_sync.OrchardMigrationImmediatePlan?,
      IronwoodActiveMigrationImmediatePlanRequest
    >((ref, request) async {
      if (request.runId.isEmpty) return null;
      return ref
          .watch(ironwoodMigrationServiceProvider)
          .immediatePlan(
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
