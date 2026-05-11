import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'app_loading_icon.dart';

/// Name-based handles for every design-system icon.
///
/// Keeping the asset paths behind typed constants means a rename /
/// re-export only touches this file; call sites reference
/// `AppIcons.book` instead of a string literal.
///
/// Names mostly follow the curated export set under `assets/icons/`: Figma
/// Icons page node names normalized to snake_case, with a few
/// compatibility-preserving aliases where older app code already shipped
/// stable names (`import_wallet`, `shield_keyhole`, `arrow_upward`, etc.).
/// [loader] is code-drawn rather than loaded from SVG.
abstract final class AppIcons {
  static const addNew = 'add_new';
  static const arrowBack = 'arrow_back';
  static const arrowBottomLeft = 'arrow_bottom_left';
  static const arrowDown = 'arrow_down';
  static const arrowDownCircle = 'arrow_down_circle';
  static const arrowDownward = 'arrow_downward';
  static const arrowForwardIos = 'arrow_forward_ios';
  static const arrowTopRight = 'arrow_top_right';
  static const arrowUpward = 'arrow_upward';
  static const block = 'block';
  static const book = 'book';
  static const calendar = 'calendar';
  static const check = 'check';
  static const checkCircle = 'check_circle';
  static const chevronBackward = 'chevron_backward';
  static const chevronForward = 'chevron_forward';
  static const collapsed = 'collapsed';
  static const cog = 'cog';
  static const copy = 'copy';
  static const cross = 'cross';
  static const crystalBall = 'crystal_ball';
  static const day = 'day';
  static const dragon = 'dragon';
  static const endpoint = 'endpoint';
  static const eye = 'eye';
  static const eyeClosed = 'eye_closed';
  static const expand = 'expand';
  static const help = 'help';
  static const history = 'history';
  static const importWallet = 'import_wallet';
  static const key = 'key';
  static const link = 'link';
  static const loader = 'loader';
  static const lock = 'lock';
  static const logOut = 'log_out';
  static const monitor = 'monitor';
  static const night = 'night';
  static const plane = 'plane';
  static const qr = 'qr';
  static const qrCodeFill = 'qr_code_fill';
  static const renew = 'renew';
  static const scroll = 'scroll';
  static const shieldAsset = 'shield_asset';
  static const shieldKeyhole = 'shield_keyhole';
  static const shieldKeyholeOutline = 'shield_keyhole_outline';
  static const skip = 'skip';
  static const skull = 'skull';
  static const sync = 'sync';
  static const theme = 'theme';
  static const time = 'time';
  static const transparentBalance = 'transparent_balance';
  static const unlock = 'unlock';
  static const users = 'users';
  static const vizor = 'vizor';
  static const wallet = 'wallet';
  static const warning = 'warning';
  static const zcash = 'zcash';
  static const zcashCurrency = 'zcash_currency';
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
/// would need a different render path. [AppIcons.loader] is code-drawn so it
/// can animate while keeping the same public [AppIcon] call pattern.
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
    this.animated = true,
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

  /// Controls the pulse animation for [AppIcons.loader]. Ignored by SVG icons.
  final bool animated;

  /// Optional accessibility label forwarded to [SvgPicture.asset].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ?? IconTheme.of(context).color ?? context.colors.icon.regular;
    if (name == AppIcons.loader) {
      return AppLoadingIcon(
        size: size,
        color: resolved,
        animated: animated,
        semanticLabel: semanticLabel,
      );
    }
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
    );
  }
}
