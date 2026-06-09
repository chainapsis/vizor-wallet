import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

void main() {
  testWidgets('desktop shell owns the default window backing', (tester) async {
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AppDesktopShell(
            sidebar: SizedBox(width: 256),
            pane: AppDesktopPane(child: SizedBox.expand()),
          ),
        ),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor,
      AppThemeData.light.colors.background.window,
    );
  });

  testWidgets(
    'desktop shell background can be transparent for image-backed pages',
    (tester) async {
      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: AppDesktopShell(
              backgroundColor: Colors.transparent,
              sidebar: SizedBox(width: 256),
              pane: AppDesktopPane(child: SizedBox.expand()),
            ),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.transparent);
    },
  );

  testWidgets('glass sidebar surface uses macOS nav-panel tokens', (
    tester,
  ) async {
    await _pumpSidebarSurface(tester, AppThemeData.light);

    expect(
      _decoratedBoxColors(tester),
      contains(AppThemeData.light.colors.macosUtility.navPanel),
    );
    expect(
      _decoratedBoxColors(tester),
      isNot(contains(const Color(0xFFFFFFFF))),
    );

    await _pumpSidebarSurface(tester, AppThemeData.dark);

    expect(
      _decoratedBoxColors(tester),
      contains(AppThemeData.dark.colors.macosUtility.navPanel),
    );
    expect(
      _decoratedBoxColors(tester),
      isNot(contains(const Color(0xFF101010))),
    );
  });
}

Future<void> _pumpSidebarSurface(
  WidgetTester tester,
  AppThemeData theme,
) async {
  await tester.pumpWidget(
    AppTheme(
      data: theme,
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 256,
          height: 640,
          child: AppDesktopSidebarSurface(
            glass: true,
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

Iterable<Color?> _decoratedBoxColors(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((widget) => widget.decoration)
      .whereType<BoxDecoration>()
      .map((decoration) => decoration.color);
}
