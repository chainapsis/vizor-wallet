import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Colors, CircularProgressIndicator, Divider, LinearProgressIndicator;
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
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/primitives.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../providers/ironwood_migration_announcement_provider.dart';
import '../services/ironwood_migration_service.dart';

enum IronwoodMigrationFlowStep { intro, howItWorks, options, review }

const _privateStatusAutoAdvanceInterval = Duration(seconds: 30);
const _keystoneMigrationProofPollInterval = Duration(seconds: 1);
const _keystoneMigrationSignBatchResultUrType = 'zcash-batch-sig-result';
const _keystoneMigrationLegacySignResultUrType = 'zcash-sign-result';
const _keystoneMigrationFirmwareUpdateError =
    'Update Keystone firmware to sign Ironwood migrations, then try again.';

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
    FutureProvider.autoDispose<IronwoodMigrationFlowData?>((ref) async {
      final cta = await ref.watch(ironwoodHomeMigrationCtaProvider.future);
      if (!cta.visible) return null;

      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      if (inputs.accountUuid == null || !inputs.hasAccountScopedData) {
        return null;
      }

      final targetTotal = _sumTargetValues(cta.status);
      final amount = targetTotal > BigInt.zero
          ? targetTotal
          : inputs.orchardBalance + inputs.orchardPendingBalance;
      if (amount <= BigInt.zero) return null;

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
      final flowData = await ref.watch(
        ironwoodMigrationFlowDataProvider.future,
      );
      if (flowData == null) return null;

      final inputs = ref.watch(ironwoodMigrationInputsProvider);
      final accountUuid = inputs.accountUuid;
      if (accountUuid == null || !inputs.hasAccountScopedData) return null;

      return ref
          .watch(ironwoodMigrationServiceProvider)
          .privatePlan(network: inputs.network, accountUuid: accountUuid);
    });

BigInt _sumTargetValues(rust_sync.MigrationStatus? status) {
  if (status == null) return BigInt.zero;
  BigInt total = BigInt.zero;
  for (final value in status.targetValuesZatoshi) {
    total += value;
  }
  return total;
}

class IronwoodMigrationFlowScreen extends ConsumerWidget {
  const IronwoodMigrationFlowScreen({
    required this.step,
    this.previewData,
    this.previewPrivatePlan,
    this.onOpenReleaseNotesOverride,
    super.key,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData? previewData;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewData;
    if (preview != null) {
      return _IronwoodMigrationShell(
        step: step,
        data: preview,
        previewPrivatePlan: previewPrivatePlan,
        onOpenReleaseNotesOverride: onOpenReleaseNotesOverride,
      );
    }

    final dataAsync = ref.watch(ironwoodMigrationFlowDataProvider);
    return dataAsync.when(
      skipLoadingOnReload: true,
      loading: () => _IronwoodMigrationLoadingShell(step: step),
      error: (_, _) => const _RedirectHome(),
      data: (data) {
        if (data == null) return const _RedirectHome();
        return _IronwoodMigrationShell(
          step: step,
          data: data,
          previewPrivatePlan: previewPrivatePlan,
          onOpenReleaseNotesOverride: onOpenReleaseNotesOverride,
        );
      },
    );
  }
}

class IronwoodMigrationEntryScreen extends ConsumerWidget {
  const IronwoodMigrationEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    return ctaAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _IronwoodMigrationLoadingShell(
        step: IronwoodMigrationFlowStep.intro,
      ),
      error: (_, _) => _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: const _IronwoodMigrationPrivateStatusErrorContent(),
      ),
      data: (cta) {
        final target = switch (cta.mode) {
          IronwoodHomeMigrationCtaMode.resume => '/migration/private/status',
          IronwoodHomeMigrationCtaMode.start => '/migration/intro',
          IronwoodHomeMigrationCtaMode.hidden => '/home',
        };
        return _RedirectTo(target);
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
      return _IronwoodMigrationFrame(
        toolbar: _privateStatusToolbar(context),
        disableSidebarActions: true,
        child: _IronwoodMigrationPrivateStatusContent(status: preview),
      );
    }

    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    return ctaAsync.when(
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
      data: (cta) {
        if (cta.mode == IronwoodHomeMigrationCtaMode.start) {
          return const _RedirectTo('/migration/intro');
        }
        final status = cta.status;
        if (cta.mode != IronwoodHomeMigrationCtaMode.resume || status == null) {
          return const _RedirectHome();
        }
        return _IronwoodMigrationFrame(
          toolbar: _privateStatusToolbar(context),
          disableSidebarActions: true,
          child: _IronwoodMigrationPrivateStatusContent(
            status: status,
            accountUuid: cta.accountUuid,
          ),
        );
      },
    );
  }
}

class IronwoodMigrationKeystoneDenominationSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneDenominationSignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.denominations,
    );
  }
}

class IronwoodMigrationKeystoneBatchSignScreen extends StatelessWidget {
  const IronwoodMigrationKeystoneBatchSignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _IronwoodMigrationKeystonePrivateSignScreen(
      step: _KeystonePrivateSignStep.batch,
    );
  }
}

class _IronwoodMigrationKeystonePrivateSignScreen
    extends ConsumerStatefulWidget {
  const _IronwoodMigrationKeystonePrivateSignScreen({required this.step});

  final _KeystonePrivateSignStep step;

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
  }) {
    return switch (this) {
      _KeystonePrivateSignStep.denominations =>
        service.completeKeystoneDenominationPrivateMigration(
          accountUuid: accountUuid,
          requestId: requestId,
          signedMessages: signedMessages,
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
      );
      if (!mounted) return;
      _stopProofPolling();
      _requestCompleted = true;
      _pendingSignedMessages = null;
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
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

class _RedirectHome extends StatefulWidget {
  const _RedirectHome();

  @override
  State<_RedirectHome> createState() => _RedirectHomeState();
}

class _RedirectHomeState extends State<_RedirectHome> {
  @override
  Widget build(BuildContext context) => const _RedirectTo('/home');
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
    this.onOpenReleaseNotesOverride,
  });

  final IronwoodMigrationFlowStep step;
  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPrivatePlan;
  final VoidCallback? onOpenReleaseNotesOverride;

  @override
  Widget build(BuildContext context) {
    final content = switch (step) {
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
          previewPlan: previewPrivatePlan,
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
        IronwoodMigrationFlowStep.intro => 'Home',
        IronwoodMigrationFlowStep.howItWorks => 'Ironwood Pool',
        IronwoodMigrationFlowStep.options => 'How Migration Works',
        IronwoodMigrationFlowStep.review => 'Migration Options',
      },
      onTap: () {
        switch (step) {
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
                const _DarkBadge(label: 'Zcash Network Update'),
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
                    'Ironwood is the latest Zcash shielded pool. '
                    "It's the first formally verified pool with cutting "
                    'edge cryptography.',
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
                    'There will be a one-time mandatory upgrade from '
                    'the legacy (orchard) shielded pool. You need to '
                    'transition your $amount ZEC from the old Orchard pool '
                    'into the new Ironwood pool.',
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
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryLabel: 'How the Migration works',
              onPrimary: () => context.go('/migration/how-it-works'),
              secondaryLabel: 'Official Release Note',
              onSecondary: onOpenReleaseNotes,
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
    final amount = data.amountText;

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
            height: 386,
            child: _ProcessCard(
              steps: [
                _ProcessStepData(
                  icon: _ProcessIconKind.split,
                  title: 'Split funds',
                  body:
                      'Your $amount ZEC balance is divided into several '
                      'smaller common notes (10/1/0.1 ZEC). Splitting the '
                      'balance into smaller batches mixes your transactions '
                      'with other users maximizing privacy.',
                ),
                const _ProcessStepData(
                  icon: _ProcessIconKind.schedule,
                  title: 'Schedule',
                  body:
                      'Transactions dispatch at irregular intervals instead '
                      'of all at once.',
                ),
                const _ProcessStepData(
                  icon: _ProcessIconKind.sign,
                  title: 'Sign Once',
                  body:
                      'You grant permission at the start, and the Vizor '
                      'executes the remaining steps.',
                ),
              ],
            ),
          ),
          Positioned(
            left: 95,
            top: 540,
            width: 230,
            child: _FlowButtons(
              primaryLabel: 'Continue',
              onPrimary: () => context.go('/migration/options'),
              secondaryLabel: 'Go Back',
              onSecondary: () => context.go('/migration/intro'),
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
    final amount = widget.data.amountText;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 49,
            top: 32,
            width: 322,
            child: Column(
              children: [
                Text(
                  'Chose How to Migrate\nyour $amount ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 298,
                  child: Text(
                    'Whichever option you choose, your funds will be '
                    'safely deposited into the Ironwood pool.',
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
            top: 180.5,
            width: 396,
            child: Column(
              children: [
                _MigrationOptionCard(
                  mode: _MigrationMode.private,
                  selected: _selected == _MigrationMode.private,
                  title: 'Private Migration',
                  badge: 'Recommended',
                  body:
                      'Sends independent parts over time windows.\n'
                      'Slower, harder to correlate.',
                  onTap: () =>
                      setState(() => _selected = _MigrationMode.private),
                ),
                const SizedBox(height: 12),
                _MigrationOptionCard(
                  mode: _MigrationMode.fast,
                  selected: _selected == _MigrationMode.fast,
                  title: 'Fast Migration',
                  body:
                      'Sends now in one step. Amount and\n'
                      'timing are easier to associate.',
                  onTap: () => setState(() => _selected = _MigrationMode.fast),
                ),
              ],
            ),
          ),
          Positioned(
            left: 51,
            top: 457,
            width: 318,
            child: Text(
              'Plain-language comparison: speed vs. correlation\n'
              'exposure. No anchors, cohorts, PCZTs, or action counts\n'
              'here.',
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
  AppLifecycleListener? _lifecycleListener;
  Timer? _autoAdvanceTimer;
  bool _isAdvancing = false;
  String? _advanceError;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _advanceIfAutomatic);
    _syncAutoAdvanceTimer();
  }

  @override
  void didUpdateWidget(_IronwoodMigrationPrivateStatusContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.phase != widget.status.phase ||
        oldWidget.accountUuid != widget.accountUuid) {
      _advanceError = null;
      _syncAutoAdvanceTimer();
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _syncAutoAdvanceTimer() {
    final shouldRun =
        widget.accountUuid != null && _shouldAutoAdvanceStatus(widget.status);
    if (!shouldRun) {
      _autoAdvanceTimer?.cancel();
      _autoAdvanceTimer = null;
      return;
    }
    if (_autoAdvanceTimer != null) return;

    _autoAdvanceTimer = Timer.periodic(
      _privateStatusAutoAdvanceInterval,
      (_) => unawaited(_advanceIfAutomatic()),
    );
  }

  Future<void> _advanceIfAutomatic() async {
    if (!_shouldAutoAdvanceStatus(widget.status)) return;
    await _advanceMigration(showErrors: false);
  }

  Future<void> _advanceMigration({required bool showErrors}) async {
    if (_isAdvancing) return;

    final accountUuid = widget.accountUuid;
    if (accountUuid == null) return;

    if (await _shouldOpenKeystoneBatchSigner(accountUuid)) {
      if (!mounted) return;
      if (showErrors) {
        context.go('/migration/private/keystone/batch/sign');
      }
      return;
    }

    setState(() {
      _isAdvancing = true;
      if (showErrors) _advanceError = null;
    });

    try {
      await ref
          .read(ironwoodMigrationServiceProvider)
          .continueSoftwarePrivateMigration(accountUuid: accountUuid);
      if (!mounted) return;
      _refreshMigrationState();
    } catch (e) {
      if (!mounted) return;
      if (showErrors) {
        setState(() {
          _advanceError = _privateMigrationContinueErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAdvancing = false;
        });
      }
    }
  }

  Future<bool> _shouldOpenKeystoneBatchSigner(String accountUuid) async {
    if (widget.status.phase != kIronwoodMigrationReadyToMigratePhase) {
      return false;
    }
    final accountState = await ref.read(accountProvider.future);
    return accountState.activeAccountUuid == accountUuid &&
        (accountState.activeAccount?.isHardware ?? false);
  }

  void _refreshMigrationState() {
    ref.invalidate(ironwoodMigrationRouteCtaProvider);
    ref.invalidate(ironwoodHomeMigrationCtaProvider);
    ref.invalidate(ironwoodMigrationFlowDataProvider);
    ref.invalidate(ironwoodMigrationPrivatePlanProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = widget.status;
    final presentation = _statusPresentation(status);
    final progress = _statusProgress(status);
    final action = _statusAction(status);
    final canUseAction = widget.accountUuid != null;
    final actionLabel = _isAdvancing
        ? action.busyLabel
        : switch (action) {
            _StatusAction.advance || _StatusAction.retry => action.label,
            _StatusAction.backHome ||
            _StatusAction.none => presentation.buttonLabel,
          };
    final footerText = _advanceError ?? presentation.footer;
    final actionCallback = switch (action) {
      _StatusAction.advance || _StatusAction.retry =>
        canUseAction
            ? () => unawaited(_advanceMigration(showErrors: true))
            : null,
      _StatusAction.backHome => () => context.go('/home'),
      _StatusAction.none => null,
    };

    if (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase) {
      return _PrivateDenominationWaitingStatusContent(
        status: status,
        presentation: presentation,
        footerText: footerText,
        actionLabel: actionLabel,
        actionCallback: actionCallback,
      );
    }

    return SizedBox(
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
              onPressed: _isAdvancing ? null : actionCallback,
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

enum _StatusAction { none, advance, retry, backHome }

extension _StatusActionLabels on _StatusAction {
  String get label => switch (this) {
    _StatusAction.advance => 'Continue migration',
    _StatusAction.retry => 'Retry migration',
    _StatusAction.backHome => 'Back home',
    _StatusAction.none => '',
  };

  String get busyLabel => switch (this) {
    _StatusAction.retry => 'Retrying...',
    _ => 'Continuing...',
  };
}

_StatusAction _statusAction(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase => _StatusAction.backHome,
    kIronwoodMigrationReadyToMigratePhase ||
    kIronwoodMigrationBroadcastScheduledPhase => _StatusAction.advance,
    kIronwoodMigrationFailedRecoverablePhase => _StatusAction.retry,
    kIronwoodMigrationCompletePhase => _StatusAction.backHome,
    _ => _StatusAction.none,
  };
}

bool _shouldAutoAdvanceStatus(rust_sync.MigrationStatus status) {
  return status.phase == kIronwoodMigrationReadyToMigratePhase ||
      status.phase == kIronwoodMigrationBroadcastScheduledPhase;
}

_StatusPresentation _statusPresentation(rust_sync.MigrationStatus status) {
  return switch (status.phase) {
    kIronwoodMigrationWaitingDenomConfirmationsPhase =>
      const _StatusPresentation(
        title: 'Preparing your notes',
        body:
            'We are preparing the Migration.\n'
            'This usually takes about 10-20 minutes.',
        footer:
            'You can leave this screen — keep Vizor open or running in the '
            'background. Progress will be checked when Vizor can run again.',
        buttonLabel: 'Back to Home',
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
      title: 'Broadcasting Migration',
      body:
          'Vizor is broadcasting the prepared Ironwood migration transaction.',
      footer:
          'Stay connected while the transaction is submitted to the Zcash '
          'network.',
      buttonLabel: 'Broadcasting',
    ),
    kIronwoodMigrationWaitingConfirmationsPhase => const _StatusPresentation(
      title: 'Waiting for Ironwood',
      body:
          'The migration transaction was broadcast. Vizor is waiting for '
          'network confirmations.',
      footer:
          'Your balance will move to the Ironwood pool once the transaction '
          'is confirmed and synced.',
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
    final total = status.denominationSplitTotalCount;
    if (total > 0) {
      return (status.denominationSplitCompletedCount / total).clamp(0, 1);
    }
    final target = status.denominationConfirmationTarget;
    if (target > 0) {
      return (status.denominationConfirmationCount / target).clamp(0, 1);
    }
    return 0.25;
  }

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
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;

  @override
  ConsumerState<_IronwoodMigrationPrivateReviewContent> createState() =>
      _IronwoodMigrationPrivateReviewContentState();
}

class _IronwoodMigrationPrivateReviewContentState
    extends ConsumerState<_IronwoodMigrationPrivateReviewContent> {
  bool _isStarting = false;
  String? _startError;

  Future<void> _startMigration() async {
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
      if (accountState.activeAccount?.isHardware ?? false) {
        context.go('/migration/private/keystone/denominations/sign');
        return;
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .startSoftwarePrivateMigration(accountUuid: accountUuid);
      if (!mounted) return;
      ref.invalidate(ironwoodMigrationRouteCtaProvider);
      ref.invalidate(ironwoodHomeMigrationCtaProvider);
      ref.invalidate(ironwoodMigrationFlowDataProvider);
      ref.invalidate(ironwoodMigrationPrivatePlanProvider);
      context.go('/migration/private/status');
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = widget.data.amountText;
    final previewPlan = widget.previewPlan;
    final planAsync = previewPlan == null
        ? ref.watch(ironwoodMigrationPrivatePlanProvider)
        : AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(previewPlan);
    final plan = planAsync.asData?.value;

    final content = planAsync.when(
      skipLoadingOnReload: true,
      loading: () => const _PrivateReviewLoading(),
      error: (_, _) => const _PrivateReviewUnavailable(
        title: "Couldn't load migration review",
        body:
            'Try again after sync finishes. No transaction has been '
            'prepared or broadcast.',
      ),
      data: (loadedPlan) => loadedPlan == null
          ? const _PrivateReviewUnavailable(
              title: 'Private migration is not ready yet',
              body:
                  'Wait for sync to complete or for Orchard funds to '
                  'become spendable, then try again.',
            )
          : _PrivateReviewPlan(plan: loadedPlan),
    );
    final canStart = plan != null && !_isStarting;

    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 29,
            top: 32,
            width: 362,
            child: Column(
              children: [
                const AppIcon(AppIcons.shieldKeyhole, size: 18),
                const SizedBox(height: 16),
                Text(
                  'Review Migration Plan',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$amount ZEC',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(left: 12, top: 174, width: 396, child: content),
          if (_startError != null)
            Positioned(
              left: 51,
              top: 528,
              width: 318,
              child: Text(
                _startError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          Positioned(
            left: 95,
            top: 582,
            width: 230,
            child: AppButton(
              onPressed: canStart ? _startMigration : null,
              height: 44,
              minWidth: 230,
              expand: true,
              constrainContent: true,
              trailing: const AppIcon(AppIcons.chevronForward, size: 20),
              child: Text(
                _isStarting ? 'Preparing...' : 'Authorize & Start',
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
                    label: '${plan.plannedBatchCount} Planned batches',
                    value: 'View',
                    trailingIcon: AppIcons.chevronForward,
                    semiboldLabel: true,
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

class _ReviewTextRow extends StatelessWidget {
  const _ReviewTextRow({
    required this.label,
    required this.value,
    this.trailingIcon,
    this.mutedLabel = false,
    this.semiboldLabel = false,
  });

  final String label;
  final String value;
  final String? trailingIcon;
  final bool mutedLabel;
  final bool semiboldLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rowStyle = mutedLabel
        ? AppTypography.bodyMediumStrong
        : AppTypography.labelLarge;
    return Row(
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
  }
}

class _PrivateDenominationWaitingStatusContent extends StatelessWidget {
  const _PrivateDenominationWaitingStatusContent({
    required this.status,
    required this.presentation,
    required this.footerText,
    required this.actionLabel,
    required this.actionCallback,
  });

  final rust_sync.MigrationStatus status;
  final _StatusPresentation presentation;
  final String footerText;
  final String actionLabel;
  final VoidCallback? actionCallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            left: 43,
            top: 52,
            width: 334,
            child: Column(
              children: [
                Text(
                  presentation.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  presentation.body,
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
            top: 156,
            width: 396,
            height: 110,
            child: _PreparingNotesDiagram(status: status),
          ),
          Positioned(
            left: 12,
            top: 286,
            width: 396,
            height: 222,
            child: _SplitSubmittingCard(status: status),
          ),
          Positioned(
            left: 70,
            top: 526,
            width: 280,
            child: Text(
              footerText,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Positioned(
            left: 129,
            top: 606,
            width: 162,
            child: AppButton(
              onPressed: actionCallback,
              height: 36,
              minWidth: 162,
              expand: true,
              constrainContent: true,
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

class _PreparingNotesDiagram extends StatelessWidget {
  const _PreparingNotesDiagram({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final targetTotal = _sumTargetValues(status);
    final amountText = targetTotal > BigInt.zero
        ? '${_formatZecAmountCompact(targetTotal)} ZEC'
        : '${status.preparedNoteCount} notes';
    final noteLabels = _statusNoteLabels(status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 91,
            top: 47,
            child: Text(
              amountText,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            left: 190,
            top: 0,
            bottom: 0,
            child: CustomPaint(
              size: const Size(1, 110),
              painter: _PreparingNotesConnectorPainter(
                color: GreenPrimitives.p500Light,
              ),
            ),
          ),
          Positioned(
            left: 204,
            top: 25,
            width: 192,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final label in noteLabels)
                  _NoteChip(label: label, dimmed: label != noteLabels.first),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.label, required this.dimmed});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dimmed ? colors.background.raised : const Color(0xFFEAFBF1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: dimmed ? colors.border.subtle : GreenPrimitives.p500Light,
          width: 0.6,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: dimmed ? colors.text.secondary : colors.text.accent,
          ),
        ),
      ),
    );
  }
}

class _PreparingNotesConnectorPainter extends CustomPainter {
  const _PreparingNotesConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    canvas.drawCircle(Offset(x, size.height / 2), 12, Paint()..color = color);

    final arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final center = Offset(x, size.height / 2);
    final path = Path()
      ..moveTo(center.dx - 3, center.dy - 4.4)
      ..lineTo(center.dx + 2.5, center.dy)
      ..lineTo(center.dx - 3, center.dy + 4.4);
    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _PreparingNotesConnectorPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SplitSubmittingCard extends StatelessWidget {
  const _SplitSubmittingCard({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const confirmationText =
        'Confirm waiting for the source chain\n'
        'and provider to recognise the deposit';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Stack(
          children: [
            Positioned(
              left: 11,
              top: 40,
              height: 92,
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
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: colors.background.inverse,
                          shape: const OvalBorder(),
                        ),
                        child: const Center(
                          child: AppIcon(
                            AppIcons.loader,
                            size: 16,
                            color: Colors.white,
                            animated: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Submitting split transaction...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Text(
                    confirmationText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _StatusCheckRow(
                  icon: AppIcons.scroll,
                  label: 'Confirmation',
                  complete:
                      status.denominationConfirmationTarget > 0 &&
                      status.denominationConfirmationCount >=
                          status.denominationConfirmationTarget,
                ),
                const SizedBox(height: 14),
                _StatusCheckRow(
                  icon: AppIcons.calendar,
                  label: 'Migration schedule ready',
                  complete:
                      status.denominationSplitCompletedCount >=
                      status.denominationSplitTotalCount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCheckRow extends StatelessWidget {
  const _StatusCheckRow({
    required this.icon,
    required this.label,
    required this.complete,
  });

  final String icon;
  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = complete ? GreenPrimitives.p500Light : colors.icon.muted;
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: complete
                  ? const Color(0xFFE3FBEE)
                  : colors.background.raised,
              shape: const OvalBorder(),
            ),
            child: Center(child: AppIcon(icon, size: 16, color: color)),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
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

String _estimatedMigrationArrivalLabel(
  rust_sync.OrchardMigrationPrivatePlan plan,
) {
  final batches = math.max(1, plan.plannedBatchCount);
  final totalSeconds = plan.broadcastWindowSeconds * BigInt.from(batches);
  const minute = 60;
  const hour = minute * 60;
  const day = hour * 24;

  if (totalSeconds >= BigInt.from(day)) {
    final days = (totalSeconds + BigInt.from(day - 1)) ~/ BigInt.from(day);
    return '~$days days';
  }
  if (totalSeconds >= BigInt.from(hour)) {
    final hours = (totalSeconds + BigInt.from(hour - 1)) ~/ BigInt.from(hour);
    return '~$hours hr';
  }
  if (totalSeconds >= BigInt.from(minute)) {
    final minutes =
        (totalSeconds + BigInt.from(minute - 1)) ~/ BigInt.from(minute);
    return '~$minutes min';
  }
  return 'Scheduled';
}

List<String> _statusNoteLabels(rust_sync.MigrationStatus status) {
  final labels = <String>[
    for (final value in status.targetValuesZatoshi.take(9))
      '${_formatZecAmountCompact(value)} ZEC',
  ];
  const fallbackLabels = [
    '1 ZEC',
    '1 ZEC',
    '1 ZEC',
    '1 ZEC',
    '0.1 ZEC',
    '0.1 ZEC',
    '0.1 ZEC',
    '0.01 ZEC',
    '0.01 ZEC',
    '0.01 ZEC',
  ];
  for (var i = labels.length; i < 9; i++) {
    labels.add(fallbackLabels[i]);
  }
  return labels;
}

class _FlowButtons extends StatelessWidget {
  const _FlowButtons({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          onPressed: onPrimary,
          height: 44,
          minWidth: 230,
          expand: true,
          constrainContent: true,
          trailing: const AppIcon(AppIcons.chevronForward, size: 20),
          child: Text(
            primaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 20),
        AppButton(
          onPressed: onSecondary,
          variant: AppButtonVariant.ghost,
          height: 36,
          minWidth: 230,
          expand: true,
          constrainContent: true,
          child: Text(
            secondaryLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _PoolMigrationHeroPainter()),
          Positioned(
            left: 24,
            top: 24,
            child: AppProfilePicture(
              profilePictureId: data.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
          ),
          Positioned(
            right: 27,
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
            left: 159,
            top: 95,
            width: 100,
            height: 30,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: GreenPrimitives.p500Light,
                shape: const StadiumBorder(),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(
                        AppIcons.shieldKeyhole,
                        size: 16,
                        color: Color(0xFFEAFEEF),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Migration',
                        style: AppTypography.labelLarge.copyWith(
                          color: const Color(0xFFEAFEEF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 32,
            top: 136,
            width: 116,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Ironwood Pool',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: GreenPrimitives.p500Light,
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

class _PoolMigrationHeroPainter extends CustomPainter {
  const _PoolMigrationHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()..color = Colors.white;
    canvas.drawRect(rect, basePaint);

    final greenSoft = Paint()..color = const Color(0xFFE3FBEE);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.91, size.height * 0.50),
        width: 168,
        height: 270,
      ),
      greenSoft,
    );
    final greenSofter = Paint()..color = const Color(0xFFF0FFF6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.99, size.height * 0.50),
        width: 154,
        height: 270,
      ),
      greenSofter,
    );

    final dashedPath = Path()
      ..moveTo(size.width * 0.25, -16)
      ..cubicTo(
        size.width * 0.42,
        size.height * 0.20,
        size.width * 0.42,
        size.height * 0.79,
        size.width * 0.25,
        size.height + 16,
      );
    _drawDashedPath(
      canvas,
      dashedPath,
      Paint()
        ..color = const Color(0xFFB8B8B8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
      dashLength: 2.4,
      gapLength: 4.2,
    );

    final linePaint = Paint()
      ..color = const Color(0xFF9A9A9A)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.355, size.height * 0.50),
      Offset(size.width * 0.655, size.height * 0.50),
      linePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.355, size.height * 0.50),
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * 0.355, size.height * 0.50),
      5,
      Paint()..color = const Color(0xFFB8B8B8),
    );
    canvas.drawCircle(
      Offset(size.width * 0.655, size.height * 0.50),
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(size.width * 0.655, size.height * 0.50),
      5,
      Paint()..color = GreenPrimitives.p500Light,
    );
  }

  @override
  bool shouldRepaint(covariant _PoolMigrationHeroPainter oldDelegate) => false;
}

void _drawDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  required double dashLength,
  required double gapLength,
}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dashLength, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + gapLength;
    }
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
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              _ProcessStep(step: steps[index]),
              if (index != steps.length - 1) ...[
                const SizedBox(height: 17),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.border.subtle,
                  indent: 36,
                  endIndent: 12,
                ),
                const SizedBox(height: 17),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProcessStepData {
  const _ProcessStepData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final _ProcessIconKind icon;
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
        SizedBox(
          width: 20,
          height: 20,
          child: CustomPaint(
            painter: _ProcessIconPainter(step.icon, GreenPrimitives.p500Light),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                step.body,
                maxLines: step.icon == _ProcessIconKind.split ? 4 : 2,
                overflow: TextOverflow.ellipsis,
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

enum _ProcessIconKind { split, schedule, sign }

class _ProcessIconPainter extends CustomPainter {
  const _ProcessIconPainter(this.kind, this.color);

  final _ProcessIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (kind) {
      case _ProcessIconKind.split:
        canvas.drawLine(const Offset(5, 5), const Offset(5, 11), paint);
        canvas.drawLine(const Offset(5, 11), const Offset(12, 11), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(16, 7), paint);
        _arrow(canvas, const Offset(12, 16), math.pi / 2, paint);
        _arrow(canvas, const Offset(16, 7), -math.pi / 4, paint);
      case _ProcessIconKind.schedule:
        canvas.drawCircle(const Offset(10, 10), 6.5, paint);
        canvas.drawLine(const Offset(10, 10), const Offset(10, 6), paint);
        canvas.drawLine(const Offset(10, 10), const Offset(13, 12), paint);
        canvas.drawLine(const Offset(6, 2), const Offset(4, 4), paint);
        canvas.drawLine(const Offset(14, 2), const Offset(16, 4), paint);
      case _ProcessIconKind.sign:
        canvas.drawLine(const Offset(4, 15), const Offset(16, 15), paint);
        canvas.drawLine(const Offset(5, 12), const Offset(8, 6), paint);
        canvas.drawLine(const Offset(8, 6), const Offset(12, 12), paint);
        canvas.drawLine(const Offset(12, 12), const Offset(15, 5), paint);
        canvas.drawCircle(const Offset(8, 6), 1.5, paint);
    }
  }

  void _arrow(Canvas canvas, Offset tip, double angle, Paint paint) {
    const length = 3.5;
    final a = angle + math.pi * 0.75;
    final b = angle - math.pi * 0.75;
    canvas.drawLine(
      tip,
      tip + Offset(math.cos(a), math.sin(a)) * length,
      paint,
    );
    canvas.drawLine(
      tip,
      tip + Offset(math.cos(b), math.sin(b)) * length,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProcessIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}

enum _MigrationMode { private, fast }

class _MigrationOptionCard extends StatelessWidget {
  const _MigrationOptionCard({
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
          height: 118,
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
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
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
                            const SizedBox(height: 12),
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
          ? const Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: Color(0xFFFFFFFF),
              ),
            )
          : null,
    );
  }
}
