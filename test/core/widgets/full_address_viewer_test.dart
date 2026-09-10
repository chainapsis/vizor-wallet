import 'package:flutter/material.dart' show MaterialApp, Overlay;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/full_address_viewer.dart';

const _address =
    'u10O0qrstuvwxyzO0O0abcdefghijklO0O0mnopqrstuvwxO0O001234567890O0O0';

void main() {
  test('fullAddressCopyText trims without inserting spaces', () {
    expect(fullAddressCopyText('  $_address\n'), _address);
    expect(fullAddressCopyText(_address).contains(' '), isFalse);
    expect(fullAddressCopyText(_address).contains('\n'), isFalse);
  });

  testWidgets('address text wraps the exact string in Geist Mono', (
    tester,
  ) async {
    await _pump(tester, const FullAddressText(address: _address));

    final text = tester.widget<Text>(
      find.byKey(const ValueKey('full_address_text')),
    );
    expect(text.data, _address);
    expect(text.softWrap, isTrue);
    expect(text.style?.fontFamily, 'Geist Mono');
  });

  testWidgets('copy button writes the exact address without spaces', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pump(tester, const FullAddressCopyButton(address: '  $_address  '));

    await tester.tap(find.byKey(const ValueKey('full_address_copy_button')));
    await tester.pump();

    expect(copied, [_address]);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) =>
                  Center(child: SizedBox(width: 312, child: child)),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}
