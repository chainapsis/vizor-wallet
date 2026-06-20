import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_signing_modal.dart';

Widget _app(Widget child) {
  return AppTheme(
    data: AppThemeData.light,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );
}

void main() {
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
          frameInterval: Duration(milliseconds: 250),
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
          frameInterval: Duration(milliseconds: 100),
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

    expect(tester.getSize(find.byType(PrettyQrView)), const Size(264, 264));
    final qrView = tester.widget<PrettyQrView>(find.byType(PrettyQrView));
    final decoration = (qrView as dynamic).decoration as PrettyQrDecoration;
    expect(decoration.quietZone, const PrettyQrQuietZone.modules(3));
    expect(find.byType(CustomPaint), findsNothing);
  });
}
