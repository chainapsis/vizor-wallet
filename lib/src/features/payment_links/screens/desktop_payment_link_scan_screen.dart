import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/navigation/external_action_guard_hold.dart';
import '../../../core/theme/app_theme.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../../onboarding/shared/onboarding_chrome.dart';
import '../models/payment_link_scan_payload.dart';
import '../widgets/desktop_gift_setup_shell.dart';

class DesktopPaymentLinkScanScreen extends ConsumerStatefulWidget {
  const DesktopPaymentLinkScanScreen({
    required this.networkName,
    this.onboarding = true,
    this.addingAccount = false,
    super.key,
  });

  final String networkName;
  final bool onboarding;
  final bool addingAccount;

  @override
  ConsumerState<DesktopPaymentLinkScanScreen> createState() =>
      _DesktopPaymentLinkScanScreenState();
}

class _DesktopPaymentLinkScanScreenState
    extends ConsumerState<DesktopPaymentLinkScanScreen>
    with ExternalActionGuardHoldMixin {
  bool _finished = false;
  int _resetToken = 0;
  String? _error;

  void _scan(String raw) {
    if (!mounted || _finished || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    try {
      final link = decodePaymentLinkQr(raw, networkName: widget.networkName);
      _finished = true;
      context.pop(link);
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
        _resetToken++;
      });
    }
  }

  void _back() {
    _finished = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        widget.onboarding
            ? (widget.addingAccount ? '/gift?addAccount=true' : '/gift')
            : '/payment-links',
      );
    }
  }

  @override
  Widget build(BuildContext context) => DesktopPaymentLinkScanView(
    onboarding: widget.onboarding,
    addingAccount: widget.addingAccount,
    onBack: _back,
    scanner: KeystoneQrScannerCard.plain(
      onPlainComplete: _scan,
      scanSessionResetToken: _resetToken,
      error: _error,
      unavailableMessage:
          'Connect a camera to scan the gift card QR code, or go back to paste the card link.',
    ),
  );
}

/// Gift scanning shares the desktop Keystone scan page's card and geometry.
class DesktopPaymentLinkScanView extends StatelessWidget {
  const DesktopPaymentLinkScanView({
    required this.scanner,
    required this.onBack,
    this.onboarding = true,
    this.addingAccount = false,
    super.key,
  });

  final Widget scanner;
  final VoidCallback onBack;
  final bool onboarding;
  final bool addingAccount;

  @override
  Widget build(BuildContext context) {
    final backTarget = OnboardingBackTarget.callback(
      label: 'Redeem the card',
      onTap: onBack,
    );
    final body = LayoutBuilder(
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
                      'Scan QR Code',
                      style: AppTypography.displayLarge.copyWith(
                        color: context.colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Show the gift card QR code to your camera',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    scanner,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (onboarding) {
      return DesktopGiftSetupShell(
        step: DesktopGiftSetupStep.redeem,
        showPasswordStep: !addingAccount,
        backTarget: backTarget,
        child: body,
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: OnboardingPaneChrome(backTarget: backTarget, child: body),
    );
  }
}
