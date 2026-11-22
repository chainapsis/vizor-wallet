import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/settings/settings_focus.dart';

const _viewport = 600.0;

Widget _settings(ProviderContainer container, {bool reduceMotion = false}) =>
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: _viewport,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 2000),
                  SettingsFocusTarget(
                    focus: SettingsFocus.privateQueries,
                    child: SizedBox(height: 60),
                  ),
                  SizedBox(height: 500),
                ],
              ),
            ),
          ),
        ),
      ),
    );

void _expectInView(WidgetTester tester) {
  final rect = tester.getRect(find.byType(SettingsFocusTarget));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(_viewport));
}

void main() {
  testWidgets('open Settings scrolls to the requested row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_settings(container));
    expect(
      tester.getRect(find.byType(SettingsFocusTarget)).top,
      greaterThan(_viewport),
    );

    container
        .read(settingsFocusRequestProvider.notifier)
        .request(SettingsFocus.privateQueries);
    await tester.pumpAndSettle();

    _expectInView(tester);
    expect(container.read(settingsFocusRequestProvider), isNull);
  });

  testWidgets('Settings opened for a row starts there', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(settingsFocusRequestProvider.notifier)
        .request(SettingsFocus.privateQueries);

    await tester.pumpWidget(_settings(container));
    await tester.pumpAndSettle();

    _expectInView(tester);
    expect(container.read(settingsFocusRequestProvider), isNull);
  });

  testWidgets('reduced motion jumps to the row', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_settings(container, reduceMotion: true));

    container
        .read(settingsFocusRequestProvider.notifier)
        .request(SettingsFocus.privateQueries);
    await tester.pump();
    await tester.pump();

    _expectInView(tester);
  });
}
