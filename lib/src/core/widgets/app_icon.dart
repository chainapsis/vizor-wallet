import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';

/// Name-based handles for every icon bundled under `assets/icons/`.
///
/// Keeping the asset paths behind typed constants means a rename /
/// re-export only touches this file; call sites reference
/// `AppIcons.book` instead of a string literal.
///
/// Names are the Figma Icons page node names, normalized to snake_case
/// and de-typoed (`cehvron-*` → `chevron_*`, `zcashh` → `zcash`). The
/// Figma side still has the typos; raise the rename there so the
/// two stay in sync.
abstract final class AppIcons {
  static const addNew = 'add_new';
  static const arrowDownward = 'arrow_downward';
  static const arrowForwardIos = 'arrow_forward_ios';
  static const arrowUpward = 'arrow_upward';
  static const block = 'block';
  static const book = 'book';
  static const chevronBackward = 'chevron_backward';
  static const chevronForward = 'chevron_forward';
  static const copy = 'copy';
  static const crystalBall = 'crystal_ball';
  static const eye = 'eye';
  static const help = 'help';
  static const importWallet = 'import_wallet';
  static const key = 'key';
  static const link = 'link';
  static const shieldKeyhole = 'shield_keyhole';
  static const skip = 'skip';
  static const time = 'time';
  static const wallet = 'wallet';
  static const warning = 'warning';
  static const zcash = 'zcash';
}

/// Renders a Figma-exported icon from `assets/icons/<name>.svg`.
///
/// Each SVG ships with a `viewBox="0 0 24 24"` — the exact dimensions
/// of the Figma icon frame — so the art's position inside the frame is
/// preserved when Flutter scales the SVG to any [size]. Colour is
/// swapped at paint time via `ColorFilter.mode(color, BlendMode.srcIn)`:
/// the SVG keeps its own alpha shape, every non-transparent pixel gets
/// re-colored to [color]. Works for the single-fill monochrome icons
/// the design system currently ships; multi-fill / gradient icons
/// would need a different render path.
///
/// Color resolution order, first non-null wins:
/// 1. Explicit [color] argument at the call site.
/// 2. `IconTheme.of(context).color` — ambient theme. This is what lets
///    a widget like [AppButton] merge its label color into an
///    `IconTheme` wrapper and have every `AppIcon` child pick it up
///    without the caller having to thread the color through.
/// 3. [AppColors.icon.regular] from the ambient [AppTheme] — default
///    "neutral icon" when no other context has spoken.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    this.size = AppIconSize.medium,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// Pass a constant from [AppIcons] — e.g. `AppIcons.book`.
  final String name;

  /// Rendered pixel size (width == height). Defaults to
  /// [AppIconSize.medium] (16); use [AppIconSize.large] (24) for the
  /// asset's native pixel-perfect size.
  final double size;

  /// Tint applied via `BlendMode.srcIn`. When null, falls back through
  /// ambient `IconTheme` and then [AppColors.icon.regular] — see the
  /// class doc for the full resolution order.
  final Color? color;

  /// Optional accessibility label forwarded to [SvgPicture.asset].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        context.colors.icon.regular;
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}
