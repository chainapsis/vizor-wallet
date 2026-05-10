import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../services/qr_scanner.dart';
import 'keystone_onboarding_flow.dart';

class KeystoneScanQrScreen extends ConsumerStatefulWidget {
  const KeystoneScanQrScreen({super.key});

  @override
  ConsumerState<KeystoneScanQrScreen> createState() =>
      _KeystoneScanQrScreenState();
}

class _KeystoneScanQrScreenState extends ConsumerState<KeystoneScanQrScreen> {
  int _progress = 0;
  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(keystoneOnboardingProvider.notifier).resetScan();
  }

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
      _progress = 100;
    });

    try {
      final accounts = await rust_keystone.decodeAccountsFromCbor(
        cbor: result.data,
      );
      if (!mounted) return;
      if (accounts.isEmpty) {
        setState(() {
          _decoding = false;
          _error = 'No Zcash accounts were found on this Keystone QR.';
        });
        return;
      }

      ref.read(keystoneOnboardingProvider.notifier).setAccounts(accounts);
      context.go(KeystoneOnboardingStep.selectAccount.routePath);
    } catch (e, st) {
      log('KeystoneScanQrScreen: account decode error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _decoding = false;
        _error =
            'This QR code could not be decoded as a Keystone Zcash account.';
      });
    }
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the Zcash account QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return KeystoneOnboardingTrailingPane(
      child: Column(
        children: [
          KeystoneBackRow(
            routePath: KeystoneOnboardingStep.howToConnect.routePath,
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Scan QR Code',
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: 360,
                      child: Text(
                        'Grant access to your camera and then place the QR code in front of your screen.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _CameraGuidance(),
                    const SizedBox(height: AppSpacing.md),
                    _ScannerCard(
                      progress: _progress,
                      decoding: _decoding,
                      error: _error,
                      onProgress: (progress) {
                        if (!mounted) return;
                        setState(() {
                          _progress = progress;
                          if (progress > 0) _error = null;
                        });
                      },
                      onDecodeError: _handleDecodeError,
                      onComplete: _handleScanComplete,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraGuidance extends StatelessWidget {
  const _CameraGuidance();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 456,
      child: Text(
        'A camera is required. Monitor webcams may struggle to focus on QR codes; increase the distance, improve lighting, or use an external webcam.',
        style: AppTypography.labelMedium.copyWith(color: colors.text.secondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.progress,
    required this.decoding,
    required this.error,
    required this.onProgress,
    required this.onDecodeError,
    required this.onComplete,
  });

  final int progress;
  final bool decoding;
  final String? error;
  final ValueChanged<int> onProgress;
  final ValueChanged<Object> onDecodeError;
  final ValueChanged<ScanResult> onComplete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 456,
      child: Column(
        children: [
          Container(
            height: 316,
            decoration: BoxDecoration(
              color: colors.background.overlay.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: colors.border.regular, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (QrScanner.isAvailable)
                  AnimatedUrScannerView(
                    expectedUrType: 'zcash-accounts',
                    onProgress: onProgress,
                    onDecodeError: onDecodeError,
                    onComplete: onComplete,
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'Keystone import uses camera QR scanning only. Connect a camera and try again.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const _ScanFrame(),
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: _ProgressBar(progress: progress),
                ),
                if (decoding)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.ground.withValues(alpha: 0.72),
                    ),
                    child: Center(
                      child: Text(
                        'Reading accounts...',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Text(
                'Camera',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const Spacer(),
              Text(
                QrScanner.isAvailable ? 'Default camera' : 'No camera found',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.chevronForward,
                size: AppIconSize.medium,
                color: colors.icon.accent,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              error!,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (!QrScanner.isAvailable) ...[
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: null,
              variant: AppButtonVariant.primary,
              minWidth: 256,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Container(
        width: 188,
        height: 188,
        decoration: BoxDecoration(
          border: Border.all(color: colors.border.strong, width: 2),
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = progress.clamp(0, 100) / 100;
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: colors.background.overlay.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value == 0 ? 0.02 : value,
        child: Container(
          decoration: BoxDecoration(
            color: colors.button.primary.bg,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}
