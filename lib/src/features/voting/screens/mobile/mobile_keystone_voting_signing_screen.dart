import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/payment_uri_busy_surface_hold.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/voting/voting_submission_job_provider.dart';
import '../../../keystone/widgets/mobile_keystone_pczt_signing_flow.dart';
import '../voting_status_screen.dart';

class MobileKeystoneVotingSigningScreen extends StatelessWidget {
  const MobileKeystoneVotingSigningScreen({
    super.key,
    required this.presentation,
    this.scannerBuilder,
    this.forceScannerActiveForTesting = false,
    this.startInScannerForTesting = false,
  });

  final VotingKeystoneStatusPresentation presentation;
  final MobileKeystonePcztScannerBuilder? scannerBuilder;
  final bool forceScannerActiveForTesting;
  final bool startInScannerForTesting;

  @override
  Widget build(BuildContext context) {
    final batchCount = presentation.batchMessageCount;
    final totalCount = presentation.batchTotalCount;
    final contextLabel = batchCount <= 0
        ? null
        : totalCount > batchCount
        ? '$batchCount of $totalCount remaining bundles'
        : batchCount == 1
        ? '1 voting bundle'
        : '$batchCount voting bundles';
    final flowKey = ValueKey<String>(
      'mobile_voting_keystone_${presentation.bundleIndex}_'
      '${presentation.urParts.first.hashCode}',
    );

    // Above the keyed flow on purpose: the key changes per bundle, so a hold
    // taken inside the flow would fall back to zero between bundles.
    return PaymentUriBusySurfaceHold(
      child: MobileKeystonePcztSigningFlow(
        key: flowKey,
        title: 'Sign vote with Keystone',
        failedTitle: 'Voting signature failed',
        description:
            'Scan the voting request with Keystone, approve it, then scan the signed result with this device.',
        keyPrefix: 'mobile_voting_keystone',
        logTag: 'MobileKeystoneVoting',
        readingSignatureLabel: 'Reading voting signature...',
        finalizingSignatureLabel: 'Checking voting signature...',
        scanCaption: 'Scan the signed voting QR shown on Keystone',
        expectedSignedUrType: 'zcash-batch-sig-result',
        unexpectedUrMessage:
            'Open the signed voting QR on Keystone, then scan again.',
        recoverSignedCallbackErrorInScanner: true,
        signingContextLabel: contextLabel,
        requestDetails: presentation.batchMemos.isEmpty
            ? null
            : _MobileVotingMemoPager(memos: presentation.batchMemos),
        requestAuxiliaryActionLabel: presentation.canSkipRemainingBundles
            ? 'Skip unsigned bundles'
            : null,
        onRequestAuxiliaryAction: presentation.canSkipRemainingBundles
            ? presentation.onSkipRemainingBundles
            : null,
        showCancelAction: false,
        allowQrContentScrolling: true,
        preparePczt: (_, _) async => MobileKeystonePcztSigningPayload(
          urParts: presentation.urParts,
          pcztWithProofs: Future<List<int>>.value(const []),
        ),
        signedPcztDecoder: (responseCbor) async =>
            Uint8List.fromList(responseCbor),
        onSigned: (_, _, _, responseCbor) =>
            presentation.onSigned(responseCbor),
        friendlyError: (error) =>
            presentation.scanError ?? _friendlyVotingScanError(error),
        scannerBuilder: scannerBuilder,
        forceScannerActiveForTesting: forceScannerActiveForTesting,
        startInScannerForTesting: startInScannerForTesting,
        onCancel: () => context.go('/voting'),
      ),
    );
  }
}

String _friendlyVotingScanError(Object error) {
  final message = error.toString();
  return message
      .replaceFirst(RegExp(r'^(Bad state|StateError):\s*'), '')
      .trim();
}

class _MobileVotingMemoPager extends StatefulWidget {
  const _MobileVotingMemoPager({required this.memos});

  final List<VotingKeystoneBatchMemo> memos;

  @override
  State<_MobileVotingMemoPager> createState() => _MobileVotingMemoPagerState();
}

class _MobileVotingMemoPagerState extends State<_MobileVotingMemoPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final memos = [
      for (final memo in widget.memos)
        if (memo.displayMemo.trim().isNotEmpty) memo,
    ];
    if (memos.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, memos.length - 1);
    final memo = memos[index];
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.ground,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              _MemoPagerAction(
                semanticLabel: 'Previous voting bundle',
                icon: AppIcons.chevronBackward,
                onTap: index > 0
                    ? () => setState(() => _index = index - 1)
                    : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bundle ${memo.bundleIndex + 1} of ${memo.bundleCount}',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      memo.displayMemo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ),
              _MemoPagerAction(
                semanticLabel: 'Next voting bundle',
                icon: AppIcons.chevronForward,
                onTap: index + 1 < memos.length
                    ? () => setState(() => _index = index + 1)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoPagerAction extends StatelessWidget {
  const _MemoPagerAction({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
  });

  final String semanticLabel;
  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: AppIcon(
              icon,
              size: 18,
              color: context.colors.icon.accent.withValues(
                alpha: onTap == null ? 0.3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
