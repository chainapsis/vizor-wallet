import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/address_line_text.dart';

const _style = TextStyle(fontSize: 10);
const _address = '0x9aDF ... 819E2';

double _width(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

Future<String> _shown(
  WidgetTester tester,
  AddressLine line, {
  required double width,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: AddressLineText(line, style: _style),
        ),
      ),
    ),
  );
  return tester.widget<Text>(find.byType(Text)).data!;
}

void main() {
  final withChain = AddressLine.inTemplate(
    (address) => 'To: $address on Ethereum',
    address: _address,
    label: 'Treasury',
  );
  final plain = AddressLine.inTemplate(
    (address) => 'To: $address',
    address: _address,
    label: 'Treasury',
  );

  test('a template splits around its address', () {
    expect(withChain.before, 'To: ');
    expect(withChain.after, ' on Ethereum');
    expect(withChain.text, 'To: Treasury ($_address) on Ethereum');
    expect(
      AddressLine.inTemplate(
        (address) => 'To: $address',
        address: _address,
      ).text,
      'To: $_address',
    );
  });

  test('a blank contact name is left out', () {
    expect(
      const AddressLine(address: _address, label: '  ', before: 'To: ').text,
      'To: $_address',
    );
  });

  testWidgets('the whole line shows when it fits', (tester) async {
    final whole = withChain.text;
    expect(await _shown(tester, withChain, width: _width(whole)), whole);
  });

  testWidgets('the text after the address gives way first', (tester) async {
    const named = 'To: Treasury ($_address)';
    expect(await _shown(tester, withChain, width: _width(named)), named);
  });

  testWidgets('a name that does not fit moves to its own line', (tester) async {
    final width = _width('To: Treasury ($_address)') - 1;
    expect(
      await _shown(tester, plain, width: width),
      'To: Treasury\n$_address',
    );
    expect(
      await _shown(tester, withChain, width: width),
      'To: Treasury\n$_address on Ethereum',
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('a name too long for its own line shortens there', (
    tester,
  ) async {
    final shown = await _shown(tester, plain, width: _width('To: Treas…'));
    expect(shown, 'To: Treas…\n$_address');
  });

  testWidgets('a name with no room beside "To:" keeps its own line alone', (
    tester,
  ) async {
    final shown = await _shown(tester, plain, width: _width('To: Tre…') - 1);
    expect(shown, 'Treasu…\n$_address');
  });

  testWidgets('a name with no room for three characters is left out', (
    tester,
  ) async {
    final shown = await _shown(tester, plain, width: _width('Tre…') - 1);
    expect(shown, _address);
  });

  testWidgets('without a name, the chain gives way before "To:"', (
    tester,
  ) async {
    const line = AddressLine(
      address: _address,
      before: 'To: ',
      after: ' on Ethereum',
    );
    const withoutAfter = 'To: $_address';
    expect(
      await _shown(tester, line, width: _width(withoutAfter)),
      withoutAfter,
    );
  });

  const unnamed = AddressLine(address: _address, before: 'To: ');

  testWidgets('the address shows alone when nothing else fits', (tester) async {
    expect(await _shown(tester, unnamed, width: _width(_address)), _address);
    expect(
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('an address too wide on its own wraps instead of losing its '
      'tail', (tester) async {
    expect(
      await _shown(tester, unnamed, width: _width(_address) - 1),
      _address,
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.maxLines, isNull);
  });

  testWidgets('a kept role wraps the address below it instead of dropping', (
    tester,
  ) async {
    AddressLine refund({String? label}) => AddressLine.inTemplate(
      (address) => 'Refund to: $address',
      address: _address,
      label: label,
      keepBefore: true,
    );
    const withRole = 'Refund to: $_address';
    expect(await _shown(tester, refund(), width: _width(withRole)), withRole);
    expect(
      await _shown(tester, refund(), width: _width(_address)),
      'Refund to:\n$_address',
    );
    expect(
      await _shown(
        tester,
        refund(label: 'Treasury'),
        width: _width('Refund to: Treasury'),
      ),
      'Refund to: Treasury\n$_address',
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('the shortened name drops a trailing space', (tester) async {
    final line = AddressLine.inTemplate(
      (address) => 'To: $address',
      address: _address,
      label: 'Rowan Ledger',
    );
    final shown = await _shown(tester, line, width: _width('To: Rowan …'));
    expect(shown.split('\n').first, 'To: Rowan…');
  });

  testWidgets('a long form that does not fit gives way to the short form', (
    tester,
  ) async {
    const long = '0x52908400098 ... 7D2E4169EE7';
    const line = AddressLine(address: long, shortAddress: _address);
    expect(await _shown(tester, line, width: _width(long)), long);
    expect(await _shown(tester, line, width: _width(long) - 1), _address);
    expect(
      tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('a single-line row never wraps', (tester) async {
    const line = AddressLine(
      address: '0x52908400098 ... 7D2E4169EE7',
      shortAddress: _address,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _width(_address) - 1,
            child: const AddressLineText(line, style: _style, singleLine: true),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, _address);
    expect(text.maxLines, 1);
  });

  testWidgets('screen readers hear the whole line', (tester) async {
    final semantics = tester.ensureSemantics();
    await _shown(tester, withChain, width: _width(_address));
    expect(find.bySemanticsLabel(withChain.text), findsOneWidget);
    semantics.dispose();
  });
}
