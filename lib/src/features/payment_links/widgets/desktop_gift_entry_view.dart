import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../onboarding/shared/onboarding_chrome.dart';
import 'desktop_gift_setup_shell.dart';
import 'payment_link_copy.dart';
import 'payment_link_wizard_chrome.dart';

/// The Gift entry uses the same sidebar and pane as its account setup steps.
class DesktopGiftEntryView extends StatelessWidget {
  const DesktopGiftEntryView({
    required this.addingAccount,
    required this.invalid,
    required this.onBack,
    required this.onPaste,
    required this.onScan,
    super.key,
  });

  final bool addingAccount;
  final bool invalid;
  final VoidCallback onBack;
  final VoidCallback? onPaste;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) => DesktopGiftSetupShell(
    step: DesktopGiftSetupStep.redeem,
    showPasswordStep: !addingAccount,
    backTarget: OnboardingBackTarget.callback(
      label: addingAccount ? 'Add account' : 'Welcome',
      onTap: onBack,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: 396,
            height: math.max(constraints.maxHeight, 490),
            child: Column(
              children: [
                Text(
                  kPaymentLinkRedeemTheCardTitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Copy the card link you’ve\nreceived, and paste it below.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PaymentLinkDashedDropZone(
                        borderColor: context.colors.border.regular,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (invalid) ...[
                              Text(
                                kPaymentLinkInvalidTitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: context.colors.text.destructive,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s),
                            ],
                            SizedBox(
                              width: 156,
                              child: AppButton(
                                key: const ValueKey(
                                  'gift_desktop_paste_button',
                                ),
                                onPressed: onPaste,
                                size: AppButtonSize.mediumLarge,
                                expand: true,
                                leading: const AppIcon(AppIcons.paste),
                                child: const Text(kPaymentLinkPasteLabel),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            SizedBox(
                              width: 156,
                              child: AppButton(
                                key: const ValueKey('gift_desktop_scan_button'),
                                onPressed: onScan,
                                size: AppButtonSize.mediumLarge,
                                expand: true,
                                variant: AppButtonVariant.secondary,
                                leading: const AppIcon(AppIcons.qr),
                                child: const Text('Scan QR code'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      SizedBox(
                        width: 233,
                        child: Text(
                          addingAccount
                              ? 'Redeem the card to create a new account with '
                                    'the card’s balance in your wallet.'
                              : 'Once the card is redeemed, we will create a '
                                    'new Vizor wallet with the card’s balance.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: context.colors.text.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
