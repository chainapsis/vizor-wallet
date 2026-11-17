@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_scroll_edge_fades.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

const _surface = Color(0xFF123456);
const _top = ValueKey('mobile_scroll_edge_fade_top');
const _bottom = ValueKey('mobile_scroll_edge_fade_bottom');

Widget _harness(Widget child, {double height = 300}) => MaterialApp(
  localizationsDelegates: appLocalizationsDelegates,
  home: AppTheme(
    data: AppThemeData.dark,
    child: Center(
      child: SizedBox(width: 360, height: height, child: child),
    ),
  ),
);

Widget _rows(int count) => ListView(
  children: [for (var i = 0; i < count; i++) const SizedBox(height: 50)],
);

double _alpha(WidgetTester tester, Key key) {
  final box = tester.widget<DecoratedBox>(find.byKey(key));
  final gradient = (box.decoration as BoxDecoration).gradient!;
  return gradient.colors.first.a;
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('a list that fits shows no fades', (tester) async {
    await tester.pumpWidget(
      _harness(MobileScrollEdgeFades(color: _surface, child: _rows(3))),
    );
    await tester.pump();

    expect(find.byKey(_top), findsNothing);
    expect(find.byKey(_bottom), findsNothing);
  });

  testWidgets('an overflowing list fades at the edges where it cuts content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(MobileScrollEdgeFades(color: _surface, child: _rows(20))),
    );
    await tester.pump();

    // At rest only the bottom is cut.
    expect(find.byKey(_top), findsNothing);
    expect(_alpha(tester, _bottom), 1);

    _position(tester).jumpTo(200);
    await tester.pump();
    expect(_alpha(tester, _top), 1);
    expect(_alpha(tester, _bottom), 1);

    final position = _position(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(_alpha(tester, _top), 1);
    expect(find.byKey(_bottom), findsNothing);
  });

  testWidgets('off holds even below a re-wrapped scroll behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MobileScrollEdgeFades(
          color: _surface,
          child: Builder(
            builder: (context) => MobileScrollEdgeFades.off(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: _rows(20),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_bottom), findsNothing);
  });

  testWidgets('text fields keep their own scrolling unfaded', (tester) async {
    await tester.pumpWidget(
      _harness(
        MobileScrollEdgeFades(
          color: _surface,
          child: Material(
            child: TextField(
              controller: TextEditingController(
                text: List.filled(40, 'long line').join('\n'),
              ),
              maxLines: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(_top), findsNothing);
    expect(find.byKey(_bottom), findsNothing);
  });

  testWidgets('a sheet body taller than the room scrolls instead of '
      'overflowing, and fades into the sheet', (tester) async {
    await tester.pumpWidget(
      _harness(
        MobileModalCard(
          child: MobileModalScaffold(
            title: 'Add contact',
            onClose: () {},
            child: Column(
              children: [
                for (var i = 0; i < 12; i++) const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('mobile_modal_body_scroll')),
      findsOneWidget,
    );
    expect(_alpha(tester, _bottom), 1);
    final fade = tester.widget<DecoratedBox>(find.byKey(_bottom));
    final gradient = (fade.decoration as BoxDecoration).gradient!;
    expect(
      gradient.colors.first.withValues(alpha: 1),
      AppThemeData.dark.colors.background.base.withValues(alpha: 1),
    );
  });
}
