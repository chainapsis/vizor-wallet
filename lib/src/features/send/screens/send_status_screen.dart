import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../services/keystone_transport.dart';
import 'send_review_screen.dart';

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

enum _SendStatusPhase { sending, succeeded, failed }

class SendStatusScreen extends ConsumerStatefulWidget {
  const SendStatusScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendStatusScreen> createState() => _SendStatusScreenState();
}

class _SendStatusScreenState extends ConsumerState<SendStatusScreen> {
  _SendStatusPhase _phase = _SendStatusPhase.sending;
  bool _proposalConsumed = false;
  bool _discardScheduled = false;
  String? _error;
  String? _txid;
  late final DateTime _startedAt = DateTime.now();
  DateTime? _completedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    if (_phase != _SendStatusPhase.sending) {
      _scheduleDiscardIfNeeded();
    }
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      rust_sync
          .discardProposal(proposalId: widget.args.proposalId)
          .then((_) {
            log(
              'SendStatus: released proposal ${widget.args.proposalId} on dispose',
            );
          })
          .catchError((Object e) {
            log(
              'SendStatus: discardProposal cleanup failed (non-critical): $e',
            );
          }),
    );
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
      return 'Insufficient balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') ||
        lower.contains('connection refused') ||
        lower.contains('dns error') ||
        lower.contains('tls error')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some transactions were broadcast but not all. Please check history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again later.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired before it could be sent.';
    }
    return 'Transaction could not be sent. Please return to your wallet and verify the latest status.';
  }

  String _formatReceiptAmount(BigInt zatoshi) {
    final whole = zatoshi ~/ BigInt.from(100000000);
    final fraction =
        ((zatoshi % BigInt.from(100000000)) ~/ BigInt.from(1000000))
            .toString()
            .padLeft(2, '0');
    return '$whole,$fraction zec';
  }

  String _formatFee(BigInt zatoshi) {
    final whole = zatoshi ~/ BigInt.from(100000000);
    var fraction = (zatoshi % BigInt.from(100000000)).toString().padLeft(
      8,
      '0',
    );
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$whole' : '$whole.$fraction';
  }

  String _formatDate(DateTime value) {
    const months = <String>[
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '${months[value.month]} ${value.day}, ${value.year} $hh:$mm';
  }

  List<TextSpan> _addressSpans(BuildContext context, String line) {
    final colors = context.colors;
    if (!widget.args.isShielded || line.length < 8) {
      return [
        TextSpan(
          text: line,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ];
    }
    final prefix = line.substring(0, 7);
    final suffix = line.length > 8 ? line.substring(line.length - 8) : '';
    final middle = line.substring(prefix.length, line.length - suffix.length);
    return [
      TextSpan(
        text: prefix,
        style: AppTypography.labelLarge.copyWith(
          color: colors.text.brandPurple,
        ),
      ),
      TextSpan(
        text: middle,
        style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
      ),
      if (suffix.isNotEmpty)
        TextSpan(
          text: suffix,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.brandPurple,
          ),
        ),
    ];
  }

  List<String> _splitAddress() {
    final address = widget.args.address.trim();
    if (address.length <= 16) return [address];
    final midpoint = (address.length / 2).ceil();
    return [address.substring(0, midpoint), address.substring(midpoint)];
  }

  Future<bool> _showSaplingParamsDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Download Required'),
            content: const Text(
              'This transaction uses Sapling shielded notes, which require '
              'proving parameters (~50MB) to generate zero-knowledge proofs.\n\n'
              'This is a one-time download. Network data charges may apply.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Download'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _downloadAndVerify(
    String url,
    String destPath,
    String expectedSha1,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'Download failed: HTTP ${response.statusCode} for $url',
        );
      }
      final tempPath = '${destPath}_tmp';
      final file = File(tempPath);
      final sink = file.openWrite();
      await response.pipe(sink);

      final bytes = await File(tempPath).readAsBytes();
      final digest = sha1.convert(bytes);
      if (digest.toString() != expectedSha1) {
        await File(tempPath).delete();
        throw Exception('SHA-1 mismatch: expected $expectedSha1, got $digest');
      }

      await File(tempPath).rename(destPath);
      log('SendStatus: downloaded and verified $destPath');
    } finally {
      client.close();
    }
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _copyTransactionHash() async {
    final txid = _txid;
    if (txid == null) return;
    await Clipboard.setData(ClipboardData(text: txid));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Transaction hash copied')));
  }

  Future<Uint8List> _signWithTransport(
    KeystoneTransport transport,
    Uint8List redactedPczt,
  ) {
    final signingContext = context;
    return transport.signPczt(signingContext, redactedPczt);
  }

  Future<bool> _abortIfUnmounted() async {
    if (mounted) return false;
    if (!_proposalConsumed && !_discardScheduled) {
      _discardScheduled = true;
      try {
        await rust_sync.discardProposal(proposalId: widget.args.proposalId);
      } catch (e) {
        log(
          'SendStatus: discardProposal cleanup failed after unmount (non-critical): $e',
        );
      }
    }
    return true;
  }

  Future<void> _startBroadcast() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final paramsDir = '${dir.path}${Platform.pathSeparator}sapling_params';
      final spendPath =
          '$paramsDir${Platform.pathSeparator}sapling-spend.params';
      final outputPath =
          '$paramsDir${Platform.pathSeparator}sapling-output.params';

      if (widget.args.needsSaplingParams) {
        final spendExists = File(spendPath).existsSync();
        final outputExists = File(outputPath).existsSync();

        if (!spendExists || !outputExists) {
          if (await _abortIfUnmounted()) return;
          final downloadConfirmed = await _showSaplingParamsDialog();
          if (!downloadConfirmed) {
            if (await _abortIfUnmounted()) return;
            setState(() {
              _phase = _SendStatusPhase.failed;
              _error =
                  'Sending was cancelled before proving parameters were downloaded.';
            });
            return;
          }

          await Directory(paramsDir).create(recursive: true);
          if (!spendExists) {
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-spend.params',
              spendPath,
              _saplingSpendHash,
            );
          }
          if (!outputExists) {
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-output.params',
              outputPath,
              _saplingOutputHash,
            );
          }
          if (await _abortIfUnmounted()) return;
        }
      }

      final isHardware = ref
          .read(accountProvider.notifier)
          .isActiveAccountHardware;

      late final String txid;
      if (isHardware) {
        log(
          'SendStatus: creating PCZT from proposal ${widget.args.proposalId}',
        );
        final pcztBytes = await rust_sync.createPcztFromProposal(
          dbPath: dbPath,
          network: ZcashNetwork.mainnet.name,
          proposalId: widget.args.proposalId,
        );
        _proposalConsumed = true;

        final pcztWithProofs = await rust_sync.addProofsToPczt(
          pcztBytes: pcztBytes,
          spendParamsPath: widget.args.needsSaplingParams ? spendPath : null,
          outputParamsPath: widget.args.needsSaplingParams ? outputPath : null,
        );
        final redactedPczt = await rust_sync.redactPcztForSigner(
          pcztBytes: pcztBytes,
        );

        if (await _abortIfUnmounted()) return;
        final dialogContext = context;
        // ignore: use_build_context_synchronously
        final transport = await KeystoneTransport.select(dialogContext);
        if (transport == null) {
          if (await _abortIfUnmounted()) return;
          setState(() {
            _phase = _SendStatusPhase.failed;
            _error =
                'Signing was cancelled before the transaction was broadcast.';
          });
          return;
        }

        if (await _abortIfUnmounted()) return;
        final pcztWithSignatures = await _signWithTransport(
          transport,
          redactedPczt,
        );
        txid = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          network: ZcashNetwork.mainnet.name,
          pcztWithProofsBytes: pcztWithProofs,
          pcztWithSignaturesBytes: pcztWithSignatures,
          spendParamsPath: widget.args.needsSaplingParams ? spendPath : null,
          outputParamsPath: widget.args.needsSaplingParams ? outputPath : null,
        );
      } else {
        final mnemonic = await ref
            .read(accountProvider.notifier)
            .getActiveMnemonic();
        if (mnemonic == null) {
          if (await _abortIfUnmounted()) return;
          setState(() {
            _phase = _SendStatusPhase.failed;
            _error = 'Mnemonic not found for the active account.';
          });
          return;
        }

        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
        txid = await rust_sync.executeProposal(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          proposalId: widget.args.proposalId,
          seed: seedBytes,
          spendParamsPath: widget.args.needsSaplingParams ? spendPath : null,
          outputParamsPath: widget.args.needsSaplingParams ? outputPath : null,
        );
        _proposalConsumed = true;
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('SendStatus: refreshAfterSend failed (non-critical): $e');
      }

      if (Platform.isIOS) {
        try {
          const channel = MethodChannel('com.zcash.wallet/background_sync');
          final available =
              await channel.invokeMethod<bool>('isAvailable') ?? false;
          if (available) {
            await channel.invokeMethod('startTxTracking');
          }
        } catch (e) {
          log('SendStatus: iOS TX tracking failed (non-critical): $e');
        }
      }

      if (await _abortIfUnmounted()) return;
      setState(() {
        _phase = _SendStatusPhase.succeeded;
        _txid = txid;
        _completedAt = DateTime.now();
      });
    } catch (e) {
      log('SendStatus: ERROR: $e');
      final message = _friendlyError(e.toString());
      if (!mounted) {
        if (!_proposalConsumed) {
          try {
            await rust_sync.discardProposal(proposalId: widget.args.proposalId);
          } catch (_) {}
        }
        return;
      }
      setState(() {
        _phase = _SendStatusPhase.failed;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final accountName = accountAsync.value?.activeAccount?.name ?? 'Username';
    final matchedLocation = GoRouterState.of(context).matchedLocation;
    final addressLines = _splitAddress();

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_goHome());
        }
      },
      child: AppDesktopShell(
        sidebar: AppMainSidebar(
          accountName: accountName,
          matchedLocation: matchedLocation,
        ),
        pane: AppDesktopPane(
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(child: _SendStatusIllustration()),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      _SendStatusBackRow(onTap: _goHome),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 255),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _SendStatusContent(
                              phase: _phase,
                              amountText: _formatReceiptAmount(
                                widget.args.amountZatoshi,
                              ),
                              addressLines: addressLines,
                              addressSpanBuilder: (line) =>
                                  _addressSpans(context, line),
                              feeText:
                                  '${_formatFee(widget.args.feeZatoshi)} ZEC',
                              dateText: _formatDate(_completedAt ?? _startedAt),
                              error: _error,
                              onCopyTxid: _phase == _SendStatusPhase.succeeded
                                  ? _copyTransactionHash
                                  : null,
                              onBackToWallet: _phase == _SendStatusPhase.failed
                                  ? _goHome
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendStatusBackRow extends StatelessWidget {
  const _SendStatusBackRow({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(onTap()),
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.chevronBackward,
                  size: 16,
                  color: colors.icon.accent,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Back',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _SendStatusContent extends StatelessWidget {
  const _SendStatusContent({
    required this.phase,
    required this.amountText,
    required this.addressLines,
    required this.addressSpanBuilder,
    required this.feeText,
    required this.dateText,
    required this.error,
    required this.onCopyTxid,
    required this.onBackToWallet,
  });

  final _SendStatusPhase phase;
  final String amountText;
  final List<String> addressLines;
  final List<TextSpan> Function(String line) addressSpanBuilder;
  final String feeText;
  final String dateText;
  final String? error;
  final VoidCallback? onCopyTxid;
  final VoidCallback? onBackToWallet;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 328,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SendStatusHeadline(phase: phase, amountText: amountText),
              const SizedBox(height: AppSpacing.md),
              _SendStatusBlock(
                title: 'To',
                rightLabel: const _SendStatusFieldTrailing(label: 'Andrew'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in addressLines)
                      RichText(
                        text: TextSpan(children: addressSpanBuilder(line)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _SendStatusBlock(
                      title: 'Date',
                      child: Text(
                        dateText,
                        style: AppTypography.labelLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _SendStatusBlock(
                      title: 'Tx Fee',
                      child: Text(
                        feeText,
                        style: AppTypography.labelLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: 256,
          child: switch (phase) {
            _SendStatusPhase.sending => const SizedBox(height: 40),
            _SendStatusPhase.succeeded => AppButton(
              onPressed: onCopyTxid,
              variant: AppButtonVariant.secondary,
              minWidth: 256,
              trailing: AppIcon(
                AppIcons.arrowTopRight,
                color: context.colors.button.secondary.label,
              ),
              child: const Text('Transaction Hash'),
            ),
            _SendStatusPhase.failed => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SendStatusFailureMessage(message: error ?? 'Send failed'),
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  onPressed: onBackToWallet,
                  variant: AppButtonVariant.secondary,
                  minWidth: 256,
                  child: const Text('Back to Wallet'),
                ),
              ],
            ),
          },
        ),
      ],
    );
  }
}

class _SendStatusHeadline extends StatelessWidget {
  const _SendStatusHeadline({required this.phase, required this.amountText});

  final _SendStatusPhase phase;
  final String amountText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final icon = switch (phase) {
      _SendStatusPhase.sending => AppIcons.loader,
      _SendStatusPhase.succeeded => AppIcons.check,
      _SendStatusPhase.failed => AppIcons.warning,
    };
    final label = switch (phase) {
      _SendStatusPhase.sending => 'Sending...',
      _SendStatusPhase.succeeded => 'Succeeded',
      _SendStatusPhase.failed => 'Failed',
    };
    final labelColor = switch (phase) {
      _SendStatusPhase.sending => colors.text.accent,
      _SendStatusPhase.succeeded => const Color(0xFF47BE47),
      _SendStatusPhase.failed => colors.text.warning,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 16, color: labelColor),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(color: labelColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          amountText,
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
        ),
      ],
    );
  }
}

class _SendStatusBlock extends StatelessWidget {
  const _SendStatusBlock({
    required this.title,
    required this.child,
    this.rightLabel,
  });

  final String title;
  final Widget child;
  final Widget? rightLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailingChildren = rightLabel == null ? null : <Widget>[rightLabel!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            ...?trailingChildren,
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

class _SendStatusFieldTrailing extends StatelessWidget {
  const _SendStatusFieldTrailing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        AppIcon(AppIcons.chevronForward, size: 16, color: colors.icon.regular),
      ],
    );
  }
}

class _SendStatusFailureMessage extends StatelessWidget {
  const _SendStatusFailureMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(AppIcons.warning, size: 16, color: context.colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}

class _SendStatusIllustration extends StatelessWidget {
  const _SendStatusIllustration();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assetPath = isDark
        ? 'assets/illustrations/send_status_illustration_dark.png'
        : 'assets/illustrations/send_status_illustration_light.png';
    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Image.asset(
              assetPath,
              fit: BoxFit.fitHeight,
              alignment: Alignment.centerRight,
              height: double.infinity,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.fade.illustration),
          ),
        ),
      ],
    );
  }
}
