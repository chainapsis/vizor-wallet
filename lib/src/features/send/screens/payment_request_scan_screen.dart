import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../../onboarding/shared/onboarding_chrome.dart';
import '../services/payment_request_scanner.dart';

class PaymentRequestScanScreen extends StatefulWidget {
  const PaymentRequestScanScreen({required this.networkName, super.key});
  final String networkName;

  @override
  State<PaymentRequestScanScreen> createState() =>
      _PaymentRequestScanScreenState();
}

class _PaymentRequestScanScreenState extends State<PaymentRequestScanScreen> {
  bool _processing = false;
  bool _finished = false;
  int _resetToken = 0;
  String? _error;

  Future<void> _scan(String raw) async {
    if (!mounted ||
        _finished ||
        _processing ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _processing = true;
    try {
      final prefill = await decodePaymentRequestQr(
        raw,
        networkName: widget.networkName,
      );
      if (!mounted || _finished || ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _finished = true;
      context.pop(prefill);
    } on FormatException catch (error) {
      if (!mounted || _finished) return;
      setState(() {
        _error = error.message;
        _resetToken++;
      });
    } catch (_) {
      if (!mounted || _finished) return;
      setState(() {
        _error = "Couldn't check this QR code. Try again.";
        _resetToken++;
      });
    } finally {
      _processing = false;
    }
  }

  void _back() {
    _finished = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) => AppDesktopShell(
    sidebar: const AppMainSidebar(),
    pane: OnboardingPaneChrome(
      backTarget: OnboardingBackTarget.callback(
        label: 'Payment request',
        onTap: _back,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: SizedBox(
                width: 420,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Scan original QR',
                        style: AppTypography.displayLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Show the requester’s original QR code to your camera',
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.base),
                      KeystoneQrScannerCard.plain(
                        onPlainComplete: _scan,
                        scanSessionResetToken: _resetToken,
                        error: _error,
                        unavailableMessage:
                            'Connect a camera, or go back and review the link details.',
                        permissionDescription:
                            'A camera is required to scan the payment request QR code.\n'
                            'You can change camera access in settings at any time.',
                        troubleScanningTips: const [
                          'Open the requester’s original QR code full screen on another device.',
                          'Move the QR code a few inches further from the camera so it can focus.',
                          "Make sure the room is well-lit and the QR code isn't reflecting glare.",
                          'On a Mac, you can use Continuity Camera to scan with your iPhone instead.',
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
