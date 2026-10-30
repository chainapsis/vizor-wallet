@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_connection_help.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_help_navigation.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Finder _body() => find.descendant(
  of: find.byType(MobileLedgerSheetContent),
  matching: find.byType(SingleChildScrollView),
);

ScrollableState _scroll(WidgetTester tester) => tester.state<ScrollableState>(
  find.descendant(of: _body(), matching: find.byType(Scrollable)),
);

void _expectTop(WidgetTester tester, String firstInstruction) {
  expect(_scroll(tester).position.pixels, 0);
  final viewport = tester.getRect(_body());
  final instruction = tester.getRect(find.text(firstInstruction));
  expect(instruction.top, greaterThanOrEqualTo(viewport.top));
  expect(instruction.top, lessThan(viewport.bottom));
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  final position = _scroll(tester).position;
  expect(position.maxScrollExtent, greaterThan(0));
  position.jumpTo(position.maxScrollExtent);
  await _frames(tester);
  expect(position.pixels, greaterThan(0));
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final inline in [false, true]) {
      testWidgets(
        'help starts each step at the top ($platform, inline: $inline)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await loadFigmaCompareFonts();
          final navigation = MobileLedgerHelpNavigation();
          var closes = 0;
          var searches = 0;
          var showError = false;
          late StateSetter updateHost;
          await tester.pumpWidget(
            MaterialApp(
              home: AppTheme(
                data: AppThemeData.light,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(2)),
                    child: StatefulBuilder(
                      builder: (context, update) {
                        updateHost = update;
                        final help = MobileLedgerConnectionHelp(
                          platform: platform,
                          initialModel: LedgerHelpModel.nanoX,
                          onBack: () => closes++,
                          onClose: () => closes++,
                          onSearch: () => searches++,
                          onSettings: () {},
                          error: showError ? 'Settings are unavailable.' : null,
                        );
                        return inline
                            ? MobileLedgerHelpScope(
                                navigation: navigation,
                                child: MobileShieldScene(
                                  phase: MobileShieldPhase.hardware,
                                  amount: '1',
                                  title: 'Shield with Ledger',
                                  animateHardware: true,
                                  onClose: () => closes++,
                                  onPrevious: () {
                                    if (!navigation.previous()) closes++;
                                  },
                                  focusChild: LedgerInlinePresentation(
                                    child: help,
                                  ),
                                ),
                              )
                            : MobileLedgerSigningSurface(
                                canLeave: true,
                                onBack: () => closes++,
                                child: help,
                              );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await _frames(tester);
          if (inline) await tester.pump(const Duration(seconds: 4));
          final helpState = tester.state(
            find.byType(MobileLedgerConnectionHelp),
          );
          const checks =
              'Unlock Ledger, turn on Bluetooth, and keep it close to your phone.';
          _expectTop(tester, checks);

          Future<void> next(String label, String firstInstruction) async {
            await _scrollToBottom(tester);
            await tester.tap(find.text(label));
            await _frames(tester);
            _expectTop(tester, firstInstruction);
          }

          await next('Reset Bluetooth pairing', 'Step 1 of 3 · On your Ledger');
          await _scrollToBottom(tester);
          final sameStepScroll = _scroll(tester);
          final sameStepOffset = sameStepScroll.position.pixels;
          updateHost(() => showError = true);
          await _frames(tester);
          expect(_scroll(tester), same(sameStepScroll));
          expect(_scroll(tester).position.pixels, sameStepOffset);

          await next('Next: phone settings', 'Step 2 of 3 · On your phone');
          await next('Next: search in Vizor', 'Step 3 of 3 · Back in Vizor');
          for (final firstInstruction in [
            'Step 2 of 3 · On your phone',
            'Step 1 of 3 · On your Ledger',
            checks,
          ]) {
            await _scrollToBottom(tester);
            await tester.binding.handlePopRoute();
            await _frames(tester);
            _expectTop(tester, firstInstruction);
          }
          await next('Reset Bluetooth pairing', 'Step 1 of 3 · On your Ledger');
          expect(
            tester
                .widget<DropdownButton<LedgerHelpModel>>(
                  find.byType(DropdownButton<LedgerHelpModel>),
                )
                .value,
            LedgerHelpModel.nanoX,
          );
          expect(
            tester.state(find.byType(MobileLedgerConnectionHelp)),
            same(helpState),
          );
          expect(closes, 0);
          expect(searches, 0);
          if (inline) {
            await tester.tap(find.text('Cancel shielding'));
          } else {
            await tester.tap(find.bySemanticsLabel('Close'));
          }
          expect(closes, 1);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }
}
