import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Shows a mobile modal as a floating card — the Figma modal base
/// (`_Modal Type`, e.g. 4600:50437). It still rises from the bottom, but
/// the designer reworked the base so the card is inset from the screen
/// sides, lifted off the bottom, and rounded on all four corners:
///
/// - 16px side margins ([AppSpacing.sm]) — card x=16, width=361 on the
///   393-wide artboard.
/// - 32px bottom gap ([AppSpacing.base]) — bottom-anchored cards end at
///   y=820 on the 852-tall artboard. On iOS the home indicator is a
///   ~13pt overlay, so the fixed gap already clears it and the safe-area
///   inset is not stacked on top (matching the project's
///   `MobileBottomSafeArea` rule). On Android the navigation bar takes
///   real, device-dependent space, so its inset is added on top of the
///   visual gap.
/// - All-corner radius of [AppRadii.xLarge] (radii/L = 32) on a
///   `background.ground` surface with the Figma shadow overlay.
/// - When the software keyboard is open the card floats 16px above it
///   (Figma `Review Add Memo`, 4638:74505), so text-entry modals like the
///   send memo no longer need a separate top-pinned presentation.
///
/// This is the mobile counterpart of the desktop pane modal overlay —
/// account switching, pickers, and confirmations present as sheets on
/// mobile. Content widgets supply only their own internal padding; the
/// outer margins, bottom safe area, keyboard avoidance, and card surface
/// all live here.
Future<T?> showAppMobileSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool transparentBackground = false,
}) {
  final colors = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    isScrollControlled: true,
    useSafeArea: true,
    // Root navigator so the sheet and its scrim cover the floating tab
    // bar (the shell's bottomNavigationBar sits outside the branch
    // navigators) — the Figma modals always overlay the nav.
    useRootNavigator: true,
    // The card draws its own surface, radius and shadow, so the sheet
    // itself is transparent with no default elevation shadow or shape.
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    barrierColor: colors.background.neutralScrim,
    builder: (sheetContext) => _MobileSheetFrame(
      transparentBackground: transparentBackground,
      child: builder(sheetContext),
    ),
  );
}

/// The floating-card frame applied to every [showAppMobileSheet] body:
/// side margins, the keyboard/safe-area-aware bottom gap, and (unless
/// [transparentBackground]) the rounded ground surface with the modal
/// shadow.
class _MobileSheetFrame extends StatelessWidget {
  const _MobileSheetFrame({
    required this.child,
    required this.transparentBackground,
  });

  final Widget child;

  /// For content that is already its own card (e.g. the birthday calendar
  /// panel): only the outer margins are applied, not the ground surface.
  final bool transparentBackground;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;

    final double bottomGap;
    if (keyboardInset > 0) {
      // Figma `Review Add Memo` (4638:74505): 16px between the card and
      // the software keyboard.
      bottomGap = keyboardInset + AppSpacing.sm;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The home indicator floats inside the 32px gap; do not stack the
      // safe-area inset on top of it.
      bottomGap = AppSpacing.base;
    } else {
      // Android nav bars vary per device and occupy real space — keep the
      // 32px visual gap above whatever inset the device reports.
      bottomGap = AppSpacing.base + mediaQuery.viewPadding.bottom;
    }

    final Widget card = transparentBackground
        ? child
        : DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.xLarge)),
              boxShadow: _modalShadow,
            ),
            child: Material(
              color: colors.background.ground,
              clipBehavior: Clip.antiAlias,
              // The 1px highlight approximates the Figma inner-shadow rim
              // (#FFFFFF26) that separates the card from the dark scrim.
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadii.xLarge),
                ),
                side: BorderSide(color: _modalRimHighlight),
              ),
              child: child,
            ),
          );

    // The card carries the Figma 16px side margins. Transparent content
    // is already its own card and owns its horizontal sizing, so only the
    // bottom gap applies there.
    final double sideMargin = transparentBackground ? 0 : AppSpacing.sm;
    return Padding(
      padding: EdgeInsets.only(
        left: sideMargin,
        right: sideMargin,
        bottom: bottomGap,
      ),
      child: card,
    );
  }
}

/// Figma `Shadow Overlay` inner highlight (#FFFFFF26) — a faint rim that
/// separates the card from the dark scrim.
const Color _modalRimHighlight = Color(0x26FFFFFF);

/// Figma `Shadow Overlay` — a soft, mostly-downward elevation behind the
/// modal card. The black layers are subtle over the dark scrim; the card
/// surface and the rim highlight do most of the visual separation.
const List<BoxShadow> _modalShadow = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
  BoxShadow(color: Color(0x0A000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
];
