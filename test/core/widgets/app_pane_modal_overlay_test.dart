import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';

void main() {
  testWidgets('matches the pane scrim shape without backdrop blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Text('Pane'),
                AppPaneModalOverlay(
                  onDismiss: () {},
                  child: const SizedBox(width: 80, height: 80),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ClipRRect &&
            widget.borderRadius == AppPaneModalOverlay.defaultBorderRadius,
      ),
      findsOneWidget,
    );
  });

  testWidgets('desktop pane clips to the same radius as the modal scrim', (
    tester,
  ) async {
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 320,
            height: 240,
            child: AppDesktopPane(child: Text('Pane')),
          ),
        ),
      ),
    );

    final paneContainer = tester.widget<Container>(
      find.byType(Container).first,
    );
    final decoration = paneContainer.decoration as BoxDecoration;
    expect(
      decoration.borderRadius,
      BorderRadius.circular(AppWindowSizing.paneRadius),
    );
    expect(paneContainer.clipBehavior, Clip.antiAlias);
  });

  testWidgets('scopes modal overlay to parent stack', (tester) async {
    var sidebarTaps = 0;
    var childTaps = 0;
    var dismisses = 0;

    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 360,
            height: 240,
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => sidebarTaps++,
                  child: const SizedBox(width: 100, child: Text('Sidebar')),
                ),
                SizedBox(
                  width: 260,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Text('Pane'),
                      AppPaneModalOverlay(
                        onDismiss: () => dismisses++,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => childTaps++,
                          child: const SizedBox(
                            width: 80,
                            height: 80,
                            child: Text('Modal'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Sidebar'));
    expect(sidebarTaps, 1);
    expect(dismisses, 0);

    await tester.tap(find.text('Modal'));
    expect(childTaps, 1);
    expect(dismisses, 0);

    await tester.tapAt(const Offset(340, 20));
    expect(dismisses, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(dismisses, 2);
  });
}
