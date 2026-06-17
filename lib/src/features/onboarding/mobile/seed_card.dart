import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Dark numbered mnemonic card — Figma `Seed Card` (instance
/// 4575:108110): 3-column word grid with two-digit gray indices, used
/// by the create-flow passphrase step and the import review step.
class SeedCard extends StatelessWidget {
  const SeedCard({
    required this.words,
    this.obscured = false,
    this.onCopy,
    this.copied = false,
    this.showTitle = true,
    this.rowGap = AppSpacing.s,
    super.key,
  });

  final List<String> words;

  /// Vertical gap between word rows. The import review frame uses the
  /// 37 px pitch (12 + the 25 px line); the create-flow passphrase
  /// frame spreads the same grid to a 44 px pitch (19 + 25).
  final double rowGap;

  /// Blurs the words until the user explicitly reveals them.
  final bool obscured;

  /// Shows the Copy action in the card header when non-null.
  final VoidCallback? onCopy;
  final bool copied;

  /// The import review frame shows the bare word grid without the
  /// "Secret Passphrase" header row.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final grid = _WordGrid(words: words, rowGap: rowGap);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle || onCopy != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    showTitle ? 'Secret Passphrase' : '',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.homeCard,
                    ),
                  ),
                ),
                if (onCopy != null)
                  Semantics(
                    button: true,
                    label: 'Copy secret passphrase',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onCopy,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            copied ? 'Copied' : 'Copy',
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.text.homeCard,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          AppIcon(
                            AppIcons.copy,
                            size: AppIconSize.medium,
                            color: colors.text.homeCard,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (obscured)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: grid,
            )
          else
            grid,
        ],
      ),
    );
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words, required this.rowGap});

  final List<String> words;
  final double rowGap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = (words.length / 3).ceil();
    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) SizedBox(height: rowGap),
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: row * 3 + col < words.length
                      ? Row(
                          children: [
                            Text(
                              (row * 3 + col + 1).toString().padLeft(2, '0'),
                              style: AppTypography.codeSmall.copyWith(
                                color: colors.text.homeCard.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                            Expanded(
                              child: Text(
                                words[row * 3 + col],
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.homeCard,
                                ),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
