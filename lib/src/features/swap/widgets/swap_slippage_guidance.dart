import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

const _refundGuidance = 'Price changes may cause a refund.';

/// Keeps the explanation and warning in the same measured space.
class SwapSlippageGuidance extends StatelessWidget {
  const SwapSlippageGuidance({
    required this.lowSlippage,
    required this.paymentMode,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final bool lowSlippage;
  final bool paymentMode;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final explanation = paymentMode
        ? 'Extra ZEC allowed for price movement.'
        : "Maximum price movement you'll accept.";
    final message = lowSlippage ? _refundGuidance : explanation;
    final style = AppTypography.bodySmall.copyWith(
      color: context.colors.text.secondary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const iconSize = AppIconSize.medium;
        const iconSpacing = AppSpacing.xs;
        final warningWidth = constraints.maxWidth - iconSize - iconSpacing;

        double heightOf(String text, double maxWidth) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textAlign: textAlign,
            textWidthBasis: TextWidthBasis.longestLine,
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout(maxWidth: maxWidth);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final explanationHeight = heightOf(explanation, constraints.maxWidth);
        final refundHeight = heightOf(_refundGuidance, warningWidth);
        final lineHeight = heightOf('0', warningWidth);
        final warningHeight = refundHeight > iconSize ? refundHeight : iconSize;
        final text = Text(
          message,
          key: ValueKey(
            lowSlippage
                ? 'swap_slippage_low_warning'
                : 'swap_slippage_description',
          ),
          textAlign: textAlign,
          textWidthBasis: TextWidthBasis.longestLine,
          style: style,
        );
        return Semantics(
          container: true,
          liveRegion: true,
          label: message,
          child: ExcludeSemantics(
            child: SizedBox(
              height: explanationHeight > warningHeight
                  ? explanationHeight
                  : warningHeight,
              width: double.infinity,
              child: lowSlippage
                  ? Align(
                      alignment: textAlign == TextAlign.center
                          ? Alignment.topCenter
                          : AlignmentDirectional.topStart,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: lineHeight,
                            child: Center(
                              child: AppIcon(
                                AppIcons.warning,
                                size: iconSize,
                                color: context.colors.icon.warningStrong,
                              ),
                            ),
                          ),
                          const SizedBox(width: iconSpacing),
                          Flexible(child: text),
                        ],
                      ),
                    )
                  : text,
            ),
          ),
        );
      },
    );
  }
}
