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
  bool _decoding = false;
  String? _error;

  Future<void> _handleScanComplete(ScanResult result) async {
    if (_decoding) return;
    setState(() {
      _decoding = true;
      _error = null;
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
                      width: 340,
                      child: Text(
                        'Grant access to your camera and then place the QR code in front of your screen.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _ScannerCard(
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

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.decoding,
    required this.error,
    required this.onProgress,
    required this.onDecodeError,
    required this.onComplete,
  });

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
              borderRadius: BorderRadius.circular(20),
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

  static const _width = 263.0;
  static const _height = 262.0;
  static const _segmentLength = 58.0;
  static const _strokeWidth = 5.0;
  static const _radius = 17.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          children: [
            _ScanCorner(
              alignment: Alignment.topLeft,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.topRight,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.bottomLeft,
              color: colors.text.accent,
            ),
            _ScanCorner(
              alignment: Alignment.bottomRight,
              color: colors.text.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCorner extends StatelessWidget {
  const _ScanCorner({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;
    final border = BorderSide(
      color: color,
      width: _ScanFrame._strokeWidth,
      strokeAlign: BorderSide.strokeAlignInside,
    );
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: _ScanFrame._segmentLength,
        height: _ScanFrame._segmentLength,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: isLeft ? border : BorderSide.none,
              right: isLeft ? BorderSide.none : border,
              top: isTop ? border : BorderSide.none,
              bottom: isTop ? BorderSide.none : border,
            ),
            borderRadius: BorderRadius.only(
              topLeft: isLeft && isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              topRight: !isLeft && isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              bottomLeft: isLeft && !isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
              bottomRight: !isLeft && !isTop
                  ? const Radius.circular(_ScanFrame._radius)
                  : Radius.zero,
            ),
          ),
        ),
      ),
    );
  }
}
