import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';

/// A single design-token swatch card that mirrors the Figma spec layout.
///
/// Named [TokenSwatch] (not `ColorSwatch`) to avoid colliding with Flutter's
/// built-in `ColorSwatch<T>` in the painting library.
///
/// Shows the dark-mode color on the left half, the light-mode color on the
/// right half, with the hex value overlaid on each. Below the split swatch
/// is the token [name] and a one-line [description]. Reads its own chrome
/// (card background, border, label colors) from the ambient [AppTheme] so
/// toggling dark/light in Widgetbook updates the page without altering the
/// shown color values.
class TokenSwatch extends StatelessWidget {
  const TokenSwatch({
    super.key,
    required this.name,
    required this.description,
    required this.dark,
    required this.light,
  });

  final String name;
  final String description;
  final Color dark;
  final Color light;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 196,
      height: 124,
      decoration: BoxDecoration(
        color: colors.surface.card,
        border: Border.all(color: colors.border.subtle, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              children: [
                Expanded(child: _ColorHalf(color: dark, label: 'D')),
                Expanded(child: _ColorHalf(color: light, label: 'L')),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: colors.text.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.text.muted,
                      fontSize: 10,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorHalf extends StatelessWidget {
  const _ColorHalf({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textColor = _textColorFor(color);
    return Container(
      color: color,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Text(
              label,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.5),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                height: 1.0,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Text(
              _hex(color),
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _textColorFor(Color bg) {
    return bg.computeLuminance() > 0.5
        ? const Color(0xFF151818)
        : const Color(0xFFE1E1E1);
  }

  static String _hex(Color c) {
    final argb = c.toARGB32();
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// Full-viewport page that hosts a grid of [ColorSwatch] cards plus an
/// optional section title. Uses `background.ground` as the page background
/// so the page itself responds to the ambient theme mode.
class ColorCategoryPage extends StatelessWidget {
  const ColorCategoryPage({
    super.key,
    required this.title,
    required this.swatches,
  });

  final String title;
  final List<Widget> swatches;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.ground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: colors.text.secondary,
                fontSize: 11,
                letterSpacing: 0.88,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 0.5,
              color: colors.border.subtle,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: swatches,
            ),
          ],
        ),
      ),
    );
  }
}
