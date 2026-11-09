import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import 'passcode_widgets.dart';

/// Keeps the original composition whenever it fits the available content area.
/// Short portrait and wide windows share the same compact fallback.
class AdaptivePasscodeLayout extends StatelessWidget {
  const AdaptivePasscodeLayout({
    required this.title,
    required this.subtitle,
    required this.prompt,
    required this.keypad,
    required this.legacy,
    this.legacyPadding = EdgeInsets.zero,
    this.legacySpacing = AppSpacing.s + AppSpacing.md * 2,
    this.subtitleMaxWidth = double.infinity,
    this.scaleLegacyKeypadToWidth = false,
    this.footer,
    this.footerHeight = 0,
    this.adapt = true,
    this.titleKey,
    this.legacyCentersPrompt = true,
    this.legacyKeypadGap = 0,
    super.key,
  });

  final String title;
  final Key? titleKey;
  final String subtitle;
  final PasscodePromptField prompt;
  final PasscodeNumpad keypad;
  final Widget legacy;

  /// Insets and fixed gaps inside [legacy], excluding text, dots and keypad.
  /// The parent has already removed its navigation bar and safe-area insets.
  final EdgeInsets legacyPadding;
  final double legacySpacing;
  final double subtitleMaxWidth;
  final bool scaleLegacyKeypadToWidth;
  final Widget? footer;
  final double footerHeight;
  final bool adapt;

  /// A centered heading shares surplus space above and below the prompt.
  /// Fixed stacks instead need their explicit floor gap to contain the error.
  final bool legacyCentersPrompt;
  final double legacyKeypadGap;

  double _textHeight(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: math.max(1, width));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    if (!adapt) {
      return legacy;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
          return legacy;
        }
        final width = math.max(
          1.0,
          constraints.maxWidth - legacyPadding.horizontal,
        );
        final legacyKeypadWidth = math.min(kPasscodeKeypadWidth, width);
        final columns =
            ((legacyKeypadWidth + AppSpacing.sm) /
                    (kPasscodeKeySize + AppSpacing.sm))
                .floor()
                .clamp(1, 3);
        final rows = (12 / columns).ceil();
        final keypadHeight = scaleLegacyKeypadToWidth
            ? kPasscodeKeypadHeight *
                  math.min(1.0, width / kPasscodeKeypadWidth)
            : rows * kPasscodeKeySize + (rows - 1) * AppSpacing.sm;
        final errorHeight = prompt.error == null
            ? 0.0
            : _textHeight(
                context,
                prompt.error!,
                AppTypography.labelLarge,
                width - AppSpacing.md * 2,
              );
        // The legacy error extends below the 81px dot box. Include that extent
        // when deciding whether its original composition is safe to retain.
        final errorOverhang = prompt.error == null
            ? 0.0
            : math.max(0.0, 36 + errorHeight - kPasscodePromptDigitsHeight / 2);
        final requiredHeight =
            legacyPadding.vertical +
            legacySpacing +
            footerHeight +
            _textHeight(context, title, AppTypography.displayLarge, width) +
            _textHeight(
              context,
              subtitle,
              AppTypography.bodyMediumStrong,
              math.min(width, subtitleMaxWidth),
            ) +
            kPasscodePromptDigitsHeight +
            (legacyCentersPrompt ? errorOverhang * 2 : 0) +
            keypadHeight;
        final errorFits =
            legacyCentersPrompt || errorOverhang <= legacyKeypadGap;
        if (requiredHeight <= constraints.maxHeight && errorFits) return legacy;

        const padding = EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.s,
        );
        final compactWidth = math.max(
          1.0,
          constraints.maxWidth - padding.horizontal,
        );
        final compactErrorHeight = _textHeight(
          context,
          prompt.error ?? '',
          AppTypography.labelLarge,
          compactWidth,
        );
        final promptHeight =
            kPasscodeDotSize * math.sqrt2 + AppSpacing.xs + compactErrorHeight;
        final headingHeight =
            _textHeight(
              context,
              title,
              AppTypography.displayLarge,
              compactWidth,
            ) +
            AppSpacing.s +
            _textHeight(
              context,
              subtitle,
              AppTypography.bodyMediumStrong,
              math.min(compactWidth, subtitleMaxWidth),
            ) +
            AppSpacing.s +
            promptHeight;
        final fixedHeight =
            padding.vertical +
            headingHeight +
            AppSpacing.s +
            (footer == null ? 0.0 : AppSpacing.s + footerHeight);
        var keySize = 64.0;
        for (final candidate in const [72.0, 68.0, 64.0]) {
          if (fixedHeight + candidate * 4 + AppSpacing.s * 3 <=
              constraints.maxHeight) {
            keySize = candidate;
            break;
          }
        }
        final colors = context.colors;
        return Padding(
          key: const ValueKey('compact_passcode'),
          padding: padding,
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              key: titleKey,
                              textAlign: TextAlign.center,
                              style: AppTypography.displayLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: subtitleMaxWidth,
                              ),
                              child: Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: colors.text.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            // Reserve the error line even while empty, keeping the dots
                            // stationary as errors appear. Long messages grow in flow.
                            SizedBox(
                              height: kPasscodeDotSize * math.sqrt2,
                              child: Center(
                                child: PasscodeDots(
                                  length: prompt.length,
                                  filled: prompt.filled,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              prompt.error ?? '',
                              textAlign: TextAlign.center,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.destructive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    SizedBox(
                      height: keySize * 4 + AppSpacing.s * 3,
                      child: PasscodeNumpad(
                        keySize: keySize,
                        spacing: AppSpacing.s,
                        onDigit: keypad.onDigit,
                        onBackspace: keypad.onBackspace,
                        canDelete: keypad.canDelete,
                        onHelp: keypad.onHelp,
                        enabled: keypad.enabled,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: AppSpacing.s),
                      footer!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
