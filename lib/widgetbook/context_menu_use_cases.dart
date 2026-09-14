// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_context_menu.dart';
import '../src/core/widgets/app_icon.dart';
import 'support/wb_layout.dart';

Widget buildContextMenuGalleryUseCase(BuildContext context) {
  final colors = context.colors;

  return ColoredBox(
    color: colors.background.ground,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CONTEXT MENU',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.xl,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: const [
              _MenuSample(
                label: 'Contact actions',
                child: _ContactActionsMenu(),
              ),
              _MenuSample(
                label: 'Account actions',
                child: _AccountActionsMenu(),
              ),
              _MenuSample(label: 'Narrow width', child: _NarrowActionsMenu()),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget buildContextMenuContactUseCase(BuildContext context) {
  return _ContextMenuFrame(child: const _ContactActionsMenu());
}

Widget buildContextMenuAccountUseCase(BuildContext context) {
  return _ContextMenuFrame(child: const _AccountActionsMenu());
}

Widget buildContextMenuNarrowUseCase(BuildContext context) {
  return _ContextMenuFrame(child: const _NarrowActionsMenu());
}

class _ContextMenuFrame extends StatelessWidget {
  const _ContextMenuFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.ground,
      child: Center(child: child),
    );
  }
}

class _MenuSample extends StatelessWidget {
  const _MenuSample({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

class _ContactActionsMenu extends StatelessWidget {
  const _ContactActionsMenu();

  @override
  Widget build(BuildContext context) {
    return AppContextMenu(
      children: [
        AppContextMenuItem(
          iconName: AppIcons.scroll,
          label: 'Edit contact',
          onTap: _noop,
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.plane,
          label: 'Send ZEC',
          onTap: _noop,
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.copy,
          label: 'Copy address',
          onTap: _noop,
        ),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          iconName: AppIcons.trash,
          label: 'Remove contact',
          destructive: true,
          onTap: _noop,
        ),
      ],
    );
  }
}

class _AccountActionsMenu extends StatelessWidget {
  const _AccountActionsMenu();

  @override
  Widget build(BuildContext context) {
    return AppContextMenu(
      children: [
        AppContextMenuItem(
          iconName: AppIcons.edit,
          label: 'Edit name',
          onTap: _noop,
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.user,
          label: 'Change picture',
          onTap: _noop,
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.trash,
          label: 'Remove account',
          destructive: true,
          onTap: _noop,
        ),
      ],
    );
  }
}

class _NarrowActionsMenu extends StatelessWidget {
  const _NarrowActionsMenu();

  @override
  Widget build(BuildContext context) {
    return AppContextMenu(
      width: 128,
      children: [
        AppContextMenuItem(
          iconName: AppIcons.scroll,
          label: 'Edit contact',
          onTap: _noop,
        ),
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.copy,
          label: 'Copy long address',
          onTap: _noop,
        ),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          iconName: AppIcons.trash,
          label: 'Remove',
          destructive: true,
          onTap: _noop,
        ),
      ],
    );
  }
}

void _noop() {}

// --- Anchor positions -------------------------------------------------------

/// Where the menu is pinned inside the pane, which is what drives
/// [AppContextMenu]'s own edge self-correction.
enum ContextMenuAnchor {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  tallClamped,
}

/// Narrow width option, matching the narrow menu fixture above.
const double kContextMenuNarrowWidth = 128;

/// One menu pinned near a pane edge, so the flip / shift / clamp correction is
/// what the preview shows.
///
/// The menu measures itself against the ambient [Overlay], so the fixture
/// gives it a local one filling the pane — otherwise it would measure the
/// whole widgetbook canvas and never need to correct.
Widget contextMenuAnchorFixture(
  BuildContext context, {
  required ContextMenuAnchor anchor,
  required double width,
}) {
  return WbFrame(
    layout: WbLayout.desktop,
    child: ColoredBox(
      color: context.colors.background.ground,
      child: Overlay(
        // `initialEntries` is read once in `initState`, so a knob change needs
        // a new Overlay rather than a rebuild of the old one.
        key: ValueKey('$anchor|$width'),
        initialEntries: [
          OverlayEntry(
            builder: (context) => Stack(
              children: [_anchoredMenu(anchor: anchor, width: width)],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _anchoredMenu({
  required ContextMenuAnchor anchor,
  required double width,
}) {
  // Negative insets put the menu's natural rect past the pane edge, which is
  // the overflow a row near the edge produces at the real call sites.
  final menu = AppContextMenu(
    width: width,
    children: _anchorMenuItems(
      anchor == ContextMenuAnchor.tallClamped ? 14 : 3,
    ),
  );
  return switch (anchor) {
    ContextMenuAnchor.topLeft => Positioned(left: 24, top: 24, child: menu),
    ContextMenuAnchor.topRight => Positioned(right: -72, top: 24, child: menu),
    ContextMenuAnchor.bottomLeft => Positioned(
      left: 24,
      bottom: -48,
      child: menu,
    ),
    ContextMenuAnchor.bottomRight => Positioned(
      right: -72,
      bottom: -48,
      child: menu,
    ),
    // Taller than half the pane, so flipping up would overflow the top and the
    // menu clamps to the bottom edge instead.
    ContextMenuAnchor.tallClamped => Positioned(
      left: 24,
      bottom: -48,
      child: menu,
    ),
  };
}

List<Widget> _anchorMenuItems(int count) {
  return [
    for (var index = 0; index < count; index++) ...[
      if (index > 0) const SizedBox(height: AppSpacing.xxs),
      AppContextMenuItem(
        iconName: AppIcons.copy,
        label: 'Copy address',
        onTap: _noop,
      ),
    ],
  ];
}
