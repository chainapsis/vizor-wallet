import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('external link warning', () {
    PaymentRequestView external(PaymentRequestSource source) =>
        PaymentRequestView(
          source: source,
          address: _address,
          amountZecText: '0.5 ZEC',
        );

    testWidgets('an incoming link offers to scan the original QR', (
      tester,
    ) async {
      await _pump(tester, external(PaymentRequestSource.link));

      expect(
        find.byKey(const ValueKey('external_request_warning')),
        findsOneWidget,
      );
      expect(find.text('Scan original QR'), findsOneWidget);
      expect(
        find.text('Scan the original QR code directly in Vizor.'),
        findsOneWidget,
      );
    });

    testWidgets('a pasted link is reviewed instead', (tester) async {
      await _pump(tester, external(PaymentRequestSource.pastedLink));

      expect(
        find.byKey(const ValueKey('external_request_warning')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('payment_request_scan')), findsNothing);
      expect(
        find.text('Confirm the details with the person who sent it.'),
        findsOneWidget,
      );
      final review = tester.widget<AppButton>(
        find.byKey(const ValueKey('payment_request_link_details')),
      );
      expect(review.variant, AppButtonVariant.primary);
    });
  });

  group('original QR check', () {
    PaymentRequestView scanned(
      Set<PaymentRequestLinkDifference>? differences,
    ) => PaymentRequestView(
      source: PaymentRequestSource.qrCode,
      address: _address,
      amountZecText: '0.5 ZEC',
      linkDifferences: differences,
    );

    testWidgets('a matching QR says so', (tester) async {
      await _pump(tester, scanned(const {}));

      expect(find.text('Matches the link'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_link_mismatch')),
        findsNothing,
      );
    });

    testWidgets('a different QR names what the link changed', (tester) async {
      await _pump(
        tester,
        scanned(const {PaymentRequestLinkDifference.address}),
      );

      expect(find.text('The link had a different address'), findsOneWidget);
      expect(
        find.text('Using the QR instead — the link may have been changed.'),
        findsOneWidget,
      );
    });

    testWidgets('several differences read as different details', (
      tester,
    ) async {
      await _pump(
        tester,
        scanned(const {
          PaymentRequestLinkDifference.amount,
          PaymentRequestLinkDifference.memo,
        }),
      );

      expect(find.text('The link had different details'), findsOneWidget);
    });

    testWidgets('a card that checked no link shows neither', (tester) async {
      await _pump(tester, scanned(null));

      expect(
        find.byKey(const ValueKey('payment_request_link_match')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment_request_link_mismatch')),
        findsNothing,
      );
    });
  });

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
  source: PaymentRequestSource.qrCode,
  address: _address,
  amountZecText: '0.5 ZEC',
  memo: memo,
);

Future<void> _pump(
  WidgetTester tester,
  PaymentRequestView request, {
  bool initialMessageExpanded = true,
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
