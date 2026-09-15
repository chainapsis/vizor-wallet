import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/pay/widgets/pay_review_step.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';

import 'playgrounds/flow_capture.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpFlowCaptures();
  final rust = _UnexpectedRustCalls();
  final storageCalls = <String>[];

  setUpAll(() => RustLib.initMock(api: rust));

  setUp(() {
    rust.calls.clear();
    storageCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (call) async {
          storageCalls.add(call.method);
          throw PlatformException(code: 'unexpected_widgetbook_storage_access');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  testWidgets('Pay screen carries amount and recipient to simulated result', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildPayScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.enterText(
      find.byKey(const ValueKey('pay_amount_input')),
      '25',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_amount_continue_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('pay_recipient_search_field')),
        matching: find.byType(EditableText),
      ),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_select_recipient_button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PayReviewStep>(find.byType(PayReviewStep))
          .quote
          .receiveAmount,
      25,
    );
    await captureFlowState(tester, 'pay.review.desktop');
    await tester.tap(find.byKey(const ValueKey('pay_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.byType(SwapActivityDetailScreen), findsOneWidget);
    await captureFlowState(tester, 'pay.result.desktop');
  });

  testWidgets('Pay screen back retains entered amount', (tester) async {
    await pumpUseCase(
      tester,
      buildPayScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.enterText(
      find.byKey(const ValueKey('pay_amount_input')),
      '12',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_amount_continue_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay_recipient_step')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pay_wizard_step_back_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay_amount_input')), findsOneWidget);
    expect(
      find
          .byType(EditableText)
          .evaluate()
          .map((element) => (element.widget as EditableText).controller.text),
      contains('12'),
    );
  });

  testWidgets('Pay saves modal choices and submits without real services', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildPayScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.tap(find.byKey(const ValueKey('pay_asset_selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('swap_asset_row_${SwapAsset.usdc.identityKey}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_slippage_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('1%'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('pay_amount_input')),
      '25',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_amount_continue_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay_recipient_step')), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('pay_recipient_search_field')),
        matching: find.byType(EditableText),
      ),
      '0x1111111111111111111111111111111111111111',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay_select_recipient_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SwapActivityDetailScreen), findsOneWidget);
    expect(storageCalls, isEmpty);
    expect(rust.calls, isEmpty);
  });
}

const _storageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _UnexpectedRustCalls implements RustLibApi {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError(
      'Widgetbook flow tried to call Rust: ${invocation.memberName}',
    );
  }
}
