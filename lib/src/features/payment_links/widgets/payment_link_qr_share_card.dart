/// The offscreen Gift Card share surface rendered into a PNG.
///
/// It lives apart from the desktop step views because it is not a screen: it
/// is a fixed 396×270 composite captured by the QR export path, so its
/// [PaymentLinkQrShareCard.size] and
/// [PaymentLinkQrShareCard.brandBadgeAssetPath] contract is addressed
/// directly by the export code and by tests, independently of any wizard step.
library;

import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import 'payment_link_gift_card.dart';

/// The exportable 396×270 Gift Card artwork and QR composite.
class PaymentLinkQrShareCard extends StatelessWidget {
  const PaymentLinkQrShareCard({
    required this.artwork,
    required this.qrData,
    super.key,
  });

  static const size = Size(396, 270);
  static const _foreground = Color(0xFFFFFFFF);
  static const _secondary = Color(0xFFA3A4A4);
  static const brandBadgeAssetPath =
      'assets/icons/payment_link_share_badge.png';

  final PaymentLinkCardArtwork artwork;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Gift Card QR code',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: SizedBox.fromSize(
          key: const ValueKey('payment_link_qr_share_card'),
          size: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                artwork.assetPath,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                    stops: [0.03, 0.78],
                  ),
                ),
              ),
              Positioned(
                left: 25,
                top: 25,
                child: Text(
                  'You’ve\ngot ZEC',
                  style: AppTypography.headlineLarge.copyWith(
                    color: _foreground,
                  ),
                ),
              ),
              Positioned(
                left: 25,
                top: 107,
                child: Text(
                  'Scan to redeem',
                  style: AppTypography.bodyMedium.copyWith(color: _secondary),
                ),
              ),
              Positioned(
                right: 18,
                top: 66,
                child: Container(
                  key: const ValueKey('payment_link_qr_code'),
                  width: 184,
                  height: 184,
                  padding: const EdgeInsets.all(AppSpacing.s),
                  decoration: BoxDecoration(
                    color: _foreground,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xF2000000),
                        offset: Offset(0, 4),
                        blurRadius: 54,
                      ),
                    ],
                  ),
                  child: PrettyQrView.data(
                    data: qrData,
                    errorCorrectLevel: QrErrorCorrectLevel.L,
                    decoration: const PrettyQrDecoration(
                      quietZone: PrettyQrQuietZone.zero,
                      shape: PrettyQrSmoothSymbol(roundFactor: 0.5),
                    ),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: AppIcon(
                        AppIcons.warning,
                        color: Color(0xFF141818),
                        semanticLabel: 'QR code could not be generated',
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 20,
                bottom: 20,
                child: _PaymentLinkShareBrand(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLinkShareBrand extends StatelessWidget {
  const _PaymentLinkShareBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          PaymentLinkQrShareCard.brandBadgeAssetPath,
          key: const ValueKey('payment_link_share_brand_badge'),
          width: 26,
          height: 26,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 9),
        Text(
          'vizor.cash',
          style: AppTypography.labelMedium.copyWith(
            color: PaymentLinkQrShareCard._foreground,
            fontSize: 12.5,
            letterSpacing: -0.375,
          ),
        ),
      ],
    );
  }
}
