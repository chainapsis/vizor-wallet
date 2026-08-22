import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/qr_scanner.dart';
import '../../../keystone/widgets/keystone_qr_scanner_card.dart';

/// Mobile scan step of the Keystone voting flow: reads the signed
/// `zcash-batch-sig-result` QR from the device and pops the CBOR bytes back
/// to the status screen, mirroring the desktop scan screen.
class MobileKeystoneVotingScanScreen extends ConsumerStatefulWidget {
  const MobileKeystoneVotingScanScreen({super.key});

  @override
  ConsumerState<MobileKeystoneVotingScanScreen> createState() =>
      _MobileKeystoneVotingScanScreenState();
}

class _MobileKeystoneVotingScanScreenState
    extends ConsumerState<MobileKeystoneVotingScanScreen> {
  bool _decoding = false;
  String? _error;

  void _handleScanComplete(ScanResult result) {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
    });

    if (!mounted) return;
    context.pop(result.data);
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed voting QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/voting');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: 'Scan voting signature', onBack: _goBack),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Text(
                      'Hold the Keystone QR code steady in front of your camera',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.base),
                    KeystoneQrScannerCard(
                      expectedUrType: 'zcash-batch-sig-result',
                      decoding: _decoding,
                      error: _error,
                      onProgress: (progress) {
                        if (!mounted) return;
                        setState(() {
                          if (progress > 0) _error = null;
                        });
                      },
                      onDecodeError: _handleDecodeError,
                      onComplete: _handleScanComplete,
                      decodingLabel: 'Reading signature...',
                      unavailableMessage:
                          'Keystone voting uses camera QR scanning only. Connect a camera and try again.',
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
