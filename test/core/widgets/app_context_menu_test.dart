import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_context_menu.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

void main() {
  testWidgets('AppContextMenu uses semantic menu surface tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.light,
        child: AppContextMenu(
          children: [
            AppContextMenuItem(
              iconName: AppIcons.trash,
              label: 'Remove contact',
              destructive: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final decoration = _menuDecoration(tester);
    final border = decoration.border as Border?;

    expect(decoration.color, AppThemeData.light.colors.background.inverse);
    expect(border?.top.color, AppThemeData.light.colors.border.subtleOpacity);
    expect(decoration.boxShadow, appContextMenuShadow);

    final text = tester.widget<Text>(find.text('Remove contact'));
    expect(text.style?.color, AppThemeData.light.colors.text.destructiveLight);
    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.color, AppThemeData.light.colors.icon.destructiveLight);
  });

  testWidgets('AppContextMenuDivider uses the inverse opacity border token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.dark,
        child: const AppContextMenu(children: [AppContextMenuDivider()]),
      ),
    );

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(AppContextMenuDivider),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, AppThemeData.dark.colors.border.inverseOpacity);
  });

  testWidgets('AppContextMenuItem applies the inverse-surface hover token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.dark,
        child: AppContextMenu(
          children: [
            AppContextMenuItem(
              iconName: AppIcons.scroll,
              label: 'Edit contact',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Edit contact')));
    await tester.pumpAndSettle();

    final decoration = _itemDecoration(tester);
    expect(decoration.color, AppThemeData.dark.colors.state.hoverOpacity);

    await gesture.removePointer();
  });

  testWidgets('AppContextMenuItem can be removed while hovered', (
    tester,
  ) async {
    var showMenu = true;

    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.dark,
        child: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 420,
              height: 220,
              child: Stack(
                children: [
                  if (showMenu)
                    AppContextMenu(
                      children: [
                        AppContextMenuItem(
                          iconName: AppIcons.scroll,
                          label: 'Edit contact',
                          onTap: () {},
                        ),
                      ],
                    ),
                  Positioned(
                    left: 240,
                    top: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => showMenu = false),
                      child: const SizedBox(
                        width: 120,
                        height: 40,
                        child: Text('Hide menu'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Edit contact')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit contact'), findsNothing);

    await gesture.removePointer();
  });

  testWidgets(
    'AppContextMenu opens downward (no flip) when there is room below',
    (tester) async {
      const anchorTop = 40.0;
      const followerDrop = 22.0;
      const screenSize = Size(420, 600);
      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const _MenuPositionHarness(
          screenSize: screenSize,
          anchorTop: anchorTop,
          followerDrop: followerDrop,
        ),
      );
      await tester.pumpAndSettle();

      // With ~500px of room below the anchor, the menu must not move at all:
      // the painted surface stays exactly at the follower-anchored position
      // (byte-identical to the no-flip path).
      final surface = _surfaceRect(tester);
      expect(surface.top, moreOrLessEquals(anchorTop + followerDrop));
      expect(surface.bottom, greaterThan(surface.top));
    },
  );

  testWidgets(
    'AppContextMenu flips upward when the downward placement overflows bottom',
    (tester) async {
      const screenSize = Size(420, 600);
      // Anchor near the very bottom: a downward menu would overflow the screen.
      const anchorTop = 560.0;
      const followerDrop = 22.0;
      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const _MenuPositionHarness(
          screenSize: screenSize,
          anchorTop: anchorTop,
          followerDrop: followerDrop,
        ),
      );
      await tester.pumpAndSettle();

      final surface = _surfaceRect(tester);

      // Flipped: the menu now sits ABOVE the follower-anchored downward top.
      final downwardTop = anchorTop + followerDrop;
      expect(
        surface.top,
        lessThan(downwardTop),
        reason: 'menu should flip above the anchor, not open downward',
      );

      // Contained: the flipped menu stays within the screen bounds.
      expect(surface.bottom, lessThanOrEqualTo(screenSize.height));
      expect(surface.top, greaterThanOrEqualTo(0));
    },
  );

  testWidgets('AppContextMenu shifts left when it overflows the right edge', (
    tester,
  ) async {
    const screenSize = Size(300, 600);
    // Anchor the menu's left edge near the right edge so its 160px width spills.
    const anchorTop = 40.0;
    const followerDrop = 22.0;
    const anchorLeft = 260.0;
    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const _MenuPositionHarness(
        screenSize: screenSize,
        anchorTop: anchorTop,
        followerDrop: followerDrop,
        anchorLeft: anchorLeft,
      ),
    );
    await tester.pumpAndSettle();

    final surface = _surfaceRect(tester);
    expect(
      surface.right,
      lessThanOrEqualTo(screenSize.width),
      reason: 'menu should shift left to stay within the right edge',
    );
    expect(surface.left, greaterThanOrEqualTo(0));
  });
}

/// The painted menu surface rectangle in global coordinates. This is the
/// outer [DecoratedBox] inside [AppContextMenu] — a child of the auto-flip
/// transform, so its rect reflects any applied flip/shift correction (which is
/// exactly the region that would clip if containment failed).
Rect _surfaceRect(WidgetTester tester) {
  return tester.getRect(
    find
        .descendant(
          of: find.byType(AppContextMenu),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
}

BoxDecoration _menuDecoration(WidgetTester tester) {
  return tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(AppContextMenu),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration
      as BoxDecoration;
}

BoxDecoration _itemDecoration(WidgetTester tester) {
  return tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(AppContextMenuItem),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration!
      as BoxDecoration;
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.theme, required this.child});

  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppTheme(
      data: theme,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );
  }
}

/// Reproduces the production anchoring path: an [Overlay] sized to [screenSize]
/// with a [CompositedTransformFollower] dropping the menu [followerDrop] px
/// below a zero-size trigger at ([anchorLeft], [anchorTop]). This is exactly
/// how `_ContactRowMenuButton` / `_AccountRowMenuButton` position the menu, so
/// the auto-flip logic is exercised against the real geometry.
class _MenuPositionHarness extends StatelessWidget {
  const _MenuPositionHarness({
    required this.screenSize,
    required this.anchorTop,
    required this.followerDrop,
    this.anchorLeft = 40,
  });

  final Size screenSize;
  final double anchorTop;
  final double anchorLeft;
  final double followerDrop;

  @override
  Widget build(BuildContext context) {
    final link = LayerLink();
    return AppTheme(
      data: AppThemeData.light,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: screenSize),
          child: SizedBox.fromSize(
            size: screenSize,
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (_) {
                    return Stack(
                      children: [
                        Positioned(
                          left: anchorLeft,
                          top: anchorTop,
                          child: CompositedTransformTarget(
                            link: link,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                        CompositedTransformFollower(
                          link: link,
                          showWhenUnlinked: false,
                          targetAnchor: Alignment.topLeft,
                          followerAnchor: Alignment.topLeft,
                          offset: Offset(0, followerDrop),
                          child: AppTheme(
                            data: AppThemeData.light,
                            child: AppContextMenu(
                              children: [
                                AppContextMenuItem(
                                  iconName: AppIcons.copy,
                                  label: 'Copy address',
                                  onTap: () {},
                                ),
                                AppContextMenuItem(
                                  iconName: AppIcons.scroll,
                                  label: 'Edit contact',
                                  onTap: () {},
                                ),
                                const AppContextMenuDivider(),
                                AppContextMenuItem(
                                  iconName: AppIcons.trash,
                                  label: 'Remove contact',
                                  destructive: true,
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
