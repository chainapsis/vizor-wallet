// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/voting/screens/mobile/mobile_voting_screens.dart';
import '../src/features/voting/screens/voting_polls_screen.dart';
import '../src/features/voting/screens/voting_proposal_detail_screen.dart';
import '../src/features/voting/screens/voting_results_screen.dart';
import '../src/features/voting/screens/voting_review_screen.dart';
import '../src/features/voting/screens/voting_software_account_guard.dart';
import '../src/features/voting/screens/voting_status_screen.dart';
import '../src/features/voting/screens/voting_submission_confirmation_screen.dart';
import '../src/features/voting/widgets/voting_metadata_widgets.dart';
import '../src/features/voting/widgets/voting_pane_scroll_area.dart';
import '../src/features/voting/voting_flow_models.dart';
import '../src/features/voting/voting_resume_plan.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/voting/voting_config_provider.dart';
import '../src/providers/voting/voting_config_source_provider.dart';
import '../src/providers/voting/voting_participation_provider.dart';
import '../src/providers/voting/voting_pir_warmup_provider.dart';
import '../src/providers/voting/voting_tree_sync_provider.dart';
import '../src/providers/voting/voting_poll_eligibility_provider.dart';
import '../src/providers/voting/voting_round_visibility_provider.dart';
import '../src/providers/voting/voting_rounds_provider.dart';
import '../src/providers/voting/voting_service_providers.dart';
import '../src/providers/voting/voting_session_provider.dart';
import '../src/providers/voting/voting_snapshot_warmup_provider.dart';
import '../src/providers/voting/voting_state.dart';
import '../src/providers/voting/voting_submission_job_provider.dart';
import '../src/services/voting/pir_snapshot_resolver.dart';
import '../src/services/voting/voting_api_client.dart';
import '../src/services/voting/voting_config_loader.dart';
import '../src/services/voting/voting_http.dart';
import '../src/services/voting/voting_models.dart';
import '../src/rust/third_party/zcash_voting/config.dart' as rust_config;
import '../src/rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../src/rust/third_party/zcash_voting/wire.dart' as rust_wire;
import 'support/wb_layout.dart';
import 'support/wb_voting_dates.dart';
import 'support/wb_sidebar.dart';

// ---------------------------------------------------------------------------
// Review step
// ---------------------------------------------------------------------------

/// How far the review screen's session load got.
enum VotingReviewSessionCase { loaded, loading, failed }

/// Whether this account's voting power is known, and why not when it isn't.
enum VotingReviewEligibilityCase { confirmed, preparing, unavailable, failed }

/// How much of the draft the reviewer answered.
enum VotingReviewAnswersCase { allAnswered, someSkipped, none }

/// Review step: `VotingReviewScreen` (desktop) / `MobileVotingReviewScreen`
/// (mobile), both thin shells over `VotingReviewView`.
Widget votingReviewFixture({
  required WbLayout layout,
  VotingReviewSessionCase session = VotingReviewSessionCase.loaded,
  VotingReviewEligibilityCase eligibility =
      VotingReviewEligibilityCase.confirmed,
  VotingReviewAnswersCase answers = VotingReviewAnswersCase.allAnswered,
}) {
  return _votingScreenHost(
    overrides: [
      votingSessionProvider.overrideWith2(
        (roundId) => _PreviewVotingSessionNotifier(
          roundId,
          _reviewSessionState(eligibility),
          loading: session == VotingReviewSessionCase.loading,
          loadError: session == VotingReviewSessionCase.failed
              ? 'the voting service did not respond.'
              : null,
          // The view refreshes eligible weight from a post-frame callback; a
          // pending future keeps "Preparing voting power." on screen.
          eligibleWeightPending:
              eligibility == VotingReviewEligibilityCase.preparing,
        ),
      ),
      votingDraftProvider.overrideWith2(
        (key) => _PreviewVotingDraftNotifier(key, _reviewChoices(answers)),
      ),
    ],
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(const VotingReviewScreen(roundId: _previewRoundId))
        : WbFrame(
            layout: layout,
            child: const MobileVotingReviewScreen(roundId: _previewRoundId),
          ),
  );
}

VotingSessionState _reviewSessionState(
  VotingReviewEligibilityCase eligibility,
) {
  return VotingSessionState(
    roundId: _previewRoundId,
    accountUuid: _previewAccountUuid,
    phase: switch (eligibility) {
      VotingReviewEligibilityCase.confirmed => VotingSessionPhase.readyToVote,
      VotingReviewEligibilityCase.preparing => VotingSessionPhase.idle,
      // Not one of the phases that prepares voting power, so the view reports
      // it as unavailable instead of pending.
      VotingReviewEligibilityCase.unavailable =>
        VotingSessionPhase.resolvingPir,
      VotingReviewEligibilityCase.failed => VotingSessionPhase.error,
    },
    round: _previewRoundDetails,
    config: _previewVotingConfig,
    eligibleWeightZatoshi: eligibility == VotingReviewEligibilityCase.confirmed
        ? _previewVotingPowerZatoshi
        : null,
    error: eligibility == VotingReviewEligibilityCase.failed
        ? const VotingSessionError(
            message:
                'Voting eligibility could not be checked for this account.',
          )
        : null,
  );
}

Map<int, int> _reviewChoices(VotingReviewAnswersCase answers) {
  return switch (answers) {
    VotingReviewAnswersCase.allAnswered => const {1: 1, 2: 2},
    VotingReviewAnswersCase.someSkipped => const {1: 1},
    VotingReviewAnswersCase.none => const {},
  };
}

// ---------------------------------------------------------------------------
// Submission confirmation
// ---------------------------------------------------------------------------

/// How far the confirmation screen's session load got.
enum VotingConfirmationSessionCase {
  loaded,
  loading,
  failedWithReceipt,
  failedWithoutReceipt,
}

/// What the confirmation screen concluded about this submission.
enum VotingConfirmationOutcomeCase {
  confirmed,
  notComplete,
  checkingEligibility,
  eligibilityNotConfirmed,
  refreshFailed,
}

/// Submission confirmation: `VotingSubmissionConfirmationScreen` (desktop) /
/// `MobileVotingSubmissionConfirmationScreen` (mobile).
Widget votingConfirmationFixture({
  required WbLayout layout,
  VotingConfirmationSessionCase session = VotingConfirmationSessionCase.loaded,
  VotingConfirmationOutcomeCase outcome =
      VotingConfirmationOutcomeCase.confirmed,
}) {
  final state = _confirmationSessionState(outcome);
  final failsAfterReceipt =
      session == VotingConfirmationSessionCase.failedWithReceipt;
  final initialSession = switch (session) {
    VotingConfirmationSessionCase.loading =>
      const AsyncValue<VotingSessionState>.loading(),
    VotingConfirmationSessionCase.failedWithoutReceipt =>
      AsyncValue<VotingSessionState>.error(
        _confirmationLoadError,
        StackTrace.empty,
      ),
    // The cached-receipt branch needs one data frame before the failure.
    _ => AsyncValue<VotingSessionState>.data(state),
  };
  final refresh = switch (outcome) {
    VotingConfirmationOutcomeCase.eligibilityNotConfirmed =>
      _PreviewEligibleWeightRefresh.resolvesUnconfirmed,
    VotingConfirmationOutcomeCase.refreshFailed =>
      _PreviewEligibleWeightRefresh.fails,
    _ => _PreviewEligibleWeightRefresh.pending,
  };
  return _votingScreenHost(
    overrides: [
      _previewConfirmationSessionProvider.overrideWith(
        () => _PreviewConfirmationSessionNotifier(initialSession),
      ),
      votingSubmissionJobSessionProvider.overrideWith(
        (ref, key) => ref.watch(_previewConfirmationSessionProvider),
      ),
      votingSubmissionSessionProvider.overrideWith2(
        (key) => _PreviewVotingSubmissionSessionNotifier(
          key,
          state,
          refresh: refresh,
        ),
      ),
      votingSubmissionJobsProvider.overrideWith(
        _PreviewVotingSubmissionJobsNotifier.new,
      ),
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
    ],
    builder: (context) {
      final screen = layout == WbLayout.desktop
          ? _desktopWindow(
              const VotingSubmissionConfirmationScreen(
                roundId: _previewRoundId,
                accountUuid: _previewAccountUuid,
              ),
            )
          : WbFrame(
              layout: layout,
              child: const MobileVotingSubmissionConfirmationScreen(
                roundId: _previewRoundId,
                accountUuid: _previewAccountUuid,
              ),
            );
      return failsAfterReceipt
          ? _VotingConfirmationLoadFailure(child: screen)
          : screen;
    },
  );
}

/// The receipt's voting-power row is coupled to the outcome, not a knob:
/// a confirmed receipt is only reachable with eligible weight, and every
/// other outcome renders 'Not available'.
VotingSessionState _confirmationSessionState(
  VotingConfirmationOutcomeCase outcome,
) {
  final confirmedPower = outcome == VotingConfirmationOutcomeCase.confirmed;
  return VotingSessionState(
    roundId: _previewRoundId,
    accountUuid: _previewAccountUuid,
    phase: VotingSessionPhase.done,
    round: _previewRoundDetails,
    roundPlan: outcome == VotingConfirmationOutcomeCase.notComplete
        ? _incompleteRoundPlan
        : _completedRoundPlan,
    eligibleWeightZatoshi: confirmedPower ? _previewVotingPowerZatoshi : null,
  );
}

/// Session the confirmation screen reads, as a notifier so the cached-receipt
/// case can hand the view data first and the load error second — the only way
/// that branch of the screen is reachable.
final _previewConfirmationSessionProvider =
    NotifierProvider<
      _PreviewConfirmationSessionNotifier,
      AsyncValue<VotingSessionState>
    >(
      () => _PreviewConfirmationSessionNotifier(
        const AsyncValue<VotingSessionState>.loading(),
      ),
    );

class _PreviewConfirmationSessionNotifier
    extends Notifier<AsyncValue<VotingSessionState>> {
  _PreviewConfirmationSessionNotifier(this._initial);

  final AsyncValue<VotingSessionState> _initial;

  @override
  AsyncValue<VotingSessionState> build() => _initial;

  void fail(Object error) => state = AsyncValue.error(error, StackTrace.empty);
}

/// Fails the preview session one frame after the screen has seen its receipt.
class _VotingConfirmationLoadFailure extends ConsumerStatefulWidget {
  const _VotingConfirmationLoadFailure({required this.child});

  final Widget child;

  @override
  ConsumerState<_VotingConfirmationLoadFailure> createState() =>
      _VotingConfirmationLoadFailureState();
}

class _VotingConfirmationLoadFailureState
    extends ConsumerState<_VotingConfirmationLoadFailure> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(_previewConfirmationSessionProvider.notifier)
          .fail(_confirmationLoadError);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _confirmationLoadError = 'the voting service did not respond.';

// ---------------------------------------------------------------------------
// Submit status
// ---------------------------------------------------------------------------

/// Which submission step the status screen is reporting.
enum VotingStatusStepCase {
  waitingForWalletSync,
  preparing,
  delegating,
  castingVotes,
  submittingShares,
  finalizing,
  complete,
}

/// Whether the voting account signs in software or on a Keystone.
enum VotingStatusAccountCase { software, keystone }

/// What went wrong, if anything.
///
/// The four PIR cases are the round's snapshot lookup failing. Which line the
/// session reports depends on what the endpoint probes answered, so each one
/// carries the diagnostics that produce it.
enum VotingStatusProblemCase {
  none,
  couldNotStart,
  jobFailed,
  jobFailedClearable,
  softwareAccountRequired,
  pirDataBehind,
  pirDataAhead,
  pirUnreachable,
  pirNoMatch,
}

/// Whether the vote step reports a question count or an indeterminate bar.
enum VotingStatusVoteProgressCase { questionCount, indeterminate }

/// Submit status: `VotingStatusScreen` (desktop) / `MobileVotingStatusScreen`
/// (mobile), the latter injecting the mobile progress and Keystone screens.
Widget votingStatusFixture({
  required WbLayout layout,
  VotingStatusStepCase step = VotingStatusStepCase.delegating,
  VotingStatusAccountCase account = VotingStatusAccountCase.software,
  VotingStatusProblemCase problem = VotingStatusProblemCase.none,
  VotingStatusVoteProgressCase voteProgress =
      VotingStatusVoteProgressCase.questionCount,
}) {
  final hardware = account == VotingStatusAccountCase.keystone;
  final state = _statusSessionState(
    step: step,
    hardware: hardware,
    voteProgress: voteProgress,
    sessionError: problem == VotingStatusProblemCase.jobFailed,
    pirFailure: _statusPirFailure(problem),
  );
  return _votingStatusScreen(
    layout: layout,
    session: problem == VotingStatusProblemCase.couldNotStart
        ? const AsyncValue<VotingSessionState>.loading()
        : AsyncValue.data(state),
    job: VotingSubmissionJobState(
      // The completed step keeps the job idle: a `complete` job routes the
      // screen straight to the confirmation surface.
      status: problem == VotingStatusProblemCase.jobFailedClearable
          ? VotingSubmissionJobStatus.error
          : step == VotingStatusStepCase.complete
          ? VotingSubmissionJobStatus.idle
          : VotingSubmissionJobStatus.running,
      errorMessage: problem == VotingStatusProblemCase.jobFailedClearable
          ? 'Submitting this vote failed before it reached the vote server.'
          : null,
      softwareAccountRequired:
          problem == VotingStatusProblemCase.softwareAccountRequired,
    ),
    startError: problem == VotingStatusProblemCase.couldNotStart
        ? "Couldn't start the voting session for this account."
        : null,
  );
}

/// The PIR snapshot failure a problem case stands for: the line the session
/// reports plus the probe results that produced it.
///
/// The session, not the status screen, formats this line, so the preview
/// carries the same four sentences `_pirSnapshotMismatchMessage` builds.
({String message, List<PirSnapshotEndpointDiagnostic> diagnostics})?
_statusPirFailure(VotingStatusProblemCase problem) {
  PirSnapshotEndpointDiagnostic probe(
    String host,
    PirSnapshotEndpointStatus status, {
    int? reportedHeight,
  }) {
    return PirSnapshotEndpointDiagnostic(
      endpoint: Uri.parse('https://$host.example/root'),
      status: status,
      reportedHeight: reportedHeight,
    );
  }

  return switch (problem) {
    VotingStatusProblemCase.pirDataBehind => (
      message:
          'Voting PIR data is not ready for this voting round yet. Expected '
          'snapshot block 3,543,600; PIR endpoints report 3,543,100. Retry '
          'once the PIR service catches up.',
      diagnostics: [
        probe(
          'pir-1',
          PirSnapshotEndpointStatus.behind,
          reportedHeight: 3542900,
        ),
        probe(
          'pir-2',
          PirSnapshotEndpointStatus.behind,
          reportedHeight: 3543100,
        ),
      ],
    ),
    VotingStatusProblemCase.pirDataAhead => (
      message:
          'Configured PIR endpoints are ahead of this voting round snapshot. '
          'Expected snapshot block 3,543,600; endpoints report 3,543,900.',
      diagnostics: [
        probe(
          'pir-1',
          PirSnapshotEndpointStatus.ahead,
          reportedHeight: 3543900,
        ),
        probe(
          'pir-2',
          PirSnapshotEndpointStatus.ahead,
          reportedHeight: 3544200,
        ),
      ],
    ),
    VotingStatusProblemCase.pirUnreachable => (
      message:
          "Couldn't reach any configured PIR endpoint. Check your network "
          'connection and retry.',
      diagnostics: [
        probe('pir-1', PirSnapshotEndpointStatus.timeoutOrNetworkError),
        probe('pir-2', PirSnapshotEndpointStatus.timeoutOrNetworkError),
      ],
    ),
    VotingStatusProblemCase.pirNoMatch => (
      message:
          'No PIR endpoint matched this voting round snapshot. Expected '
          // The diagnostics tail is the raw `_pirDiagnosticLog` shape: the
          // enum's own name and an ungrouped height.
          'snapshot block 3,543,600. Diagnostics: '
          'https://pir-1.example/root status=ahead height=3543900; '
          'https://pir-2.example/root status=malformedJson.',
      diagnostics: [
        probe(
          'pir-1',
          PirSnapshotEndpointStatus.ahead,
          reportedHeight: 3543900,
        ),
        probe('pir-2', PirSnapshotEndpointStatus.malformedJson),
      ],
    ),
    _ => null,
  };
}

VotingSessionState _statusSessionState({
  required VotingStatusStepCase step,
  required bool hardware,
  required VotingStatusVoteProgressCase voteProgress,
  required bool sessionError,
  ({String message, List<PirSnapshotEndpointDiagnostic> diagnostics})?
  pirFailure,
}) {
  final counted = voteProgress == VotingStatusVoteProgressCase.questionCount;
  final voteStepDone =
      step == VotingStatusStepCase.finalizing ||
      step == VotingStatusStepCase.complete;
  final sharingStep = step == VotingStatusStepCase.submittingShares;
  return VotingSessionState(
    roundId: _previewRoundId,
    accountUuid: _previewAccountUuid,
    phase: sessionError || pirFailure != null
        ? VotingSessionPhase.error
        : switch (step) {
            VotingStatusStepCase.waitingForWalletSync =>
              VotingSessionPhase.waitingForWalletSync,
            VotingStatusStepCase.preparing => VotingSessionPhase.resolvingPir,
            VotingStatusStepCase.delegating => VotingSessionPhase.delegating,
            VotingStatusStepCase.castingVotes =>
              VotingSessionPhase.castingVotes,
            VotingStatusStepCase.submittingShares =>
              VotingSessionPhase.submittingShares,
            VotingStatusStepCase.finalizing =>
              VotingSessionPhase.submittingShares,
            VotingStatusStepCase.complete => VotingSessionPhase.done,
          },
    round: _previewRoundDetails,
    roundPlan: step == VotingStatusStepCase.complete
        ? _completedRoundPlan
        : _incompleteRoundPlan,
    isHardwareAccount: hardware,
    eligibleWeightZatoshi: _previewVotingPowerZatoshi,
    walletScannedHeight: step == VotingStatusStepCase.waitingForWalletSync
        ? 3540000
        : null,
    walletSnapshotHeight: step == VotingStatusStepCase.waitingForWalletSync
        ? 3543600
        : null,
    walletChainTipHeight: step == VotingStatusStepCase.waitingForWalletSync
        ? 3544100
        : null,
    delegationProgress: step == VotingStatusStepCase.delegating
        ? const {
            0: VotingSessionProgress(
              phase: VotingProgressPhase.proofProgress,
              proofProgress: 0.45,
            ),
          }
        : const {},
    // Casting and share submission share one step row, so the share step
    // reports the helper-delivery message the row falls back to instead of a
    // question count.
    currentVoteKey: sharingStep ? _previewVoteKey : null,
    voteProgress: sharingStep ? _previewShareProgress : const {},
    voteSubmissionTotalCount: voteStepDone || (counted && !sharingStep) ? 4 : 0,
    voteSubmissionCompletedCount: voteStepDone
        ? 4
        : counted && !sharingStep
        ? 1
        : 0,
    voteSubmissionProgress: voteStepDone
        ? 1
        : sharingStep
        ? 0.75
        : counted
        ? 0.25
        : null,
    error: pirFailure != null
        ? VotingSessionError(
            message: pirFailure.message,
            pirDiagnostics: pirFailure.diagnostics,
          )
        : sessionError
        ? const VotingSessionError(
            message: 'Voting could not continue for this account.',
          )
        : null,
    pirDiagnostics: pirFailure?.diagnostics ?? const [],
  );
}

// ---------------------------------------------------------------------------
// Desktop Keystone signing panel
// ---------------------------------------------------------------------------

/// Whether the signing QR is ready to scan.
enum VotingKeystoneQrCase { preparing, ready, failed }

/// How many bundles this QR covers.
enum VotingKeystoneBundlesCase { single, batch }

/// How many bundle memos accompany the QR.
enum VotingKeystoneMemosCase { none, one, pager }

/// Desktop Keystone signing panel inside `VotingStatusScreen`: a hardware
/// account in the Keystone signing phase with no mobile Keystone builder.
Widget votingKeystoneSigningPanelFixture({
  VotingKeystoneQrCase qr = VotingKeystoneQrCase.ready,
  VotingKeystoneBundlesCase bundles = VotingKeystoneBundlesCase.single,
  VotingKeystoneMemosCase memos = VotingKeystoneMemosCase.one,
  bool scanError = false,
  bool skipAction = false,
}) {
  final batch = bundles == VotingKeystoneBundlesCase.batch;
  return _votingStatusScreen(
    layout: WbLayout.desktop,
    session: AsyncValue.data(
      VotingSessionState(
        roundId: _previewRoundId,
        accountUuid: _previewAccountUuid,
        phase: VotingSessionPhase.keystoneSigning,
        round: _previewRoundDetails,
        roundPlan: _keystoneRoundPlan,
        isHardwareAccount: true,
        eligibleWeightZatoshi: _previewVotingPowerZatoshi,
        keystoneSigningRequests: [_previewKeystoneSigningRequest(skipAction)],
        // A signed prefix is what earns the Skip action.
        keystoneSignatures: skipAction
            ? {0: _previewKeystoneSignature}
            : const {},
        keystoneScanError: scanError
            ? 'That QR was not a signed voting response. Try again.'
            : null,
      ),
    ),
    job: VotingSubmissionJobState(
      status: VotingSubmissionJobStatus.waitingForKeystone,
      keystoneUrParts: qr == VotingKeystoneQrCase.ready
          ? const [_previewVotingKeystoneUr]
          : const [],
      keystoneBatchMemos: switch (memos) {
        VotingKeystoneMemosCase.none => const [],
        VotingKeystoneMemosCase.one => const [_previewKeystoneMemoOne],
        VotingKeystoneMemosCase.pager => const [
          _previewKeystoneMemoOne,
          _previewKeystoneMemoTwo,
        ],
      },
      keystoneBatchMessageCount: batch ? 2 : 1,
      keystoneBatchTotalCount: batch ? 3 : 1,
      keystoneQrError: qr == VotingKeystoneQrCase.failed
          ? "Couldn't build the signing QR for this bundle."
          : null,
    ),
  );
}

rust_delegate.KeystoneSigningRequest _previewKeystoneSigningRequest(
  bool multiBundle,
) {
  return rust_delegate.KeystoneSigningRequest(
    pcztBytes: Uint8List(0),
    redactedPcztBytes: Uint8List(0),
    pcztSighash: Uint8List(32),
    rk: Uint8List(32),
    actionIndex: 0,
    displayMemo: _previewKeystoneMemoOne.displayMemo,
    eligibleWeightZatoshi: _previewVotingPowerZatoshi,
    delegatedWeightZatoshi: _previewVotingPowerZatoshi,
    bundleCount: multiBundle ? 3 : 1,
    bundleIndex: 0,
  );
}

const _previewKeystoneMemoOne = VotingKeystoneBatchMemo(
  bundleIndex: 0,
  bundleCount: 3,
  displayMemo: 'Voting power: 0.375 ZEC\nRound: Snack governance 3',
);

const _previewKeystoneMemoTwo = VotingKeystoneBatchMemo(
  bundleIndex: 1,
  bundleCount: 3,
  displayMemo: 'Voting power: 0.125 ZEC\nRound: Snack governance 3',
);

final _previewKeystoneSignature = rust_wire.KeystoneSignatureRecord(
  bundleIndex: 0,
  sig: Uint8List(64),
  sighash: Uint8List(32),
  rk: Uint8List(32),
);

const _previewVotingKeystoneUr =
    'ur:zcash-sign-batch/1-1/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcx';

Widget _votingStatusScreen({
  required WbLayout layout,
  required AsyncValue<VotingSessionState> session,
  required VotingSubmissionJobState job,
  String? startError,
}) {
  return _votingScreenHost(
    overrides: [
      votingSubmissionJobsProvider.overrideWith(
        () => _PreviewVotingSubmissionJobsNotifier(
          startErrorsByRoundId: startError == null
              ? const {}
              : {_previewRoundId: startError},
        ),
      ),
      votingSubmissionJobProvider.overrideWith2(
        (key) =>
            _PreviewVotingSubmissionJobNotifier(key, job.copyWith(key: key)),
      ),
      votingSubmissionJobSessionProvider.overrideWith((ref, key) => session),
    ],
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(
            VotingStatusScreen(
              roundId: _previewRoundId,
              accountUuid: _previewAccountUuid,
              onOpenKeystoneFirmware: () {},
            ),
          )
        : WbFrame(
            layout: layout,
            child: MobileVotingStatusScreen(
              roundId: _previewRoundId,
              accountUuid: _previewAccountUuid,
              onOpenKeystoneFirmware: () {},
            ),
          ),
  );
}

// ---------------------------------------------------------------------------
// Account guard
// ---------------------------------------------------------------------------

/// What the account boundary is showing.
enum VotingGuardAccountCase { loading, failed }

/// Account boundary: `VotingSoftwareAccountGuard` (desktop) /
/// `MobileVotingAccountGuard` (mobile).
Widget votingAccountGuardFixture({
  required WbLayout layout,
  VotingGuardAccountCase account = VotingGuardAccountCase.loading,
}) {
  return _votingScreenHost(
    overrides: [
      accountProvider.overrideWith(() => _PreviewGuardAccountNotifier(account)),
    ],
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(
            const VotingSoftwareAccountGuard(child: SizedBox.shrink()),
          )
        : WbFrame(
            layout: layout,
            child: const MobileVotingAccountGuard(child: SizedBox.shrink()),
          ),
  );
}

class _PreviewGuardAccountNotifier extends AccountNotifier {
  _PreviewGuardAccountNotifier(this.account);

  final VotingGuardAccountCase account;

  @override
  Future<AccountState> build() {
    if (account == VotingGuardAccountCase.loading) {
      return Completer<AccountState>().future;
    }
    // Thrown, not returned as a failed future: the guard then has its error on
    // the first frame instead of one microtask later.
    throw 'the account store could not be opened.';
  }
}

// ---------------------------------------------------------------------------
// Poll list
// ---------------------------------------------------------------------------

/// Which rounds the list holds.
enum VotingPollRoundsCase { rounds, mixedEligibility, snapshotUsed, empty }

/// How far the rounds load got.
enum VotingPollLoadCase { loaded, loading, failed }

/// Poll list: `VotingPollsScreen` (desktop) / `MobileVotingPollsScreen`
/// (mobile), both wrapping `VotingPollsView`.
Widget votingPollListFixture({
  required WbLayout layout,
  VotingPollRoundsCase rounds = VotingPollRoundsCase.rounds,
  VotingPollLoadCase load = VotingPollLoadCase.loaded,
}) {
  final mixed =
      rounds == VotingPollRoundsCase.mixedEligibility ||
      rounds == VotingPollRoundsCase.snapshotUsed;
  return _votingPollsScreen(
    layout: layout,
    overrides: _votingPollListOverrides(
      rounds: switch (rounds) {
        VotingPollRoundsCase.empty => const [],
        _ when mixed => _previewMixedEligibilityRounds,
        _ => _previewPollListRounds,
      },
      loading: load == VotingPollLoadCase.loading,
      failed: load == VotingPollLoadCase.failed,
      eligibility: (roundId) async =>
          mixed && roundId == _previewIneligibleRoundId
          ? VotingPollEligibility.ineligible
          : VotingPollEligibility.eligible,
      participationUnavailable: (roundId) =>
          rounds == VotingPollRoundsCase.snapshotUsed &&
          roundId == _previewActiveRoundId,
    ),
  );
}

// ---------------------------------------------------------------------------
// Poll card
// ---------------------------------------------------------------------------

/// The card's own status, from `_PollCardState`.
enum VotingPollCardState { inProgress, active, voted, tallying, closed }

/// Which date the round carries. The card's 'Closes' / 'Closed' wording
/// follows the status knob, so this axis only picks which date exists.
enum VotingPollCardDate { endDate, startDate, none }

/// What the mobile card knows about this account's eligibility. The desktop
/// card never reads it, and the mobile card reads it only while active.
enum VotingPollCardEligibility {
  eligible,
  ineligible,
  alreadyUsed,
  checking,
  checkFailed,
}

/// One poll card, driven through the real list so the card stays private:
/// `_DesktopPollCard` / `_MobilePollCard` on a one-round preview list.
Widget votingPollCardFixture({
  required WbLayout layout,
  VotingPollCardState state = VotingPollCardState.active,
  VotingPollCardDate date = VotingPollCardDate.endDate,
  VotingPollCardEligibility eligibility = VotingPollCardEligibility.eligible,
  bool forumLink = true,
  bool emptyText = false,
  VotingExternalUriLauncher launchExternalUri = _previewExternalUriNoop,
}) {
  final round = VotingRoundView(
    roundId: _previewActiveRoundId,
    title: emptyText ? '' : 'NU7 Scope',
    status: switch (state) {
      VotingPollCardState.tallying => 'tallying',
      VotingPollCardState.closed => 'closed',
      _ => 'active',
    },
    voted: state == VotingPollCardState.voted,
    inProgress: state == VotingPollCardState.inProgress,
    rawJson: {
      if (!emptyText)
        'description':
            'This vote concerns the scope of NU7. It is one component of '
            "governance, but it represents the coinholders' view about "
            'NSM, supply, and release timing.',
      if (date == VotingPollCardDate.endDate)
        'vote_end_time': state == VotingPollCardState.closed ||
                state == VotingPollCardState.tallying
            ? '2026-08-24T12:00:00Z'
            : wbVotingActiveEndTime,
      if (date == VotingPollCardDate.startDate)
        'ceremony_phase_start': '2026-08-01T12:00:00Z',
      if (forumLink)
        'forum_url': 'https://forum.zcashcommunity.com/t/nu7-scope',
    },
  );
  return VotingExternalUriLauncherScope(
    launcher: launchExternalUri,
    child: _votingPollsScreen(
      layout: layout,
      overrides: _votingPollListOverrides(
        rounds: [round],
        eligibility: (_) => switch (eligibility) {
          VotingPollCardEligibility.ineligible => Future.value(
            VotingPollEligibility.ineligible,
          ),
          VotingPollCardEligibility.checking =>
            Completer<VotingPollEligibility>().future,
          VotingPollCardEligibility.checkFailed => Future.error(
            'the voting service did not answer the eligibility check.',
            StackTrace.empty,
          ),
          _ => Future.value(VotingPollEligibility.eligible),
        },
        participationUnavailable: (_) =>
            eligibility == VotingPollCardEligibility.alreadyUsed,
      ),
    ),
  );
}

Future<void> _previewExternalUriNoop(Uri _) async {}

Widget _votingPollsScreen({
  required WbLayout layout,
  required List<Override> overrides,
}) {
  return _votingScreenHost(
    overrides: overrides,
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(const VotingPollsScreen())
        : WbFrame(layout: layout, child: const MobileVotingPollsScreen()),
  );
}

/// The override set `buildMobileVotingPollsUseCase` proved renders the poll
/// list with no wallet, network, or Rust work.
List<Override> _votingPollListOverrides({
  required List<VotingRoundView> rounds,
  bool loading = false,
  bool failed = false,
  required Future<VotingPollEligibility> Function(String roundId) eligibility,
  required bool Function(String roundId) participationUnavailable,
}) {
  return [
    votingParticipationUnavailableProvider.overrideWith(
      (ref, roundId) => participationUnavailable(roundId),
    ),
    votingPollEligibilityProvider.overrideWith(
      (ref, roundId) => eligibility(roundId),
    ),
    votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
    votingRoundsProvider.overrideWith(
      () => _PreviewPollListRoundsNotifier(
        rounds: rounds,
        loading: loading,
        failed: failed,
      ),
    ),
    votingConfigSourceProvider.overrideWith(
      _PreviewVotingConfigSourceNotifier.new,
    ),
    showTestVotingRoundsProvider.overrideWith(
      _PreviewShowTestVotingRoundsNotifier.new,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Proposal detail
// ---------------------------------------------------------------------------

/// How far the detail screen's session load got.
enum VotingDetailSessionCase { loaded, loading, failed, roundUnavailable }

/// Which content branch the loaded session selects.
enum VotingDetailBranchCase {
  activePoll,
  voted,
  voteInProgress,
  redirectToResults,
}

/// What the session knows about this account's voting power.
enum VotingDetailPowerCase { ready, preparing, unavailable }

/// Proposal detail: `VotingProposalDetailScreen` (desktop) /
/// `MobileVotingProposalDetailScreen` (mobile), both over
/// `VotingProposalDetailView`.
Widget votingProposalDetailFixture({
  required WbLayout layout,
  VotingDetailSessionCase session = VotingDetailSessionCase.loaded,
  VotingDetailBranchCase branch = VotingDetailBranchCase.activePoll,
  VotingDetailPowerCase power = VotingDetailPowerCase.ready,
}) {
  return _votingScreenHost(
    key: ValueKey((layout, session, branch, power)),
    overrides: [
      votingParticipationUnavailableProvider.overrideWith(
        (ref, roundId) => false,
      ),
      votingPollEligibilityProvider.overrideWith(
        (ref, roundId) async => VotingPollEligibility.eligible,
      ),
      // The view prepares voting power from a post-frame callback; the real
      // coordinator would open the wallet DB to answer it.
      votingParticipationProvider.overrideWith(
        _PreviewVotingParticipationCoordinator.new,
      ),
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingConfigSourceProvider.overrideWith(
        _PreviewVotingConfigSourceNotifier.new,
      ),
      votingSessionProvider.overrideWith2(
        (roundId) => _PreviewVotingSessionNotifier(
          roundId,
          _detailSessionState(branch: branch, power: power, session: session),
          loading: session == VotingDetailSessionCase.loading,
          loadError: session == VotingDetailSessionCase.failed
              ? 'the voting service did not respond.'
              : null,
          eligibleWeightPending: power == VotingDetailPowerCase.preparing,
        ),
      ),
      votingDraftProvider.overrideWith2(
        (key) => _PreviewVotingDraftNotifier(key, const {1: 1}),
      ),
    ],
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(
            const VotingProposalDetailScreen(roundId: _previewRoundId),
          )
        : WbFrame(
            layout: layout,
            child: const MobileVotingProposalDetailScreen(
              roundId: _previewRoundId,
            ),
          ),
  );
}

VotingSessionState _detailSessionState({
  required VotingDetailBranchCase branch,
  required VotingDetailPowerCase power,
  VotingDetailSessionCase session = VotingDetailSessionCase.loaded,
}) {
  return VotingSessionState(
    roundId: _previewRoundId,
    accountUuid: _previewAccountUuid,
    // `idle` is one of the phases that prepares voting power, so it is what
    // keeps the preparing spinner on screen; `resolvingPir` is not, so the
    // view reports unavailable instead of pending.
    phase: switch (power) {
      VotingDetailPowerCase.ready => VotingSessionPhase.readyToVote,
      VotingDetailPowerCase.preparing => VotingSessionPhase.idle,
      VotingDetailPowerCase.unavailable => VotingSessionPhase.resolvingPir,
    },
    round: session == VotingDetailSessionCase.roundUnavailable
        ? null
        : branch == VotingDetailBranchCase.redirectToResults
        ? _previewClosedRoundDetails
        : _previewRoundDetails,
    roundPlan: switch (branch) {
      VotingDetailBranchCase.voted => _votedRoundPlan,
      VotingDetailBranchCase.voteInProgress => _recoveringRoundPlan,
      _ => _incompleteRoundPlan,
    },
    eligibleWeightZatoshi: power == VotingDetailPowerCase.ready
        ? _previewVotingPowerZatoshi
        : null,
  );
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// What the vote server answered for this round's tally.
enum VotingResultsTallyCase { results, loading, pending, failed }

/// Whether this account's own choice is in the tally.
enum VotingResultsVotedCase { voted, notVoted }

/// How many proposals the round carries.
enum VotingResultsProposalsCase { some, none }

/// Results: `VotingResultsScreen` (desktop) / `MobileVotingResultsScreen`
/// (mobile), both over `VotingResultsView`.
Widget votingResultsScreenFixture({
  required WbLayout layout,
  VotingResultsTallyCase tally = VotingResultsTallyCase.results,
  VotingResultsVotedCase voted = VotingResultsVotedCase.voted,
  VotingResultsProposalsCase proposals = VotingResultsProposalsCase.some,
}) {
  final round = proposals == VotingResultsProposalsCase.some
      ? (tally == VotingResultsTallyCase.pending
            ? _previewTallyingRoundDetails
            : _previewClosedRoundDetails)
      : _previewProposalFreeRoundDetails;
  return _votingScreenHost(
    overrides: [
      // The tally sits behind a file-private provider, so it is driven from
      // below: the API client the round-tally future reads.
      votingApiClientProvider.overrideWith(
        (ref, servers) => _PreviewVotingApiClient(tally),
      ),
      votingConfigProvider.overrideWith(_PreviewResultsConfigNotifier.new),
      votingSessionProvider.overrideWith2(
        (roundId) => _PreviewVotingSessionNotifier(
          roundId,
          VotingSessionState(
            roundId: _previewRoundId,
            accountUuid: _previewAccountUuid,
            phase: VotingSessionPhase.done,
            round: round,
            roundPlan: voted == VotingResultsVotedCase.voted
                ? _votedRoundPlan
                : _incompleteRoundPlan,
            eligibleWeightZatoshi: _previewVotingPowerZatoshi,
          ),
        ),
      ),
    ],
    builder: (context) => layout == WbLayout.desktop
        ? _desktopWindow(const VotingResultsScreen(roundId: _previewRoundId))
        : WbFrame(
            layout: layout,
            child: const MobileVotingResultsScreen(roundId: _previewRoundId),
          ),
  );
}

/// Answers the round-tally read without a socket. Subclassing keeps the real
/// `VotingApiClient` type the provider family hands the screen.
class _PreviewVotingApiClient extends VotingApiClient {
  _PreviewVotingApiClient(this.tally)
    : super(baseUrl: _previewVoteServerUri, httpClient: _previewHttpClient);

  final VotingResultsTallyCase tally;

  @override
  Future<VotingRoundTally> getRoundTally(String roundId) {
    return switch (tally) {
      VotingResultsTallyCase.loading => Completer<VotingRoundTally>().future,
      VotingResultsTallyCase.pending => Future.error(
        VotingHttpException(
          uri: _previewVoteServerUri,
          statusCode: 404,
          body: 'tally not ready',
        ),
        StackTrace.empty,
      ),
      VotingResultsTallyCase.failed => Future.error(
        'the vote server did not answer the tally request.',
        StackTrace.empty,
      ),
      VotingResultsTallyCase.results => Future.value(
        VotingRoundTally(roundId: roundId, rawJson: _previewTallyJson),
      ),
    };
  }
}

/// Never called: `_PreviewVotingApiClient` answers before any transport.
class _PreviewVotingHttpClient implements VotingHttpClient {
  const _PreviewVotingHttpClient();

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) => Completer<VotingHttpResponse>().future;

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) => Completer<VotingHttpResponse>().future;
}

// ---------------------------------------------------------------------------
// Expandable text
// ---------------------------------------------------------------------------

/// How much text the widget is given.
enum VotingExpandableTextCase { short, long, empty }

/// Which toggle copy the call site asks for.
enum VotingExpandableControlsCase { viewMore, showDescription }

/// `VotingExpandableText` at a fixed width, so 'long' really overflows.
Widget votingExpandableTextFixture(
  BuildContext context, {
  VotingExpandableTextCase text = VotingExpandableTextCase.long,
  VotingExpandableControlsCase controls = VotingExpandableControlsCase.viewMore,
  bool toggleWhenItFits = false,
}) {
  final showDescription =
      controls == VotingExpandableControlsCase.showDescription;
  return ColoredBox(
    color: context.colors.background.ground,
    child: Center(
      child: SizedBox(
        width: 360,
        child: VotingExpandableText(
          text: switch (text) {
            VotingExpandableTextCase.short => 'A short round description.',
            VotingExpandableTextCase.long => _previewExpandableLongText,
            VotingExpandableTextCase.empty => '',
          },
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.primary,
          ),
          collapsedLabel: showDescription ? 'Show description' : 'View more',
          expandedLabel: showDescription ? 'Hide description' : 'View less',
          buttonAlignment: showDescription
              ? Alignment.centerLeft
              : Alignment.centerRight,
          showToggleWhenNotOverflowing: toggleWhenItFits,
        ),
      ),
    ),
  );
}

const _previewExpandableLongText =
    'This vote concerns the scope of NU7. It is one component of governance, '
    "but it represents the coinholders' view about issuance smoothing, "
    'supply, and release timing. Already in NU7, established by prior '
    'consensus, are the features listed in the forum thread linked above.';

// ---------------------------------------------------------------------------
// Pane primitives
// ---------------------------------------------------------------------------

/// Which shared voting pane primitive is on screen.
enum VotingPanePrimitiveCase {
  loading,
  stateView,
  listView,
  scrollView,
  centeredScrollView,
}

/// The voting pane primitives in isolation. The scrollbar's edge gap comes
/// from `kAppFormFactor`, so each lane previews its own gap.
Widget votingPanePrimitiveFixture(
  BuildContext context, {
  VotingPanePrimitiveCase primitive = VotingPanePrimitiveCase.loading,
  double backLinkMinWidth = 0,
}) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.base,
    // `VotingPaneStateView`'s toolbar resolves its back label from the router.
    child: InheritedGoRouter(
      goRouter: _previewPaneRouter,
      child: switch (primitive) {
        VotingPanePrimitiveCase.loading => const VotingPaneLoading(),
        VotingPanePrimitiveCase.stateView => VotingPaneStateView(
          backLinkMinWidth: backLinkMinWidth,
          child: const VotingPaneLoading(),
        ),
        VotingPanePrimitiveCase.listView => VotingPaneListView.separated(
          maxWidth: 480,
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: 12,
          itemBuilder: (context, index) =>
              _VotingPanePlaceholderRow(label: 'Voting round ${index + 1}'),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        ),
        VotingPanePrimitiveCase.scrollView => VotingPaneScrollView(
          maxWidth: 480,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              for (var index = 0; index < 12; index++) ...[
                _VotingPanePlaceholderRow(label: 'Section ${index + 1}'),
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
        ),
        VotingPanePrimitiveCase.centeredScrollView =>
          VotingPaneCenteredScrollView(
            maxWidth: 480,
            minHeight: 400,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: const _VotingPanePlaceholderRow(
              label: 'Centered pane content',
            ),
          ),
      },
    ),
  );
}

/// Detached router: the pane toolbar reads `GoRouter.of(context)` while it
/// builds, and answers 'Home' because this router cannot pop.
final GoRouter _previewPaneRouter = GoRouter(
  routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
);

class _VotingPanePlaceholderRow extends StatelessWidget {
  const _VotingPanePlaceholderRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 64,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Text(
        label,
        style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile voting scaffold
// ---------------------------------------------------------------------------

/// The six titles the mobile voting routes give the scaffold.
enum VotingScaffoldTitleCase {
  polls,
  voted,
  review,
  submit,
  submitted,
  results,
}

/// `MobileVotingScaffold` with placeholder content, so the nav band and the
/// body padding are the only things on screen.
Widget votingMobileScaffoldFixture(
  BuildContext context, {
  VotingScaffoldTitleCase title = VotingScaffoldTitleCase.polls,
  bool horizontalPadding = false,
}) {
  return WbFrame(
    layout: WbLayout.mobile,
    // The back action only reaches the router when tapped; the detached
    // instance keeps a reviewer's tap from throwing.
    child: InheritedGoRouter(
      goRouter: _previewPaneRouter,
      child: MobileVotingScaffold(
        title: switch (title) {
          VotingScaffoldTitleCase.polls => 'Coinholder voting',
          VotingScaffoldTitleCase.voted => 'Voted',
          VotingScaffoldTitleCase.review => 'Review your answers',
          VotingScaffoldTitleCase.submit => 'Submit vote',
          VotingScaffoldTitleCase.submitted => 'Vote submitted',
          VotingScaffoldTitleCase.results => 'Voting results',
        },
        horizontalPadding: horizontalPadding ? AppSpacing.sm : 0,
        child: const _VotingPanePlaceholderRow(label: 'Screen content'),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared preview host
// ---------------------------------------------------------------------------

/// Every voting screen here either sits in `AppDesktopShell` with the real
/// `AppMainSidebar` (which reads `GoRouterState`) or navigates on tap, so the
/// fixtures run inside a throwaway router with the routes they can reach.
Widget _votingScreenHost({
  Key? key,
  required List<Override> overrides,
  required WidgetBuilder builder,
}) {
  return ProviderScope(
    key: key,
    // No retry: Riverpod's default backoff reloads a failed provider, which
    // would turn a preview's error state back into a spinner.
    retry: (_, _) => null,
    overrides: [..._previewShellOverrides(), ...overrides],
    child: Builder(
      builder: (context) => VotingExternalUriLauncherScope(
        launcher: VotingExternalUriLauncherScope.maybeOf(context) ??
            _previewExternalUriNoop,
        child: VotingDisplayTimeScope(
          now: wbVotingReferenceDate,
          child: _VotingScreenHostApp(builder: builder),
        ),
      ),
    ),
  );
}

Widget _desktopWindow(Widget child) {
  return Center(child: WbDesktopWindowBox(child: child));
}

class _VotingScreenHostApp extends StatefulWidget {
  const _VotingScreenHostApp({required this.builder});

  final WidgetBuilder builder;

  @override
  State<_VotingScreenHostApp> createState() => _VotingScreenHostAppState();
}

class _VotingScreenHostAppState extends State<_VotingScreenHostApp> {
  // Built once; the route reads `widget.builder` so a knob change still
  // reaches the screen.
  late final GoRouter _router = GoRouter(
    initialLocation: '/voting',
    routes: [
      GoRoute(
        path: '/voting',
        builder: (context, _) => widget.builder(context),
      ),
      for (final path in const [
        ...wbSidebarPaths,
        '/voting/keystone/scan',
        '/voting/poll/:roundId',
        '/voting/poll/:roundId/review',
        '/voting/poll/:roundId/status',
        '/voting/poll/:roundId/submitted',
        '/voting/poll/:roundId/results',
      ])
        if (path != '/voting')
          GoRoute(
            path: path,
            builder: (_, _) => _VotingPreviewRouteTarget(path: path),
          ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Landing surface for a preview that navigates away, so a redirect reads as
/// one instead of as a blank canvas.
class _VotingPreviewRouteTarget extends StatelessWidget {
  const _VotingPreviewRouteTarget({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.base,
      child: Center(
        child: Text(
          'Preview navigated to $path',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

/// The provider floor `AppMainSidebar` needs to build without wallet, sync,
/// network, or migration I/O.
List<Override> _previewShellOverrides() {
  return [
    wbSidebarActions,
    wbPostMigrationState,
    votingTreePreSyncProvider.overrideWith(_PreviewVotingTreePreSync.new),
    appBootstrapProvider.overrideWithValue(_previewBootstrap),
    syncProvider.overrideWith(_PreviewSyncNotifier.new),
    networkPrivacyProvider.overrideWith(_PreviewNetworkPrivacyNotifier.new),
    swapFeatureEnabledProvider.overrideWithValue(true),
    ironwoodHomeMigrationPresentationProvider.overrideWithValue(
      const IronwoodHomeMigrationCtaState.hidden(),
    ),
    ironwoodMigrationCoordinatorProvider.overrideWith(
      _PreviewMigrationCoordinator.new,
    ),
    // The polls and detail screens kick off a warm-up pass from `initState`,
    // which would resolve a real wallet DB path and call the vote servers.
    votingPirWarmupProvider.overrideWith(_PreviewVotingPirWarmup.new),
  ];
}

/// States the fixtures' offline behaviour instead of relying on the preview
/// config's empty server list plus the coordinator's swallowed exception.
class _PreviewVotingPirWarmup extends VotingPirWarmupCoordinator {
  _PreviewVotingPirWarmup(super.ref);

  @override
  Future<void> maybeWarmActiveRounds() async {}
}

class _PreviewVotingTreePreSync extends VotingTreePreSyncService {
  _PreviewVotingTreePreSync(super.ref);

  @override
  Future<void> preSyncRound(String roundId) async {}
}

final _previewBootstrap = AppBootstrapState(
  initialLocation: '/voting',
  initialAccountState: _previewAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _previewAccountState = AccountState(
  accounts: [
    AccountInfo(uuid: _previewAccountUuid, name: 'Demo wallet', order: 0),
  ],
  activeAccountUuid: _previewAccountUuid,
  activeAddress: 'u1previewvotingaddress',
);

class _PreviewSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _previewAccountUuid,
    hasAccountScopedData: true,
    isSyncComplete: true,
    percentage: 1,
    scannedHeight: 3544100,
    chainTipHeight: 3544100,
  );

  @override
  Future<void> refreshAfterAccountSwitch() async {}
}

class _PreviewNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

class _PreviewMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

// ---------------------------------------------------------------------------
// Preview notifiers
// ---------------------------------------------------------------------------

/// How a preview session answers the screens' eligible-weight refresh.
enum _PreviewEligibleWeightRefresh { pending, resolvesUnconfirmed, fails }

class _PreviewVotingSessionNotifier extends VotingSessionNotifier {
  _PreviewVotingSessionNotifier(
    super.roundId,
    this._state, {
    this.loading = false,
    this.loadError,
    this.eligibleWeightPending = false,
  });

  final VotingSessionState _state;
  final bool loading;
  final String? loadError;
  final bool eligibleWeightPending;

  @override
  Future<VotingSessionState> build() {
    if (loading) return Completer<VotingSessionState>().future;
    // Thrown, not returned as a failed future: the screen then has its error
    // on the first frame instead of one microtask later.
    final error = loadError;
    if (error != null) throw error;
    return Future<VotingSessionState>.value(_state);
  }

  @override
  Future<BigInt?> refreshEligibleWeight() {
    if (eligibleWeightPending) return Completer<BigInt?>().future;
    return Future<BigInt?>.value(_state.eligibleWeightZatoshi);
  }

  @override
  Future<VotingSnapshotWarmupResult> precomputeSnapshotBundles({
    required String accountUuid,
  }) async => const VotingSnapshotWarmupResult.ready();
}

class _PreviewVotingSubmissionSessionNotifier
    extends VotingSubmissionSessionNotifier {
  _PreviewVotingSubmissionSessionNotifier(
    super.key,
    this._state, {
    this.refresh = _PreviewEligibleWeightRefresh.pending,
  });

  final VotingSessionState _state;
  final _PreviewEligibleWeightRefresh refresh;

  @override
  Future<VotingSessionState> build() async => _state;

  @override
  Future<BigInt?> refreshEligibleWeight() {
    return switch (refresh) {
      _PreviewEligibleWeightRefresh.pending => Completer<BigInt?>().future,
      _PreviewEligibleWeightRefresh.resolvesUnconfirmed =>
        Future<BigInt?>.value(null),
      _PreviewEligibleWeightRefresh.fails => Future<BigInt?>.error(
        'the vote server did not answer the eligibility check.',
        StackTrace.empty,
      ),
    };
  }

  @override
  Future<VotingSnapshotWarmupResult> precomputeSnapshotBundles({
    required String accountUuid,
  }) async => const VotingSnapshotWarmupResult.ready();
}

class _PreviewVotingDraftNotifier extends VotingDraftNotifier {
  _PreviewVotingDraftNotifier(super.key, this._choices);

  final Map<int, int> _choices;

  @override
  VotingDraftState build() => VotingDraftState(choices: _choices);

  @override
  Future<VotingDraftState> ensureLoaded() async => state;

  @override
  Future<void> clearAll() async {}
}

class _PreviewVotingSubmissionJobsNotifier
    extends VotingSubmissionJobsNotifier {
  _PreviewVotingSubmissionJobsNotifier({this.startErrorsByRoundId = const {}});

  final Map<String, String> startErrorsByRoundId;

  @override
  VotingSubmissionJobsState build() =>
      VotingSubmissionJobsState(startErrorsByRoundId: startErrorsByRoundId);

  @override
  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) async {
    if (accountUuid == null) return null;
    return VotingSessionKey(roundId: roundId, accountUuid: accountUuid);
  }

  @override
  Future<void> retry(VotingSessionKey key) async {}

  @override
  void dismiss(VotingSessionKey key) {}

  @override
  Future<void> handleKeystoneBatchSignResponse(
    VotingSessionKey key,
    List<int> responseCbor,
  ) async {}

  @override
  Future<void> skipRemainingKeystoneBundles(VotingSessionKey key) async {}
}

class _PreviewVotingSubmissionJobNotifier extends VotingSubmissionJobNotifier {
  _PreviewVotingSubmissionJobNotifier(super.key, this._state);

  final VotingSubmissionJobState _state;

  @override
  VotingSubmissionJobState build() => _state;

  @override
  Future<void> start() async {}

  @override
  Future<void> retry() async {}

  @override
  void dismiss() {}
}

class _PreviewVotingConfigNotifier extends VotingConfigNotifier {
  @override
  Future<rust_config.ResolvedVotingConfig> build() async =>
      _previewVotingConfig;

  @override
  Future<void> refresh() async {}
}

class _PreviewVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => const [];

  @override
  Future<void> reload() async {
    state = const AsyncData([]);
  }
}

class _PreviewPollListRoundsNotifier extends VotingRoundsNotifier {
  _PreviewPollListRoundsNotifier({
    required this.rounds,
    this.loading = false,
    this.failed = false,
  });

  final List<VotingRoundView> rounds;
  final bool loading;
  final bool failed;

  @override
  Future<List<VotingRoundView>> build() {
    if (loading) return Completer<List<VotingRoundView>>().future;
    if (failed) throw _pollListLoadError;
    return Future<List<VotingRoundView>>.value(rounds);
  }

  // Settles instead of throwing: the screen's entry refresh awaits this and an
  // error would escape as an unhandled future.
  @override
  Future<void> reload() async {
    if (loading) return;
    state = failed
        ? AsyncValue.error(_pollListLoadError, StackTrace.empty)
        : AsyncValue.data(rounds);
  }
}

const _pollListLoadError = 'the voting service did not respond.';

class _PreviewVotingConfigSourceNotifier extends VotingConfigSourceNotifier {
  @override
  Future<VotingConfigSourceState> build() async =>
      const VotingConfigSourceState(
        sourceUrl: kDefaultStaticVotingConfigSource,
        isDefault: true,
      );
}

class _PreviewShowTestVotingRoundsNotifier
    extends ShowTestVotingRoundsNotifier {
  @override
  Future<bool> build() async => false;
}

class _PreviewVotingParticipationCoordinator
    extends VotingParticipationCoordinator {
  _PreviewVotingParticipationCoordinator(super.ref);

  @override
  Future<void> checkRound(
    String round, {
    bool force = false,
    VotingRoundDetails? knownRound,
    bool Function()? isHomeCurrent,
  }) async {}
}

class _PreviewResultsConfigNotifier extends VotingConfigNotifier {
  @override
  Future<rust_config.ResolvedVotingConfig> build() async =>
      _previewResultsVotingConfig;

  @override
  Future<void> refresh() async {}
}

// ---------------------------------------------------------------------------
// Preview round data
// ---------------------------------------------------------------------------

const _previewRoundId = 'snack-governance-active';
const _previewVoteKey = VotingVoteKey(bundleIndex: 0, proposalId: 1);
final _previewShareProgress = {
  _previewVoteKey: const VotingSessionProgress(
    phase: VotingProgressPhase.submitting,
    message: 'Delivering share 3 of 5 to helper servers',
  ),
};
const _previewAccountUuid = '550e8400-e29b-41d4-a716-446655440000';
final _previewVotingPowerZatoshi = BigInt.from(37500000);

final _previewRoundDetails = VotingRoundDetails(
  roundId: _previewRoundId,
  title: '[TEST] Very Serious Snack Governance 3',
  status: 'active',
  snapshotHeight: 3543600,
  eaPk: Uint8List(32),
  ncRoot: Uint8List(32),
  nullifierImtRoot: Uint8List(32),
  rawJson: _previewRoundJson,
);

final _previewRoundJson = <String, dynamic>{
  'title': '[TEST] Very Serious Snack Governance 3',
  'status': 'active',
  'snapshot_height': 3543600,
  'vote_end_time': wbVotingActiveEndTime,
  'forum_url': 'https://forum.zcashcommunity.com/t/snack-governance',
  'proposals': [
    {
      'id': 1,
      'title': 'Official Snack of the Next Team Sync',
      'zip_number': 'ZIP-2033',
      'description':
          'Which snack should be recognized as the official snack of the '
          'next team sync?',
      'options': [
        {'index': 1, 'label': 'Option 1'},
        {'index': 2, 'label': 'Option 2'},
        {'index': 3, 'label': 'Option 3'},
      ],
    },
    {
      'id': 2,
      'title': 'Cadence of the Team Sync',
      'zip_number': 'ZIP-2034',
      'description': 'How often should the team sync happen?',
      'options': [
        {'index': 1, 'label': 'Every week'},
        {'index': 2, 'label': 'Every other week'},
        {'index': 3, 'label': 'Abstain'},
      ],
    },
  ],
};

// --- Poll list rounds ------------------------------------------------------

const _previewActiveRoundId = 'nu7-scope-active';
const _previewIneligibleRoundId = 'nu7-scope-ineligible';

final _previewPollListRounds = [
  VotingRoundView(
    roundId: _previewActiveRoundId,
    title: 'NU7 Scope',
    status: 'active',
    rawJson: _previewPollListRoundJson,
  ),
  VotingRoundView(
    roundId: 'nu7-scope-voted',
    title: 'NSM Issuance Smoothing',
    status: 'active',
    voted: true,
    rawJson: _previewPollListRoundJson,
  ),
  VotingRoundView(
    roundId: 'nu7-scope-closed',
    title: 'Official Snack of the Next Team Sync',
    status: 'closed',
    rawJson: {
      ..._previewPollListRoundJson,
      'vote_end_time': '2026-08-24T12:00:00Z',
    },
  ),
];

/// One ineligible row beside the eligible ones, so the list shows both.
final _previewMixedEligibilityRounds = [
  VotingRoundView(
    roundId: _previewIneligibleRoundId,
    title: 'NU7 Scope',
    status: 'active',
    rawJson: _previewPollListRoundJson,
  ),
  ..._previewPollListRounds,
];

final _previewPollListRoundJson = <String, dynamic>{
  'description':
      'This vote concerns the scope of NU7. It is one component of '
      "governance, but it represents the coinholders' view about NSM, "
      'supply, and release timing.',
  'vote_end_time': wbVotingActiveEndTime,
  'forum_url': 'https://forum.zcashcommunity.com/t/nu7-scope',
};

// --- Detail and results rounds ---------------------------------------------

final _previewClosedRoundDetails = _previewRoundDetailsWith(
  status: 'closed',
  json: {
    ..._previewRoundJson,
    'status': 'closed',
    'vote_end_time': '2026-08-24T12:00:00Z',
  },
);

final _previewTallyingRoundDetails = _previewRoundDetailsWith(
  status: 'tallying',
  json: {
    ..._previewRoundJson,
    'status': 'tallying',
    'vote_end_time': '2026-08-24T12:00:00Z',
  },
);

final _previewProposalFreeRoundDetails = _previewRoundDetailsWith(
  status: 'closed',
  json: {
    ..._previewRoundJson,
    'status': 'closed',
    'vote_end_time': '2026-08-24T12:00:00Z',
  }..remove('proposals'),
);

VotingRoundDetails _previewRoundDetailsWith({
  required String status,
  required Map<String, dynamic> json,
}) {
  return VotingRoundDetails(
    roundId: _previewRoundId,
    title: '[TEST] Very Serious Snack Governance 3',
    status: status,
    snapshotHeight: 3543600,
    eaPk: Uint8List(32),
    ncRoot: Uint8List(32),
    nullifierImtRoot: Uint8List(32),
    rawJson: json,
  );
}

/// Tally envelope shaped like the vote server's `tally-results` response.
const _previewTallyJson = <String, dynamic>{
  'round_id': _previewRoundId,
  'results': [
    {
      'proposal_id': 1,
      'entries': {'1': 7880, '2': 80, '3': 40},
    },
    {
      'proposal_id': 2,
      'entries': {'1': 1200, '2': 6600, '3': 200},
    },
  ],
};

final _previewVoteServerUri = Uri.parse('https://vote.example.org');
const _previewHttpClient = _PreviewVotingHttpClient();

/// The results screen asserts the round is authenticated and resolves an API
/// server set, neither of which the empty preview config can answer.
final _previewResultsVotingConfig = rust_config.ResolvedVotingConfig(
  sourceFingerprint: 'preview-source',
  trustedKeyFingerprint: 'preview-key',
  dynamicConfigFingerprint: 'preview-config',
  voteServers: [
    rust_config.ServiceEndpoint(
      url: _previewVoteServerUri.toString(),
      label: 'Preview vote server',
    ),
  ],
  pirEndpoints: const [],
  pirLayout: const rust_config.PirLayout(
    pirDepth: 19,
    tier0Layers: 12,
    tier1Layers: 7,
    polyLen: 4096,
  ),
  supportedVersions: const rust_config.SupportedVersions(
    pir: [],
    voteProtocol: 'preview',
    tally: 'preview',
    voteServer: 'preview',
  ),
  authenticatedRounds: [
    rust_config.AuthenticatedRound(
      roundId: _previewRoundId,
      eaPk: Uint8List(32),
    ),
  ],
  skippedRoundIds: const [],
  conditions: const [],
);

final _completedRoundPlan = _roundPlan(completed: true);
final _incompleteRoundPlan = _roundPlan(completed: false);
final _keystoneRoundPlan = _previewRoundPlan(
  primaryAction: rust_wire.RoundPlanActionKind.delegate,
  delegationStatuses: [
    for (var index = 0; index < 3; index++)
      rust_wire.DelegationStatusView(
        bundleIndex: index,
        phase: rust_wire.WorkflowPhaseView.prepared,
        terminal: false,
      ),
  ],
  delegationBundlesNeedingWork: Uint32List.fromList(const [0, 1, 2]),
  delegationBundlesNeedingSigning: Uint32List.fromList(const [0, 1, 2]),
  needsDelegationSigning: true,
);

/// A submitted vote the detail and results screens can display.
final _votedRoundPlan = _previewRoundPlan(
  hotkeyBound: true,
  completedVoteArtifact: true,
  completedForDisplay: true,
  completedVoteDisplay: rust_wire.CompletedVoteDisplayView(
    choices: const [
      rust_wire.CompletedVoteChoiceView(proposalId: 1, choice: 1),
      rust_wire.CompletedVoteChoiceView(proposalId: 2, choice: 2),
    ],
    votedAt: BigInt.from(1787313600),
  ),
  primaryAction: rust_wire.RoundPlanActionKind.done,
  immediateShareConfirmed: true,
  allDecided: true,
);

/// Local progress the app has to finish before it accepts another vote.
final _recoveringRoundPlan = _previewRoundPlan(
  pendingRecovery: true,
  blockingRecovery: true,
  hotkeyBound: true,
  completedVoteArtifact: true,
  completedForDisplay: false,
  primaryAction: rust_wire.RoundPlanActionKind.vote,
  immediateShareConfirmed: false,
  allDecided: false,
);

rust_wire.RoundPlanView _roundPlan({required bool completed}) {
  return _previewRoundPlan(
    hotkeyBound: completed,
    completedVoteArtifact: completed,
    completedForDisplay: completed,
    primaryAction: completed
        ? rust_wire.RoundPlanActionKind.done
        : rust_wire.RoundPlanActionKind.idle,
    immediateShareConfirmed: completed,
    allDecided: completed,
  );
}

rust_wire.RoundPlanView _previewRoundPlan({
  bool pendingRecovery = false,
  bool blockingRecovery = false,
  bool blockingShareWork = false,
  bool hasUnconfirmedShares = false,
  bool hotkeyBound = false,
  bool completedVoteArtifact = false,
  bool completedForDisplay = false,
  rust_wire.CompletedVoteDisplayView? completedVoteDisplay,
  bool needsDraftSetup = false,
  bool needsBundleSetup = false,
  bool needsDelegationSigning = false,
  bool hasInFlightDelegation = false,
  Uint32List? delegationBundlesNeedingWork,
  Uint32List? delegationBundlesNeedingSigning,
  bool needsVotePolling = false,
  bool hasRemainingVoteOrShareWork = false,
  bool hasRecoverableVoteOrShareWork = false,
  rust_wire.RoundPlanActionKind primaryAction =
      rust_wire.RoundPlanActionKind.idle,
  List<rust_wire.DelegationStatusView> delegationStatuses = const [],
  bool immediateShareConfirmed = false,
  bool allDecided = false,
}) {
  return rust_wire.RoundPlanView(
    roundId: _previewRoundId,
    pendingRecovery: pendingRecovery,
    blockingRecovery: blockingRecovery,
    blockingShareWork: blockingShareWork,
    hasUnconfirmedShares: hasUnconfirmedShares,
    hotkeyBound: hotkeyBound,
    completedVoteArtifact: completedVoteArtifact,
    completedForDisplay: completedForDisplay,
    completedVoteDisplay: completedVoteDisplay,
    needsDraftSetup: needsDraftSetup,
    needsBundleSetup: needsBundleSetup,
    needsDelegationSigning: needsDelegationSigning,
    hasInFlightDelegation: hasInFlightDelegation,
    delegationBundlesNeedingWork: delegationBundlesNeedingWork ?? Uint32List(0),
    delegationBundlesNeedingSigning:
        delegationBundlesNeedingSigning ?? Uint32List(0),
    needsVotePolling: needsVotePolling,
    hasRemainingVoteOrShareWork: hasRemainingVoteOrShareWork,
    hasRecoverableVoteOrShareWork: hasRecoverableVoteOrShareWork,
    primaryAction: primaryAction,
    nextSteps: const [],
    delegationStatuses: delegationStatuses,
    recoveredDelegationWork: const [],
    recoveredVoteWork: const [],
    openProposals: Uint32List(0),
    unrosteredIntents: Uint32List(0),
    immediateShareConfirmed: immediateShareConfirmed,
    allDecided: allDecided,
  );
}

const _previewVotingConfig = rust_config.ResolvedVotingConfig(
  sourceFingerprint: 'preview-source',
  trustedKeyFingerprint: 'preview-key',
  dynamicConfigFingerprint: 'preview-config',
  voteServers: [],
  pirEndpoints: [],
  pirLayout: rust_config.PirLayout(
    pirDepth: 19,
    tier0Layers: 12,
    tier1Layers: 7,
    polyLen: 4096,
  ),
  supportedVersions: rust_config.SupportedVersions(
    pir: [],
    voteProtocol: 'preview',
    tally: 'preview',
    voteServer: 'preview',
  ),
  authenticatedRounds: [],
  skippedRoundIds: [],
  conditions: [],
);
