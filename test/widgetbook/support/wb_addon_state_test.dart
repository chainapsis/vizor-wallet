import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/support/wb_compare_layouts.dart';
import 'package:zcash_wallet/widgetbook/support/wb_design_status.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

void main() {
  for (final withLayout in [true, false]) {
    testWidgets(
      'addon toggles preserve the primary session, layout=$withLayout',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final mounts = <String, int>{};
        late WidgetbookState primary;
        await tester.pumpWidget(
          Widgetbook.material(
            initialRoute: '/?path=probe/session',
            addons: [
              ThemeAddon<AppThemeData>(
                themes: [
                  WidgetbookTheme(name: 'Dark', data: AppThemeData.dark),
                ],
                themeBuilder: (_, theme, child) =>
                    AppTheme(data: theme, child: child),
              ),
              WbDesignStatusAddon(),
              WbCompareLayoutsAddon(),
            ],
            directories: [
              WidgetbookComponent(
                name: 'Probe',
                useCases: [
                  WidgetbookUseCase(
                    name: 'Session',
                    designLink: kWbNoFigma,
                    builder: (context) {
                      final lane = withLayout
                          ? wbLayoutKnob(context).name
                          : 'single';
                      context.knobs.string(
                        label: 'Seed',
                        initialValue: 'initial',
                      );
                      if (lane != 'mobile') {
                        primary = WidgetbookState.of(context);
                      }
                      return _Session(lane: lane, mounts: mounts);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final lane = withLayout ? 'desktop' : 'single';
        final field = find.byKey(ValueKey('input-$lane'));
        await tester.enterText(field, 'retained input');
        await tester.tap(find.byKey(ValueKey('next-$lane')));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('sheet-$lane')));
        await tester.pumpAndSettle();

        for (final addon in [WbCompareLayoutsAddon(), WbDesignStatusAddon()]) {
          if (withLayout && addon is WbDesignStatusAddon) {
            final compare = WbCompareLayoutsAddon();
            primary.updateQueryField(
              group: compare.groupName,
              field: compare.name,
              value: 'true',
            );
            await tester.pumpAndSettle();
            // The dialog is still open; seed the other pane without closing it.
            tester
                    .widget<TextField>(
                      find.byKey(const ValueKey('input-mobile')),
                    )
                    .controller!
                    .text =
                'secondary input';
          }
          for (final enabled in [true, false, true, false]) {
            primary.updateQueryField(
              group: addon.groupName,
              field: addon.name,
              value: '$enabled',
            );
            await tester.pumpAndSettle();
            expect(mounts[lane], 1);
            expect(
              tester.widget<TextField>(field).controller!.text,
              'retained input',
            );
            expect(find.text('$lane step 1'), findsOneWidget);
            expect(find.text('Session sheet'), findsOneWidget);
            if (withLayout && addon is WbDesignStatusAddon) {
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(const ValueKey('input-mobile')),
                    )
                    .controller!
                    .text,
                'secondary input',
              );
            }
            expect(tester.takeException(), isNull);
          }
        }

        await tester.tap(find.text('Close sheet'));
        await tester.pumpAndSettle();

        // A real knob change must still start a new fixture session.
        primary.updateQueryField(
          group: 'knobs',
          field: 'Seed',
          value: 'changed',
        );
        await tester.pumpAndSettle();
        expect(mounts[lane], 2);
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Session extends StatefulWidget {
  const _Session({required this.lane, required this.mounts});
  final String lane;
  final Map<String, int> mounts;
  @override
  State<_Session> createState() => _SessionState();
}

class _SessionState extends State<_Session> {
  final controller = TextEditingController();
  int step = 0;
  @override
  void initState() {
    super.initState();
    widget.mounts.update(widget.lane, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: ValueKey('input-${widget.lane}'),
          controller: controller,
        ),
        Text('${widget.lane} step $step'),
        TextButton(
          key: ValueKey('next-${widget.lane}'),
          onPressed: () => setState(() => step++),
          child: const Text('Next'),
        ),
        TextButton(
          key: ValueKey('sheet-${widget.lane}'),
          onPressed: () => showDialog<void>(
            context: context,
            useRootNavigator: true,
            builder: (context) => AlertDialog(
              title: const Text('Session sheet'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close sheet'),
                ),
              ],
            ),
          ),
          child: const Text('Open sheet'),
        ),
      ],
    ),
  );
}
