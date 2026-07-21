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

class IronwoodMigrationKeystoneDenominationSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneDenominationSignScreen({
    this.approvedSchedule = const [],
    super.key,
  });

  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.denominations,
      approvedSchedule: approvedSchedule,
    );
  }
}

class IronwoodMigrationKeystoneBatchSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneBatchSignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.batch,
      approvedSchedule: [],
    );
  }
}

class _IronwoodMigrationKeystonePrivateSignScreen
    extends ConsumerStatefulWidget {
  const _IronwoodMigrationKeystonePrivateSignScreen({
    required this.step,
    required this.approvedSchedule,
  });

  final _KeystonePrivateSignStep step;
  final List<rust_sync.MigrationScheduledTransfer> approvedSchedule;

  @override
  ConsumerState<_IronwoodMigrationKeystonePrivateSignScreen> createState() =>
      _IronwoodMigrationKeystonePrivateSignScreenState();
}

enum _KeystonePrivateSignStep { denominations, batch }

extension _KeystonePrivateSignStepCopy on _KeystonePrivateSignStep {
  String get logName => switch (this) {
    _KeystonePrivateSignStep.denominations => 'denominations',
    _KeystonePrivateSignStep.batch => 'batch',
  };

  String get toolbarLabel => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Review migration',
    _KeystonePrivateSignStep.batch => 'Migration status',
  };

  String get previousRoute => switch (this) {
    _KeystonePrivateSignStep.denominations => '/migration/private/review',
    _KeystonePrivateSignStep.batch => '/migration/private/status',
  };

  String get previousButtonLabel => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Back to review',
    _KeystonePrivateSignStep.batch => 'Back to status',
  };

  String get qrTitle => switch (this) {
    _KeystonePrivateSignStep.denominations => 'Sign private split',
    _KeystonePrivateSignStep.batch => 'Sign Ironwood batch',
  };

  String get qrBody => switch (this) {
    _KeystonePrivateSignStep.denominations =>
      'Scan this QR code with Keystone to sign the private split transactions.',
    _KeystonePrivateSignStep.batch =>
      'Scan this QR code with Keystone to sign the Ironwood migration batch.',
  };

  String get messageUnit => switch (this) {
    _KeystonePrivateSignStep.denominations => 'split transaction',
    _KeystonePrivateSignStep.batch => 'migration transaction',
  };

  Future<rust_sync.KeystoneMigrationSigningRequest> prepare(
    IronwoodMigrationService service, {
    required String accountUuid,
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.denominations =>
        service.prepareKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
        ),
      _KeystonePrivateSignStep.batch =>
        service.prepareKeystoneBatchPrivateMigration(accountUuid: accountUuid),
    };
  }

  Future<rust_sync.IronwoodMigrationResult> complete(
    IronwoodMigrationService service, {
    required String accountUuid,
    required String requestId,
    required List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.denominations =>
        service.completeKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
          approvedSchedule: approvedSchedule,
        ),
      _KeystonePrivateSignStep.batch =>
        service.completeKeystoneBatchPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
        ),
    };
  }
}

enum _KeystoneDenominationSignStage {
  preparing,
  showQr,
  scanning,
  waitingForProofs,
  completing,
  failed,
}

class _IronwoodMigrationKeystonePrivateSignScreenState
    extends ConsumerState<_IronwoodMigrationKeystonePrivateSignScreen> {
  _KeystoneDenominationSignStage _stage =
      _KeystoneDenominationSignStage.preparing;
  late final IronwoodMigrationService _migrationService;
  rust_sync.KeystoneMigrationSigningRequest? _request;
  String? _accountUuid;
  List<String> _urParts = const [];
  String? _error;
  Timer? _proofPollTimer;
  rust_sync.KeystoneMigrationProofStatus? _proofStatus;
  List<rust_sync.KeystoneSignedMigrationMessage>? _pendingSignedMessages;
  bool _decoding = false;
  bool _requestCompleted = false;

  @override
  void initState() {
    super.initState();
    _migrationService = ref.read(ironwoodMigrationServiceProvider);
    unawaited(_prepareRequest());
  }

  @override
  void dispose() {
    _stopProofPolling();
    if (!_requestCompleted) {
      final requestId = _request?.requestId;
      if (requestId != null) {
        unawaited(_discardRequest(requestId));
      }
    }
    super.dispose();
  }

  Future<void> _prepareRequest() async {
    _stopProofPolling();
    setState(() {
      _stage = _KeystoneDenominationSignStage.preparing;
      _request = null;
      _accountUuid = null;
      _urParts = const [];
      _error = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
      _decoding = false;
    });

    String? requestIdToDiscard;
    try {
      final accountState = await ref.read(accountProvider.future);
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      final activeAccount = accountState.activeAccount;
      if (activeAccount == null || !activeAccount.isHardware) {
        throw StateError('Active account is not a Keystone account.');
      }

      final request = await widget.step.prepare(
        _migrationService,
        accountUuid: accountUuid,
      );
      requestIdToDiscard = request.requestId;
      if (!mounted) {
        await _discardRequest(request.requestId);
        return;
      }
      if (request.messages.isEmpty) {
        throw StateError('Keystone migration request has no messages.');
      }
      _request = request;
      _accountUuid = accountUuid;
      _startProofPolling(request.requestId);

      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: request.requestId,
        messages: request.messages
            .map(
              (message) => rust_keystone_wallet.ZcashBatchMessageInput(
                id: message.id,
                pcztBytes: message.redactedPczt,
              ),
            )
            .toList(),
        maxFragmentLen: BigInt.from(140),
      );
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.showQr;
        _urParts = urParts;
      });
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'prepare error: $e\n$st',
      );
      _stopProofPolling();
      final requestId = _request?.requestId ?? requestIdToDiscard;
      _request = null;
      _accountUuid = null;
      _proofStatus = null;
      _pendingSignedMessages = null;
      if (requestId != null) {
        unawaited(_discardRequest(requestId));
      }
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.failed;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding ||
        _stage != _KeystoneDenominationSignStage.scanning ||
        _pendingSignedMessages != null) {
      return;
    }
    final request = _request;
    final accountUuid = _accountUuid;
    if (request == null || accountUuid == null) return;

    setState(() {
      _decoding = true;
      _stage = _KeystoneDenominationSignStage.completing;
      _error = null;
    });

    try {
      final decoded = await rust_keystone.decodeZcashBatchSignResponse(
        cbor: result.data,
        expectedRequestId: request.requestId,
        messageIds: request.messages.map((message) => message.id).toList(),
      );
      final signedMessages = _signedMigrationMessagesFor(request, decoded);
      final proofStatus = _proofStatus;
      if (ironwoodMigrationKeystoneProofFailed(proofStatus)) {
        if (!mounted) return;
        setState(() {
          _stage = _KeystoneDenominationSignStage.scanning;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofFailureMessage(proofStatus);
        });
        return;
      }
      if (ironwoodMigrationKeystoneProofShouldWait(proofStatus)) {
        if (!mounted) return;
        setState(() {
          _stage = _KeystoneDenominationSignStage.waitingForProofs;
          _pendingSignedMessages = signedMessages;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofWaitingMessage(proofStatus);
        });
        return;
      }

      await _completeSignedMessages(signedMessages);
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'complete error: $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _stage = _KeystoneDenominationSignStage.scanning;
        _decoding = false;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  void _startProofPolling(String requestId) {
    _stopProofPolling();
    _proofPollTimer = Timer.periodic(
      _keystoneMigrationProofPollInterval,
      (_) => unawaited(_refreshProofStatus(requestId)),
    );
    unawaited(_refreshProofStatus(requestId));
  }

  Future<void> _refreshProofStatus(String requestId) async {
    try {
      final status = await _migrationService.keystoneProofStatus(
        requestId: requestId,
      );
      if (!mounted || _requestCompleted || _request?.requestId != requestId) {
        return;
      }

      final pendingSignedMessages = _pendingSignedMessages;
      if (status.isReady || status.isFailed) {
        _stopProofPolling();
      }

      setState(() {
        _proofStatus = status;
        if (status.isFailed) {
          _pendingSignedMessages = null;
          _error = ironwoodMigrationKeystoneProofFailureMessage(status);
          if (_stage == _KeystoneDenominationSignStage.waitingForProofs) {
            _stage = _KeystoneDenominationSignStage.scanning;
          }
        } else if (_stage == _KeystoneDenominationSignStage.waitingForProofs) {
          _error = status.isReady
              ? null
              : ironwoodMigrationKeystoneProofWaitingMessage(status);
        }
      });

      if (status.isReady &&
          pendingSignedMessages != null &&
          !_decoding &&
          !_requestCompleted) {
        unawaited(_completeSignedMessages(pendingSignedMessages));
      }
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'proof status error: $e\n$st',
      );
      if (!mounted || _requestCompleted || _request?.requestId != requestId) {
        return;
      }
      setState(() {
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _completeSignedMessages(
    List<rust_sync.KeystoneSignedMigrationMessage> signedMessages,
  ) async {
    final request = _request;
    final accountUuid = _accountUuid;
    if (request == null || accountUuid == null || _requestCompleted) return;

    setState(() {
      _stage = _KeystoneDenominationSignStage.completing;
      _decoding = true;
      _error = null;
    });

    try {
      await widget.step.complete(
        _migrationService,
        accountUuid: accountUuid,
        requestId: request.requestId,
        signedMessages: signedMessages,
        approvedSchedule: widget.approvedSchedule,
      );
      if (!mounted) return;
      _stopProofPolling();
      _requestCompleted = true;
      _pendingSignedMessages = null;
      _invalidateIronwoodMigrationStatusState(
        ref,
        statusRequest: IronwoodMigrationStatusRequest(
          network: ref.read(ironwoodMigrationInputsProvider).network,
          accountUuid: accountUuid,
        ),
      );
      context.go('/migration/private/status');
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'complete error: $e\n$st',
      );
      if (!mounted) return;
      if (_keystoneMigrationProofStillPendingError(e)) {
        _pendingSignedMessages = signedMessages;
        _startProofPolling(request.requestId);
        setState(() {
          _stage = _KeystoneDenominationSignStage.waitingForProofs;
          _decoding = false;
          _error = ironwoodMigrationKeystoneProofWaitingMessage(_proofStatus);
        });
        return;
      }
      setState(() {
        _stage = _KeystoneDenominationSignStage.scanning;
        _pendingSignedMessages = null;
        _decoding = false;
        _error = _keystoneMigrationSigningErrorMessage(e);
      });
    }
  }

  Future<void> _discardRequest(String requestId) async {
    try {
      await _migrationService.discardKeystonePrivateMigrationRequest(
        requestId: requestId,
      );
    } catch (e, st) {
      log(
        'IronwoodMigrationKeystoneSign(${widget.step.logName}): '
        'discard error: $e\n$st',
      );
    }
  }

  Future<void> _returnToReview() async {
    if (_stage == _KeystoneDenominationSignStage.completing) return;
    final requestId = _request?.requestId;
    _stopProofPolling();
    _request = null;
    if (requestId != null) {
      await _discardRequest(requestId);
    }
    if (!mounted) return;
    context.go(widget.step.previousRoute);
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = ironwoodMigrationKeystoneScanErrorMessage(error);
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  void _stopProofPolling() {
    _proofPollTimer?.cancel();
    _proofPollTimer = null;
  }

  String? get _proofStatusText {
    final status = _proofStatus;
    if (status == null) return null;
    if (status.isFailed) {
      return ironwoodMigrationKeystoneProofFailureMessage(status);
    }
    if (status.isReady) return 'Local proofs ready';
    if (status.totalCount > 0) {
      return 'Preparing local proofs ${status.readyCount}/${status.totalCount}';
    }
    return 'Preparing local proofs';
  }

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationFrame(
      toolbar: _keystoneDenominationToolbar(
        label: widget.step.toolbarLabel,
        onBack: () => unawaited(_returnToReview()),
      ),
      disableSidebarActions: true,
      child: SizedBox(
        width: 520,
        child: switch (_stage) {
          _KeystoneDenominationSignStage.preparing => const SizedBox(
            height: 560,
            child: Center(child: CircularProgressIndicator()),
          ),
          _KeystoneDenominationSignStage.showQr => _buildQrContent(context),
          _KeystoneDenominationSignStage.scanning ||
          _KeystoneDenominationSignStage.waitingForProofs ||
          _KeystoneDenominationSignStage.completing => _buildScannerContent(
            context,
          ),
          _KeystoneDenominationSignStage.failed => _buildFailureContent(
            context,
          ),
        },
      ),
    );
  }

  Widget _buildQrContent(BuildContext context) {
    final colors = context.colors;
    final request = _request;
    final proofStatusText = _proofStatusText;
    final proofFailed = ironwoodMigrationKeystoneProofFailed(_proofStatus);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.step.qrTitle,
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 360,
            child: Text(
              widget.step.qrBody,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          KeystonePcztQrStage(
            phase: KeystonePcztQrStagePhase.ready,
            urParts: _urParts,
            error: _error,
            size: 264,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            request == null
                ? 'Preparing migration request'
                : '${request.messages.length} ${widget.step.messageUnit}'
                      '${request.messages.length == 1 ? '' : 's'} to sign',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (proofStatusText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: 360,
              child: Text(
                proofStatusText,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: proofFailed
                      ? colors.text.destructive
                      : colors.text.secondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            onPressed: _urParts.isEmpty || proofFailed
                ? null
                : () {
                    setState(() {
                      _stage = _KeystoneDenominationSignStage.scanning;
                      _error = null;
                      _decoding = false;
                    });
                  },
            height: 44,
            minWidth: 230,
            trailing: const AppIcon(AppIcons.chevronForward, size: 20),
            child: const Text('Scan signature'),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: () => unawaited(_returnToReview()),
            variant: AppButtonVariant.ghost,
            height: 36,
            minWidth: 230,
            child: Text(widget.step.previousButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerContent(BuildContext context) {
    final colors = context.colors;
    final completing = _stage == _KeystoneDenominationSignStage.completing;
    final waitingForProofs =
        _stage == _KeystoneDenominationSignStage.waitingForProofs;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan Keystone signature',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 360,
            child: Text(
              completing
                  ? 'Applying the Keystone signature to your migration plan.'
                  : waitingForProofs
                  ? 'Signature captured. Vizor will continue when local proofs are ready.'
                  : 'Show the signed migration QR on Keystone and scan it here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          KeystoneQrScannerCard(
            expectedUrType: _keystoneMigrationSignBatchResultUrType,
            decoding: _decoding,
            error: _error,
            onProgress: (_) {
              if (_pendingSignedMessages != null) return;
              if (_error == null || !mounted) return;
              setState(() {
                _error = null;
              });
            },
            onDecodeError: _handleDecodeError,
            onComplete: (result) => unawaited(_handleScanComplete(result)),
            decodingLabel: 'Reading signature...',
            unavailableMessage:
                'Keystone migration signing uses camera QR scanning only. '
                'Connect a camera and try again.',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: completing || waitingForProofs
                ? null
                : () {
                    setState(() {
                      _stage = _KeystoneDenominationSignStage.showQr;
                      _error = null;
                      _decoding = false;
                    });
                  },
            variant: AppButtonVariant.ghost,
            height: 36,
            minWidth: 230,
            child: const Text('Back to QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureContent(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 560,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keystone signing unavailable',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: 360,
              child: Text(
                _error ?? 'Try again after sync finishes.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              onPressed: () => unawaited(_prepareRequest()),
              minWidth: 230,
              leading: const AppIcon(AppIcons.renew, size: 20),
              child: const Text('Try again'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              onPressed: () => unawaited(_returnToReview()),
              variant: AppButtonVariant.ghost,
              minWidth: 230,
              child: Text(widget.step.previousButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _keystoneDenominationToolbar({
  required String label,
  required VoidCallback onBack,
}) {
  return AppPaneToolbar(
    leading: AppBackLink(label: label, onTap: onBack),
  );
}

List<rust_sync.KeystoneSignedMigrationMessage> _signedMigrationMessagesFor(
  rust_sync.KeystoneMigrationSigningRequest request,
  rust_keystone.KeystoneSigResult decoded,
) {
  final signedById = <String, List<rust_keystone.KeystoneActionSig>>{};
  for (final result in decoded.results) {
    signedById[utf8.decode(result.messageId)] = result.sigs;
  }

  return [
    for (final message in request.messages)
      rust_sync.KeystoneSignedMigrationMessage(
        id: message.id,
        sigs:
            signedById[message.id] ??
            (throw StateError(
              'Keystone signature for ${message.id} is missing.',
            )),
      ),
  ];
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofReady(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status?.isReady == true;
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofFailed(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status?.isFailed == true;
}

@visibleForTesting
bool ironwoodMigrationKeystoneProofShouldWait(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  return status == null || (!status.isReady && !status.isFailed);
}

@visibleForTesting
String ironwoodMigrationKeystoneProofWaitingMessage(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  if (status != null && status.totalCount > 0) {
    return 'Signature captured. Vizor is still preparing local proofs '
        '(${status.readyCount}/${status.totalCount}). Keep this screen open.';
  }
  return 'Signature captured. Vizor is still preparing local proofs. '
      'Keep this screen open.';
}

@visibleForTesting
String ironwoodMigrationKeystoneProofFailureMessage(
  rust_sync.KeystoneMigrationProofStatus? status,
) {
  final message = status?.message?.trim();
  if (message != null && message.isNotEmpty) return message;
  return 'Vizor could not prepare local proofs. Go back and prepare this request again.';
}

@visibleForTesting
String ironwoodMigrationKeystoneScanErrorMessage(Object error) {
  final message = error.toString();
  if (message.contains('Unexpected UR type') &&
      message.contains(_keystoneMigrationLegacySignResultUrType)) {
    return _keystoneMigrationFirmwareUpdateError;
  }
  if (message.contains('Unexpected UR type')) {
    return 'Open the signed migration QR on Keystone, then scan again.';
  }
  return 'Keep the QR code steady and fully visible.';
}

bool _keystoneMigrationProofStillPendingError(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('proof') &&
      (lower.contains('pending') ||
          lower.contains('not ready') ||
          lower.contains('still'));
}

String _keystoneMigrationSigningErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('not a keystone')) {
    return 'Use a Keystone account to sign this migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('password') ||
      lower.contains('secret storage') ||
      lower.contains('unlocked session')) {
    return 'Unlock Vizor before signing migration.';
  }
  if (lower.contains('request') && lower.contains('not found')) {
    return 'This Keystone signing request expired. Prepare it again.';
  }
  if (lower.contains('signature') || lower.contains('qr')) {
    return 'Keystone signature could not be applied.';
  }
  return 'Keystone signing could not be prepared. Try again.';
}

class _RedirectTo extends StatefulWidget {
  const _RedirectTo(this.location);

  final String location;

  @override
  State<_RedirectTo> createState() => _RedirectToState();
}

class _RedirectToState extends State<_RedirectTo> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(widget.location);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IronwoodMigrationLoadingShell extends StatelessWidget {
  const _IronwoodMigrationLoadingShell({required this.step});

  final IronwoodMigrationFlowStep step;

  @override
  Widget build(BuildContext context) {
    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _IronwoodMigrationShell extends StatelessWidget {
  const _IronwoodMigrationShell({
    required this.step,
    required this.data,
    this.previewPrivatePlan,
    this.previewReviewStage = IronwoodMigrationReviewPreviewStage.review,
    this.onOpenReleaseNotesOverride,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final IronwoodMigrationReviewPreviewStage previewReviewStage;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
      IronwoodMigrationFlowStep.prepare => const Center(
        child: CircularProgressIndicator(),
      ),
      IronwoodMigrationFlowStep.intro => _IronwoodMigrationIntroContent(
        data: data,
        onOpenReleaseNotes: () =>
            _openReleaseNotes(context, override: onOpenReleaseNotesOverride),
      ),
      IronwoodMigrationFlowStep.howItWorks =>
        _IronwoodMigrationHowItWorksContent(data: data),
      IronwoodMigrationFlowStep.options => _IronwoodMigrationOptionsContent(
        data: data,
      ),
      IronwoodMigrationFlowStep.review =>
        _IronwoodMigrationPrivateReviewContent(
          data: data,
          previewPlan:
              previewReviewStage ==
                  IronwoodMigrationReviewPreviewStage.analyzing
              ? null
              : previewPrivatePlan,
          forceAnalyzing:
              previewReviewStage ==
              IronwoodMigrationReviewPreviewStage.analyzing,
        ),
    };

    return _IronwoodMigrationFrame(
      toolbar: _toolbarFor(context, step),
      disableSidebarActions: step != IronwoodMigrationFlowStep.options,
      child: content,
    );
  }
}

Future<void> _openReleaseNotes(
  BuildContext context, {
  VoidCallback? override,
}) async {
  if (override != null) {
    override();
    return;
  }
  final uri = Uri.parse(kIronwoodMigrationReleaseNotesUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Widget _toolbarFor(BuildContext context, IronwoodMigrationFlowStep step) {
  return AppPaneToolbar(
    leading: AppBackLink(
      label: switch (step) {
        IronwoodMigrationFlowStep.prepare => 'Home',
        IronwoodMigrationFlowStep.intro => 'Home',
        IronwoodMigrationFlowStep.howItWorks => 'Ironwood Pool',
        IronwoodMigrationFlowStep.options => 'How Migration Works',
        IronwoodMigrationFlowStep.review => 'Migration Options',
      },
      onTap: () {
        switch (step) {
          case IronwoodMigrationFlowStep.prepare:
            context.go('/home');
          case IronwoodMigrationFlowStep.intro:
            context.go('/home');
          case IronwoodMigrationFlowStep.howItWorks:
            context.go('/migration/intro');
          case IronwoodMigrationFlowStep.options:
            context.go('/migration/how-it-works');
          case IronwoodMigrationFlowStep.review:
            context.go('/migration/options');
        }
      },
    ),
  );
}

Widget _privateStatusToolbar(BuildContext context) {
  return AppPaneToolbar(
    leading: AppBackLink(label: 'Home', onTap: () => context.go('/home')),
  );
}

class _IronwoodMigrationFrame extends StatelessWidget {
  const _IronwoodMigrationFrame({
    required this.toolbar,
    required this.child,
    required this.disableSidebarActions,
  });

  final Widget toolbar;
  final Widget child;
  final bool disableSidebarActions;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: AppMainSidebar(
        disabledRoutePaths: disableSidebarActions
            ? const {'/swap', '/voting'}
            : const {},
      ),
      pane: AppPaneScrollScaffold(
        toolbar: toolbar,
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }
}

class _IronwoodMigrationIntroContent extends StatelessWidget {
  const _IronwoodMigrationIntroContent({
    required this.data,
    required this.onOpenReleaseNotes,
  });

  final IronwoodMigrationFlowData data;
  final VoidCallback onOpenReleaseNotes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = data.amountText;
    final isDark = colors.background.window == AppColors.dark.background.window;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 16,
            width: 420,
            height: 200,
            child: _PoolMigrationHero(data: data),
          ),
          Positioned(
            left: 0,
            top: 250,
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _DarkBadge(label: 'Zcash Network Upgrade'),
                const SizedBox(height: 24),
                SvgPicture.asset(
                  'assets/illustrations/ironwood_wordmark.svg',
                  width: 290,
                  height: 39,
                  colorFilter: ColorFilter.mode(
                    colors.text.accent,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 352,
                  child: Text(
                    'A new shielded pool for Zcash.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 328,
                  child: Text(
                    'Your $amount ZEC is currently in Orchard.\n'
                    'To keep using these funds for shielded payments, '
                    'you will need to move them to Ironwood. You will '
                    'review the migration plan before any funds move.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? colors.text.muted : colors.text.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryKey: const ValueKey(
                'ironwood_migration_intro_continue_button',
              ),
              primaryLabel: 'Next',
              onPrimary: () => context.go('/migration/how-it-works'),
              secondaryLabel: 'Official Announcement',
              onSecondary: onOpenReleaseNotes,
              secondaryLeading: const AppIcon(AppIcons.link, size: 16),
              secondaryFirst: true,
              spacing: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationHowItWorksContent extends StatelessWidget {
  const _IronwoodMigrationHowItWorksContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            top: 24,
            width: 396,
            child: Text(
              'How Migration Works',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 81.5,
            width: 396,
            child: const Column(
              children: [
                _ProcessCard(
                  steps: [
                    _ProcessStepData(
                      number: 1,
                      title: 'Choose how you migrate',
                      body:
                          'Compare a privacy-optimized schedule with a faster '
                          'migration.',
                    ),
                    _ProcessStepData(
                      number: 2,
                      title: 'Prepare your balance',
                      body:
                          'Vizor reorganizes your balance into common-sized '
                          'parts before migration begins.',
                    ),
                    _ProcessStepData(
                      number: 3,
                      title: 'Move to Ironwood',
                      body:
                          'Privacy-optimized migrations send parts at staggered '
                          'times to reduce linkability.',
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _SpendAsFundsArriveCard(),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: AppButton(
              key: const ValueKey(
                'ironwood_migration_how_it_works_continue_button',
              ),
              onPressed: () => context.go('/migration/options'),
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              child: const Text(
                'Continue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationOptionsContent extends StatefulWidget {
  const _IronwoodMigrationOptionsContent({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  State<_IronwoodMigrationOptionsContent> createState() =>
      _IronwoodMigrationOptionsContentState();
}

class _IronwoodMigrationOptionsContentState
    extends State<_IronwoodMigrationOptionsContent> {
  var _selected = _MigrationMode.private;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 49,
            top: 68,
            width: 322,
            child: Column(
              children: [
                Text(
                  'Choose How to Migrate',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 322,
                  child: Text(
                    'Choose between more privacy over time or a faster '
                    'migration. You can review the details before anything '
                    'moves.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 193,
            width: 396,
            child: Column(
              children: [
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_private_option'),
                  mode: _MigrationMode.private,
                  selected: _selected == _MigrationMode.private,
                  title: 'Privacy optimized',
                  badge: 'Recommended',
                  body: 'Sends independent parts over different time windows.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.private),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  key: const ValueKey('ironwood_migration_fast_option'),
                  mode: _MigrationMode.fast,
                  selected: _selected == _MigrationMode.fast,
                  title: 'Faster but less private',
                  body: 'Coming soon. Moves funds sooner with less separation.',
                  onTap: () => setState(() => _selected = _MigrationMode.fast),
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey('ironwood_migration_select_review_button'),
              onPressed: _selected == _MigrationMode.private
                  ? () => context.go('/migration/private/review')
                  : null,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text('Select & Review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationPrivateStatusContent extends ConsumerStatefulWidget {
  const _IronwoodMigrationPrivateStatusContent({
    required this.status,
    this.accountUuid,
  });

  final rust_sync.MigrationStatus status;
  final String? accountUuid;

  @override
  ConsumerState<_IronwoodMigrationPrivateStatusContent> createState() =>
      _IronwoodMigrationPrivateStatusContentState();
}

class _IronwoodMigrationPrivateStatusContentState
    extends ConsumerState<_IronwoodMigrationPrivateStatusContent> {
  Future<void> _handleAction(_StatusAction action) async {
    final accountUuid = widget.accountUuid;
    if (accountUuid == null) return;
    if (action == _StatusAction.needsInput) {
      context.go('/migration/private/keystone/batch/sign');
      return;
    }
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } catch (e) {
      log('Migration continuation failed: $e');
    }
    _invalidateIronwoodMigrationStatusState(
      ref,
      statusRequest: IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = widget.status;
    final presentation = _statusPresentation(status);
    final progress = _statusProgress(status);
    final syncState = ref.watch(syncProvider).asData?.value;
    final currentHeight = _currentMigrationHeight(syncState);
    final accountState = ref.watch(accountProvider).value;
    final isHardware =
        accountState?.accounts
            .where((account) => account.uuid == widget.accountUuid)
            .any((account) => account.isHardware) ??
        false;
    final action = _statusAction(status, isHardware: isHardware);
    final canUseAction = widget.accountUuid != null;
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    final isAdvancing =
        widget.accountUuid != null &&
        coordinator.advancingAccounts.contains(widget.accountUuid);
    final actionLabel = isAdvancing
        ? action.busyLabel
        : switch (action) {
            _StatusAction.needsInput || _StatusAction.retry => action.label,
            _StatusAction.backHome ||
            _StatusAction.none => presentation.buttonLabel,
          };
    final coordinatorError = widget.accountUuid == null
        ? null
        : coordinator.errors[widget.accountUuid!];
    final footerText = coordinatorError == null
        ? presentation.footer
        : _privateMigrationContinueErrorMessage(coordinatorError);
    final actionCallback = switch (action) {
      _StatusAction.needsInput || _StatusAction.retry =>
        canUseAction ? () => unawaited(_handleAction(action)) : null,
      _StatusAction.backHome => () => context.go('/home'),
      _StatusAction.none => null,
    };

    if (status.activeRunId != null &&
        {
          kIronwoodMigrationWaitingDenomConfirmationsPhase,
          kIronwoodMigrationReadyToMigratePhase,
          kIronwoodMigrationBroadcastScheduledPhase,
          kIronwoodMigrationBroadcastingPhase,
          kIronwoodMigrationWaitingConfirmationsPhase,
        }.contains(status.phase)) {
      return _MigrationStatusContent(
        status: status,
        action: action,
        isAdvancing: isAdvancing,
        currentHeight: currentHeight,
        onAction: actionCallback,
      );
    }

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 29,
            top: 48,
            width: 362,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 318,
                  child: Text(
                    presentation.body,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 210,
            width: 396,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                child: Column(
                  children: [
                    if (progress != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: colors.background.raised,
                          color: GreenPrimitives.p500Light,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _ReviewMetricRow(
                      icon: AppIcons.swapArrows,
                      label: 'Split progress',
                      value:
                          '${status.denominationSplitCompletedCount}/'
                          '${status.denominationSplitTotalCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.time,
                      label: 'Pending broadcasts',
                      value: '${status.pendingTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.plane,
                      label: 'Broadcasted',
                      value: '${status.broadcastedTxCount}',
                    ),
                    const SizedBox(height: 16),
                    _ReviewMetricRow(
                      icon: AppIcons.checkCircle,
                      label: 'Confirmed',
                      value: '${status.confirmedTxCount}/${status.totalCount}',
                    ),
                    if (status.message != null) ...[
                      const SizedBox(height: 18),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: colors.border.subtle,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        status.message!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 51,
            top: 515,
            width: 318,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              key: const ValueKey('ironwood_migration_status_action_button'),
              onPressed: isAdvancing ? null : actionCallback,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IronwoodMigrationPrivateStatusErrorContent extends StatelessWidget {
  const _IronwoodMigrationPrivateStatusErrorContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 29,
            top: 74,
            width: 362,
            child: Column(
              children: [
                Text(
                  'Migration status unavailable',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 318,
                  child: Text(
                    "Vizor couldn't verify the current Ironwood migration "
                    'state. No new migration will start until the status can '
                    'be checked.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 262,
            width: 396,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: Text(
                  'Return home and try again after sync refreshes. If a '
                  'migration is already in progress, Vizor will continue from '
                  'the saved state after it can be read.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: AppButton(
              onPressed: () => context.go('/home'),
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: const Text(
                'Back home',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.title,
    required this.body,
    required this.footer,
    required this.buttonLabel,
  });

  final String title;
  final String body;
  final String footer;
  final String buttonLabel;
}

enum _StatusAction { none, needsInput, retry, backHome }

extension _StatusActionLabels on _StatusAction {
  String get label => switch (this) {
    _StatusAction.needsInput => 'Sign with Keystone',
    _StatusAction.retry => 'Retry migration',
    _StatusAction.backHome => 'Back home',
    _StatusAction.none => '',
  };

  String get busyLabel => switch (this) {
    _StatusAction.retry => 'Retrying...',
    _ => 'Continuing...',
  };
}

_StatusAction _statusAction(
  rust_sync.MigrationStatus status, {
  required bool isHardware,
}) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase => _StatusAction.none,
    kIronwoodMigrationReadyToMigratePhase =>
      isHardware ? _StatusAction.needsInput : _StatusAction.none,
    kIronwoodMigrationFailedRecoverablePhase => _StatusAction.retry,
    kIronwoodMigrationCompletePhase => _StatusAction.backHome,
    _ => _StatusAction.none,
  };
}

_StatusPresentation _statusPresentation(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase =>
      const _StatusPresentation(
        title: 'Preparing...',
        body: 'This will take around 10-20m',
        footer: 'You can leave this screen.\nBut keep Vizor open & running.',
        buttonLabel: '',
      ),
    kIronwoodMigrationReadyToMigratePhase => const _StatusPresentation(
      title: 'Ready to Migrate',
      body:
          'The private split is ready. The next step will prepare the '
          'Ironwood migration batch.',
      footer:
          'Continue migration to prepare and broadcast the Ironwood '
          'transaction when it is due.',
      buttonLabel: 'Continue migration',
    ),
    kIronwoodMigrationBroadcastScheduledPhase => const _StatusPresentation(
      title: 'Broadcast Scheduled',
      body:
          'Your migration transaction is prepared and waiting for its '
          'scheduled broadcast window.',
      footer:
          'When Vizor is open, scheduled broadcasts will be advanced by the '
          'migration worker.',
      buttonLabel: 'Continue migration',
    ),
    kIronwoodMigrationBroadcastingPhase => const _StatusPresentation(
      title: 'Migrating...',
      body:
          'Vizor is broadcasting the prepared Ironwood migration transaction.',
      footer: 'You can leave this screen.\nBut keep Vizor open & running.',
      buttonLabel: 'Broadcasting',
    ),
    kIronwoodMigrationWaitingConfirmationsPhase => const _StatusPresentation(
      title: 'Migrating...',
      body:
          'The migration transaction was broadcast. Vizor is waiting for '
          'network confirmations.',
      footer: 'You can leave this screen.\nBut keep Vizor open & running.',
      buttonLabel: 'Waiting for confirmations',
    ),
    kIronwoodMigrationCompletePhase => const _StatusPresentation(
      title: 'Migration Complete',
      body: 'Your funds have moved into the Ironwood pool.',
      footer: 'You can return home and continue using Vizor.',
      buttonLabel: 'Back home',
    ),
    kIronwoodMigrationPausedPhase => const _StatusPresentation(
      title: 'Migration Paused',
      body: 'The private migration is paused before the next action.',
      footer:
          'No new transaction will be prepared until migration execution is '
          'resumed.',
      buttonLabel: 'Paused',
    ),
    kIronwoodMigrationFailedRecoverablePhase => const _StatusPresentation(
      title: 'Migration Needs Attention',
      body:
          'Vizor hit a recoverable migration error before completing the '
          'Ironwood transition.',
      footer:
          'No funds are lost. Retry migration after checking that Vizor is '
          'synced and online.',
      buttonLabel: 'Retry migration',
    ),
    _ => const _StatusPresentation(
      title: 'Migration Status',
      body: 'Vizor is tracking the current Ironwood migration state.',
      footer:
          'This state is visible for diagnostics while the migration flow is '
          'being connected.',
      buttonLabel: 'Migration in progress',
    ),
  };
}

double? _statusProgress(rust_sync.MigrationStatus status) {
  if (status.phase == kIronwoodMigrationFailedRecoverablePhase ||
      status.phase == kIronwoodMigrationPausedPhase) {
    return null;
  }
  if (status.phase == kIronwoodMigrationCompletePhase) return 1;

  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    final target = status.denominationConfirmationTarget;
    if (target > 0) {
      return (status.denominationConfirmationCount / target).clamp(0, 1);
    }
    final total = status.denominationSplitTotalCount;
    if (total > 0) {
      return (status.denominationSplitCompletedCount / total).clamp(0, 1);
    }
    return 0.25;
  }

  final partProgress = _migrationPartProgress(status);
  if (partProgress != null) return partProgress;

  final total = status.totalCount;
  if (total > 0) {
    return (status.confirmedTxCount / total).clamp(0, 1);
  }

  return switch (status.phase) {
    kIronwoodMigrationReadyToMigratePhase => 0.45,
    kIronwoodMigrationBroadcastScheduledPhase => 0.65,
    kIronwoodMigrationBroadcastingPhase => 0.75,
    kIronwoodMigrationWaitingConfirmationsPhase => 0.85,
    _ => 0.1,
  };
}

class _IronwoodMigrationPrivateReviewContent extends ConsumerStatefulWidget {
  const _IronwoodMigrationPrivateReviewContent({
    required this.data,
    this.previewPlan,
    this.forceAnalyzing = false,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool forceAnalyzing;

  @override
  ConsumerState<_IronwoodMigrationPrivateReviewContent> createState() =>
      _IronwoodMigrationPrivateReviewContentState();
}

class _IronwoodMigrationPrivateReviewContentState
    extends ConsumerState<_IronwoodMigrationPrivateReviewContent> {
  bool _isStarting = false;
  String? _startError;
  late final Future<void> _minimumAnalyzingDelay;

  @override
  void initState() {
    super.initState();
    _minimumAnalyzingDelay = widget.forceAnalyzing
        ? Future<void>.value()
        : _createMinimumAnalyzingDelay();
  }

  Future<void> _createMinimumAnalyzingDelay() {
    final duration = ref.read(
      ironwoodMigrationAnalyzingMinimumDurationProvider,
    );
    if (duration <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(duration);
  }

  Future<void> _startMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;

    IronwoodMigrationStatusRequest? statusRequest;
    var softwareStartAttempted = false;
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
      statusRequest = IronwoodMigrationStatusRequest(
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
      softwareStartAttempted = true;
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .startSoftwareMigration(
            accountUuid: accountUuid,
            approvedSchedule: plan.scheduledTransfers,
          );
      if (!mounted) return;
      await _refreshMigrationStatusBestEffort(statusRequest);
      if (!mounted) return;
      _openMigrationStatus();
    } catch (e) {
      if (!mounted) return;
      final request = statusRequest;
      if (softwareStartAttempted &&
          request != null &&
          await _migrationMayHaveStarted(request)) {
        if (!mounted) return;
        _openMigrationStatus();
        return;
      }
      if (!mounted) return;
      setState(() {
        _startError = _privateMigrationStartErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<bool> _migrationMayHaveStarted(
    IronwoodMigrationStatusRequest request,
  ) async {
    ref.invalidate(ironwoodMigrationStatusProvider(request));
    try {
      final status = await ref
          .read(ironwoodMigrationStatusProvider(request).future)
          .timeout(_privateStatusStartVerificationTimeout);
      return status.activeRunId != null;
    } catch (_) {
      // The start operation may already have persisted a run. An unavailable
      // status is not sufficient evidence that retrying start is safe.
      return true;
    }
  }

  Future<void> _refreshMigrationStatusBestEffort(
    IronwoodMigrationStatusRequest request,
  ) async {
    ref.invalidate(ironwoodMigrationStatusProvider(request));
    try {
      await ref
          .read(ironwoodMigrationStatusProvider(request).future)
          .timeout(_privateStatusStartVerificationTimeout);
    } catch (_) {
      // The status route owns unavailable-state rendering after start.
    }
  }

  void _openMigrationStatus() {
    _invalidateIronwoodMigrationStatusState(ref);
    context.go('/migration/private/status');
  }

  @override
  Widget build(BuildContext context) {
    final previewPlan = widget.previewPlan;
    final planAsync = widget.forceAnalyzing
        ? const AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.loading()
        : previewPlan == null
        ? ref.watch(ironwoodMigrationPrivatePlanProvider)
        : AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(previewPlan);
    final plan = planAsync.asData?.value;
    if (planAsync.isLoading) return const _MigrationAnalyzingContent();
    return FutureBuilder<void>(
      future: _minimumAnalyzingDelay,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MigrationAnalyzingContent();
        }
        if (planAsync.hasError || plan == null) {
          return const SizedBox(
            width: 420,
            height: 656,
            child: Center(
              child: _PrivateReviewUnavailable(
                title: "Couldn't analyze this balance",
                body: 'Wait for sync to finish, then try again.',
              ),
            ),
          );
        }

        return _MigrationReviewContent(
          plan: plan,
          isStarting: _isStarting,
          error: _startError,
          onContinue: () => unawaited(_startMigration(plan)),
        );
      },
    );
  }
}

class _MigrationAnalyzingContent extends StatefulWidget {
  const _MigrationAnalyzingContent();

  @override
  State<_MigrationAnalyzingContent> createState() =>
      _MigrationAnalyzingContentState();
}

class _MigrationAnalyzingContentState extends State<_MigrationAnalyzingContent>
    with SingleTickerProviderStateMixin {
  static const _messages = [
    'Analyzing your balance...',
    'Finding private batches...',
    'Preparing your migration plan...',
  ];
  static const _switchDuration = Duration(milliseconds: 320);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: _MigrationAnalyzingMotion.period,
  );
  Timer? _reducedMotionMessageTimer;
  var _messageIndex = 0;
  var _advancedMessageThisCycle = false;

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _shimmer.addListener(_handleShimmerTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      _reducedMotionMessageTimer?.cancel();
      _reducedMotionMessageTimer = null;
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer
        ..stop()
        ..value = 0;
      _reducedMotionMessageTimer ??= Timer.periodic(
        _MigrationAnalyzingMotion.period,
        (_) => _advanceMessage(),
      );
    }
  }

  void _handleShimmerTick() {
    if (!mounted || !_shouldAnimate) return;
    final progress = _shimmer.value;
    if (progress < _MigrationAnalyzingMotion.cycleResetProgress) {
      _advancedMessageThisCycle = false;
      return;
    }
    if (!_advancedMessageThisCycle &&
        progress >= _MigrationAnalyzingMotion.messageAdvanceProgress) {
      _advancedMessageThisCycle = true;
      _advanceMessage();
    }
  }

  void _advanceMessage() {
    if (!mounted) return;
    setState(() {
      _messageIndex = (_messageIndex + 1) % _messages.length;
    });
  }

  @override
  void dispose() {
    _reducedMotionMessageTimer?.cancel();
    _shimmer.removeListener(_handleShimmerTick);
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _messages[_messageIndex];
    return SizedBox(
      key: const ValueKey('ironwood_migration_analyzing_screen'),
      width: 420,
      height: 656,
      child: Column(
        children: [
          const SizedBox(height: 178),
          const _MigrationAnalyzingProgressBar(),
          const SizedBox(height: 72),
          AnimatedBuilder(
            animation: _shimmer,
            builder: (context, _) {
              return AnimatedSwitcher(
                duration: _shouldAnimate ? _switchDuration : Duration.zero,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _MigrationAnalyzingShimmerText(
                  key: ValueKey(title),
                  label: title,
                  baseColor: colors.text.muted,
                  highlightColor: colors.text.accent,
                  progress: _shimmer.value,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 298,
            child: Text(
              'Vizor is working hard to find a perfect balance of safety, '
              'privacy, and speed for your migration',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationAnalyzingProgressBar extends StatefulWidget {
  const _MigrationAnalyzingProgressBar();

  @override
  State<_MigrationAnalyzingProgressBar> createState() =>
      _MigrationAnalyzingProgressBarState();
}

class _MigrationAnalyzingProgressBarState
    extends State<_MigrationAnalyzingProgressBar>
    with SingleTickerProviderStateMixin {
  static const _barWidth = 196.0;
  static const _segmentWidth = 72.0;
  static const _initialProgress = _segmentWidth / (_barWidth + _segmentWidth);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void initState() {
    super.initState();
    _controller.value = _initialProgress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = _initialProgress;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: _barWidth,
      height: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.overlay),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _shouldAnimate
                  ? _controller.value
                  : _initialProgress;
              final left =
                  -_segmentWidth + progress * (_barWidth + _segmentWidth);
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: _segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

abstract final class _MigrationAnalyzingMotion {
  static const period = Duration(seconds: 2);
  static const messageAdvanceProgress = 0.96;
  static const cycleResetProgress = 0.2;
  static const _bandHalf = 0.18;
}

class _MigrationAnalyzingShimmerText extends StatelessWidget {
  const _MigrationAnalyzingShimmerText({
    required this.label,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    super.key,
  });

  final String label;
  final Color baseColor;
  final Color highlightColor;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final shift = (progress * 2 - 1) * bounds.width;
        final rect = Rect.fromLTWH(
          bounds.left + shift,
          bounds.top,
          bounds.width,
          bounds.height,
        );
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, highlightColor, baseColor],
          stops: const [
            0.5 - _MigrationAnalyzingMotion._bandHalf,
            0.5 - _MigrationAnalyzingMotion._bandHalf / 4,
            0.5 + _MigrationAnalyzingMotion._bandHalf / 4,
            0.5 + _MigrationAnalyzingMotion._bandHalf,
          ],
          tileMode: TileMode.clamp,
        ).createShader(rect);
      },
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTypography.headlineSmall.copyWith(
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

class _MigrationReviewContent extends StatelessWidget {
  const _MigrationReviewContent({
    required this.plan,
    required this.isStarting,
    required this.onContinue,
    this.error,
  });

  final rust_sync.OrchardMigrationPrivatePlan plan;
  final bool isStarting;
  final VoidCallback onContinue;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final values = [for (final value in plan.targetValuesZatoshi) value];
    final rows = values.isEmpty
        ? <BigInt>[plan.totalMigratableZatoshi]
        : values;
    return SizedBox(
      key: const ValueKey('ironwood_migration_review_screen'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 46,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Review migration plan',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 160,
            width: 396,
            height: 378,
            child: _MigrationBatchOverview(
              values: rows,
              totalZatoshi: plan.totalMigratableZatoshi,
              feeZatoshi: plan.estimatedTotalFeeZatoshi,
              completionLabel: _estimatedMigrationArrivalLabel(plan),
            ),
          ),
          if (error != null)
            Positioned(
              left: 45,
              top: 545,
              width: 330,
              child: Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.warning,
                ),
              ),
            ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey(
                  'ironwood_migration_authorize_start_button',
                ),
                onPressed: isStarting ? null : onContinue,
                height: 36,
                minWidth: 130,
                expand: false,
                child: SizedBox(
                  width: 98,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(isStarting ? 'Starting...' : 'Start migration'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationBatchOverview extends StatelessWidget {
  const _MigrationBatchOverview({
    required this.values,
    required this.totalZatoshi,
    required this.feeZatoshi,
    required this.completionLabel,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final BigInt feeZatoshi;
  final String completionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Migration',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                  children: [
                    TextSpan(
                      text: values.length == 1
                          ? '  1 note'
                          : '  ${values.length} notes',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_formatMigrationTotal(totalZatoshi)} ZEC',
              maxLines: 1,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        SizedBox(
          height: 12,
          child: Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: _migrationSegmentFlex(values[i], totalZatoshi),
                  child: _MigrationProgressSegment(
                    index: i,
                    status: _MigrationBatchStatus.none,
                    progress: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: values.length,
            itemBuilder: (context, index) => _MigrationBatchRow(
              key: ValueKey('ironwood_migration_batch_$index'),
              index: index,
              value: values[index],
              totalZatoshi: totalZatoshi,
              status: _MigrationBatchStatus.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _MigrationBatchFooter(
          completionLabel: completionLabel,
          secondLabel: 'Fees (estimate)',
          secondValue: '~${_formatZecAmountCompact(feeZatoshi)} ZEC',
        ),
      ],
    );
  }
}

class _MigrationBatchFooter extends StatelessWidget {
  const _MigrationBatchFooter({
    required this.completionLabel,
    required this.secondLabel,
    required this.secondValue,
  });

  final String completionLabel;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MigrationBatchFooterRow(
          label: 'Est. completion',
          value: completionLabel,
        ),
        const SizedBox(height: 4),
        _MigrationBatchFooterRow(label: secondLabel, value: secondValue),
      ],
    );
  }
}

class _MigrationBatchFooterRow extends StatelessWidget {
  const _MigrationBatchFooterRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textColor = context.colors.text.primary;
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.labelLarge.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationProgressSegment extends StatelessWidget {
  const _MigrationProgressSegment({
    required this.index,
    required this.status,
    required this.progress,
  });

  final int index;
  final _MigrationBatchStatus status;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = status == _MigrationBatchStatus.complete
        ? 1.0
        : progress.clamp(0, 1).toDouble();

    return TweenAnimationBuilder<double>(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: effectiveProgress),
      builder: (context, animatedProgress, child) {
        final visibleProgress = _migrationSegmentVisibleProgress(
          status,
          animatedProgress,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _MigrationProgressSegmentPainter(
                status: status,
                progress: animatedProgress,
                isDark: context.appTheme == AppThemeData.dark,
              ),
            ),
            SizedBox.expand(
              key: ValueKey('ironwood_migration_segment_track_$index'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: visibleProgress.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: SizedBox.expand(
                  key: ValueKey('ironwood_migration_segment_fill_$index'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MigrationProgressSegmentPainter extends CustomPainter {
  const _MigrationProgressSegmentPainter({
    required this.status,
    required this.progress,
    required this.isDark,
  });

  static const _green = GreenPrimitives.p500Light;
  static const _greenStripe = Color(0xFF008752);
  static const _greenSoftFill = Color(0x400DC87D);
  static const _purple = Color(0xFFB83AD9);
  static const _purpleStripe = Color(0xFF8F25AB);
  static const _strokeWidth = 1.5;

  final _MigrationBatchStatus status;
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final outlineRect = Offset.zero & size;
    final borderRect = outlineRect.deflate(_strokeWidth / 2);
    final radius = Radius.circular(size.height / 2);
    final outline = RRect.fromRectAndRadius(outlineRect, radius);
    final border = RRect.fromRectAndRadius(borderRect, radius);
    final clipPath = Path()..addRRect(outline);
    final borderPath = Path()..addRRect(border);

    switch (status) {
      case _MigrationBatchStatus.complete:
        _drawFilledPill(canvas, outline, _green);
        break;
      case _MigrationBatchStatus.none:
        _drawFilledPill(canvas, outline, _greenSoftFill);
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.preparing:
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          progress,
          fillColor: _green,
        );
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.scheduled:
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          progress,
          fillColor: _greenSoftFill,
          stripeColor: _scheduledStripeColor,
        );
        _drawDashedBorder(canvas, borderPath, _green);
        break;
      case _MigrationBatchStatus.migrating:
      case _MigrationBatchStatus.confirming:
        final solidProgress = math.min(
          progress.clamp(0, 1).toDouble(),
          _scheduledBlockProgressCap,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _green,
        );
        if (progress > _scheduledBlockProgressCap) {
          _drawProgressFill(
            canvas,
            clipPath,
            outlineRect,
            progress,
            startProgress: _scheduledBlockProgressCap,
            fillColor: _activeStripeFillColor,
            stripeColor: _activeStripeColor,
          );
        }
        break;
      case _MigrationBatchStatus.needsInput:
        final solidProgress = math.min(
          math.max(progress, 0.18).clamp(0, 1).toDouble(),
          0.18,
        );
        _drawProgressFill(
          canvas,
          clipPath,
          outlineRect,
          solidProgress,
          fillColor: _purple,
        );
        if (progress > 0.18) {
          _drawProgressFill(
            canvas,
            clipPath,
            outlineRect,
            math.max(progress, 0.18),
            startProgress: 0.18,
            fillColor: _purple.withValues(alpha: 0.22),
            stripeColor: _purpleStripe.withValues(alpha: 0.44),
          );
        }
        break;
    }
  }

  void _drawFilledPill(Canvas canvas, RRect rrect, Color color) {
    canvas.drawRRect(rrect, Paint()..color = color);
  }

  Color get _activeStripeFillColor =>
      isDark ? const Color(0x590DC87D) : _greenSoftFill;

  Color get _activeStripeColor => isDark
      ? _green.withValues(alpha: 0.42)
      : _greenStripe.withValues(alpha: 0.48);

  Color get _scheduledStripeColor => isDark
      ? _green.withValues(alpha: 0.34)
      : _greenStripe.withValues(alpha: 0.28);

  void _drawProgressFill(
    Canvas canvas,
    Path clipPath,
    Rect rect,
    double progress, {
    double startProgress = 0,
    required Color fillColor,
    Color? stripeColor,
  }) {
    final clampedStart = startProgress.clamp(0, 1).toDouble();
    final clampedProgress = progress.clamp(0, 1).toDouble();
    if (clampedProgress <= clampedStart) return;

    final fillRect = Rect.fromLTWH(
      rect.left + rect.width * clampedStart,
      rect.top,
      rect.width * (clampedProgress - clampedStart),
      rect.height,
    );

    canvas.save();
    canvas.clipPath(clipPath);
    canvas.drawRect(fillRect, Paint()..color = fillColor);
    if (stripeColor != null) {
      _drawDiagonalStripes(canvas, fillRect, stripeColor);
    }
    canvas.restore();
  }

  void _drawDiagonalStripes(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const spacing = 4.0;
    final diagonal = rect.height * 1.45;
    for (
      var x = rect.left - diagonal;
      x < rect.right + diagonal;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + diagonal, rect.top),
        paint,
      );
    }
  }

  void _drawDashedBorder(Canvas canvas, Path path, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 3.5;
      const gap = 2.5;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressSegmentPainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark;
  }
}

double _migrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required List<_MigrationBatchStatus> statuses,
  required List<double> progresses,
  required int index,
}) {
  if (index >= values.length) return 0;
  if (statuses.isEmpty) return 0;
  if (index >= statuses.length) return 0;

  final status = statuses[index];
  if (status == _MigrationBatchStatus.complete) return 1;

  final rawProgress = index < progresses.length
      ? progresses[index].clamp(0, 1).toDouble()
      : 0.0;

  final hasSharedPreparingProgress =
      rawProgress > 0 &&
      statuses.every((status) => status == _MigrationBatchStatus.preparing) &&
      progresses.isNotEmpty;
  if (!hasSharedPreparingProgress) return rawProgress;

  return _distributedMigrationSegmentProgress(
    values: values,
    totalZatoshi: totalZatoshi,
    progress: rawProgress,
    index: index,
  );
}

double _distributedMigrationSegmentProgress({
  required List<BigInt> values,
  required BigInt totalZatoshi,
  required double progress,
  required int index,
}) {
  if (totalZatoshi <= BigInt.zero) return progress;
  var before = BigInt.zero;
  for (var i = 0; i < index; i++) {
    before += values[i];
  }
  final current = values[index];
  if (current <= BigInt.zero) return 0;

  final start = before / totalZatoshi;
  final end = (before + current) / totalZatoshi;
  if (end <= start) return progress;
  return ((progress - start) / (end - start)).clamp(0, 1).toDouble();
}

double _migrationSegmentVisibleProgress(
  _MigrationBatchStatus status,
  double progress,
) {
  return switch (status) {
    _MigrationBatchStatus.none => 0,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => math.max(progress, 0.18),
    _ => progress,
  };
}

enum _MigrationBatchStatus {
  none,
  preparing,
  scheduled,
  migrating,
  confirming,
  complete,
  needsInput,
}

bool _isPendingMigrationBatchStatus(_MigrationBatchStatus status) =>
    status == _MigrationBatchStatus.preparing ||
    status == _MigrationBatchStatus.scheduled;

class _MigrationBatchRow extends StatelessWidget {
  const _MigrationBatchRow({
    super.key,
    required this.index,
    required this.value,
    required this.totalZatoshi,
    required this.status,
  });

  final int index;
  final BigInt value;
  final BigInt totalZatoshi;
  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusLabel = switch (status) {
      _MigrationBatchStatus.none => null,
      _MigrationBatchStatus.preparing => 'Preparing',
      _MigrationBatchStatus.scheduled => 'Scheduled',
      _MigrationBatchStatus.migrating => 'Migrating...',
      _MigrationBatchStatus.confirming => 'Confirming...',
      _MigrationBatchStatus.complete => 'Completed',
      _MigrationBatchStatus.needsInput => 'Needs input',
    };
    return SizedBox(
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border.subtle)),
        ),
        child: Row(
          children: [
            Text(
              'Part ${index + 1}',
              style: AppTypography.bodyMedium.copyWith(
                color: _isPendingMigrationBatchStatus(status)
                    ? colors.text.secondary
                    : colors.text.accent,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: statusLabel == null ? 150 : 108,
              child: Text(
                '${_formatZecAmountCompact(value)} ZEC '
                '${_migrationPercentage(value, totalZatoshi)}',
                textAlign: TextAlign.right,
                style: AppTypography.bodyMedium.copyWith(
                  color: _isPendingMigrationBatchStatus(status)
                      ? colors.text.secondary
                      : colors.text.accent,
                ),
              ),
            ),
            if (statusLabel != null)
              SizedBox(
                width: 120,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == _MigrationBatchStatus.complete) ...[
                      const AppIcon(AppIcons.checkCircle, size: 14),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: status == _MigrationBatchStatus.needsInput
                              ? const Color(0xFFB83AD9)
                              : _isPendingMigrationBatchStatus(status)
                              ? colors.text.secondary
                              : colors.text.accent,
                        ),
                      ),
                    ),
                    if (status == _MigrationBatchStatus.needsInput) ...[
                      const SizedBox(width: 4),
                      const AppIcon(AppIcons.chevronForward, size: 14),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MigrationStatusBatchPanel extends StatelessWidget {
  const _MigrationStatusBatchPanel({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
    required this.completionLabel,
    required this.spendableLabel,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;
  final String completionLabel;
  final String spendableLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 396,
      height: 540,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 57.5,
            width: 396,
            height: 329,
            child: _MigrationStatusBatchWrap(
              values: values,
              partNumbers: partNumbers,
              totalZatoshi: totalZatoshi,
              statuses: statuses,
              progresses: progresses,
            ),
          ),
          Positioned(
            left: 0,
            top: 410.5,
            width: 396,
            height: 52,
            child: _MigrationBatchFooter(
              completionLabel: completionLabel,
              secondLabel: 'Currently Spendable Balance',
              secondValue: spendableLabel,
            ),
          ),
          const Positioned(
            left: 83,
            top: 486.5,
            width: 230,
            height: 40,
            child: _MigrationStatusInfo(),
          ),
        ],
      ),
    );
  }
}

class _MigrationStatusBatchWrap extends StatelessWidget {
  const _MigrationStatusBatchWrap({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 12,
          width: 396,
          height: 65,
          child: _MigrationStatusBatchChart(
            values: values,
            totalZatoshi: totalZatoshi,
            statuses: statuses,
            progresses: progresses,
          ),
        ),
        Positioned(
          left: 0,
          top: 101,
          width: 396,
          height: 216,
          child: _MigrationStatusBatchRows(
            values: values,
            partNumbers: partNumbers,
            totalZatoshi: totalZatoshi,
            statuses: statuses,
          ),
        ),
      ],
    );
  }
}

class _MigrationStatusBatchChart extends StatelessWidget {
  const _MigrationStatusBatchChart({
    required this.values,
    required this.totalZatoshi,
    required this.statuses,
    required this.progresses,
  });

  final List<BigInt> values;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;
  final List<double> progresses;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 8,
          width: 396,
          height: 29,
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Migration',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                    ),
                    children: [
                      TextSpan(
                        text: values.length == 1
                            ? '  1 note'
                            : '  ${values.length} notes',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatMigrationTotal(totalZatoshi)} ZEC',
                maxLines: 1,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 45,
          width: 396,
          height: 12,
          child: Row(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  flex: _migrationSegmentFlex(values[i], totalZatoshi),
                  child: _MigrationProgressSegment(
                    index: i,
                    status: i < statuses.length
                        ? statuses[i]
                        : _MigrationBatchStatus.none,
                    progress: _migrationSegmentProgress(
                      values: values,
                      totalZatoshi: totalZatoshi,
                      statuses: statuses,
                      progresses: progresses,
                      index: i,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MigrationStatusBatchRows extends StatelessWidget {
  const _MigrationStatusBatchRows({
    required this.values,
    required this.partNumbers,
    required this.totalZatoshi,
    required this.statuses,
  });

  final List<BigInt> values;
  final List<int> partNumbers;
  final BigInt totalZatoshi;
  final List<_MigrationBatchStatus> statuses;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final isLast = index == values.length - 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MigrationStatusBatchRow(
              key: ValueKey('ironwood_migration_status_batch_$index'),
              partNumber: index < partNumbers.length
                  ? partNumbers[index]
                  : index + 1,
              value: values[index],
              totalZatoshi: totalZatoshi,
              status: index < statuses.length
                  ? statuses[index]
                  : _MigrationBatchStatus.none,
            ),
            if (!isLast) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: context.colors.border.subtle,
              ),
              const SizedBox(height: 11),
            ],
          ],
        );
      },
    );
  }
}

class _MigrationStatusBatchRow extends StatelessWidget {
  const _MigrationStatusBatchRow({
    super.key,
    required this.partNumber,
    required this.value,
    required this.totalZatoshi,
    required this.status,
  });

  final int partNumber;
  final BigInt value;
  final BigInt totalZatoshi;
  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final opacity = status == _MigrationBatchStatus.scheduled ? 0.5 : 1.0;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 90,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Part $partNumber',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: _MigrationBatchAmountLabel(
                value: value,
                totalZatoshi: totalZatoshi,
              ),
            ),
            SizedBox(
              width: 130,
              child: _MigrationBatchStatusLabel(status: status),
            ),
          ],
        ),
      ),
    );
  }
}

class _MigrationBatchAmountLabel extends StatelessWidget {
  const _MigrationBatchAmountLabel({
    required this.value,
    required this.totalZatoshi,
  });

  final BigInt value;
  final BigInt totalZatoshi;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '${_formatZecAmountCompact(value)} ZEC',
        style: AppTypography.labelLarge.copyWith(
          color: context.colors.text.accent,
        ),
        children: [
          TextSpan(
            text: ' ${_migrationPercentage(value, totalZatoshi)}',
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
    );
  }
}

class _MigrationBatchStatusLabel extends StatelessWidget {
  const _MigrationBatchStatusLabel({required this.status});

  final _MigrationBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = switch (status) {
      _MigrationBatchStatus.none => null,
      _MigrationBatchStatus.preparing => 'Preparing',
      _MigrationBatchStatus.scheduled => 'Scheduled',
      _MigrationBatchStatus.migrating => 'Migrating...',
      _MigrationBatchStatus.confirming => 'Confirming...',
      _MigrationBatchStatus.complete => 'Completed',
      _MigrationBatchStatus.needsInput => 'Needs input',
    };
    if (label == null) return const SizedBox.shrink();

    final isScheduled = status == _MigrationBatchStatus.scheduled;
    final textColor = status == _MigrationBatchStatus.needsInput
        ? const Color(0xFFB83AD9)
        : isScheduled
        ? colors.text.primary
        : colors.text.accent;
    final textStyle = AppTypography.labelLarge.copyWith(
      color: textColor,
      fontWeight: isScheduled ? FontWeight.w400 : FontWeight.w500,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (status == _MigrationBatchStatus.complete) ...[
          AppIcon(AppIcons.checkCircle, size: 16, color: colors.icon.regular),
          const SizedBox(width: 4),
        ] else if (status == _MigrationBatchStatus.migrating ||
            status == _MigrationBatchStatus.confirming) ...[
          AppIcon(AppIcons.loader, size: 16, color: colors.icon.regular),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: textStyle,
          ),
        ),
        if (status == _MigrationBatchStatus.needsInput) ...[
          const SizedBox(width: 4),
          const AppIcon(
            AppIcons.chevronForward,
            size: 16,
            color: Color(0xFFB83AD9),
          ),
        ],
      ],
    );
  }
}

class _MigrationStatusInfo extends StatelessWidget {
  const _MigrationStatusInfo();

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.labelLarge.copyWith(
      color: context.colors.text.secondary,
    );
    return Column(
      children: [
        Text(
          'You can leave this screen.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
        const SizedBox(height: 8),
        Text(
          'But keep Vizor open & running.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: style,
        ),
      ],
    );
  }
}

int _migrationSegmentFlex(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return 1;
  final flex = ((value * BigInt.from(1000)) ~/ total).toInt();
  return flex.clamp(1, 1000);
}

String _migrationPercentage(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return '';
  final tenths = ((value * BigInt.from(1000)) ~/ total).toInt();
  final whole = tenths ~/ 10;
  final decimal = tenths % 10;
  return decimal == 0 ? '$whole%' : '$whole.$decimal%';
}

String _formatMigrationTotal(BigInt zatoshi) {
  final whole = zatoshi ~/ BigInt.from(100000000);
  final hundredths =
      (zatoshi.remainder(BigInt.from(100000000)) ~/ BigInt.from(1000000))
          .toString()
          .padLeft(2, '0');
  return '$whole.$hundredths';
}

String _migrationSpendableBalanceLabel({
  required List<BigInt> values,
  required List<_MigrationBatchStatus> statuses,
}) {
  var spendable = BigInt.zero;
  for (var i = 0; i < values.length; i++) {
    if (i < statuses.length && statuses[i] == _MigrationBatchStatus.complete) {
      spendable += values[i];
    }
  }
  return '${_formatZecAmountCompact(spendable)} ZEC';
}

class _MigrationStatusContent extends StatelessWidget {
  const _MigrationStatusContent({
    required this.status,
    required this.action,
    required this.isAdvancing,
    required this.currentHeight,
    required this.onAction,
  });

  final rust_sync.MigrationStatus status;
  final _StatusAction action;
  final bool isAdvancing;
  final int currentHeight;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final parts = [...status.parts];
    var values = parts.isNotEmpty
        ? [for (final part in parts) part.valueZatoshi]
        : [for (final value in status.targetValuesZatoshi) value];
    if (values.isEmpty) values = [BigInt.zero];
    final partNumbers = parts.isNotEmpty
        ? [for (final part in parts) part.partIndex + 1]
        : [for (var i = 0; i < values.length; i++) i + 1];
    final statuses = parts.isNotEmpty
        ? [for (final part in parts) _migrationBatchStatus(part.state)]
        : _legacyMigrationBatchStatuses(status, values.length);
    if (action == _StatusAction.needsInput &&
        !statuses.contains(_MigrationBatchStatus.needsInput)) {
      final inputIndex = statuses.indexWhere(
        (status) => status != _MigrationBatchStatus.complete,
      );
      if (inputIndex >= 0) {
        statuses[inputIndex] = _MigrationBatchStatus.needsInput;
      }
    }
    final progresses = _migrationBatchProgresses(
      status: status,
      parts: parts,
      statuses: statuses,
      currentHeight: currentHeight,
      isAdvancing: isAdvancing,
    );
    final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
    final spendableLabel = _migrationSpendableBalanceLabel(
      values: values,
      statuses: statuses,
    );
    final buttonLabel = switch (action) {
      _StatusAction.needsInput => 'Sign with Keystone',
      _StatusAction.retry => 'Retry migration',
      _ => 'Go home',
    };
    final actionRequiresContinuation =
        action == _StatusAction.needsInput || action == _StatusAction.retry;

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 37.5,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Migration in Progress',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 24,
            width: 396,
            height: 540,
            child: _MigrationStatusBatchPanel(
              values: values,
              partNumbers: partNumbers,
              totalZatoshi: total,
              statuses: statuses,
              progresses: progresses,
              completionLabel: _transferEstimatedArrival(status),
              spendableLabel: spendableLabel,
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey('ironwood_migration_status_action_button'),
                onPressed: isAdvancing && actionRequiresContinuation
                    ? null
                    : actionRequiresContinuation
                    ? onAction
                    : () => context.go('/home'),
                variant: actionRequiresContinuation
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                height: 36,
                minWidth: action == _StatusAction.needsInput ? 150 : 96,
                expand: false,
                child: SizedBox(
                  width: action == _StatusAction.needsInput
                      ? 118
                      : action == _StatusAction.retry
                      ? 92
                      : 64,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(buttonLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

_MigrationBatchStatus _migrationBatchStatus(
  rust_sync.MigrationPartState state,
) => switch (state) {
  rust_sync.MigrationPartState.preparing => _MigrationBatchStatus.preparing,
  rust_sync.MigrationPartState.scheduled => _MigrationBatchStatus.scheduled,
  rust_sync.MigrationPartState.migrating => _MigrationBatchStatus.migrating,
  rust_sync.MigrationPartState.confirming => _MigrationBatchStatus.confirming,
  rust_sync.MigrationPartState.completed => _MigrationBatchStatus.complete,
  rust_sync.MigrationPartState.needsInput => _MigrationBatchStatus.needsInput,
};

List<_MigrationBatchStatus> _legacyMigrationBatchStatuses(
  rust_sync.MigrationStatus status,
  int count,
) {
  final hasBroadcastSchedule =
      status.scheduledBroadcasts.isNotEmpty ||
      status.phase == kIronwoodMigrationBroadcastScheduledPhase ||
      status.phase == kIronwoodMigrationBroadcastingPhase ||
      status.phase == kIronwoodMigrationWaitingConfirmationsPhase;
  final submittedCount = status.confirmedTxCount + status.broadcastedTxCount;
  return [
    for (var i = 0; i < count; i++)
      if (i < status.confirmedTxCount)
        _MigrationBatchStatus.confirming
      else if (i < submittedCount)
        _MigrationBatchStatus.migrating
      else if (hasBroadcastSchedule)
        _MigrationBatchStatus.scheduled
      else
        _MigrationBatchStatus.preparing,
  ];
}

int _currentMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  final scannedHeight = syncState.scannedHeight;
  final chainTipHeight = syncState.chainTipHeight;
  if (scannedHeight > 0 && chainTipHeight > 0) {
    return math.min(scannedHeight, chainTipHeight);
  }
  return math.max(scannedHeight, chainTipHeight);
}

List<double> _migrationBatchProgresses({
  required rust_sync.MigrationStatus status,
  required List<rust_sync.MigrationPartStatus> parts,
  required List<_MigrationBatchStatus> statuses,
  required int currentHeight,
  required bool isAdvancing,
}) {
  if (statuses.isEmpty) return const [];

  if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
    final progress = _prepareMigrationProgress(
      status,
      isAdvancing: isAdvancing,
    );
    return List<double>.filled(statuses.length, progress);
  }

  if (parts.isNotEmpty) {
    return [
      for (var i = 0; i < parts.length; i++)
        _migrationPartStatusProgress(
          part: parts[i],
          visualStatus: i < statuses.length
              ? statuses[i]
              : _migrationBatchStatus(parts[i].state),
          currentHeight: currentHeight,
          isAdvancing: isAdvancing,
        ),
    ];
  }

  return [
    for (var i = 0; i < statuses.length; i++)
      _legacyMigrationBatchProgress(
        status: status,
        visualStatus: statuses[i],
        index: i,
        currentHeight: currentHeight,
        isAdvancing: isAdvancing,
      ),
  ];
}

double _prepareMigrationProgress(
  rust_sync.MigrationStatus status, {
  required bool isAdvancing,
}) {
  final totalStages = status.denominationSplitTotalCount;
  final stageProgress = totalStages > 0
      ? (status.denominationSplitCompletedCount / totalStages).clamp(0, 1)
      : 0.0;

  if (status.pendingSplitStageCount > 0) {
    return math.max(stageProgress.toDouble(), isAdvancing ? 0.18 : 0.12);
  }

  final confirmationTarget = status.denominationConfirmationTarget;
  if (confirmationTarget > 0) {
    final confirmationProgress =
        (status.denominationConfirmationCount / confirmationTarget).clamp(0, 1);
    final combined =
        _prepareBroadcastCommitProgress +
        (1 - _prepareBroadcastCommitProgress) * confirmationProgress;
    return math.max(stageProgress.toDouble(), combined);
  }

  return math.max(stageProgress.toDouble(), isAdvancing ? 0.24 : 0.16);
}

double _migrationPartStatusProgress({
  required rust_sync.MigrationPartStatus part,
  required _MigrationBatchStatus visualStatus,
  required int currentHeight,
  required bool isAdvancing,
}) {
  if (visualStatus == _MigrationBatchStatus.needsInput) {
    return math.max(
      _scheduledBlockProgress(
        startHeight: part.scheduleStartHeight,
        targetHeight: part.scheduledHeight,
        currentHeight: currentHeight,
      ),
      _scheduledBlockProgressCap,
    );
  }

  return switch (part.state) {
    rust_sync.MigrationPartState.preparing => 0.12,
    rust_sync.MigrationPartState.scheduled => _scheduledBlockProgress(
      startHeight: part.scheduleStartHeight,
      targetHeight: part.scheduledHeight,
      currentHeight: currentHeight,
    ),
    rust_sync.MigrationPartState.migrating =>
      isAdvancing ? _broadcastCommitProgressCap : _scheduledBlockProgressCap,
    rust_sync.MigrationPartState.confirming => _confirmationProgress(
      confirmationCount: part.confirmationCount,
      confirmationTarget: part.confirmationTarget,
    ),
    rust_sync.MigrationPartState.completed => 1,
    rust_sync.MigrationPartState.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyMigrationBatchProgress({
  required rust_sync.MigrationStatus status,
  required _MigrationBatchStatus visualStatus,
  required int index,
  required int currentHeight,
  required bool isAdvancing,
}) {
  return switch (visualStatus) {
    _MigrationBatchStatus.none => 1,
    _MigrationBatchStatus.preparing => isAdvancing ? 0.18 : 0.12,
    _MigrationBatchStatus.scheduled => _legacyScheduledProgress(
      status,
      index,
      currentHeight: currentHeight,
    ),
    _MigrationBatchStatus.migrating =>
      isAdvancing ? _broadcastCommitProgressCap : _scheduledBlockProgressCap,
    _MigrationBatchStatus.confirming =>
      status.totalCount > 0
          ? _confirmationProgress(
              confirmationCount: status.confirmedTxCount,
              confirmationTarget: status.totalCount,
            )
          : _broadcastCommitProgressCap,
    _MigrationBatchStatus.complete => 1,
    _MigrationBatchStatus.needsInput => _scheduledBlockProgressCap,
  };
}

double _legacyScheduledProgress(
  rust_sync.MigrationStatus status,
  int index, {
  required int currentHeight,
}) {
  final scheduled = [...status.scheduledBroadcasts]
    ..sort((a, b) => a.scheduledHeight.compareTo(b.scheduledHeight));
  if (index >= scheduled.length) return 0;
  final broadcast = scheduled[index];
  return _scheduledBlockProgress(
    startHeight: broadcast.scheduleStartHeight,
    targetHeight: broadcast.scheduledHeight,
    currentHeight: currentHeight,
  );
}

double _scheduledBlockProgress({
  required int? startHeight,
  required int? targetHeight,
  required int currentHeight,
}) {
  if (targetHeight == null || currentHeight <= 0) return 0;
  final effectiveStart = startHeight ?? math.max(0, targetHeight - 1);
  if (targetHeight <= effectiveStart) {
    return currentHeight >= targetHeight ? _scheduledBlockProgressCap : 0;
  }
  final elapsed = (currentHeight - effectiveStart).clamp(
    0,
    targetHeight - effectiveStart,
  );
  return _scheduledBlockProgressCap *
      (elapsed / (targetHeight - effectiveStart));
}

double _confirmationProgress({
  required int confirmationCount,
  required int confirmationTarget,
}) {
  if (confirmationTarget <= 0) return _broadcastCommitProgressCap;
  final confirmationRatio = (confirmationCount / confirmationTarget).clamp(
    0,
    1,
  );
  return _broadcastCommitProgressCap +
      (1 - _broadcastCommitProgressCap) * confirmationRatio;
}

String _privateMigrationStartErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('mnemonic')) {
    return "Secret Passphrase isn't available for this account.";
  }
  if (lower.contains('secret storage') || lower.contains('unlocked session')) {
    return 'Unlock Vizor before starting migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't start migration. Try again.";
}

String _privateMigrationContinueErrorMessage(Object error) {
  final message = error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('secret storage') || lower.contains('unlocked session')) {
    return 'Unlock Vizor before continuing migration.';
  }
  if (lower.contains('sync')) {
    return 'Wait for sync to finish, then try again.';
  }
  if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
    return "Couldn't broadcast the migration transaction. Try again.";
  }
  return "Couldn't continue migration. Try again.";
}

// Kept for the unavailable-state fallback used by older deep links.
// ignore: unused_element
class _PrivateReviewLoading extends StatelessWidget {
  const _PrivateReviewLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 254,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.background.ground,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _PrivateReviewUnavailable extends StatelessWidget {
  const _PrivateReviewUnavailable({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 254,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppIcon(AppIcons.warning, size: 24),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _PrivateReviewPlan extends StatelessWidget {
  const _PrivateReviewPlan({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final feeText =
        '~${_formatZecAmountCompact(plan.estimatedTotalFeeZatoshi)} ZEC';
    final orchardRemainderText =
        '~${_formatZecAmountCompact(plan.orchardChangeZatoshi ?? BigInt.zero)} ZEC';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ReviewTextRow(
                    key: const ValueKey('ironwood_migration_schedule_view'),
                    label: '${plan.plannedBatchCount} Planned batches',
                    value: 'View',
                    trailingIcon: AppIcons.chevronForward,
                    semiboldLabel: true,
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _MigrationScheduleDialog(plan: plan),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReviewTextRow(
                    label: 'Estimated arrival time',
                    value: _estimatedMigrationArrivalLabel(plan),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ReviewTextRow(
                    label: 'Fees (estimate)',
                    value: 'Total, $feeText',
                    mutedLabel: true,
                  ),
                  const SizedBox(height: 14),
                  _ReviewTextRow(
                    label: 'Orchard remains',
                    value: orchardRemainderText,
                    trailingIcon: AppIcons.help,
                    mutedLabel: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIcon(AppIcons.shieldKeyhole, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Separate windows reduce correlation — the total '
                      'crossing amount stays publicly visible. Spending is '
                      'best effort, not a delivery time.',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MigrationScheduleDialog extends StatelessWidget {
  const _MigrationScheduleDialog({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Migration schedule',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Broadcast heights are relative to the block where the '
                'migration transactions are prepared.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: ListView.separated(
                  key: const ValueKey('ironwood_migration_schedule_list'),
                  shrinkWrap: true,
                  itemCount: plan.scheduledTransfers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final transfer = plan.scheduledTransfers[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _ReviewTextRow(
                        key: ValueKey(
                          'ironwood_migration_schedule_batch_$index',
                        ),
                        label: 'Part ${index + 1}',
                        value:
                            '${_formatZecAmountCompact(transfer.valueZatoshi)} '
                            'ZEC  ·  +${transfer.blockOffset} blocks',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('ironwood_migration_schedule_close'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTextRow extends StatelessWidget {
  const _ReviewTextRow({
    super.key,
    required this.label,
    required this.value,
    this.trailingIcon,
    this.mutedLabel = false,
    this.semiboldLabel = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? trailingIcon;
  final bool mutedLabel;
  final bool semiboldLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rowStyle = mutedLabel
        ? AppTypography.bodyMediumStrong
        : AppTypography.labelLarge;
    final row = Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: rowStyle.copyWith(
              color: mutedLabel ? colors.text.secondary : colors.text.accent,
              fontWeight: semiboldLabel ? FontWeight.w600 : rowStyle.fontWeight,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: rowStyle.copyWith(color: colors.text.accent),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                AppIcon(trailingIcon!, size: 12, color: colors.icon.regular),
              ],
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

// ignore: unused_element
class _PrivateDenominationWaitingStatusContent extends StatelessWidget {
  const _PrivateDenominationWaitingStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final targetTotal = _sumTargetValues(status);
    final amountText = targetTotal > BigInt.zero
        ? '${_formatZecAmountCompact(targetTotal)} ZEC'
        : '${status.preparedNoteCount} notes';

    return SizedBox(
      key: const ValueKey(
        'ironwood_migration_status_waiting_denom_confirmations',
      ),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 22,
            top: 16,
            width: 376,
            height: 130,
            child: CustomPaint(
              painter: _PreparingArcPainter(
                dotColor: colors.icon.muted.withValues(alpha: 0.24),
                primaryDotColor: colors.icon.muted.withValues(alpha: 0.16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 102,
            width: 420,
            child: Column(
              children: [
                Text(
                  amountText,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: appSerifDisplayStyle(
                    color: colors.text.secondary,
                  ).copyWith(fontSize: 39, height: 42 / 39),
                ),
                const SizedBox(height: 12),
                Text(
                  presentation.body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 246,
            width: 396,
            child: _MigrationPreparationStepsCard(status: status),
          ),
          Positioned(
            left: 70,
            top: 510,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _PrivateMigrationTransferStatusContent extends StatelessWidget {
  const _PrivateMigrationTransferStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = _transferProgress(status);
    final percent = (progress * 100).round().clamp(0, 100);
    final plannedBatchCount = _plannedTransferBatchCount(status);
    final currentBatchIndex = _currentTransferBatchIndex(status);
    final currentBatchAmount = _currentTransferBatchAmount(
      status,
      plannedBatchCount: plannedBatchCount,
    );
    final leftToTransfer = _leftToTransferAmount(status, progress: progress);

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 38,
            top: 42,
            width: 344,
            height: 130,
            child: CustomPaint(
              painter: _MigrationProgressArcPainter(
                progress: progress,
                trackColor: colors.icon.muted.withValues(alpha: 0.20),
                progressColor: GreenPrimitives.p500Light,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 143,
            width: 420,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: appSerifDisplayStyle(
                    color: colors.text.accent,
                  ).copyWith(fontSize: 45, height: 48 / 45),
                ),
                const SizedBox(height: 4),
                Text(
                  'Left to transfer: '
                  '${leftToTransfer.isEstimated ? '~' : ''}'
                  '${_formatZecAmountCompact(leftToTransfer.value)} ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 278,
            width: 396,
            child: _MigrationTransferBatchCard(
              plannedBatchCount: plannedBatchCount,
              currentBatchIndex: currentBatchIndex,
              currentBatchValue: currentBatchAmount.value,
              currentBatchValueIsEstimated: currentBatchAmount.isEstimated,
              currentBatchStatus: _currentTransferBatchStatus(status),
              estimatedArrival: _transferEstimatedArrival(status),
            ),
          ),
          Positioned(
            left: 70,
            top: 552,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationProgressArcPainter extends CustomPainter {
  const _MigrationProgressArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 12, size.width - 36, size.height * 1.8);
    const startAngle = math.pi * 1.14;
    const sweepAngle = math.pi * 0.72;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, startAngle, sweepAngle, false, trackPaint);

    if (progress <= 0) return;
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MigrationProgressArcPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}

class _MigrationTransferBatchCard extends StatelessWidget {
  const _MigrationTransferBatchCard({
    required this.plannedBatchCount,
    required this.currentBatchIndex,
    required this.currentBatchValue,
    required this.currentBatchValueIsEstimated,
    required this.currentBatchStatus,
    required this.estimatedArrival,
  });

  final int plannedBatchCount;
  final int currentBatchIndex;
  final BigInt currentBatchValue;
  final bool currentBatchValueIsEstimated;
  final String currentBatchStatus;
  final String estimatedArrival;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$plannedBatchCount Planned batches',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  'View',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: colors.icon.regular,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Current Batch',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  currentBatchIndex.toString().padLeft(2, '0'),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: GoldPrimitives.p300Light,
                    shape: OvalBorder(),
                  ),
                  child: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(
                      child: AppIcon(
                        AppIcons.zcashCurrency,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${currentBatchValueIsEstimated ? '~' : ''}'
                    '${_formatZecAmountCompact(currentBatchValue)} ZEC',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  currentBatchStatus,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(height: 1, thickness: 1, color: colors.border.subtle),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated arrival time',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Text(
                  estimatedArrival,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreparingArcPainter extends CustomPainter {
  const _PreparingArcPainter({
    required this.dotColor,
    required this.primaryDotColor,
  });

  final Color dotColor;
  final Color primaryDotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 23);
    final xRadius = size.width * 0.49;
    final yRadius = size.height * 0.82;
    final dotPaint = Paint()..color = dotColor;
    for (var i = 0; i <= 28; i++) {
      final t = i / 28;
      final angle = math.pi + (math.pi * t);
      final wave = math.sin(t * math.pi * 6) * 2.8;
      final r = 2.2 + (math.sin(t * math.pi * 9).abs() * 5.4);
      final point = Offset(
        center.dx + math.cos(angle) * (xRadius + wave),
        center.dy + math.sin(angle) * (yRadius + wave),
      );
      canvas.drawCircle(point, r, dotPaint);
    }

    final primaryPaint = Paint()..color = primaryDotColor;
    canvas
      ..drawCircle(Offset(center.dx, 14), 17, primaryPaint)
      ..drawCircle(Offset(center.dx - 39, 18), 9, primaryPaint)
      ..drawCircle(Offset(center.dx + 40, 19), 6.5, primaryPaint);
  }

  @override
  bool shouldRepaint(covariant _PreparingArcPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.primaryDotColor != primaryDotColor;
  }
}

class _MigrationPreparationStepsCard extends StatelessWidget {
  const _MigrationPreparationStepsCard({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = status.denominationConfirmationTarget;
    final confirmationCount = target > 0
        ? math.min(status.denominationConfirmationCount, target)
        : status.denominationConfirmationCount;
    final confirmationComplete = target > 0 && confirmationCount >= target;
    final scheduleReady =
        status.denominationSplitTotalCount > 0 &&
        status.denominationSplitCompletedCount >=
            status.denominationSplitTotalCount;
    final confirmationLabel = target > 0
        ? '$confirmationCount/$target'
        : '$confirmationCount confirmations';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 50, 18, 54),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 62,
              height: 112,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.border.subtle,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: const SizedBox(width: 2),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MigrationPreparationStepRow(
                  state: _MigrationPreparationStepState.complete,
                  label: 'Transaction splits submitted',
                ),
                const SizedBox(height: 32),
                _MigrationPreparationStepRow(
                  state: confirmationComplete
                      ? _MigrationPreparationStepState.complete
                      : _MigrationPreparationStepState.active,
                  label: 'Waiting for confirmation ...',
                  trailing: confirmationLabel,
                ),
                const SizedBox(height: 32),
                _MigrationPreparationStepRow(
                  state: scheduleReady
                      ? _MigrationPreparationStepState.complete
                      : confirmationComplete
                      ? _MigrationPreparationStepState.active
                      : _MigrationPreparationStepState.pending,
                  stepNumber: 3,
                  label: 'Migration schedule',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _MigrationPreparationStepState { complete, active, pending }

class _MigrationPreparationStepRow extends StatelessWidget {
  const _MigrationPreparationStepRow({
    required this.state,
    required this.label,
    this.stepNumber,
    this.trailing,
  });

  final _MigrationPreparationStepState state;
  final String label;
  final int? stepNumber;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _MigrationPreparationStepBadge(state: state, stepNumber: stepNumber),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: state == _MigrationPreparationStepState.pending
                  ? colors.text.secondary
                  : colors.text.accent,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.raised,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Text(
                trailing!,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MigrationPreparationStepBadge extends StatelessWidget {
  const _MigrationPreparationStepBadge({
    required this.state,
    required this.stepNumber,
  });

  final _MigrationPreparationStepState state;
  final int? stepNumber;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = switch (state) {
      _MigrationPreparationStepState.complete => GreenPrimitives.p500Light,
      _MigrationPreparationStepState.active => colors.background.inverse,
      _MigrationPreparationStepState.pending => colors.background.raised,
    };
    final foregroundColor = switch (state) {
      _MigrationPreparationStepState.complete => Colors.white,
      _MigrationPreparationStepState.active => colors.icon.inverse,
      _MigrationPreparationStepState.pending => colors.text.secondary,
    };

    return SizedBox(
      width: 24,
      height: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor,
          shape: const OvalBorder(),
        ),
        child: Center(
          child: switch (state) {
            _MigrationPreparationStepState.complete => AppIcon(
              AppIcons.check,
              size: 14,
              color: foregroundColor,
            ),
            _MigrationPreparationStepState.active => AppIcon(
              AppIcons.loader,
              size: 15,
              color: foregroundColor,
              animated: false,
            ),
            _MigrationPreparationStepState.pending => Text(
              '${stepNumber ?? ''}',
              style: AppTypography.labelMedium.copyWith(color: foregroundColor),
            ),
          },
        ),
      ),
    );
  }
}

class _ReviewMetricRow extends StatelessWidget {
  const _ReviewMetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: const Color(0xFFE3FBEE),
              shape: const OvalBorder(),
            ),
            child: Center(
              child: AppIcon(icon, size: 16, color: GreenPrimitives.p500Light),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatZecAmountCompact(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).compactBalancePretty(minFractionDigits: 0, maxFractionDigits: 4).amountText;
}

double _transferProgress(rust_sync.MigrationStatus status) {
  final partProgress = _migrationPartProgress(status);
  if (partProgress != null) return partProgress;

  if (status.totalCount > 0) {
    final transferredCount = _transferCompletedCountForPhase(status);
    final progress = (transferredCount / status.totalCount)
        .clamp(0, 1)
        .toDouble();
    if (_isWaitingForTrustedMigrationComplete(status)) {
      return math.min(progress, 0.99);
    }
    return progress;
  }

  final explicitProgress = _statusProgress(status);
  if (explicitProgress != null) return explicitProgress.clamp(0, 1);

  return switch (status.phase) {
    kIronwoodMigrationBroadcastScheduledPhase => 0.45,
    kIronwoodMigrationBroadcastingPhase => 0.65,
    kIronwoodMigrationWaitingConfirmationsPhase => 0.85,
    _ => 0,
  };
}

bool _isWaitingForTrustedMigrationComplete(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.phase == kIronwoodMigrationWaitingConfirmationsPhase &&
        status.parts.every(
          (part) =>
              part.state == rust_sync.MigrationPartState.confirming ||
              part.state == rust_sync.MigrationPartState.completed,
        ) &&
        status.parts.any(
          (part) => part.state == rust_sync.MigrationPartState.confirming,
        );
  }
  return status.phase == kIronwoodMigrationWaitingConfirmationsPhase &&
      status.totalCount > 0 &&
      status.confirmedTxCount >= status.totalCount;
}

int _transferCompletedCountForPhase(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) {
    return status.parts
        .where(
          (part) =>
              part.state == rust_sync.MigrationPartState.confirming ||
              part.state == rust_sync.MigrationPartState.completed,
        )
        .length;
  }
  return switch (status.phase) {
    kIronwoodMigrationWaitingConfirmationsPhase => status.confirmedTxCount,
    kIronwoodMigrationBroadcastingPhase => status.broadcastedTxCount,
    _ => math.max(status.confirmedTxCount, status.broadcastedTxCount),
  };
}

_TransferAmount _leftToTransferAmount(
  rust_sync.MigrationStatus status, {
  required double progress,
}) {
  final total = _sumTargetValues(status);
  if (total <= BigInt.zero) {
    return _TransferAmount(value: BigInt.zero, isEstimated: false);
  }

  if (status.totalCount > 0) {
    if (_isWaitingForTrustedMigrationComplete(status)) {
      return _leftToTransferAmountFromProgress(total, progress);
    }
    final completedCount = math.min(
      status.totalCount,
      _transferCompletedCountForPhase(status),
    );
    final transferred =
        (total * BigInt.from(completedCount)) ~/ BigInt.from(status.totalCount);
    final left = total - transferred;
    return _TransferAmount(
      value: left > BigInt.zero ? left : BigInt.zero,
      isEstimated: completedCount > 0 && completedCount < status.totalCount,
    );
  }

  return _leftToTransferAmountFromProgress(total, progress);
}

_TransferAmount _leftToTransferAmountFromProgress(
  BigInt total,
  double progress,
) {
  final scaledProgress = BigInt.from((progress.clamp(0, 1) * 10000).round());
  final transferred = (total * scaledProgress) ~/ BigInt.from(10000);
  final left = total - transferred;
  return _TransferAmount(
    value: left > BigInt.zero ? left : BigInt.zero,
    isEstimated:
        scaledProgress > BigInt.zero && scaledProgress < BigInt.from(10000),
  );
}

int _plannedTransferBatchCount(rust_sync.MigrationStatus status) {
  if (status.parts.isNotEmpty) return status.parts.length;
  if (status.totalCount > 0) return status.totalCount;

  final progressedCount = status.broadcastedTxCount > status.confirmedTxCount
      ? status.broadcastedTxCount
      : status.confirmedTxCount;
  final countFromProgress = status.pendingTxCount + progressedCount;
  if (countFromProgress > 0) return countFromProgress;
  if (status.scheduledBroadcasts.isNotEmpty) {
    return status.scheduledBroadcasts.length;
  }

  return math.max(1, status.denominationSplitTotalCount);
}

int _currentTransferBatchIndex(rust_sync.MigrationStatus status) {
  final planned = _plannedTransferBatchCount(status);
  if (status.parts.isNotEmpty) {
    final firstIncomplete = status.parts.indexWhere(
      (part) => part.state != rust_sync.MigrationPartState.completed,
    );
    return firstIncomplete < 0 ? planned : firstIncomplete + 1;
  }
  final completedOrSubmitted = switch (status.phase) {
    kIronwoodMigrationWaitingConfirmationsPhase => status.confirmedTxCount,
    kIronwoodMigrationBroadcastingPhase => status.broadcastedTxCount,
    _ => math.max(status.confirmedTxCount, status.broadcastedTxCount),
  };
  return math.min(planned, math.max(1, completedOrSubmitted + 1));
}

double? _migrationPartProgress(rust_sync.MigrationStatus status) {
  if (status.parts.isEmpty) return null;
  var progress = 0.0;
  for (final part in status.parts) {
    progress += switch (part.state) {
      rust_sync.MigrationPartState.completed => 1,
      rust_sync.MigrationPartState.confirming
          when part.confirmationTarget > 0 =>
        (part.confirmationCount / part.confirmationTarget).clamp(0, 1),
      _ => 0,
    };
  }
  return (progress / status.parts.length).clamp(0, 1);
}

class _TransferAmount {
  const _TransferAmount({required this.value, required this.isEstimated});

  final BigInt value;
  final bool isEstimated;
}

_TransferAmount _currentTransferBatchAmount(
  rust_sync.MigrationStatus status, {
  required int plannedBatchCount,
}) {
  final total = _sumTargetValues(status);
  if (total <= BigInt.zero) {
    return _TransferAmount(value: BigInt.zero, isEstimated: false);
  }
  return _TransferAmount(
    value: total ~/ BigInt.from(math.max(1, plannedBatchCount)),
    isEstimated: true,
  );
}

String _currentTransferBatchStatus(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationBroadcastScheduledPhase => 'Scheduled',
    kIronwoodMigrationBroadcastingPhase => 'Broadcasting...',
    kIronwoodMigrationWaitingConfirmationsPhase => 'Confirming...',
    _ => 'In progress',
  };
}

String _transferEstimatedArrival(rust_sync.MigrationStatus status) {
  final nextScheduledBroadcast = _nextScheduledBroadcast(status);
  if (nextScheduledBroadcast != null) {
    return 'Block ${nextScheduledBroadcast.scheduledHeight}';
  }

  if (status.phase == kIronwoodMigrationWaitingConfirmationsPhase) {
    return 'Confirming';
  }

  return '~${status.scheduleMeanDelayBlocks} blocks';
}

rust_sync.MigrationScheduledBroadcast? _nextScheduledBroadcast(
  rust_sync.MigrationStatus status,
) {
  rust_sync.MigrationScheduledBroadcast? fallbackScheduled;
  for (final broadcast in status.scheduledBroadcasts) {
    if (broadcast.status != 'scheduled') continue;
    fallbackScheduled ??= broadcast;
  }
  return fallbackScheduled;
}

String _estimatedMigrationArrivalLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final estimatedBlocks = _estimatedMigrationCompletionBlocks(plan);
  if (estimatedBlocks <= 0) return 'Not scheduled';
  return _formatMigrationBlockDurationEstimate(estimatedBlocks);
}

int _estimatedMigrationCompletionBlocks(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final scheduleBlocks = plan.scheduledTransfers.fold<int>(
    0,
    (maxOffset, transfer) => math.max(maxOffset, transfer.blockOffset),
  );
  final fallbackBatchCount = plan.plannedBatchCount < 1
      ? 1
      : plan.plannedBatchCount;
  final fallbackScheduleBlocks =
      plan.scheduleMeanDelayBlocks * fallbackBatchCount;
  final preparedScheduleBlocks = scheduleBlocks > 0
      ? scheduleBlocks
      : fallbackScheduleBlocks;
  if (preparedScheduleBlocks <= 0) return 0;

  final int prepareBlocks = plan.denominationSplitStageCount <= 0
      ? 0
      : plan.denominationSplitStageCount * _migrationPrepareConfirmationBlocks +
            _migrationPrepareBroadcastBufferBlocks;
  return preparedScheduleBlocks + prepareBlocks;
}

String _formatMigrationBlockDurationEstimate(int blocks) {
  if (blocks <= 0) return 'Not scheduled';
  final duration = Duration(
    seconds: blocks * _migrationEstimatedSecondsPerBlock,
  );
  final minutes = (duration.inSeconds / Duration.secondsPerMinute).ceil();
  if (minutes < 60) {
    return minutes == 1 ? '~1 min' : '~$minutes mins';
  }

  final hours = (duration.inSeconds / Duration.secondsPerHour).ceil();
  if (hours < 48) {
    return hours == 1 ? '~1 hr' : '~$hours hrs';
  }

  final days = (duration.inSeconds / Duration.secondsPerDay).ceil();
  return days == 1 ? '~1 day' : '~$days days';
}

class _FlowButtons extends StatelessWidget {
  const _FlowButtons({
    this.primaryKey,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.secondaryLeading,
    this.secondaryFirst = false,
    this.spacing = 20,
  });

  final Key? primaryKey;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final Widget? secondaryLeading;
  final bool secondaryFirst;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final primaryButton = AppButton(
      key: primaryKey,
      onPressed: onPrimary,
      height: 44,
      minWidth: 230,
      expand: true,
      constrainContent: true,
      trailing: const AppIcon(AppIcons.chevronForward, size: 20),
      child: Text(primaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final secondaryButton = AppButton(
      onPressed: onSecondary,
      variant: AppButtonVariant.ghost,
      height: 36,
      minWidth: 230,
      expand: true,
      constrainContent: true,
      leading: secondaryLeading,
      child: Text(secondaryLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final children = secondaryFirst
        ? [secondaryButton, SizedBox(height: spacing), primaryButton]
        : [primaryButton, SizedBox(height: spacing), secondaryButton];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _DarkBadge extends StatelessWidget {
  const _DarkBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.colors.background.inverse,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: context.colors.text.inverse,
          ),
        ),
      ),
    );
  }
}

class _PoolMigrationHero extends StatelessWidget {
  const _PoolMigrationHero({required this.data});

  final IronwoodMigrationFlowData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = '${data.amountText} $kZcashDefaultCurrencyTicker';
    final isDark = colors.background.window == AppColors.dark.background.window;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xLarge),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: colors.background.ground,
            child: Image.asset(
              isDark
                  ? _ironwoodMigrationIntroBannerDarkAsset
                  : _ironwoodMigrationIntroBannerLightAsset,
              key: ValueKey(
                'ironwood_migration_intro_banner_${isDark ? 'dark' : 'light'}',
              ),
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            right: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            left: 24,
            top: 116,
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '(Legacy)',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Orchard Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            top: 136,
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Ironwood Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.positiveStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  amount,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessCard extends StatelessWidget {
  const _ProcessCard({required this.steps});

  final List<_ProcessStepData> steps;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              _ProcessStep(step: steps[index]),
              if (index != steps.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessStepData {
  const _ProcessStepData({
    required this.number,
    required this.title,
    required this.body,
  });

  final int number;
  final String title;
  final String body;
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({required this.step});

  final _ProcessStepData step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProcessStepNumber(number: step.number),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.body,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProcessStepNumber extends StatelessWidget {
  const _ProcessStepNumber({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 24,
      height: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.background.base,
          shape: const CircleBorder(),
        ),
        child: Center(
          child: Text(
            '$number',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpendAsFundsArriveCard extends StatelessWidget {
  const _SpendAsFundsArriveCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: AppIcon(
                AppIcons.wallet,
                size: 20,
                color: GreenPrimitives.p400Light,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: colors.text.homeCard),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spend as funds arrive',
                      style: AppTypography.labelMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Each confirmed Ironwood amount is available to '
                      'spend while the rest continues.',
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MigrationMode { private, fast }

class _MigrationOptionCard extends StatelessWidget {
  const _MigrationOptionCard({
    super.key,
    required this.mode,
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
    this.badge,
  });

  final _MigrationMode mode;
  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 104,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(24),
              boxShadow: selected
                  ? const []
                  : const [
                      BoxShadow(
                        color: Color(0x10000000),
                        offset: Offset(0, 2),
                        blurRadius: 10,
                      ),
                    ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _OptionIcon(mode: mode, selected: selected),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodyLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 8),
                                  _RecommendedBadge(label: badge!),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Flexible(
                              child: Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SelectionMark(selected: selected),
                    ],
                  ),
                ),
                if (selected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colors.text.accent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionIcon extends StatelessWidget {
  const _OptionIcon({required this.mode, required this.selected});

  final _MigrationMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.colors.text.accent
        : context.colors.icon.disabled;
    return SizedBox(
      width: 16,
      height: 16,
      child: CustomPaint(
        painter: _OptionIconPainter(mode: mode, color: color),
      ),
    );
  }
}

class _OptionIconPainter extends CustomPainter {
  const _OptionIconPainter({required this.mode, required this.color});

  final _MigrationMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (mode == _MigrationMode.private) {
      final path = Path()
        ..moveTo(8, 1.5)
        ..lineTo(14, 4)
        ..lineTo(13, 10)
        ..quadraticBezierTo(11, 14, 8, 15)
        ..quadraticBezierTo(5, 14, 3, 10)
        ..lineTo(2, 4)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawLine(const Offset(8, 6), const Offset(8, 10), paint);
      canvas.drawLine(const Offset(6, 8), const Offset(10, 8), paint);
    } else {
      canvas.drawLine(const Offset(3, 5), const Offset(11, 5), paint);
      canvas.drawLine(const Offset(8, 2), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(12, 5), paint);
      canvas.drawLine(const Offset(5, 11), const Offset(13, 11), paint);
      canvas.drawLine(const Offset(8, 8), const Offset(5, 11), paint);
      canvas.drawLine(const Offset(8, 14), const Offset(5, 11), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OptionIconPainter oldDelegate) {
    return oldDelegate.mode != mode || oldDelegate.color != color;
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: GreenPrimitives.p500Light,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: const Color(0xFFEAFEEF),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? context.colors.background.inverse
        : context.colors.background.raised;
    return Container(
      width: 20,
      height: 20,
      decoration: ShapeDecoration(color: fill, shape: const OvalBorder()),
      child: selected
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: context.colors.icon.inverse,
              ),
            )
          : null,
    );
  }
}
