import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/widgets/ironwood_migration_shimmer_text.dart';

void main() {
  testWidgets('animates unless reduced motion is enabled', (tester) async {
    Widget app({required bool disableAnimations}) {
      return MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
        home: const Center(
          child: IronwoodMigrationShimmerText(
            text: 'Preparing...',
            style: TextStyle(fontSize: 40),
            baseColor: Color(0xFF858686),
            highlightColor: Color(0xFF141818),
          ),
        ),
      );
    }

    await tester.pumpWidget(app(disableAnimations: false));
    await tester.pump();
    expect(find.byType(ShaderMask), findsOneWidget);

    await tester.pumpWidget(app(disableAnimations: true));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(find.text('Preparing...'), findsOneWidget);
  });
}
