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
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../services/keystone_transport.dart';

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

class SendReviewArgs {
  const SendReviewArgs({
    required this.proposalId,
    required this.address,
    required this.addressType,
    required this.amountZatoshi,
    required this.feeZatoshi,
    required this.needsSaplingParams,
    this.memo,
  });

  final BigInt proposalId;
  final String address;
  final String addressType;
  final BigInt amountZatoshi;
  final BigInt feeZatoshi;
  final bool needsSaplingParams;
  final String? memo;

  bool get isShielded => addressType == 'unified' || addressType == 'sapling';
}

class SendReviewScreen extends ConsumerStatefulWidget {
  const SendReviewScreen({super.key, required this.args});

  final SendReviewArgs args;

  @override
  ConsumerState<SendReviewScreen> createState() => _SendReviewScreenState();
}

class _SendReviewScreenState extends ConsumerState<SendReviewScreen> {
  bool _isSending = false;
  bool _proposalConsumed = false;
  bool _discardScheduled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    _scheduleDiscardIfNeeded();
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
              'SendReview: released proposal ${widget.args.proposalId} on dispose',
            );
          })
          .catchError((Object e) {
            log(
              'SendReview: discardProposal cleanup failed (non-critical): $e',
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
      return 'Some transactions were broadcast but not all. '
          'Please check your transaction history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired. Please try again.';
    }
    return 'Send failed. Please try again.';
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
      log('SendReview: downloaded and verified $destPath');
    } finally {
      client.close();
    }
  }

  Future<void> _handleBack() async {
    if (_isSending) return;
    _scheduleDiscardIfNeeded();
    if (!mounted) return;
    context.pop();
  }

  Future<void> _handleSend() async {
    setState(() {
      _isSending = true;
      _error = null;
    });

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
          if (!mounted) return;
          final downloadConfirmed = await _showSaplingParamsDialog();
          if (!downloadConfirmed) {
            setState(() => _isSending = false);
            return;
          }

          await Directory(paramsDir).create(recursive: true);
          if (!spendExists) {
            setState(() => _error = 'Downloading sapling-spend.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-spend.params',
              spendPath,
              _saplingSpendHash,
            );
          }
          if (!outputExists) {
            setState(() => _error = 'Downloading sapling-output.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-output.params',
              outputPath,
              _saplingOutputHash,
            );
          }
          if (!mounted) return;
          setState(() => _error = null);
        }
      }

      final isHardware = ref
          .read(accountProvider.notifier)
          .isActiveAccountHardware;

      if (isHardware) {
        log(
          'SendReview: creating PCZT from proposal ${widget.args.proposalId}',
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

        if (!mounted) return;
        final transport = await KeystoneTransport.select(context);
        if (transport == null || !mounted) {
          setState(() => _isSending = false);
          return;
        }

        final pcztWithSignatures = await transport.signPczt(
          context,
          redactedPczt,
        );
        await rust_sync.extractAndBroadcastPczt(
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
          setState(() {
            _error = 'Mnemonic not found for active account';
            _isSending = false;
          });
          return;
        }

        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
        await rust_sync.executeProposal(
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
        log('SendReview: refreshAfterSend failed (non-critical): $e');
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
          log('SendReview: iOS TX tracking failed (non-critical): $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction sent successfully'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/home');
    } catch (e) {
      log('SendReview: ERROR: $e');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e.toString());
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final accountName = accountAsync.value?.activeAccount?.name ?? 'Username';
    final matchedLocation = GoRouterState.of(context).matchedLocation;
    final colors = context.colors;

    return AppDesktopShell(
      sidebar: AppMainSidebar(
        accountName: accountName,
        matchedLocation: matchedLocation,
      ),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            _SendReviewBackRow(onTap: _handleBack),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 352,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: _SendReviewReceiptCard(
                            args: widget.args,
                            amountText: _formatReceiptAmount(
                              widget.args.amountZatoshi,
                            ),
                            feeText: _formatFee(widget.args.feeZatoshi),
                            addressLines: _splitAddress(),
                            addressSpanBuilder: (line) =>
                                _addressSpans(context, line),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        _SendReviewError(message: _error!),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      SizedBox(
                        width: 256,
                        child: AppButton(
                          onPressed: _isSending ? null : _handleSend,
                          variant: AppButtonVariant.primary,
                          minWidth: 256,
                          trailing: _isSending
                              ? null
                              : AppIcon(
                                  AppIcons.plane,
                                  color: colors.button.primary.label,
                                ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Send'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendReviewBackRow extends StatelessWidget {
  const _SendReviewBackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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

class _SendReviewReceiptCard extends StatelessWidget {
  const _SendReviewReceiptCard({
    required this.args,
    required this.amountText,
    required this.feeText,
    required this.addressLines,
    required this.addressSpanBuilder,
  });

  final SendReviewArgs args;
  final String amountText;
  final String feeText;
  final List<String> addressLines;
  final List<TextSpan> Function(String line) addressSpanBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasMemo = args.memo != null && args.memo!.trim().isNotEmpty;

    return SizedBox(
      width: 352,
      height: 404,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 352,
            height: 484,
            child: Image.asset(
              'assets/illustrations/send_review_receipt_mask.png',
              fit: BoxFit.fill,
            ),
          ),
          Positioned(
            top: 24,
            right: 18,
            child: _SendReviewStatusBadge(isShielded: args.isShielded),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sending',
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    amountText,
                    style: AppTypography.displayMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SendReviewFieldTitle(
                    label: 'To',
                    rightLabel: _SendReviewFieldTrailing(
                      label: 'Andrew',
                      icon: AppIcon(
                        AppIcons.chevronForward,
                        size: 16,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final line in addressLines)
                    RichText(
                      text: TextSpan(children: addressSpanBuilder(line)),
                    ),
                  if (hasMemo) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _SendReviewFieldTitle(
                      label: 'Message',
                      rightLabel: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Expand',
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          AppIcon(
                            AppIcons.expand,
                            size: 16,
                            color: colors.icon.regular,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 62,
                      child: Text(
                        args.memo!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  const AppDecorativeDivider(width: 320),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Tx Fee: $feeText ZEC',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendReviewStatusBadge extends StatelessWidget {
  const _SendReviewStatusBadge({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isShielded ? 'Shielded' : 'Transparent',
          style: AppTypography.labelLarge.copyWith(
            color: isShielded ? colors.text.brandPurple : colors.text.muted,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        if (isShielded)
          _SendShieldedBadgeIcon()
        else
          AppIcon(AppIcons.eye, size: 16, color: colors.text.muted),
      ],
    );
  }
}

class _SendReviewFieldTitle extends StatelessWidget {
  const _SendReviewFieldTitle({required this.label, this.rightLabel});

  final String label;
  final Widget? rightLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        if (rightLabel != null) ...[rightLabel!],
      ],
    );
  }
}

class _SendReviewFieldTrailing extends StatelessWidget {
  const _SendReviewFieldTrailing({required this.label, required this.icon});

  final String label;
  final Widget icon;

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
        icon,
      ],
    );
  }
}

class _SendShieldedBadgeIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: OverflowBox(
              minWidth: 500.755,
              maxWidth: 500.755,
              minHeight: 562.605,
              maxHeight: 562.605,
              child: Image.asset(
                'assets/illustrations/send_review_receipt_pattern.png',
                width: 500.755,
                height: 562.605,
                fit: BoxFit.fill,
              ),
            ),
          ),
          AppIcon(
            AppIcons.shieldKeyhole,
            size: 16,
            color: colors.text.brandPurple,
          ),
        ],
      ),
    );
  }
}

class _SendReviewError extends StatelessWidget {
  const _SendReviewError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
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
