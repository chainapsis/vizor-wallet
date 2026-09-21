@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_address_verify_sheet.dart';

import '../../../figma_compare/figma_compare_font_loader.dart';

void main() {
  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      testWidgets(
        'address sheet keeps actions reachable: dark=$dark compact=$compact',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = compact
              ? const Size(320, 568)
              : const Size(393, 852);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await loadFigmaCompareFonts();
          final address = compact
              ? 'u1${List.filled(211, 'q').join()}'
              : 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';
          final copied = <String>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied.add((call.arguments as Map)['text'] as String);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => AppTheme(
                data: dark ? AppThemeData.dark : AppThemeData.light,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(compact ? 2 : 1)),
                  child: child!,
                ),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showMobileAddressVerifySheet(
                      context,
                      title: 'A long saved contact name for the address',
                      address: '  $address\n',
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(address), findsOneWidget);
          final copy = find.byKey(const ValueKey('full_address_copy_button'));
          expect(copy.hitTestable(), findsOneWidget);
          expect(find.text('Cancel'), findsNothing);
          expect(find.bySemanticsLabel('Close').hitTestable(), findsOneWidget);
          if (compact) {
            final scrollable = find.descendant(
              of: find.byType(MobileAddressVerifySheet),
              matching: find.byType(Scrollable),
            );
            final state = tester.state<ScrollableState>(scrollable);
            expect(state.position.maxScrollExtent, greaterThan(0));
            await tester.drag(scrollable, const Offset(0, -200));
            await tester.pumpAndSettle();
            expect(state.position.pixels, greaterThan(0));
          }
          await tester.tap(copy);
          await tester.pump();
          expect(copied, [address]);
          expect(find.byType(MobileAddressVerifySheet), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Close'));
          await tester.pumpAndSettle();
          expect(find.byType(MobileAddressVerifySheet), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
