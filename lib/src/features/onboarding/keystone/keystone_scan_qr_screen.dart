import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
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
    return KeystoneOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: KeystoneOnboardingStep.howToConnect.label,
        routePath: KeystoneOnboardingStep.howToConnect.routePath,
      ),
      bodyPadding: EdgeInsets.zero,
      child: _ScanQrLayout(
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
    );
  }
}

class _ScanQrLayout extends StatelessWidget {
  const _ScanQrLayout({
    required this.decoding,
    required this.error,
    required this.onProgress,
    required this.onDecodeError,
    required this.onComplete,
  });

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;
  static const double _sectionGap = 32;

  final bool decoding;
  final String? error;
  final ValueChanged<int> onProgress;
  final ValueChanged<Object> onDecodeError;
  final ValueChanged<ScanResult> onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _TitleBlock(),
                    const SizedBox(height: _sectionGap),
                    KeystoneQrScannerCard(
                      expectedUrType: 'zcash-accounts',
                      decoding: decoding,
                      error: error,
                      onProgress: onProgress,
                      onDecodeError: onDecodeError,
                      onComplete: onComplete,
                      decodingLabel: 'Reading accounts...',
                      unavailableMessage:
                          'Keystone import uses camera QR scanning only. Connect a camera and try again.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Scan QR Code',
            style: AppTypography.displayLarge.copyWith(
              fontFamily: 'Young Serif',
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Prepare your Keystone wallet',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
