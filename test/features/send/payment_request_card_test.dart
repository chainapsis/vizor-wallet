import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('transaction memo row', () {
    testWidgets('renders a padded memo exactly as the payment carries it', (
      tester,
    ) async {
      // The pre-check proposes these bytes untouched, so the row may not
      // tidy them: a payer who reads a trimmed memo is reading a different
      // memo from the one they are about to pay.
      await _pump(tester, _view(memo: '  invoice 42  '));

      expect(find.text('Transaction memo'), findsOneWidget);
      expect(find.text('  invoice 42  '), findsOneWidget);
      expect(find.text('invoice 42'), findsNothing);
    });

    testWidgets('keeps the padding when the memo is expanded', (tester) async {
      await _pump(
        tester,
        _view(memo: '  invoice 42  '),
        initialMessageExpanded: true,
      );

      expect(find.text('  invoice 42  '), findsOneWidget);
    });

    testWidgets('names a whitespace-only memo instead of drawing nothing', (
      tester,
    ) async {
      // Those bytes are paid. Rendering them verbatim would leave a row that
      // reads exactly like a request that asked for no memo at all.
      await _pump(tester, _view(memo: '   '));

      expect(find.text('Transaction memo'), findsOneWidget);
      expect(find.text('Whitespace only'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    });

    testWidgets('the whitespace placeholder is muted, not memo-colored', (
      tester,
    ) async {
      await _pump(tester, _view(memo: 'invoice 42'));
      final memoColor = tester
          .widget<Text>(find.text('invoice 42'))
          .style!
          .color;

      await _pump(tester, _view(memo: '   '));
      final placeholderColor = tester
          .widget<Text>(find.text('Whitespace only'))
          .style!
          .color;

      expect(placeholderColor, AppThemeData.light.colors.text.muted);
      expect(
        placeholderColor,
        isNot(memoColor),
        reason:
            'the placeholder is the card describing the memo, not the '
            "memo's own words, so it must not read as content",
      );
    });

    testWidgets('a request with no memo renders no memo row', (tester) async {
      await _pump(tester, _view());

      expect(find.text('Transaction memo'), findsNothing);
      expect(find.text('Whitespace only'), findsNothing);
    });

    testWidgets('an empty memo renders no memo row', (tester) async {
      await _pump(tester, _view(memo: ''));

      expect(find.text('Transaction memo'), findsNothing);
      expect(find.text('Whitespace only'), findsNothing);
    });
  });
}

PaymentRequestView _view({String? memo}) => PaymentRequestView(
  source: PaymentRequestSource.link,
  address: _address,
  amountZecText: '0.5 ZEC',
  memo: memo,
);

Future<void> _pump(
  WidgetTester tester,
  PaymentRequestView request, {
  bool initialMessageExpanded = false,
}) async {
  tester.view.physicalSize = const Size(1080, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: PaymentRequestCard(
          request: request,
          layout: PaymentRequestLayout.desktop,
          initialMessageExpanded: initialMessageExpanded,
          onContinue: () {},
          onEdit: () {},
          onCancel: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}
