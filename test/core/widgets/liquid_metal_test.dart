import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/liquid_metal.dart';

void main() {
  testWidgets('paints the baked shape with the shader', (tester) async {
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 360,
          height: 210,
          child: LiquidMetal(
            image: AssetImage(
              'assets/illustrations/nu7_liquid_metal_shape.webp',
            ),
            preprocessed: true,
            speed: 0,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(LiquidMetal),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
