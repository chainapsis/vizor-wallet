part of '../ironwood_migration_flow_screen.dart';

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
