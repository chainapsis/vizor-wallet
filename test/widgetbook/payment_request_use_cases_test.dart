import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/widgetbook/payment_request_use_cases.dart';

const _desktopSize = Size(1080, 720);
const _mobileSize = Size(393, 852);
const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b73d57f73c6dc05121591a83861cd190591';
Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  testWidgets(
    'external introduction shows only caution and a choice of review method',
    (tester) async {
      await _pumpUseCase(tester, buildPaymentRequestFullUseCase);
      expect(find.text('Payment request'), findsOneWidget);
      expect(find.text('Request from'), findsNothing);
      expect(find.text('Blue Door Coffee'), findsNothing);
      expect(find.text('0.5 ZEC'), findsNothing);
      expect(find.text(r'$35.00'), findsNothing);
      expect(find.text('Recipient'), findsNothing);
      expect(find.text('Shielded'), findsNothing);
      expect(find.text('u195091 ... 190591'), findsNothing);
      expect(find.text('Memo included'), findsNothing);
      expect(_key('external_request_warning'), findsOneWidget);
      expect(_key('payment_request_summary'), findsNothing);
      expect(find.text('Check before you pay'), findsOneWidget);
      expect(find.text('Scan original QR'), findsOneWidget);
      expect(find.text('Review link details'), findsOneWidget);
      expect(_key('payment_request_continue'), findsNothing);
      expect(_button(tester, 'payment_request_scan').onPressed, isNotNull);
      expect(
        _button(tester, 'payment_request_link_details').onPressed,
        isNotNull,
      );
      expect(_key('payment_request_memo'), findsNothing);
      expect(_key('payment_request_requester_note'), findsNothing);
    },
  );

  testWidgets('status previews show their details and matching action', (
    tester,
  ) async {
    for (final (builder, label, showsStatus) in <(WidgetBuilder, String, bool)>[
      (buildPaymentRequestCheckingUseCase, 'Checking…', false),
      (buildPaymentRequestInvalidAddressUseCase, 'Review payment', true),
      (buildPaymentRequestInsufficientUseCase, 'Review payment', true),
      (buildPaymentRequestSyncingUseCase, 'Review payment', true),
      (buildPaymentRequestSyncStalledUseCase, 'Check again', true),
      (buildPaymentRequestFailedUseCase, 'Check again', true),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder);
      expect(_key('external_request_warning'), findsNothing);
      expect(_key('payment_request_continue'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(
        _key('payment_request_status'),
        showsStatus ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'requester disclosure explains the unverified name and reveals its note',
    (tester) async {
      await _pumpUseCase(tester, buildPaymentRequestLinkDetailsUseCase);
      expect(_key('payment_request_link_origin'), findsNothing);
      expect(_key('payment_request_back_to_intro'), findsNothing);
      await tester.tap(_key('payment_request_requester_toggle'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This name comes from the request. It doesn't confirm who owns the receiving address.",
        ),
        findsOneWidget,
      );
      expect(_key('payment_request_requester_note'), findsOneWidget);
      await tester.tap(_key('payment_request_requester_toggle'));
      await tester.pumpAndSettle();
      expect(_key('payment_request_requester_note'), findsNothing);
    },
  );

  testWidgets(
    'requester, recipient and memo disclosures each expose one semantics action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpUseCase(tester, buildPaymentRequestLinkDetailsUseCase);
      for (final label in [
        'Show requester information for Blue Door Coffee',
        'Show full recipient address',
        'Payment details',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      }
      semantics.dispose();
    },
  );

  testWidgets('full address and exact memo can be opened and closed', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestLinkDetailsUseCase);
    await tester.ensureVisible(_key('payment_request_show_full_address'));
    await tester.tap(_key('payment_request_show_full_address'));
    await tester.pumpAndSettle();
    expect(_key('payment_request_address_chunks'), findsOneWidget);
    final fullAddress = find.descendant(
      of: _key('payment_request_address_chunks'),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(fullAddress).data, _address);
    await tester.ensureVisible(_key('payment_request_memo_toggle'));
    await tester.tap(_key('payment_request_memo_toggle'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction memo'), findsOneWidget);
    expect(_key('payment_request_memo'), findsOneWidget);
    await tester.ensureVisible(_key('payment_request_memo_toggle'));
    await tester.tap(_key('payment_request_memo_toggle'));
    await tester.ensureVisible(_key('payment_request_show_full_address'));
    await tester.tap(_key('payment_request_show_full_address'));
    await tester.pumpAndSettle();
    expect(_key('payment_request_memo'), findsNothing);
    expect(_key('payment_request_address_chunks'), findsNothing);
  });

  testWidgets(
    'long expanded contents scroll while title and actions stay visible',
    (tester) async {
      for (final (builder, size) in <(WidgetBuilder, Size)>[
        (buildPaymentRequestLongValuesExpandedUseCase, _desktopSize),
        (buildMobilePaymentRequestLongValuesExpandedUseCase, _mobileSize),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUseCase(tester, builder, size: size);
        await tester.ensureVisible(_key('payment_request_show_full_address'));
        await tester.tap(_key('payment_request_show_full_address'));
        await tester.pumpAndSettle();
        final title = tester.getRect(_key('payment_request_title'));
        final action = tester.getRect(_key('payment_request_continue'));
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byKey(kPaymentRequestScrollViewKey),
            )
            .controller!;
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(_key('payment_request_memo'), findsOneWidget);
        expect(_key('payment_request_address_chunks'), findsOneWidget);
        expect(tester.getRect(_key('payment_request_title')), title);
        expect(tester.getRect(_key('payment_request_continue')), action);
        expect(action.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('scrollbar and content share one controller', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestLongValuesExpandedUseCase);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(kPaymentRequestScrollViewKey),
    );
    final bar = tester.widget<RawScrollbar>(
      find.byKey(kPaymentRequestScrollbarKey),
    );
    expect(bar.controller, same(scroll.controller));
  });

  testWidgets('saved contacts and own accounts remain distinguishable', (
    tester,
  ) async {
    for (final builder in <WidgetBuilder>[
      buildPaymentRequestContactUseCase,
      buildPaymentRequestOwnAccountUseCase,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder);
      expect(_key('payment_request_recipient_name'), findsOneWidget);
      expect(_key('payment_request_recipient_address'), findsOneWidget);
      expect(
        find.text('Your account'),
        builder == buildPaymentRequestOwnAccountUseCase
            ? findsOneWidget
            : findsNothing,
      );
      await tester.ensureVisible(_key('payment_request_show_full_address'));
      await tester.tap(_key('payment_request_show_full_address'));
      await tester.pumpAndSettle();
      expect(_key('payment_request_address_chunks'), findsOneWidget);
    }
  });

  testWidgets(
    'external requests remain scannable and reviewable during every check status',
    (tester) async {
      for (final status in PaymentRequestStatus.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUseCase(
          tester,
          (_) => _surface(status: status, source: PaymentRequestSource.link),
        );
        expect(_button(tester, 'payment_request_scan').onPressed, isNotNull);
        expect(
          _button(tester, 'payment_request_link_details').onPressed,
          isNotNull,
        );
        expect(_key('payment_request_continue'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'scanned requests keep status-specific review, retry and edit actions',
    (tester) async {
      for (final status in PaymentRequestStatus.values) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUseCase(tester, (_) => _surface(status: status));
        final primary = _button(tester, 'payment_request_continue');
        final retry =
            status == PaymentRequestStatus.failed ||
            status == PaymentRequestStatus.syncStalled;
        expect(
          primary.onPressed != null,
          !status.blocksContinue || retry,
          reason: '$status',
        );
        expect(_button(tester, 'payment_request_edit').onPressed, isNotNull);
        expect(find.text('Opened from another app'), findsNothing);
        expect(
          find.text(
            retry
                ? 'Check again'
                : status == PaymentRequestStatus.checking
                ? 'Checking…'
                : 'Review payment',
          ),
          findsOneWidget,
        );
        if (defaultPaymentRequestStatusMessage(status) != null) {
          expect(
            find.text(defaultPaymentRequestStatusMessage(status)!),
            findsOneWidget,
          );
          final icons = find.descendant(
            of: _key('payment_request_status'),
            matching: find.byType(AppIcon),
          );
          expect(icons, status.isError ? findsOneWidget : findsNothing);
        }
      }
    },
  );

  testWidgets(
    'an amountless scan asks for an amount and retains an edit exit on errors',
    (tester) async {
      for (final status in [
        PaymentRequestStatus.ready,
        PaymentRequestStatus.invalidAddress,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpUseCase(
          tester,
          (_) => _surface(status: status, amount: null),
        );
        expect(_key('payment_request_amount'), findsNothing);
        expect(
          find.text(
            status == PaymentRequestStatus.ready ? 'Enter amount' : 'Edit',
          ),
          findsOneWidget,
        );
        expect(
          _button(tester, 'payment_request_continue').onPressed,
          isNotNull,
        );
      }
    },
  );

  testWidgets('replaced notice names the earlier link', (tester) async {
    await _pumpUseCase(
      tester,
      (_) => _surface(source: PaymentRequestSource.link, replaced: true),
    );
    expect(find.text('Replaced an earlier link'), findsOneWidget);
  });

  testWidgets('scanned request preview carries no replaced notice', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestScannedUseCase);
    expect(_key('payment_request_replaced_notice'), findsNothing);
  });
  testWidgets('every registered use case renders in its own lane', (
    tester,
  ) async {
    for (final builder in <WidgetBuilder>[
      buildPaymentRequestFullUseCase,
      buildPaymentRequestPastedUseCase,
      buildPaymentRequestScannedMatchesLinkUseCase,
      buildPaymentRequestScannedDiffersFromLinkUseCase,
      buildPaymentRequestMinimalUseCase,
      buildPaymentRequestLongValuesUseCase,
      buildPaymentRequestLongValuesExpandedUseCase,
      buildPaymentRequestAddressExpandedUseCase,
      buildPaymentRequestCheckingUseCase,
      buildPaymentRequestInvalidAddressUseCase,
      buildPaymentRequestInsufficientUseCase,
      buildPaymentRequestSyncingUseCase,
      buildPaymentRequestSyncStalledUseCase,
      buildPaymentRequestFailedUseCase,
      buildPaymentRequestReplacedUseCase,
      buildPaymentRequestTransparentUseCase,
      buildPaymentRequestContactUseCase,
      buildPaymentRequestOwnAccountUseCase,
      buildPaymentRequestOwnAccountExpandedUseCase,
      buildPaymentRequestNoteOnlyUseCase,
      buildPaymentRequestNoAmountUseCase,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder);
      expect(tester.takeException(), isNull);
    }

    for (final builder in <WidgetBuilder>[
      buildMobilePaymentRequestFullUseCase,
      buildMobilePaymentRequestPastedUseCase,
      buildMobilePaymentRequestScannedMatchesLinkUseCase,
      buildMobilePaymentRequestScannedDiffersFromLinkUseCase,
      buildMobilePaymentRequestMinimalUseCase,
      buildMobilePaymentRequestLongValuesUseCase,
      buildMobilePaymentRequestLongValuesExpandedUseCase,
      buildMobilePaymentRequestAddressExpandedUseCase,
      buildMobilePaymentRequestCheckingUseCase,
      buildMobilePaymentRequestInvalidAddressUseCase,
      buildMobilePaymentRequestInsufficientUseCase,
      buildMobilePaymentRequestSyncingUseCase,
      buildMobilePaymentRequestFailedUseCase,
      buildMobilePaymentRequestReplacedUseCase,
      buildMobilePaymentRequestTransparentUseCase,
      buildMobilePaymentRequestContactUseCase,
      buildMobilePaymentRequestOwnAccountUseCase,
      buildMobilePaymentRequestOwnAccountExpandedUseCase,
      buildMobilePaymentRequestNoteOnlyUseCase,
      buildMobilePaymentRequestNoAmountUseCase,
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: _mobileSize);
      expect(tester.takeException(), isNull);
    }
  });
}

AppButton _button(WidgetTester tester, String key) =>
    tester.widget<AppButton>(_key(key));

Widget _surface({
  PaymentRequestStatus status = PaymentRequestStatus.ready,
  PaymentRequestSource source = PaymentRequestSource.qrCode,
  String? amount = '0.5 ZEC',
  bool replaced = false,
}) => PaymentRequestSurface(
  request: PaymentRequestView(
    source: source,
    amountZecText: amount,
    address: _address,
    status: status,
    replacedNotice: replaced,
  ),
  onContinue: () {},
  onEdit: () {},
  onCancel: () {},
  onRecheck: () {},
  onScan: () {},
);

Future<void> _pumpUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  Size size = _desktopSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
