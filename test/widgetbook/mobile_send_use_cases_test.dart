@Tags(['mobile'])
library;

import 'package:flutter/material.dart'
    show MaterialApp, TargetPlatform, TextField, ThemeData;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/widgetbook/send_use_cases.dart';

void main() {
  testWidgets('mobile send recipient empty use case renders send screen', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendRecipientEmptyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.byType(MobileSendScreen), findsOneWidget);
    expect(find.text('Select Recipient'), findsOneWidget);
    expect(find.text('Zcash Address'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Scan a QR Code'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_send_recipient_focus_scrim')),
      findsNothing,
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_address_field'))),
      const Size(361, 60),
    );
    expect(
      find.byKey(const ValueKey('mobile_send_address_action_slot')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_scan_row'))).height,
      44,
    );
    final scanRowFinder = find.byKey(const ValueKey('mobile_send_scan_row'));
    final scanIconFrameFinder = find.byKey(
      const ValueKey('mobile_send_scan_icon_frame'),
    );
    expect(
      tester.getSize(scanIconFrameFinder),
      const Size(AppAssetSizeMobile.size, AppAssetSizeMobile.size),
    );
    final scanIconFinder = find.descendant(
      of: scanIconFrameFinder,
      matching: find.byType(AppIcon),
    );
    final scanIcon = tester.widget<AppIcon>(scanIconFinder);
    expect(scanIcon.size, AppAssetSizeMobile.icon);
    final scanIconDecoration =
        tester.widget<Container>(scanIconFrameFinder).decoration!
            as BoxDecoration;
    expect(
      scanIconDecoration.borderRadius,
      BorderRadius.circular(AppRadii.full),
    );
    expect(
      tester.getTopLeft(scanIconFrameFinder).dx -
          tester.getTopLeft(scanRowFinder).dx,
      AppAssetSizeMobile.padding,
    );
    expect(
      tester.getTopLeft(find.text('Scan a QR Code')).dx -
          tester.getTopRight(scanIconFrameFinder).dx,
      AppSpacing.s,
    );
    _expectVerticalGap(
      tester,
      topKey: const ValueKey('mobile_send_address_field'),
      bottomKey: const ValueKey('mobile_send_scan_row'),
      gap: 45,
    );
  });

  testWidgets(
    'mobile send recipient focused use case renders focus affordance',
    (tester) async {
      await _pumpMobileSendUseCase(
        tester,
        buildMobileSendRecipientFocusedUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Enter address to continue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_send_recipient_focus_scrim')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('mobile_send_address_field'))),
        const Size(361, 60),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('mobile_send_address_action_slot')),
            )
            .width,
        96,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('mobile_send_address_paste'))),
        const Size(76, 36),
      );
      _expectLabelM(tester, 'Paste');
    },
  );

  testWidgets('mobile send recipient contacts use case renders contact list', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendRecipientContactsUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('6 contacts'), findsOneWidget);
    expect(find.text('Contact label'), findsNWidgets(6));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_send_contact_contact-label-1')),
          )
          .height,
      44,
    );
  });

  testWidgets('mobile send recipient filled use case renders clear state', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendRecipientFilledUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_send_address_action_slot')),
      findsNothing,
    );
  });

  testWidgets('mobile send amount empty use case renders disabled CTA', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountEmptyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Enter Amount'), findsOneWidget);
    expect(find.text('Enter amount to continue'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_send_amount_field')))
          .height,
      164,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_send_amount_top_content')),
      ),
      const Size(361, 285),
    );
    expect(
      tester.getTopLeft(
        find.byKey(const ValueKey('mobile_send_amount_top_content')),
      ),
      const Offset(16, 88),
    );
    final amountInput = tester.widget<TextField>(
      find.byKey(const ValueKey('mobile_send_amount_input')),
    );
    expect(amountInput.decoration?.hintText, isNull);
    final zecHintPadding = amountInput.decoration?.hint as Padding?;
    expect(zecHintPadding, isA<Padding>());
    expect(zecHintPadding!.padding, const EdgeInsetsDirectional.only(end: 3.7));
    expect(amountInput.showCursor, isFalse);
    expect(
      find.byKey(const ValueKey('mobile_send_amount_empty_cursor')),
      findsOneWidget,
    );
    expect(
      amountInput.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_send_amount_recipient_block')),
      ),
      const Size(361, 97),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_send_amount_recipient_row')),
          )
          .height,
      68,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_button'))),
      const Size(361, 50),
    );
    expect(
      find.byKey(const ValueKey('mobile_send_amount_keypad')),
      findsNothing,
    );
    _expectVerticalGap(
      tester,
      topKey: const ValueKey('mobile_send_amount_field'),
      bottomKey: const ValueKey('mobile_send_amount_recipient_block'),
      gap: AppSpacing.md,
    );
  });

  testWidgets('mobile send amount empty cursor matches typed native cursor', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendAmountEmptyUseCase,
      devicePixelRatio: 3,
    );

    final inputFinder = find.byKey(const ValueKey('mobile_send_amount_input'));
    final emptyCursorFinder = find.byKey(
      const ValueKey('mobile_send_amount_empty_cursor'),
    );
    final emptyCursorRect = tester.getRect(emptyCursorFinder);

    await tester.enterText(inputFinder, '0');
    await tester.pump();

    expect(emptyCursorFinder, findsNothing);
    final editable = _findRenderEditable(
      tester.renderObject(find.byType(EditableText)),
    );
    final typedCursorRect = _globalCaretRect(editable, 1);
    expect(emptyCursorRect.center.dx, closeTo(typedCursorRect.center.dx, 0.75));
  });

  testWidgets('mobile send amount empty cursor blinks on Android cadence', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendAmountEmptyUseCase,
      platform: TargetPlatform.android,
      settleDuration: Duration.zero,
    );

    expect(_emptyCursorOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 499));
    expect(_emptyCursorOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 1));
    expect(_emptyCursorOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 500));
    expect(_emptyCursorOpacity(tester), 1);
  });

  testWidgets('mobile send amount empty cursor uses iOS opacity keyframes', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendAmountEmptyUseCase,
      platform: TargetPlatform.iOS,
      settleDuration: Duration.zero,
    );

    expect(_emptyCursorOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 650));
    expect(_emptyCursorOpacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 200));
    expect(_emptyCursorOpacity(tester), 0);

    await tester.pump(const Duration(microseconds: 37500));
    expect(_emptyCursorOpacity(tester), 0.25);

    await tester.pump(const Duration(microseconds: 112500));
    expect(_emptyCursorOpacity(tester), 1);
  });

  testWidgets('mobile send amount empty cursor does not shift amount layout', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountEmptyUseCase);

    final inputFinder = find.byKey(const ValueKey('mobile_send_amount_input'));
    final zecFinder = find.text('ZEC');
    final emptyInputRect = tester.getRect(inputFinder);
    final emptyZecRect = tester.getRect(zecFinder);

    await tester.enterText(inputFinder, '0');
    await tester.pump();

    expect(tester.getRect(inputFinder), _closeRect(emptyInputRect));
    expect(tester.getRect(zecFinder), _closeRect(emptyZecRect));
  });

  testWidgets('mobile send amount input expands for full precision ZEC', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountEmptyUseCase);

    final inputFinder = find.byKey(const ValueKey('mobile_send_amount_input'));
    await tester.enterText(inputFinder, '0.04903463');
    await tester.pump();

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('mobile_send_amount_field')),
    );
    final inputRect = tester.getRect(inputFinder);
    final zecRect = tester.getRect(find.text('ZEC'));

    expect(inputRect.width, greaterThan(220));
    expect(inputRect.left, greaterThanOrEqualTo(fieldRect.left - 0.01));
    expect(zecRect.right, lessThanOrEqualTo(fieldRect.right + 0.01));
  });

  testWidgets('mobile send amount measurement honors text scaler', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendAmountEmptyUseCase,
      textScaler: const TextScaler.linear(1.5),
    );

    final inputFinder = find.byKey(const ValueKey('mobile_send_amount_input'));
    await tester.enterText(inputFinder, '0.04903463');
    await tester.pump();

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('mobile_send_amount_field')),
    );
    final inputRect = tester.getRect(inputFinder);
    final zecRect = tester.getRect(find.text('ZEC'));

    expect(inputRect.left, greaterThanOrEqualTo(fieldRect.left - 0.01));
    expect(zecRect.right, lessThanOrEqualTo(fieldRect.right + 0.01));
    expect(inputRect.right, lessThanOrEqualTo(zecRect.left - AppSpacing.xs));
  });

  testWidgets('mobile send amount error use case renders CTA error state', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountErrorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('243.12'), findsOneWidget);
    expect(find.text('Not enough ZEC'), findsOneWidget);
    expect(find.text('Enter amount to continue'), findsNothing);
  });

  testWidgets('mobile send amount ready use case renders review CTA', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountReadyUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('24.312'), findsOneWidget);
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets('mobile send amount USD use case renders USD input mode', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountUsdUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text(r'$'), findsOneWidget);
    expect(find.text('120.12'), findsOneWidget);
    expect(find.text('12 ZEC'), findsOneWidget);
    expect(find.text('Finish & review'), findsOneWidget);
  });

  testWidgets('mobile send review default use case matches review layout', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendReviewDefaultUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Review Send'), findsOneWidget);
    expect(find.text('123.12 ZEC'), findsOneWidget);
    expect(find.text('Contact label'), findsOneWidget);
    expect(find.text('u1tvg24 .... 23hhq6d'), findsOneWidget);
    expect(find.text('Add short encrypted message'), findsOneWidget);
    expect(find.text('Confirm & Send'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_info'))),
      const Size(361, 268),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_wrap'))),
      const Size(361, 161),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_buttons'))),
      const Size(361, 112),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('mobile_send_review_recipient_picture')),
          )
          .height,
      40,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_full_address'))),
      isA<Size>().having((size) => size.height, 'height', 24),
    );
  });

  testWidgets('mobile send review with memo use case renders memo row', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendReviewWithMemoUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Message'), findsOneWidget);
    expect(find.textContaining('Zcash is a privacy-focused'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_review_wrap'))),
      const Size(361, 161),
    );
  });

  testWidgets('mobile send QR scan use case renders scanner card', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendQrScanUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Scan a Zcash QR code to continue'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_qr_scan_card'))),
      const Size(361, 694),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mobile_send_qr_scan_card'))),
      const Offset(16, 126),
    );
  });

  testWidgets('mobile send QR scan widgetbook exposes scanner states', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendQrScanLoadingUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('Loading...'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_send_qr_scan_card'))),
      const Size(361, 694),
    );

    await _pumpMobileSendUseCase(
      tester,
      buildMobileSendQrScanRequestingUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Grant access to your camera'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_address_scan_permission_card')),
      findsOneWidget,
    );

    await _pumpMobileSendUseCase(tester, buildMobileSendQrScanDeniedUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text("You've denied camera access"), findsOneWidget);
    expect(find.text('Request again'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}

void _expectLabelM(WidgetTester tester, String text) {
  final label = tester.widget<Text>(find.text(text));
  expect(label.style?.fontSize, AppTypography.labelLarge.fontSize);
  expect(label.style?.height, AppTypography.labelLarge.height);
  expect(label.style?.fontWeight, AppTypography.labelLarge.fontWeight);
}

void _expectVerticalGap(
  WidgetTester tester, {
  required ValueKey<String> topKey,
  required ValueKey<String> bottomKey,
  required double gap,
}) {
  final topRect = _rectForKey(tester, topKey);
  final bottomRect = _rectForKey(tester, bottomKey);
  expect(bottomRect.top - topRect.bottom, closeTo(gap, 0.01));
}

Rect _rectForKey(WidgetTester tester, ValueKey<String> key) {
  final finder = find.byKey(key);
  return tester.getRect(finder);
}

Matcher _closeRect(Rect expected) {
  return isA<Rect>()
      .having((rect) => rect.left, 'left', closeTo(expected.left, 0.01))
      .having((rect) => rect.top, 'top', closeTo(expected.top, 0.01))
      .having((rect) => rect.width, 'width', closeTo(expected.width, 0.01))
      .having((rect) => rect.height, 'height', closeTo(expected.height, 0.01));
}

Future<void> _pumpMobileSendUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  double devicePixelRatio = 1,
  TargetPlatform? platform,
  TextScaler? textScaler,
  Duration settleDuration = const Duration(milliseconds: 600),
}) async {
  tester.view.physicalSize = Size(
    393 * devicePixelRatio,
    852 * devicePixelRatio,
  );
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      builder: (context, child) {
        if (textScaler == null) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  if (settleDuration > Duration.zero) {
    await tester.pump(settleDuration);
  }
}

double _emptyCursorOpacity(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.byKey(const ValueKey('mobile_send_amount_empty_cursor')),
      )
      .opacity;
}

Rect _globalCaretRect(RenderEditable editable, int offset) {
  final caretLocal = editable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  return editable.localToGlobal(caretLocal.topLeft) & caretLocal.size;
}

RenderEditable _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= _findRenderEditable(child);
  });
  return found!;
}
