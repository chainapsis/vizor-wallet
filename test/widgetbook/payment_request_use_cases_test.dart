import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_safe_area.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_profile_picture.dart';
import 'package:zcash_wallet/src/core/widgets/app_tooltip.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/core/widgets/review_wrap_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/widgetbook/payment_request_use_cases.dart';

void main() {
  testWidgets('full use case renders the whole request', (tester) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Payment request'), findsOneWidget);
    // One muted line under the title names the requester, nothing else.
    expect(find.text('Requested by Blue Door Coffee'), findsOneWidget);
    expect(find.textContaining('From a link'), findsNothing);
    expect(find.text('0.5 ZEC'), findsOneWidget);
    expect(find.text('u195091 ... 190591'), findsOneWidget);
    expect(find.text('Show full address'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    // The memo row is labelled the way the composer and the review label it.
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Memo'), findsNothing);
    expect(find.text('Note'), findsOneWidget);
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
      // No ⓘ beside the requester, the message or the note: the labels
      // carry the meaning on their own.
      expect(find.byType(AppTooltip), findsNothing);
      expect(find.bySemanticsLabel('About this name'), findsNothing);
    }
  });

  testWidgets('the header keeps one title and one requester line', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildPaymentRequestFullUseCase, _desktopSize),
      (buildMobilePaymentRequestFullUseCase, _mobileSize),
    ]) {
      await _pumpUseCase(tester, builder, size: size);

      expect(tester.takeException(), isNull);
      expect(_titleText(tester), 'Payment request');
      expect(
        find.byKey(const ValueKey('payment_request_requester')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payment_request_eyebrow')),
        findsNothing,
      );
    }
  });

  testWidgets('the request rows use the send review row treatment', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestFullUseCase);

    expect(tester.takeException(), isNull);
    // The details block is the review's wrap card, with the review's
    // hairline between the To / Message / Note groups.
    expect(find.byType(ReviewWrapCard), findsOneWidget);
    expect(find.byType(ReviewWrapDivider), findsNWidgets(2));
    // Message and Note are the review's label-beside-value list rows; "To"
    // stays label-above-value, as the review's own To row is.
    expect(find.byType(ReviewListRow), findsNWidgets(2));

    final labelStyle = AppTypography.bodyMediumStrong;
    for (final label in const ['To', 'Message', 'Note']) {
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

  testWidgets('minimal use case omits the requester, message and note rows', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestMinimalUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Blue Door Coffee'), findsNothing);
    // No label, no line at all.
    expect(
      find.byKey(const ValueKey('payment_request_requester')),
      findsNothing,
    );
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
    final card = tester.getRect(find.byType(ReviewWrapCard));
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

    final card = find.byType(ReviewWrapCard);
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
    final card = tester.getRect(find.byType(ReviewWrapCard));
    final status = tester.getRect(_key('payment_request_continue'));
    expect(card.height, lessThan(status.top - card.top));
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
        'Not enough ZEC (0.21 available)',
      ),
      (
        buildPaymentRequestSyncingUseCase,
        'Wallet is still syncing — try again soon',
      ),
      (
        buildPaymentRequestFailedUseCase,
        "Couldn't check this request — open Edit to review the details",
      ),
    ]) {
      await _pumpUseCase(tester, builder);

      expect(tester.takeException(), isNull, reason: message);
      // Exactly one status line, in the one slot above the actions.
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

  testWidgets('the status line sits between the details and the actions', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestInvalidAddressUseCase);

    final status = tester.getRect(
      find.byKey(const ValueKey('payment_request_status')),
    );
    final card = tester.getRect(find.byType(ReviewWrapCard));
    final review = tester.getRect(_key('payment_request_continue'));

    expect(tester.takeException(), isNull);
    expect(status.top, greaterThanOrEqualTo(card.bottom - 0.5));
    expect(status.bottom, lessThanOrEqualTo(review.top + 0.5));
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
        'Not enough ZEC (0.21 available)',
      ),
      (
        buildPaymentRequestSyncingUseCase,
        'Wallet is still syncing — try again soon',
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
    }
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
      'Not enough ZEC',
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

  testWidgets('a note without a message renders only the note row', (
    tester,
  ) async {
    await _pumpUseCase(tester, buildPaymentRequestNoteOnlyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.byType(ReviewWrapDivider), findsOneWidget);
  });

  testWidgets('a blocked primary action still announces why', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpUseCase(tester, buildPaymentRequestInsufficientUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel(
        'Review, unavailable. Not enough ZEC (0.21 available)',
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

  testWidgets('the details card spans the full mobile content width', (
    tester,
  ) async {
    await _pumpUseCase(
      tester,
      buildMobilePaymentRequestLongValuesUseCase,
      size: _mobileSize,
    );

    expect(tester.takeException(), isNull);
    // The scroll region reserves no trailing gutter, so the wrap card sits
    // the same distance from both edges of the sheet content.
    final wrap = tester.getRect(find.byType(ReviewWrapCard));
    final actions = tester.getRect(_key('payment_request_continue'));
    expect(
      wrap.left - actions.left,
      moreOrLessEquals(actions.right - wrap.right, epsilon: 0.5),
    );
    expect(wrap.width, moreOrLessEquals(actions.width, epsilon: 0.5));
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
      // The title flows straight into the details card.
      expect(_titleText(tester), 'Payment request');
      expect(find.byType(ReviewWrapCard), findsOneWidget);
    }
  });

  testWidgets('an amount-less request still shows a blocking error', (
    tester,
  ) async {
    await _pumpUseCase(tester, (context) => _noAmountFrame(context));

    expect(tester.takeException(), isNull);
    expect(find.text("Recipient address doesn't look right"), findsOneWidget);
    expect(find.text('Enter amount'), findsOneWidget);
    expect(_button(tester, 'payment_request_continue').onPressed, isNull);
  });

  // ─── Actions ───────────────────────────────────────────────────────

  testWidgets('the actions are one full-width primary over a full-width Edit', (
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
      expect(edit.variant, AppButtonVariant.secondary);
      expect(review.expand, isTrue);
      expect(edit.expand, isTrue);

      // Same size and shape, Edit under Review, 8px apart.
      final reviewRect = tester.getRect(_key('payment_request_continue'));
      final editRect = tester.getRect(_key('payment_request_edit'));
      expect(editRect.width, moreOrLessEquals(reviewRect.width, epsilon: 0.5));
      expect(
        editRect.height,
        moreOrLessEquals(reviewRect.height, epsilon: 0.5),
      );
      expect(
        editRect.top - reviewRect.bottom,
        moreOrLessEquals(8, epsilon: 0.5),
      );

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
Widget _noAmountFrame(BuildContext context) => PaymentRequestSurface(
  layout: PaymentRequestLayout.desktop,
  request: const PaymentRequestView(
    source: PaymentRequestSource.link,
    address: 't1PZ4vMuLdt2wRfDGGKS1qXfBpJt5CJHhNz',
    status: PaymentRequestStatus.invalidAddress,
  ),
  onContinue: () {},
  onEdit: () {},
  onCancel: () {},
);

const _desktopSize = Size(1080, 720);
const _mobileSize = Size(393, 852);

Finder _key(String value) => find.byKey(ValueKey(value));

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

double _scrollOffset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(kPaymentRequestScrollViewKey))
    .controller!
    .offset;

double _maxScrollExtent(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(kPaymentRequestScrollViewKey))
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
