import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/inline_spans.dart';

void main() {
  const style = TextStyle(fontWeight: FontWeight.bold);

  String plain(List<InlineSpan> spans) =>
      TextSpan(children: spans).toPlainText();

  test('emphasis lands wherever the translation puts the placeholder', () {
    for (final text in ['Wait for the window', '서명 구간까지 Wait', 'Wait']) {
      final spans = emphasisSpans(text, ['Wait'], style);
      expect(plain(spans), text);
      expect(
        spans.whereType<TextSpan>().where((s) => s.style == style).single.text,
        'Wait',
      );
    }
  });

  test('slots are filled in order of appearance', () {
    const icon = WidgetSpan(child: SizedBox());
    final spans = inlineSlotSpans(
      'Tap $kInlineSlot on your Keystone,\nthen scan',
      {kInlineSlot: icon},
    );
    expect(spans, hasLength(3));
    expect(spans[1], same(icon));
  });

  test('a missing placeholder leaves the text intact', () {
    expect(plain(emphasisSpans('No phrase', ['Wait'], style)), 'No phrase');
  });
}
