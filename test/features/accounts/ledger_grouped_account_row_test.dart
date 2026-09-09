import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/ledger_grouped_account_row.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
    await fonts.load();
  });

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      for (final theme in [AppThemeData.light, AppThemeData.dark]) {
        testWidgets(
          'grouped selection fits a 320px phone at $direction, $scale, $theme',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(320, 852));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            var selected = true;
            var accountTaps = 0;
            var menuTaps = 0;
            late StateSetter update;

            await tester.pumpWidget(
              MaterialApp(
                home: AppTheme(
                  data: theme,
                  child: Directionality(
                    textDirection: direction,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          update = setState;
                          return Scaffold(
                            body: Padding(
                              // Accounts screen and family card each inset 16px.
                              padding: const EdgeInsets.all(AppSpacing.base),
                              child: Column(
                                children: [
                                  LedgerGroupedAccountRow(
                                    accountUuid: 'ledger',
                                    name:
                                        'My long-term savings and travel account',
                                    accountIndex: 2147483647,
                                    isCurrent: selected,
                                    leading: const SizedBox.square(
                                      dimension: 32,
                                    ),
                                    onTap: () => accountTaps++,
                                    options: GestureDetector(
                                      key: const ValueKey('options'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => menuTaps++,
                                      child: const SizedBox.square(
                                        dimension: 44,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            final name = find.text('My long-term savings and travel account');
            final index = find.text('Account 2147483647');
            final indicator = find.byKey(
              const ValueKey('ledger_grouped_account_current_ledger'),
            );
            final options = find.byKey(const ValueKey('options'));
            final selection = find.byKey(
              const ValueKey('ledger_grouped_account_selection_ledger'),
            );
            final background = find.byKey(
              const ValueKey('ledger_grouped_account_background_ledger'),
            );
            expect(
              tester.widget<Semantics>(selection).properties.selected,
              isTrue,
            );
            expect(tester.widget<Text>(indicator).data, '· Current');
            expect(find.byType(AppIcon), findsNothing);
            expect(
              tester.getRect(index).top,
              greaterThan(tester.getRect(name).bottom),
            );
            expect(
              tester.getRect(indicator).overlaps(tester.getRect(options)),
              isFalse,
            );
            final selectedDecoration =
                tester.widget<Container>(background).decoration!
                    as BoxDecoration;
            final colors = theme.colors;
            expect(selectedDecoration.color, isNull);
            expect(selectedDecoration.border, isNull);
            expect(tester.widget<Text>(name).style?.color, colors.text.accent);
            final menuRect = tester.getRect(options);
            final nameRect = tester.getRect(name);
            final rowSize = tester.getSize(background);

            await tester.tap(options);
            expect(menuTaps, 1);
            expect(accountTaps, 0);
            await tester.tap(name);
            expect(accountTaps, 1);
            update(() => selected = false);
            await tester.pump();
            expect(
              tester.widget<Semantics>(selection).properties.selected,
              isFalse,
            );
            expect(indicator, findsNothing);
            expect(tester.getRect(options), menuRect);
            expect(tester.getRect(name), nameRect);
            expect(tester.getSize(background), rowSize);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
