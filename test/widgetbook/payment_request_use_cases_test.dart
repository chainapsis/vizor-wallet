import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_safe_area.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/app_tooltip.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/widgetbook/payment_request_use_cases.dart';

void main() {
  testWidgets('full use case renders the whole request', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Payment request'), findsOneWidget);
    expect(find.text('Requester'), findsOneWidget);
    expect(find.text('Blue Door Coffee'), findsOneWidget);
    expect(find.text('Requested by Blue Door Coffee'), findsNothing);
    expect(find.textContaining('From a link'), findsNothing);
    expect(find.text('0.5 ZEC'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(find.text('Transaction memo'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Note'), findsNothing);
    // Requester notes are progressive disclosure and start hidden.
    expect(find.text('Note from requester'), findsNothing);
    expect(_key('payment_request_requester_note'), findsNothing);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    // Desktop refuses through the header's close, not a third pill in the
    // action row.
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const ValueKey('payment_request_close')), findsOneWidget);
  });

  testWidgets('the card carries no help affordances at all', (tester) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestFullUseCase, _desktopSize),
      (buildMobilePaymentRequestFullUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      // No ⓘ beside requester or transaction content: the labels carry the
      // meaning on their own.
      expect(find.byType(AppTooltip), findsNothing);
      expect(find.bySemanticsLabel('About this name'), findsNothing);
    }
  });

  testWidgets('the title and requester group stay separate', (tester) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestFullUseCase, _desktopSize),
      (buildMobilePaymentRequestFullUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      expect(_titleText(tester), 'Payment request');
      expect(
        find.byKey(const ValueKey('payment_request_requester_group')),
        findsOneWidget,
      );
      expect(find.text('Requested by Blue Door Coffee'), findsNothing);
      expect(
        find.byKey(const ValueKey('payment_request_eyebrow')),
        findsNothing,
      );
    }
  });

  testWidgets('requester note expands from the collapsed requester group', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(_key('payment_request_requester_note'), findsNothing);
    expect(find.bySemanticsLabel('Show requester details'), findsOneWidget);

    await tester.tap(_key('payment_request_requester_toggle'));
    await tester.pumpAndSettle();

    expect(find.text('Note from requester'), findsOneWidget);
    expect(_key('payment_request_requester_note'), findsOneWidget);
    expect(find.bySemanticsLabel('Hide requester details'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('requester and memo disclosures expose one semantics action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    final requester = tester.getSemantics(
      find.bySemanticsLabel('Show requester details'),
    );
    final memo = tester.getSemantics(
      find.bySemanticsLabel('Expand transaction memo'),
    );

    expect(requester.childrenCountInTraversalOrder, 0);
    expect(memo.childrenCountInTraversalOrder, 0);
    semantics.dispose();
  });

  testWidgets('a very long requester note scrolls inside its existing card', (
    tester,
  ) async {
    final note = List.filled(12000, 'a').join();
    await _pumpUseCase(
      tester,
      (_) => PaymentRequestSurface(
        layout: PaymentRequestLayout.mobile,
        request: PaymentRequestView(
          source: PaymentRequestSource.link,
          requesterLabel: 'Blue Door Coffee',
          amountZecText: '0.5 ZEC',
          address:
              'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
              '73d57f73c6dc05121591a83861cd190591',
          note: note,
        ),
        onContinue: () {},
        onEdit: () {},
        onCancel: () {},
      ),
      size: _mobileSize,
    );

    await tester.tap(_key('payment_request_requester_toggle'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(_requesterNoteMaxScrollExtent(tester), greaterThan(0));

    await tester.drag(
      find.byKey(kPaymentRequestRequesterNoteScrollViewKey),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();

    expect(_requesterNoteScrollOffset(tester), greaterThan(0));
  });

  testWidgets('a requester name without a note is not an empty accordion', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestContactUseCase);

    expect(_key('payment_request_requester_group'), findsOneWidget);
    expect(_key('payment_request_requester_toggle'), findsNothing);
    expect(find.text('Note from requester'), findsNothing);
  });

  testWidgets('the request rows use the send review row treatment', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    // Requester metadata and transaction content are separate visual groups.
    expect(_key('payment_request_requester_group'), findsOneWidget);
    expect(_key('payment_request_transaction_content'), findsOneWidget);
    expect(find.byType(ReviewWrapCard), findsNWidgets(2));
    expect(find.byType(ReviewWrapDivider), findsOneWidget);

    final labelStyle = AppTypography.bodyMediumStrong;
    for (final label in const ['To', 'Transaction memo']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style!.fontSize, labelStyle.fontSize, reason: label);
      expect(text.style!.fontWeight, labelStyle.fontWeight, reason: label);
      // One colour step off the value beside it, never a tiny muted caption.
      expect(
        text.style!.color,
        AppThemeData.light.colors.text.secondary,
        reason: label,
      );
    }
  });

  testWidgets('disclosures do not add a hover fill', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();

    for (final key in const [
      'payment_request_requester_toggle',
      'payment_request_memo_toggle',
    ]) {
      final button = _key(key);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pump();

      final decoration =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: button,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as ShapeDecoration;
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: button, matching: find.byType(AnimatedContainer)),
      );
      expect(
        decoration.color,
        AppThemeData.light.colors.background.ground.withValues(alpha: 0),
      );
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      );
    }
  });

  testWidgets('the full address expands inside the card, not out of it', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_request_address_chunks')),
      findsNothing,
    );

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hide full address'), findsOneWidget);
    expect(find.text('Show full address'), findsNothing);
    expect(find.text('u195091 ... 190591'), findsNothing);
    expect(
      find.byKey(const ValueKey('payment_request_address_chunks')),
      findsOneWidget,
    );
    // 5-character groups, taken from the verify-address grid.
    expect(find.text('u1950'), findsOneWidget);
    expect(find.text('591'), findsOneWidget);
    // Nothing left the card: the actions are still on screen.
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.text('Hide full address'));
    await tester.pumpAndSettle();
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
  });

  testWidgets('the expanded-address use cases render both lanes', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestAddressExpandedUseCase, _desktopSize),
      (buildMobilePaymentRequestAddressExpandedUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Hide full address'), findsOneWidget);
      expect(find.text('u1950'), findsOneWidget);
    }
  });

  testWidgets('minimal use case renders transaction content only', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestMinimalUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Blue Door Coffee'), findsNothing);
    expect(
      find.byKey(const ValueKey('payment_request_requester_group')),
      findsNothing,
    );
    expect(find.text('Transaction content'), findsOneWidget);
    expect(_key('payment_request_transaction_content'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Note'), findsNothing);
    expect(find.byType(ReviewWrapDivider), findsNothing);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
  });

  testWidgets('a long message expands in place and collapses again', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestLongValuesUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Collapse'), findsNothing);

    await _tapRow(tester, 'payment_request_memo');
    expect(find.text('Collapse'), findsOneWidget);

    await _tapRow(tester, 'payment_request_memo');
    expect(find.text('Collapse'), findsNothing);
  });

  testWidgets('the amount stays pinned above the scrolling details', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesExpandedUseCase,
      size: _mobileSize,
    );

    final amount = _key('payment_request_amount');
    expect(amount, findsOneWidget);
    final before = tester.getRect(amount);

    await tester.drag(
      find.byKey(kPaymentRequestScrollViewKey),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Scrolled to the very end, and the amount has not moved a pixel.
    expect(_scrollOffset(tester), greaterThan(0));
    expect(amount, findsOneWidget);
    expect(tester.getRect(amount), before);
    // The pinned amount takes the serif step above the review screens'.
    expect(
      tester.widget<Text>(amount).style!.fontSize,
      AppTypography.displayLarge.fontSize,
    );
  });

  // ─── The scroll region ─────────────────────────────────────────────

  testWidgets('an expanded message survives scrolling the region', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesUseCase,
      size: _mobileSize,
    );

    await _tapRow(tester, 'payment_request_memo');
    expect(find.text('Collapse'), findsOneWidget);

    // The scroll used to reparent the region's subtree, which discarded the
    // expansion state along with every other `State` under it.
    await tester.drag(
      find.byKey(kPaymentRequestScrollViewKey),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Collapse'), findsOneWidget);
    // The scroll actually moved, and stayed moved.
    expect(_scrollOffset(tester), greaterThan(0));
  });

  testWidgets('an expanded full address survives scrolling the region', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesUseCase,
      size: _mobileSize,
    );

    await tester.tap(find.text('Show full address'));
    await tester.pumpAndSettle();
    expect(find.text('Hide full address'), findsOneWidget);

    await tester.drag(
      find.byKey(kPaymentRequestScrollViewKey),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hide full address'), findsOneWidget);
  });

  testWidgets('the scrollbar tracks the region it lives in', (tester) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesUseCase,
      size: _mobileSize,
    );

    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(kPaymentRequestScrollbarKey),
    );
    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(kPaymentRequestScrollViewKey),
    );

    expect(tester.takeException(), isNull);
    // One controller, shared: a scrollbar attached to anything else would
    // track a scroll the user is not performing.
    expect(scrollbar.controller, isNotNull);
    expect(identical(scrollbar.controller, scrollView.controller), isTrue);
    // It rides inside the details card, not outside it.
    final region = tester.getRect(find.byKey(kPaymentRequestScrollbarKey));
    final view = tester.getRect(find.byKey(kPaymentRequestScrollViewKey));
    final card = tester.getRect(_transactionDetailsCard());
    expect(region.right, lessThanOrEqualTo(view.right + 0.5));
    expect(region.left, greaterThanOrEqualTo(card.left - 0.5));
    expect(region.right, lessThanOrEqualTo(card.right + 0.5));
    expect(region.top, greaterThanOrEqualTo(card.top - 0.5));
    expect(region.bottom, lessThanOrEqualTo(card.bottom + 0.5));
  });

  testWidgets('the details card is a fixed frame its content scrolls inside', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesExpandedUseCase,
      size: _mobileSize,
    );

    final card = _transactionDetailsCard();
    final before = tester.getRect(card);
    expect(_maxScrollExtent(tester), greaterThan(0));

    await tester.drag(
      find.byKey(kPaymentRequestScrollViewKey),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The content moved; the frame around it did not.
    expect(_scrollOffset(tester), greaterThan(0));
    expect(tester.getRect(card), before);
  });

  testWidgets('short content leaves the frame unscrollable and hugged', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestMinimalUseCase,
      size: _mobileSize,
    );

    expect(tester.takeException(), isNull);
    // Nothing to scroll, and the card takes only the height it needs rather
    // than stretching to the space the sheet could give it.
    expect(_maxScrollExtent(tester), 0);
    final card = tester.getRect(_transactionDetailsCard());
    final status = tester.getRect(_key('payment_request_continue'));
    expect(card.height, lessThan(status.top - card.top));
  });

  testWidgets('default mobile requests fit without scrolling', (tester) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildMobilePaymentRequestFullUseCase, const Size(393, 852)),
      (buildMobilePaymentRequestFullUseCase, const Size(375, 812)),
      (buildMobilePaymentRequestContactUseCase, const Size(393, 852)),
      (buildMobilePaymentRequestContactUseCase, const Size(375, 812)),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull, reason: '$builder at $size');
      expect(_maxScrollExtent(tester), 0, reason: '$builder at $size');
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    }
  });

  // ─── Status ────────────────────────────────────────────────────────

  testWidgets('blocking statuses disable the primary action and say why', (
    tester,
  ) async {
    for (final (builder, message) in <(WidgetBuilder, String)>[
      (
        buildPaymentRequestInvalidAddressUseCase,
        "Recipient address doesn't look right",
      ),
      (
        buildPaymentRequestInsufficientUseCase,
        'Not enough ZEC for this amount and the network fee (0.21 available)',
      ),
      (
        buildPaymentRequestSyncingUseCase,
        'Wallet is still syncing — this will update when it finishes',
      ),
      (
        buildPaymentRequestFailedUseCase,
        "Couldn't check this request — open Edit to review the details",
      ),
    ]) {
      await _pumpUseCase(tester, builder);

      expect(tester.takeException(), isNull, reason: message);
      // Exactly one status line, attached to the details card.
      expect(find.text(message), findsOneWidget, reason: message);
      expect(
        find.byKey(const ValueKey('payment_request_status')),
        findsOneWidget,
        reason: message,
      );
      expect(
        _button(tester, 'payment_request_continue').onPressed,
        isNull,
        reason: message,
      );
    }
  });

  testWidgets('the status line sits below the card, away from the actions', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestInvalidAddressUseCase);

    final status = tester.getRect(
      find.byKey(const ValueKey('payment_request_status')),
    );
    final card = tester.getRect(_transactionDetailsCard());
    final review = tester.getRect(_key('payment_request_continue'));

    expect(tester.takeException(), isNull);
    expect(status.top, greaterThanOrEqualTo(card.bottom - 0.5));
    expect(status.bottom, lessThanOrEqualTo(review.top + 0.5));
    expect(status.top - card.bottom, lessThan(review.top - status.bottom));
  });

  testWidgets('checking is a button state, not a status line', (tester) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestCheckingUseCase, _desktopSize),
      (buildMobilePaymentRequestCheckingUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      // No status line at all while checks run.
      expect(
        find.byKey(const ValueKey('payment_request_status')),
        findsNothing,
      );
      // The primary says it instead, disabled, with the spinner beside it.
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.text('Review'), findsNothing);
      final primary = _button(tester, 'payment_request_continue');
      expect(primary.onPressed, isNull);
      expect(primary.leading, isNotNull);
      // Edit stays reachable while the request is being checked.
      expect(_button(tester, 'payment_request_edit').onPressed, isNotNull);
    }

    expect(
      defaultPaymentRequestStatusMessage(PaymentRequestStatus.checking),
      isNull,
    );
  });

  testWidgets('errors take the destructive tone', (tester) async {
    final colors = AppThemeData.light.colors;

    for (final (builder, message) in <(WidgetBuilder, String)>[
      (
        buildPaymentRequestInvalidAddressUseCase,
        "Recipient address doesn't look right",
      ),
      (
        buildPaymentRequestInsufficientUseCase,
        'Not enough ZEC for this amount and the network fee (0.21 available)',
      ),
      (
        buildPaymentRequestFailedUseCase,
        "Couldn't check this request — open Edit to review the details",
      ),
    ]) {
      await _pumpUseCase(tester, builder);
      expect(
        _statusColor(tester, message),
        colors.text.destructive,
        reason: message,
      );
      expect(
        _statusIcons(tester),
        findsOneWidget,
        reason: 'an error carries the warning glyph: $message',
      );
    }
  });

  testWidgets('syncing is a pending line, not an error', (tester) async {
    final colors = AppThemeData.light.colors;
    const message =
        'Wallet is still syncing — this will update when it '
        'finishes';

    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestSyncingUseCase, _desktopSize),
      (buildMobilePaymentRequestSyncingUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      // The copy promises the card will update itself, so the line stays
      // quiet: secondary text and no warning glyph to act on.
      expect(_statusColor(tester, message), colors.text.secondary);
      expect(_statusIcons(tester), findsNothing);
      // Review still cannot be pressed — that is `blocksContinue`'s job, not
      // the tone's.
      expect(_button(tester, 'payment_request_continue').onPressed, isNull);
    }

    expect(PaymentRequestStatus.syncing.blocksContinue, isTrue);
    expect(PaymentRequestStatus.syncing.isError, isFalse);
  });

  testWidgets('a failed check is its own status, not a bad address', (
    tester,
  ) async {
    expect(
      defaultPaymentRequestStatusMessage(PaymentRequestStatus.failed),
      "Couldn't check this request",
      reason: 'the floor under a reason the pre-check always supplies',
    );
    expect(PaymentRequestStatus.failed.blocksContinue, isTrue);
    expect(PaymentRequestStatus.failed.isError, isTrue);
  });

  testWidgets('an insufficient-funds message without a balance stays short', (
    tester,
  ) async {
    expect(
      defaultPaymentRequestStatusMessage(
        PaymentRequestStatus.insufficientFunds,
      ),
      'Not enough ZEC for this amount and the network fee',
    );
  });

  testWidgets('a ready request renders no status line at all', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('payment_request_status')), findsNothing);
  });

  testWidgets('replaced notice renders above the content', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestReplacedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Replaced an earlier link'), findsOneWidget);
  });

  testWidgets('a transparent recipient is badged as transparent', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestTransparentUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Transparent'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
  });

  testWidgets('a requester note without a name stays collapsed', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestNoteOnlyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Requester'), findsOneWidget);
    expect(find.text('Note from requester'), findsOneWidget);
    expect(_key('payment_request_requester_note'), findsNothing);
    expect(find.text('Transaction memo'), findsNothing);

    await tester.tap(_key('payment_request_requester_toggle'));
    await tester.pumpAndSettle();

    expect(_key('payment_request_requester_note'), findsOneWidget);
    expect(
      tester.widget<Text>(_key('payment_request_requester_note')).data,
      'Saved from the invoice link you opened.',
    );
  });

  testWidgets('a blocked primary action still announces why', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpUseCase(tester, buildPaymentRequestInsufficientUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel(
        'Review, unavailable. Not enough ZEC for this amount and the '
        'network fee (0.21 available)',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('large text and RTL render without overflow', (tester) async {
    for (final builder in <WidgetBuilder>[
      buildPaymentRequestLargeTextUseCase,
      buildPaymentRequestRtlUseCase,
      buildMobilePaymentRequestLargeTextUseCase,
      buildMobilePaymentRequestRtlUseCase,
    ]) {
      await _pumpUseCase(tester, builder, size: const Size(1080, 900));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('collapsed mobile address and pool badge fit at 2x text scale', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: PaymentRequestSurface(
          layout: PaymentRequestLayout.mobile,
          request: const PaymentRequestView(
            source: PaymentRequestSource.link,
            requesterLabel: 'Blue Door Coffee',
            amountZecText: '0.5 ZEC',
            address:
                'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
                '73d57f73c6dc05121591a83861cd190591',
          ),
          onContinue: () {},
          onEdit: () {},
          onCancel: () {},
        ),
      ),
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('u195091 ... 190591')).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('every registered use case renders in its own lane', (
    tester,
  ) async {
    for (final builder in <WidgetBuilder>[
      buildPaymentRequestFullUseCase,
      buildPaymentRequestMinimalUseCase,
      buildPaymentRequestLongValuesUseCase,
      buildPaymentRequestLongValuesExpandedUseCase,
      buildPaymentRequestAddressExpandedUseCase,
      buildPaymentRequestCheckingUseCase,
      buildPaymentRequestInvalidAddressUseCase,
      buildPaymentRequestInsufficientUseCase,
      buildPaymentRequestSyncingUseCase,
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

  testWidgets('mobile use cases render the stacked action layout', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestFullUseCase,
      size: _mobileSize,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<PaymentRequestCard>(find.byType(PaymentRequestCard))
          .isMobileLayout,
      isTrue,
    );
    // The desktop close affordance belongs to the modal card only.
    expect(find.byKey(const ValueKey('payment_request_close')), findsNothing);
    expect(find.text('Review'), findsOneWidget);
    // Refusal is the sheet's own pinned ⨯ (`MobileModalScaffold`), so the
    // action stack carries no ghost Cancel link.
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const ValueKey('payment_request_cancel')), findsNothing);
  });

  testWidgets('the mobile sheet is hosted in the shared modal scaffold', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestFullUseCase,
      size: _mobileSize,
    );

    expect(tester.takeException(), isNull);
    // The app's common bottom-sheet chrome, which owns the pinned close.
    expect(find.byType(MobileModalScaffold), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    // The scaffold sits inside the floating card, which still owns the
    // bottom safe area — the card must not take it a second time.
    expect(find.byType(MobileModalCard), findsOneWidget);
    expect(find.byType(MobileBottomSafeArea), findsNothing);
    // The pinned action stack stays clear of the sheet's bottom edge.
    final actions = tester.getRect(_key('payment_request_edit'));
    final sheet = tester.getRect(find.byType(MobileModalScaffold));
    expect(actions.bottom, lessThanOrEqualTo(sheet.bottom - 8));
  });

  testWidgets('the transaction group spans the mobile action width', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesUseCase,
      size: _mobileSize,
    );

    expect(tester.takeException(), isNull);
    final transaction = tester.getRect(
      _key('payment_request_transaction_content'),
    );
    final actions = tester.getRect(_key('payment_request_continue'));
    expect(
      transaction.left - actions.left,
      moreOrLessEquals(actions.right - transaction.right, epsilon: 0.5),
    );
    expect(transaction.width, moreOrLessEquals(actions.width, epsilon: 0.5));
  });

  // ─── A recipient the wallet can name ───────────────────────────────

  testWidgets('a saved contact takes the To headline, the address drops', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestContactUseCase, _desktopSize),
      (buildMobilePaymentRequestContactUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      // The name is the headline, in the accent colour the address used to
      // take; the address is still on screen underneath it.
      final name = tester.widget<Text>(_key('payment_request_recipient_name'));
      expect(name.data, 'Blue Door Coffee');
      expect(name.style!.fontSize, AppTypography.headlineSmall.fontSize);
      expect(name.style!.color, AppThemeData.light.colors.text.accent);
      expect(find.text('u195091 ... 190591'), findsOneWidget);
      // The avatar is the contact's, not a generic wallet glyph.
      expect(
        tester
            .widget<AppProfilePicture>(_key('payment_request_recipient_avatar'))
            .profilePictureId,
        'pfp-03',
      );
      // A contact is not the user's own account, so nothing claims it is.
      expect(_key('payment_request_own_account_label'), findsNothing);
      expect(find.text('Your account'), findsNothing);
      // Everything the unmapped row carried is still there.
      expect(_key('payment_request_to_row'), findsOneWidget);
      expect(_key('payment_request_pool_badge'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);
      expect(find.text('Show full address'), findsOneWidget);
    }
  });

  testWidgets('an own-account recipient says whose account it is', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestOwnAccountUseCase, _desktopSize),
      (buildMobilePaymentRequestOwnAccountUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Text>(_key('payment_request_recipient_name')).data,
        'Savings',
      );
      expect(
        tester
            .widget<AppProfilePicture>(_key('payment_request_recipient_avatar'))
            .profilePictureId,
        'pfp-07',
      );
      // Sentence case, muted, one line — the card's own label treatment.
      final label = tester.widget<Text>(
        _key('payment_request_own_account_label'),
      );
      expect(label.data, 'Your account');
      expect(label.style!.color, AppThemeData.light.colors.text.secondary);
      expect(find.text('u195091 ... 190591'), findsOneWidget);
      expect(_key('payment_request_pool_badge'), findsOneWidget);
    }
  });

  testWidgets('a named recipient still expands to the full address', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestOwnAccountUseCase, _desktopSize),
      (buildMobilePaymentRequestOwnAccountUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);

      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_key('payment_request_address_chunks'), findsOneWidget);
      expect(find.text('u1950'), findsOneWidget);
      // The name and its sub-label stay; the truncated sub-line does not
      // repeat the address the grid is already showing.
      expect(_key('payment_request_recipient_name'), findsOneWidget);
      expect(_key('payment_request_own_account_label'), findsOneWidget);
      expect(_key('payment_request_recipient_address'), findsNothing);
      // Nothing left the card.
      expect(find.text('Review'), findsOneWidget);

      await tester.tap(find.text('Hide full address'));
      await tester.pumpAndSettle();
      expect(_key('payment_request_recipient_address'), findsOneWidget);
    }
  });

  testWidgets('the expanded own-account use cases render both lanes', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestOwnAccountExpandedUseCase, _desktopSize),
      (buildMobilePaymentRequestOwnAccountExpandedUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);
      expect(tester.takeException(), isNull);
      expect(find.text('Hide full address'), findsOneWidget);
      expect(find.text('u1950'), findsOneWidget);
      expect(find.text('Your account'), findsOneWidget);
    }
  });

  testWidgets('an unmapped recipient keeps the plain address layout', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    expect(_key('payment_request_recipient_name'), findsNothing);
    expect(_key('payment_request_recipient_avatar'), findsNothing);
    expect(find.byType(AppProfilePicture), findsNothing);
    // The address itself is the value, in the accent colour.
    final address = tester.widget<Text>(find.text('u195091 ... 190591'));
    expect(address.style!.color, AppThemeData.light.colors.text.accent);
  });

  // ─── No amount ─────────────────────────────────────────────────────

  testWidgets('an amount-less request renders no hero and edits instead', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestNoAmountUseCase, _desktopSize),
      (buildMobilePaymentRequestNoAmountUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      // No hero, and no placeholder standing in for one.
      expect(_key('payment_request_amount'), findsNothing);
      expect(_key('payment_request_fiat'), findsNothing);
      expect(find.text('Amount not set'), findsNothing);
      // The primary is the edit action; there is no second Edit under it.
      expect(find.text('Enter amount'), findsOneWidget);
      expect(find.text('Review'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(_key('payment_request_edit'), findsNothing);
      expect(_button(tester, 'payment_request_continue').onPressed, isNotNull);
      // The amount slot is omitted inside the transaction group.
      expect(_titleText(tester), 'Payment request');
      expect(_key('payment_request_transaction_content'), findsOneWidget);
    }
  });

  testWidgets('an amount-less request that is blocked still has one live '
      'control', (tester) async {
    await _pumpUseCase(tester, (context) => _noAmountFrame(context));

    expect(tester.takeException(), isNull);
    expect(find.text("Recipient address doesn't look right"), findsOneWidget);
    // The card renders no secondary without an amount, so blocking the
    // primary too would leave the ⨯ as the only exit. The primary is the
    // edit action here, and it is named after what it does.
    expect(_key('payment_request_edit'), findsNothing);
    expect(find.text('Enter amount'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(_button(tester, 'payment_request_continue').onPressed, isNotNull);
  });

  testWidgets('an amount-less request keeps waiting while it is checked', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      (context) => _noAmountFrame(context, PaymentRequestStatus.checking),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Checking…'), findsOneWidget);
    expect(_button(tester, 'payment_request_continue').onPressed, isNull);
  });

  // ─── Actions ───────────────────────────────────────────────────────

  testWidgets('the actions are full-width primary and ghost buttons', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestFullUseCase, _desktopSize),
      (buildMobilePaymentRequestFullUseCase, _mobileSize),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder, size: size);
      expect(tester.takeException(), isNull);

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);

      final review = _button(tester, 'payment_request_continue');
      final edit = _button(tester, 'payment_request_edit');
      expect(review.variant, AppButtonVariant.primary);
      expect(edit.variant, AppButtonVariant.ghost);
      expect(review.expand, isTrue);
      expect(edit.expand, isTrue);

      final reviewRect = tester.getRect(_key('payment_request_continue'));
      final editRect = tester.getRect(_key('payment_request_edit'));
      expect(editRect.width, moreOrLessEquals(reviewRect.width));
      expect(editRect.height, moreOrLessEquals(reviewRect.height));
      expect(editRect.top, greaterThan(reviewRect.bottom));

      // Nothing edits in place any more.
      expect(
        find.byKey(const ValueKey('payment_request_edit_amount')),
        findsNothing,
      );
    }
  });

  testWidgets('the address-expanded state keeps the actions visible', (
    tester,
  ) async {
    for (final builder in <WidgetBuilder>[
      buildPaymentRequestFullUseCase,
      buildPaymentRequestLongValuesUseCase,
    ]) {
      // A fresh tree per style: the address row's expanded state would
      // otherwise survive into the next iteration.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUseCase(tester, builder);
      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Hide full address'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    }
  });
}

/// The amount-less card with a failing pre-check — the one combination no
/// registered use case covers, because the gallery shows the two states
/// separately.
Widget _noAmountFrame(
  BuildContext context, [
  PaymentRequestStatus status = PaymentRequestStatus.invalidAddress,
]) => PaymentRequestSurface(
  layout: PaymentRequestLayout.desktop,
  request: PaymentRequestView(
    source: PaymentRequestSource.link,
    address: 't1PZ4vMuLdt2wRfDGGKS1qXfBpJt5CJHhNz',
    status: status,
  ),
  onContinue: () {},
  onEdit: () {},
  onCancel: () {},
);

const _desktopSize = Size(1080, 720);
const _mobileSize = Size(393, 852);

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _transactionDetailsCard() => find.descendant(
  of: _key('payment_request_transaction_content'),
  matching: find.byType(ReviewWrapCard),
);

/// Taps the value pill of a `ReviewListRow`-shaped row. The label itself is
/// not the tap target — the review's rows put the gesture on the pill.
Future<void> _tapRow(WidgetTester tester, String rowKey) async {
  await tester.tap(
    find
        .descendant(
          of: find.byKey(ValueKey(rowKey)),
          matching: find.byType(GestureDetector),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

AppButton _button(WidgetTester tester, String key) =>
    tester.widget<AppButton>(_key(key));

String _titleText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('payment_request_title')))
    .data!;

Color? _statusColor(WidgetTester tester, String message) =>
    tester.widget<Text>(find.text(message)).style?.color;

/// Glyphs inside the one status slot — the warning badge, when there is one.
Finder _statusIcons(WidgetTester tester) => find.descendant(
  of: find.byKey(const ValueKey('payment_request_status')),
  matching: find.byType(AppIcon),
);

double _scrollOffset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(kPaymentRequestScrollViewKey))
    .controller!
    .offset;

double _maxScrollExtent(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(kPaymentRequestScrollViewKey))
    .controller!
    .position
    .maxScrollExtent;

double _requesterNoteScrollOffset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
      find.byKey(kPaymentRequestRequesterNoteScrollViewKey),
    )
    .controller!
    .offset;

double _requesterNoteMaxScrollExtent(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
      find.byKey(kPaymentRequestRequesterNoteScrollViewKey),
    )
    .controller!
    .position
    .maxScrollExtent;

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
