import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' show Material, showModalBottomSheet;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';

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
///   `background.base` surface with the Figma shadow overlay.
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
  final appTheme = context.appTheme;
  final colors = context.colors;
  ProviderContainer? providerContainer;
  try {
    providerContainer = ProviderScope.containerOf(context, listen: false);
  } on StateError {
    providerContainer = null;
  }

  Widget wrapSheet(Widget child) {
    final themed = AppTheme(data: appTheme, child: child);
    final container = providerContainer;
    if (container == null) return themed;
    return UncontrolledProviderScope(container: container, child: themed);
  }

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
    builder: (sheetContext) => wrapSheet(
      Builder(
        builder: (themedContext) => MobileModalCard(
          transparentBackground: transparentBackground,
          child: builder(themedContext),
        ),
      ),
    ),
  );
}

/// The floating-card frame for mobile modals: side margins, the
/// keyboard/safe-area-aware bottom gap, and (unless [transparentBackground])
/// the rounded base surface with the modal shadow.
///
/// [showAppMobileSheet] wraps every sheet body in this. It is also reused
/// by the swap modal route (a custom multi-surface dialog), which
/// bottom-anchors it inside its own page — so the swap modals share the
/// exact base chrome. When used outside a bottom sheet, place it at the
/// bottom of a full-height column with `crossAxisAlignment.stretch` so it
/// fills the width and hugs its content height.
class MobileModalCard extends StatelessWidget {
  const MobileModalCard({
    required this.child,
    this.transparentBackground = false,
    super.key,
  });

  final Widget child;

  /// For content that is already its own card (e.g. the birthday calendar
  /// panel): only the outer margins are applied, not the base surface.
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
              color: colors.background.base,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadii.xLarge),
                ),
              ),
              child: CustomPaint(
                foregroundPainter: const _ModalInnerHighlightPainter(),
                child: child,
              ),
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

/// Figma `Shadow Overlay` inner shadow (#FFFFFF26, blur radius 2) — a
/// soft rim that separates the card from the scrim without a hard stroke.
class _ModalInnerHighlightPainter extends CustomPainter {
  const _ModalInnerHighlightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadii.xLarge),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x26FFFFFF)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.inner, 2);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_ModalInnerHighlightPainter oldDelegate) => false;
}

/// Figma `Shadow Overlay` — a soft, mostly-downward elevation behind the
/// modal card. The black layers are subtle over the dark scrim; the card
/// surface and the rim highlight do most of the visual separation.
const List<BoxShadow> _modalShadow = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
  BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
  BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
];

/// The shared `_Modal Type` content layout (Figma 4697:102962) for sheets
/// shown inside a [MobileModalCard]: the common header (title top-left, a
/// 32×32 circular close pinned top-right) plus the standard content padding,
/// so every mobile modal lines its title, close button and body up the same
/// way.
///
/// - Padding: top 32 ([AppSpacing.base]) / bottom 24 ([AppSpacing.md]) /
///   horizontal 16 ([AppSpacing.sm]); a 16px gap between the title line and
///   the body. The body ([child]) owns its own internal spacing.
/// - Title: Body L SemiBold in `text.accent`, kept clear of the close button.
///   Title-less sheets set [showTitle] to false and keep the same outer
///   padding + pinned close button without reserving the title row.
/// - Close: absolutely pinned to the top-right (right 16, top 15.5) so it sits
///   above the title line, exactly as the Figma component does — not vertically
///   centered in the title row.
class MobileModalScaffold extends StatelessWidget {
  const MobileModalScaffold({
    required this.title,
    required this.onClose,
    required this.child,
    this.leading,
    this.titleStyle,
    this.titleMaxLines = 1,
    this.showTitle = true,
    this.showClose = true,
    this.bodyGap = AppSpacing.sm,
    this.bottomPadding = AppSpacing.md,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final Widget? leading;
  final TextStyle? titleStyle;
  final int titleMaxLines;
  final bool showTitle;
  final bool showClose;

  /// Gap between the title and the body. Defaults to 16; the asset picker
  /// (whose body is a fixed-height scrolling list filling to the card edge)
  /// passes 8 to match its `_Modal Type` variant. Ignored when [showTitle] is
  /// false.
  final double bodyGap;

  /// Bottom inset below the body. Defaults to 24; the asset picker passes 0 so
  /// its list fills to the card edge.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: AppSpacing.base,
            bottom: bottomPadding,
            left: AppSpacing.sm,
            right: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTitle) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 26),
                  child: Padding(
                    // Clear the absolute 32px close (+ an 8px gap) so long
                    // titles wrap/ellipsize instead of sliding under it.
                    padding: const EdgeInsets.only(right: 40),
                    child: Row(
                      children: [
                        if (leading != null) ...[
                          leading!,
                          const SizedBox(width: AppSpacing.s),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            maxLines: titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style:
                                titleStyle ??
                                AppTypography.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.text.accent,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: bodyGap),
              ],
              child,
            ],
          ),
        ),
        if (showClose)
          Positioned(
            top: 15.5,
            right: AppSpacing.sm,
            child: _ModalCloseButton(onTap: onClose),
          ),
      ],
    );
  }
}

/// The pinned modal close — a 32×32 secondary-surface circle that picks up the
/// desktop hover tint (`button.secondary.bgHover`) on pointer devices. Mobile
/// is touch-only, but the form factor previews on desktop / Widgetbook, so the
/// hover state matches the desktop modals.
class _ModalCloseButton extends StatefulWidget {
  const _ModalCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ModalCloseButton> createState() => _ModalCloseButtonState();
}

class _ModalCloseButtonState extends State<_ModalCloseButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final secondary = colors.button.secondary;
    // Fill priority pressed > hover > default — mirrors AppButton, so a tap
    // (touch) shows the pressed tint even with no pointer hover.
    final fill = _pressed
        ? secondary.bgPressed
        : _hovered
        ? secondary.bgHover
        : secondary.bg;
    return Semantics(
      label: AppLocalizations.of(context).commonClose,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
            child: Center(
              child: AppIcon(
                AppIcons.cross,
                size: 20,
                color: colors.icon.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
