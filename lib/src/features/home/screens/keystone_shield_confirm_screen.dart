import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../keystone/widgets/keystone_transaction_progress_panel.dart';
import '../../send/services/sapling_params.dart';
import '../../send/widgets/sapling_params_prompt.dart';

enum _KeystoneShieldPhase {
  preparing,
  ready,
  broadcasting,
  broadcastWarning,
  failed,
}

class KeystoneShieldConfirmScreen extends ConsumerStatefulWidget {
  const KeystoneShieldConfirmScreen({super.key});

  @override
  ConsumerState<KeystoneShieldConfirmScreen> createState() =>
      _KeystoneShieldConfirmScreenState();
}

class _KeystoneShieldConfirmScreenState
    extends ConsumerState<KeystoneShieldConfirmScreen> {
  _KeystoneShieldPhase _phase = _KeystoneShieldPhase.preparing;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  String? _statusMessage;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;
  bool _needsSaplingParams = false;
  BigInt? _feeZatoshi;
  BigInt? _shieldedZatoshi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_preparePczt());
    });
  }

  @override
  void dispose() {
    final promptCompleter = _saplingParamsPromptCompleter;
    _saplingParamsPromptCompleter = null;
    if (promptCompleter != null && !promptCompleter.isCompleted) {
      promptCompleter.complete(false);
    }
    super.dispose();
  }

  Future<bool> _showDownloadPrompt() {
    if (!mounted) return Future.value(false);

    final existingCompleter = _saplingParamsPromptCompleter;
    if (existingCompleter != null && !existingCompleter.isCompleted) {
      return existingCompleter.future;
    }

    final completer = Completer<bool>();
    setState(() {
      _saplingParamsPromptCompleter = completer;
      _showSaplingParamsPrompt = true;
    });
    return completer.future;
  }

  void _resolveSaplingParamsDialog(bool confirmed) {
    final completer = _saplingParamsPromptCompleter;
    if (completer == null || completer.isCompleted) return;

    setState(() {
      _showSaplingParamsPrompt = false;
      _saplingParamsPromptCompleter = null;
    });
    completer.complete(confirmed);
  }

  Future<void> _preparePczt() async {
    try {
      final accountUuid = ref.read(walletProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        throw Exception('No active account.');
      }

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final shieldPczt = await rust_sync.createShieldTransparentPczt(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );

      var saplingParams = await loadSaplingParamsStatus();
      if (shieldPczt.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          if (!mounted) return;
          setState(() {
            _phase = _KeystoneShieldPhase.failed;
            _error =
                'Shielding was cancelled before proving parameters were downloaded.';
          });
          return;
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('KeystoneShieldConfirm: $message'),
        );
        saplingParams = await loadSaplingParamsStatus();
      }

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: shieldPczt.pcztBytes,
        spendParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.spendPath
            : null,
        outputParamsPath: shieldPczt.needsSaplingParams
            ? saplingParams.outputPath
            : null,
      );
      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: shieldPczt.pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(200),
      );

      if (!mounted) return;
      setState(() {
        _phase = _KeystoneShieldPhase.ready;
        _pcztWithProofs = pcztWithProofs;
        _saplingParams = saplingParams;
        _needsSaplingParams = shieldPczt.needsSaplingParams;
        _feeZatoshi = shieldPczt.feeZatoshi;
        _shieldedZatoshi = shieldPczt.shieldedZatoshi;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('KeystoneShieldConfirm._preparePczt: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _getSignature() async {
    final pcztWithProofs = _pcztWithProofs;
    final saplingParams = _saplingParams;
    if (_phase != _KeystoneShieldPhase.ready ||
        pcztWithProofs == null ||
        saplingParams == null) {
      return;
    }

    final signatures = await context.push<List<int>>('/send/keystone/scan');
    if (signatures == null || !mounted) return;
    await _broadcast(pcztWithProofs, signatures, saplingParams);
  }

  Future<void> _broadcast(
    List<int> pcztWithProofs,
    List<int> signatures,
    SaplingParamsStatus saplingParams,
  ) async {
    setState(() {
      _phase = _KeystoneShieldPhase.broadcasting;
      _error = null;
      _statusMessage = null;
    });

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final result = await rust_sync.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
        spendParamsPath: _needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: _needsSaplingParams ? saplingParams.outputPath : null,
      );
      log(
        'KeystoneShieldConfirm: broadcast shield txid=${result.txid} '
        'status=${result.status}',
      );

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('KeystoneShieldConfirm: refreshAfterSend failed: $e');
      }
      if (!mounted) return;
      if (result.status != 'broadcasted') {
        setState(() {
          _phase = _KeystoneShieldPhase.broadcastWarning;
          _statusMessage = _pcztBroadcastStatusMessage(result);
        });
        return;
      }
      context.go('/home');
    } catch (e, st) {
      log('KeystoneShieldConfirm._broadcast: ERROR: $e\n$st');
      if (!mounted) return;
      final postBroadcastMessage = _postBroadcastErrorMessage(e);
      if (postBroadcastMessage != null) {
        setState(() {
          _phase = _KeystoneShieldPhase.broadcastWarning;
          _statusMessage = postBroadcastMessage;
        });
        return;
      }
      setState(() {
        _phase = _KeystoneShieldPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  String _pcztBroadcastStatusMessage(
    rust_sync.ExtractAndBroadcastPcztResult result,
  ) {
    if (result.status == 'broadcast_unknown') {
      return result.message ??
          'The shield transaction may have reached the network, but confirmation timed out. Check activity before trying again.';
    }
    if (result.status == 'broadcasted_storage_failed') {
      return result.message ??
          'The shield transaction reached the network, but Vizor could not store it locally. Do not try again until sync or an explorer confirms the latest status.';
    }
    return result.message ??
        'The shield transaction status is uncertain. Check activity before trying again.';
  }

  String? _postBroadcastErrorMessage(Object error) {
    final raw = error.toString();
    if (!raw.toLowerCase().contains('broadcast succeeded')) return null;
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  String _friendlyError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('sync')) {
      return 'Sync the wallet before shielding transparent balance.';
    }
    if (lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return 'Transparent balance is too small to shield after fees.';
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'Shield transaction could not be broadcast.';
    }
    if (lower.contains('extract') || lower.contains('pczt')) {
      return 'Keystone signature could not be applied.';
    }
    return 'Shield balance failed. Please try again.';
  }

  void _cancelToHome() {
    context.go('/home');
  }

  String _shieldingLine() {
    final amount = _shieldedZatoshi;
    if (amount == null) return 'Shielding balance';
    return 'Shielding ${ZecAmount.fromZatoshi(amount).pretty(minFractionDigits: 2, denomStyle: ZecDenomStyle.upper)}';
  }

  String _feeLine() {
    final fee = _feeZatoshi;
    if (fee == null) return 'Fee: calculating';
    return 'Fee: ${ZecAmount.fromZatoshi(fee).fee}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isBroadcasting = _phase == _KeystoneShieldPhase.broadcasting;
    final isBroadcastWarning = _phase == _KeystoneShieldPhase.broadcastWarning;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          children: [
            Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppBackLink(label: 'Back', onTap: _cancelToHome),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Shield with Keystone',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colors.button.ghost.label,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (isBroadcasting)
                          const KeystoneTransactionProgressPanel()
                        else if (isBroadcastWarning)
                          _ShieldBroadcastWarningPanel(
                            message:
                                _statusMessage ??
                                'The shield transaction status is uncertain. Check activity before trying again.',
                          )
                        else
                          KeystonePcztQrStage(
                            phase: switch (_phase) {
                              _KeystoneShieldPhase.preparing =>
                                KeystonePcztQrStagePhase.preparing,
                              _KeystoneShieldPhase.ready =>
                                KeystonePcztQrStagePhase.ready,
                              _KeystoneShieldPhase.failed =>
                                KeystonePcztQrStagePhase.failed,
                              _KeystoneShieldPhase.broadcasting =>
                                KeystonePcztQrStagePhase.preparing,
                              _KeystoneShieldPhase.broadcastWarning =>
                                KeystonePcztQrStagePhase.failed,
                            },
                            urParts: _urParts,
                            error: _error,
                          ),
                        if (isBroadcastWarning) ...[
                          const SizedBox(height: 32),
                          SizedBox(
                            width: 256,
                            child: AppButton(
                              onPressed: _cancelToHome,
                              minWidth: 256,
                              child: const Text('Back to Wallet'),
                            ),
                          ),
                        ] else if (!isBroadcasting) ...[
                          const SizedBox(height: 48),
                          SizedBox(
                            width: 325,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shieldingLine(),
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.button.ghost.label,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  _feeLine(),
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.button.ghost.label,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'After you sign with Keystone, click Get Signature',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: 256,
                            child: AppButton(
                              onPressed: _phase == _KeystoneShieldPhase.ready
                                  ? () => unawaited(_getSignature())
                                  : null,
                              minWidth: 256,
                              child: const Text('Get Signature'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                          SizedBox(
                            width: 256,
                            child: AppButton(
                              onPressed: _cancelToHome,
                              variant: AppButtonVariant.ghost,
                              minWidth: 256,
                              child: const Text('Reject'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_showSaplingParamsPrompt)
              SaplingParamsPrompt(
                onDownload: () => _resolveSaplingParamsDialog(true),
                onCancel: () => _resolveSaplingParamsDialog(false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShieldBroadcastWarningPanel extends StatelessWidget {
  const _ShieldBroadcastWarningPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 325,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.warning, size: 28, color: colors.icon.warning),
          const SizedBox(height: AppSpacing.s),
          Text(
            message,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.warning,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
