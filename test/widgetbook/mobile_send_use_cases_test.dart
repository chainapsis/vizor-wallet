@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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
    expect(amountInput.decoration?.hintText, '0');
    expect(
      amountInput.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(amountInput.cursorWidth, 3);
    expect(amountInput.cursorHeight, 48);
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

  testWidgets('mobile send amount error use case renders visual error state', (
    tester,
  ) async {
    await _pumpMobileSendUseCase(tester, buildMobileSendAmountErrorUseCase);

    expect(tester.takeException(), isNull);
    expect(find.text('243.12'), findsOneWidget);
    expect(find.text('Not enough ZEC'), findsNothing);
    expect(find.text('Enter amount to continue'), findsOneWidget);
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

Future<void> _pumpMobileSendUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}
