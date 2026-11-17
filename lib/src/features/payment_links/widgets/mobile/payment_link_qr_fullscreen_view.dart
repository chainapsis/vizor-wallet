import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

class PaymentLinkQrFullscreenView extends StatelessWidget {
  const PaymentLinkQrFullscreenView({
    required this.link,
    required this.onClose,
    super.key,
  });

  final String link;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('payment_link_qr_fullscreen'),
      color: context.colors.background.base,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.paymentLinkQrCardSemantic,
                      style: AppTypography.bodyLarge.copyWith(
                        color: context.colors.text.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Semantics(
                    label: context.l10n.commonClose,
                    child: AppButton(
                      key: const ValueKey('payment_link_qr_fullscreen_close'),
                      variant: AppButtonVariant.secondary,
                      minWidth: 44,
                      height: 44,
                      contentPadding: EdgeInsets.zero,
                      onPressed: onClose,
                      child: const ExcludeSemantics(
                        child: AppIcon(AppIcons.cross, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: Semantics(
                      image: true,
                      label: context.l10n.paymentLinkQrCardSemantic,
                      child: SizedBox.square(
                        key: const ValueKey('payment_link_fullscreen_qr_code'),
                        dimension: constraints.biggest.shortestSide,
                        child: ColoredBox(
                          color: const Color(0xFFFFFFFF),
                          child: PrettyQrView.data(
                            data: link,
                            errorCorrectLevel: QrErrorCorrectLevel.L,
                            decoration: const PrettyQrDecoration(
                              quietZone: PrettyQrQuietZone.standard,
                              // Zero rounding gives square modules without
                              // SquaresSymbol's minimum module-size clamp.
                              shape: PrettyQrSmoothSymbol(roundFactor: 0),
                            ),
                            errorBuilder: (context, _, _) => Center(
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                child: Text(
                                  context.l10n.paymentLinkQrCouldNotBeGenerated,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: const Color(0xFF141818),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
