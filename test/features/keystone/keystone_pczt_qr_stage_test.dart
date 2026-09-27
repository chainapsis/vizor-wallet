import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';

Widget _app(Widget content) {
  return AppTheme(
    data: AppThemeData.light,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay(
        initialEntries: [OverlayEntry(builder: (_) => Center(child: content))],
      ),
    ),
  );
}

void main() {
  for (final inModal in [false, true]) {
    testWidgets(
      '${inModal ? 'signing modal' : 'QR stage'} advances and loops at 5 fps',
      (tester) async {
        const parts = [
          'UR:ZCASH-SIGN-BATCH/FIRST',
          'UR:ZCASH-SIGN-BATCH/SECOND',
        ];
        await tester.pumpWidget(
          _app(
            inModal
                ? KeystoneSigningModal(
                    phase: KeystoneSigningModalPhase.ready,
                    urParts: parts,
                    error: null,
                    title: 'Confirm transaction',
                    subtitle: 'Scan with Keystone',
                    instruction: null,
                    primaryLabel: null,
                    onPrimary: null,
                    secondaryLabel: null,
                    onSecondary: null,
                  )
                : const KeystonePcztQrStage(
                    phase: KeystonePcztQrStagePhase.ready,
                    urParts: parts,
                    error: null,
                  ),
          ),
        );
        await tester.pump();
        // Inspect the displayed frame to verify animation behavior.
        QrImage frame() =>
            // ignore: invalid_use_of_protected_member
            tester.widget<PrettyQrView>(find.byType(PrettyQrView)).qrImage;
        final first = frame();
        await tester.pump(const Duration(milliseconds: 199));
        expect(frame(), same(first));
        await tester.pump(const Duration(milliseconds: 1));
        expect(frame(), isNot(same(first)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(frame(), same(first));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'changing requests resets frames and single-part QRs stay still',
    (tester) async {
      Widget request(List<String> parts) => AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: KeystonePcztQrStage(
              phase: KeystonePcztQrStagePhase.ready,
              urParts: parts,
              error: null,
            ),
          ),
        ),
      );
      // Inspect the displayed frame to verify request replacement.
      QrImage frame() =>
          // ignore: invalid_use_of_protected_member
          tester.widget<PrettyQrView>(find.byType(PrettyQrView)).qrImage;
      await tester.pumpWidget(request(const ['UR:FIRST/A', 'UR:FIRST/B']));
      await tester.pump(const Duration(milliseconds: 200));
      final previous = frame();
      await tester.pumpWidget(request(const ['UR:SECOND/A']));
      final replacement = frame();
      expect(replacement, isNot(same(previous)));
      await tester.pump(const Duration(seconds: 1));
      expect(frame(), same(replacement));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('renders scan-optimized QR by default', (tester) async {
    await tester.pumpWidget(
      _app(
        const KeystonePcztQrStage(
          phase: KeystonePcztQrStagePhase.ready,
          urParts: ['ur:zcash-pczt/test'],
          error: null,
        ),
      ),
    );

    expect(tester.getSize(find.byType(PrettyQrView)), const Size(230, 230));
    final qrView = tester.widget<PrettyQrView>(find.byType(PrettyQrView));
    final decoration = (qrView as dynamic).decoration as PrettyQrDecoration;
    expect(decoration.quietZone, const PrettyQrQuietZone.modules(3));
    expect(find.byType(CustomPaint), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFFFFFFFF),
      ),
      findsOneWidget,
    );
  });

  testWidgets('can render a decorative QR only when explicitly requested', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const KeystonePcztQrStage(
          phase: KeystonePcztQrStagePhase.ready,
          urParts: ['ur:zcash-pczt/test'],
          error: null,
          scanOptimized: false,
        ),
      ),
    );

    expect(tester.getSize(find.byType(PrettyQrView)), const Size(230, 230));
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('can render a larger mobile scan-optimized QR', (tester) async {
    await tester.pumpWidget(
      _app(
        const KeystonePcztQrStage(
          phase: KeystonePcztQrStagePhase.ready,
          urParts: ['ur:zcash-pczt/test'],
          error: null,
          size: 280,
          scanOptimized: true,
        ),
      ),
    );

    expect(tester.getSize(find.byType(PrettyQrView)), const Size(280, 280));
    final qrView = tester.widget<PrettyQrView>(find.byType(PrettyQrView));
    final decoration = (qrView as dynamic).decoration as PrettyQrDecoration;
    expect(decoration.quietZone, const PrettyQrQuietZone.modules(3));
    expect(find.byType(CustomPaint), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFFFFFFFF),
      ),
      findsOneWidget,
    );
  });

  testWidgets('desktop signing modal uses the scan-optimized PCZT QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        KeystoneSigningModal(
          phase: KeystoneSigningModalPhase.ready,
          urParts: const ['ur:zcash-pczt/test'],
          error: null,
          title: 'Confirm transaction',
          subtitle: 'Keystone required',
          instruction: 'Scan with Keystone.',
          primaryLabel: null,
          onPrimary: null,
          secondaryLabel: null,
          onSecondary: null,
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(PrettyQrView)), const Size(264, 264));
    final qrView = tester.widget<PrettyQrView>(find.byType(PrettyQrView));
    final decoration = (qrView as dynamic).decoration as PrettyQrDecoration;
    expect(decoration.quietZone, const PrettyQrQuietZone.modules(3));
    expect(find.byType(CustomPaint), findsNothing);
    expect(find.text('Scanning issues?'), findsOneWidget);
  });
}
