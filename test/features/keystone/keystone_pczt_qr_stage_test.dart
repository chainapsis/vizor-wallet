import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';

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
  testWidgets('keeps the default desktop-sized QR treatment', (tester) async {
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
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('can render a mobile scan-optimized QR', (tester) async {
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
}
