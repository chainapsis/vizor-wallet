import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../services/sapling_params.dart';
import '../widgets/sapling_params_prompt.dart';
import 'send_review_screen.dart';

enum _KeystoneConfirmPhase { preparing, ready, failed }

class KeystoneSendConfirmScreen extends ConsumerStatefulWidget {
  const KeystoneSendConfirmScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<KeystoneSendConfirmScreen> createState() =>
      _KeystoneSendConfirmScreenState();
}

class _KeystoneSendConfirmScreenState
    extends ConsumerState<KeystoneSendConfirmScreen> {
  _KeystoneConfirmPhase _phase = _KeystoneConfirmPhase.preparing;
  bool _proposalConsumed = false;
  bool _discardScheduled = false;
  bool _showSaplingParamsPrompt = false;
  Completer<bool>? _saplingParamsPromptCompleter;
  String? _error;
  List<String> _urParts = const [];
  List<int>? _pcztWithProofs;
  SaplingParamsStatus? _saplingParams;

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
    _scheduleDiscardIfNeeded();
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      rust_sync
          .discardProposal(
            proposalId: widget.args.proposalId,
            sendFlowId: widget.args.sendFlowId,
          )
          .then((_) {
            log(
              'KeystoneSendConfirm: released proposal ${widget.args.proposalId}',
            );
          })
          .catchError((Object e) {
            log(
              'KeystoneSendConfirm: discardProposal cleanup failed (non-critical): $e',
            );
          }),
    );
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
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final saplingParams = await loadSaplingParamsStatus();

      if (widget.args.needsSaplingParams && !saplingParams.complete) {
        final confirmed = await _showDownloadPrompt();
        if (!confirmed) {
          _scheduleDiscardIfNeeded();
          if (!mounted) return;
          setState(() {
            _phase = _KeystoneConfirmPhase.failed;
            _error =
                'Signing was cancelled before proving parameters were downloaded.';
          });
          return;
        }

        await downloadMissingSaplingParams(
          saplingParams,
          log: (message) => log('KeystoneSendConfirm: $message'),
        );
      }

      if (!mounted) return;
      final currentSaplingParams = await loadSaplingParamsStatus();
      _saplingParams = currentSaplingParams;

      final pcztBytes = await rust_sync.createPcztFromProposal(
        dbPath: dbPath,
        network: endpoint.networkName,
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
      );
      _proposalConsumed = true;

      final pcztWithProofs = await rust_sync.addProofsToPczt(
        pcztBytes: pcztBytes,
        spendParamsPath: widget.args.needsSaplingParams
            ? currentSaplingParams.spendPath
            : null,
        outputParamsPath: widget.args.needsSaplingParams
            ? currentSaplingParams.outputPath
            : null,
      );
      final redactedPczt = await rust_sync.redactPcztForSigner(
        pcztBytes: pcztBytes,
      );
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: redactedPczt,
        maxFragmentLen: BigInt.from(200),
      );

      if (!mounted) return;
      setState(() {
        _phase = _KeystoneConfirmPhase.ready;
        _pcztWithProofs = pcztWithProofs;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('KeystoneSendConfirm._preparePczt: ERROR: $e\n$st');
      if (!_proposalConsumed) {
        _scheduleDiscardIfNeeded();
      }
      if (!mounted) return;
      setState(() {
        _phase = _KeystoneConfirmPhase.failed;
        _error = _friendlyError(e.toString());
      });
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('proposal not found') ||
        lower.contains('send flow mismatch')) {
      return 'Transaction expired before it could be signed.';
    }
    if (lower.contains('sapling') || lower.contains('download')) {
      return 'Required proving parameters could not be prepared.';
    }
    return 'Keystone signing could not be prepared. Return to Send and try again.';
  }

  Future<void> _cancelToSend() async {
    _scheduleDiscardIfNeeded();
    if (!mounted) return;
    context.go('/send');
  }

  Future<void> _getSignature() async {
    final pcztWithProofs = _pcztWithProofs;
    final saplingParams = _saplingParams;
    if (_phase != _KeystoneConfirmPhase.ready ||
        pcztWithProofs == null ||
        saplingParams == null) {
      return;
    }

    final signatures = await context.push<List<int>>('/send/keystone/scan');
    if (signatures == null || !mounted) return;

    context.go(
      '/send/status',
      extra: KeystoneBroadcastArgs(
        reviewArgs: widget.args,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signatures,
      ),
    );
  }

  String _amountLine() {
    final amount = ZecAmount.fromZatoshi(
      widget.args.amountZatoshi,
    ).pretty(minFractionDigits: 2, denomStyle: ZecDenomStyle.upper);
    return 'Sending $amount';
  }

  String _recipientLine() {
    final address = widget.args.address.trim();
    if (address.length <= 24) return 'To: $address';
    return 'To: ${address.substring(0, 12)} ... ${address.substring(address.length - 9)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                  child: AppBackLink(label: 'Back', onTap: _cancelToSend),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Confirm with Keystone',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colors.button.ghost.label,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        _KeystoneQrStage(
                          phase: _phase,
                          urParts: _urParts,
                          error: _error,
                        ),
                        const SizedBox(height: 48),
                        SizedBox(
                          width: 325,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _amountLine(),
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.button.ghost.label,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                _recipientLine(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                            onPressed: _phase == _KeystoneConfirmPhase.ready
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
                            onPressed: _cancelToSend,
                            variant: AppButtonVariant.ghost,
                            minWidth: 256,
                            child: const Text('Reject'),
                          ),
                        ),
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

class _KeystoneQrStage extends StatelessWidget {
  const _KeystoneQrStage({
    required this.phase,
    required this.urParts,
    required this.error,
  });

  final _KeystoneConfirmPhase phase;
  final List<String> urParts;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 230,
      height: 230,
      child: switch (phase) {
        _KeystoneConfirmPhase.ready => _AnimatedKeystoneQr(urParts: urParts),
        _KeystoneConfirmPhase.failed => Center(
          child: Text(
            error ?? 'Keystone signing could not be prepared.',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.destructive,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        _KeystoneConfirmPhase.preparing => Center(
          child: Text(
            'Preparing QR...',
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      },
    );
  }
}

class _AnimatedKeystoneQr extends StatefulWidget {
  const _AnimatedKeystoneQr({required this.urParts});

  final List<String> urParts;

  @override
  State<_AnimatedKeystoneQr> createState() => _AnimatedKeystoneQrState();
}

class _AnimatedKeystoneQrState extends State<_AnimatedKeystoneQr> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _AnimatedKeystoneQr oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urParts != widget.urParts) {
      _index = 0;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.urParts.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.urParts.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urParts.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: QrImageView(
          data: widget.urParts[_index],
          size: 226,
          backgroundColor: const Color(0xFFFFFFFF),
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF141818),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF141818),
          ),
          errorCorrectionLevel: QrErrorCorrectLevel.L,
        ),
      ),
    );
  }
}
