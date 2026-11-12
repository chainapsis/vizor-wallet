import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/inline_spans.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_prompt_lines.dart';

void main() {
  Future<void> pump(WidgetTester tester, String text) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: KeystonePromptLines(
            text: text,
            icon: const SizedBox.square(key: ValueKey('icon'), dimension: 28),
            style: const TextStyle(fontSize: 14),
            inlineGap: 6,
            lineGap: 2,
            trailing: const SizedBox.square(
              key: ValueKey('help'),
              dimension: 28,
            ),
            trailingGap: 6,
          ),
        ),
      ),
    );
  }

  testWidgets('wraps the words around the icon and trails the last line', (
    tester,
  ) async {
    await pump(
      tester,
      'Tap $kInlineSlot on your Keystone,\nthen scan this QR code',
    );

    expect(find.text('Tap'), findsOneWidget);
    expect(find.text('on your Keystone,'), findsOneWidget);
    final lastLine = tester.getRect(find.text('then scan this QR code'));
    final help = tester.getRect(find.byKey(const ValueKey('help')));
    expect(help.left, greaterThan(lastLine.right));
    expect(
      tester.getRect(find.byKey(const ValueKey('icon'))).bottom,
      lessThan(lastLine.top),
    );
  });

  testWidgets('keeps a translation that puts the icon elsewhere', (
    tester,
  ) async {
    await pump(tester, 'Keystone에서 $kInlineSlot 버튼을 누른 뒤\n이 QR 코드를 스캔하세요');

    expect(find.text('Keystone에서'), findsOneWidget);
    expect(find.text('버튼을 누른 뒤'), findsOneWidget);
    expect(find.text('이 QR 코드를 스캔하세요'), findsOneWidget);
    expect(find.byKey(const ValueKey('icon')), findsOneWidget);
  });
}
