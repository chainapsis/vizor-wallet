import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/features/activity/screens/swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';

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

  for (final layout in WbLayout.values) {
    for (final fixture in [
      SwapComposerFixture.maxAmountFailed,
      SwapComposerFixture.fiatValueInput,
    ]) {
      testWidgets(
        '${layout.name} Swap Max replaces ${fixture.name} without host services',
        (tester) async {
          await pumpUseCase(
            tester,
            buildSwapScreenGalleryCase,
            knobs: {
              'Layout': wbLayoutLabel(layout),
              'State': swapComposerFixtureLabel(fixture),
            },
            theme: AppThemeData.light,
          );
          await tester.pumpAndSettle();
          final field = find.byKey(const ValueKey('swap_amount_field'));
          final container = ProviderScope.containerOf(
            tester.element(field),
            listen: false,
          );
          if (fixture == SwapComposerFixture.fiatValueInput) {
            // This fixture starts external-to-ZEC. Max must ignore that side.
            final before = container.read(swapStateProvider);
            await container.read(swapStateProvider.notifier).useMaxZecAmount();
            expect(container.read(swapStateProvider), same(before));
            await tester.tap(
              find.byKey(const ValueKey('swap_direction_zecToExternal')),
            );
            container.read(swapStateProvider.notifier).updateAmountFiat('1');
            await tester.pumpAndSettle();
          }
          for (var attempt = 0; attempt < 2; attempt++) {
            await tester.tap(
              find.byKey(const ValueKey('swap_max_amount_button')),
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<EditableText>(
                    find.descendant(
                      of: field,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              '12.3455',
            );
            final state = container.read(swapStateProvider);
            expect(state.amountText, '12.3455');
            expect(state.quoteMode, SwapQuoteMode.exactInput);
            expect(state.amountInputMode, SwapAmountInputMode.token);
            expect(state.maxAmountError, isNull);
            expect(state.maxAmountLoading, isFalse);
            expect(state.receiveAmountText, isNotEmpty);
            expect(state.reviewVisible, isFalse);
            expect(rust.calls, isEmpty);
            expect(storageCalls, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.enterText(field, '1');
            await tester.pumpAndSettle();
          }
          await disposeTree(tester);
        },
      );
    }
  }

  testWidgets('Swap screen carries input through review and result', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.25',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '0x1111111111111111111111111111111111111111',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    await captureFlowState(tester, 'swap.review.desktop');
    await tester.tap(find.text('Confirm swap'));
    await tester.pumpAndSettle();
    expect(find.byType(SwapActivityDetailScreen), findsOneWidget);
    await captureFlowState(tester, 'swap.result.desktop');
  });

  testWidgets('Swap review back retains composer input', (tester) async {
    await pumpUseCase(
      tester,
      buildSwapScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '0x1111111111111111111111111111111111111111',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppBackLink));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('swap_destination_value')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Swap saves modal choices and submits without real services', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSwapScreenGalleryCase,
      theme: AppThemeData.light,
    );
    await tester.tap(
      find.byKey(const ValueKey('swap_external_asset_selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('swap_asset_row_${SwapAsset.eth.identityKey}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_settings_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_slippage_100bps')));
    await tester.tap(find.byKey(const ValueKey('swap_slippage_update_button')));
    await tester.pumpAndSettle();
    expect(find.text('1%'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('swap_amount_field')),
      '1.25',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_summary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '0x1111111111111111111111111111111111111111',
    );
    await tester.tap(find.byKey(const ValueKey('swap_address_update_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swap_review_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('swap_review_panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swap_start_button')));
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
