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
                    KeystoneQrScannerCard(
                      expectedUrType: 'zcash-accounts',
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
                      decodingLabel: 'Reading accounts...',
                      unavailableMessage:
                          'Keystone import uses camera QR scanning only. Connect a camera and try again.',
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
