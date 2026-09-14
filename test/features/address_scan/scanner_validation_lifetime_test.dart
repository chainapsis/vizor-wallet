import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/address_qr_scan_modal.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

Widget host(Widget child) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.dark,
    child: Scaffold(
      body: Center(child: SizedBox(width: 361, child: child)),
    ),
  ),
);

void main() {
  for (final desktop in [false, true]) {
    final name = desktop ? 'desktop' : 'mobile card';
    Future<void> scan(WidgetTester tester, String value) async {
      tester
          .widget<PlainQrScannerView>(
            find.byType(PlainQrScannerView, skipOffstage: false),
          )
          .onComplete(value);
      await tester.pump();
    }

    Widget scanner({
      required Object context,
      required MobileScanResolver resolve,
      required ValueChanged<String> accepted,
      required VoidCallback close,
    }) => desktop
        ? AddressQrScanModal(
            validationContext: context,
            resolve: resolve,
            onAddressScanned: accepted,
            onCancel: close,
          )
        : MobileAddressScanCard(
            validationContext: context,
            resolve: resolve,
            onScanned: accepted,
            onClose: close,
          );

    testWidgets('$name ignores late success after close before disposal', (
      tester,
    ) async {
      final pending = Completer<MobileScanOutcome>();
      final values = <String>[];
      var closed = false;
      await tester.pumpWidget(
        host(
          scanner(
            context: 1,
            resolve: (_) => pending.future,
            accepted: values.add,
            close: () => closed = true,
          ),
        ),
      );
      await scan(tester, 'first');
      if (desktop) {
        tester
            .widget<AddressQrScanModalContent>(
              find.byType(AddressQrScanModalContent),
            )
            .onCancel();
      } else {
        tester
            .widget<MobileQrScanCard>(find.byType(MobileQrScanCard))
            .onClose();
      }
      expect(closed, isTrue);
      pending.complete(const MobileScanOutcome.accepted('late'));
      await tester.pump();
      expect(values, isEmpty);
      // Parent may leave the scanner mounted while animating it away.
      await scan(tester, 'another');
      expect(values, isEmpty);
    });

    testWidgets(
      '$name context change drops old validation and permits new scan',
      (tester) async {
        final pending = Completer<MobileScanOutcome>();
        final values = <String>[];
        var calls = 0;
        Future<MobileScanOutcome> resolve(String raw) {
          calls++;
          return raw == 'old'
              ? pending.future
              : Future.value(MobileScanOutcome.accepted(raw));
        }

        await tester.pumpWidget(
          host(
            scanner(
              context: 1,
              resolve: resolve,
              accepted: values.add,
              close: () {},
            ),
          ),
        );
        await scan(tester, 'old');
        await tester.pumpWidget(
          host(
            scanner(
              context: 2,
              resolve: resolve,
              accepted: values.add,
              close: () {},
            ),
          ),
        );
        pending.complete(const MobileScanOutcome.rejected('stale failure'));
        await tester.pump();
        expect(find.text('stale failure'), findsNothing);
        await scan(tester, 'new');
        expect(values, ['new']);
        expect(calls, 2);
      },
    );

    testWidgets('$name cannot reuse a result after another route covered it', (
      tester,
    ) async {
      final pending = Completer<MobileScanOutcome>();
      final values = <String>[];
      await tester.pumpWidget(
        host(
          scanner(
            context: 1,
            resolve: (raw) => raw == 'old'
                ? pending.future
                : Future.value(MobileScanOutcome.accepted(raw)),
            accepted: values.add,
            close: () {},
          ),
        ),
      );
      await scan(tester, 'old');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      pending.complete(const MobileScanOutcome.accepted('late'));
      await tester.pump();
      expect(values, isEmpty);
      await scan(tester, 'fresh');
      expect(values, ['fresh']);
    });

    testWidgets('$name ignores result during route dismissal animation', (
      tester,
    ) async {
      final pending = Completer<MobileScanOutcome>();
      final values = <String>[];
      await tester.pumpWidget(host(const SizedBox.shrink()));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final route = PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(seconds: 1),
        pageBuilder: (_, _, _) => AppTheme(
          data: AppThemeData.dark,
          child: Material(
            child: Center(
              child: SizedBox(
                width: 361,
                child: scanner(
                  context: 1,
                  resolve: (_) => pending.future,
                  accepted: values.add,
                  close: () {},
                ),
              ),
            ),
          ),
        ),
      );
      unawaited(navigator.push(route));
      await tester.pump();
      await scan(tester, 'old');
      navigator.pop();
      await tester.pump(const Duration(milliseconds: 100));
      expect(route.animation!.status, AnimationStatus.reverse);
      expect(
        find.byType(
          desktop ? AddressQrScanModal : MobileAddressScanCard,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      pending.complete(const MobileScanOutcome.accepted('late'));
      await tester.pump();
      expect(values, isEmpty);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('$name ignores late exception after disposal', (tester) async {
      final pending = Completer<MobileScanOutcome>();
      final values = <String>[];
      await tester.pumpWidget(
        host(
          scanner(
            context: 1,
            resolve: (_) => pending.future,
            accepted: values.add,
            close: () {},
          ),
        ),
      );
      await scan(tester, 'old');
      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(StateError('stale'));
      await tester.pump();
      expect(values, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name rejection and ignored results allow retry', (
      tester,
    ) async {
      final values = <String>[];
      await tester.pumpWidget(
        host(
          scanner(
            context: 1,
            resolve: (raw) async => switch (raw) {
              'bad' => const MobileScanOutcome.rejected('Unsupported network'),
              'stale' => const MobileScanOutcome.ignored(),
              _ => MobileScanOutcome.accepted(raw),
            },
            accepted: values.add,
            close: () {},
          ),
        ),
      );
      await scan(tester, 'bad');
      expect(values, isEmpty);
      await scan(tester, 'stale');
      expect(values, isEmpty);
      await scan(tester, 'good');
      expect(values, ['good']);
    });
  }

  testWidgets('full screen scanner ignores late success after close', (
    tester,
  ) async {
    final pending = Completer<MobileScanOutcome>();
    final values = <String>[];
    await tester.pumpWidget(
      host(
        MobileAddressScanView(
          resolve: (_) => pending.future,
          onScanned: values.add,
          onClose: () {},
        ),
      ),
    );
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
      BarcodeCapture(barcodes: [const Barcode(rawValue: 'first')]),
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Close scanner'));
    pending.complete(const MobileScanOutcome.accepted('late'));
    await tester.pump();
    expect(values, isEmpty);
  });
}
