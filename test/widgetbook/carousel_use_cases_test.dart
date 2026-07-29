import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/carousel_use_cases.dart';

void main() {
  testWidgets('preparation fixed pages render the supplied Figma copy', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(buildCarouselPreparationCardTwoUseCase));
    await tester.pump();

    expect(
      find.text(
        'We’re organizing your balance into common-sized parts. This makes '
        'your migration harder to link.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });

  testWidgets('migration fixed pages render the supplied Figma copy', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(buildCarouselMigrationCardTwoUseCase));
    await tester.pump();

    expect(
      find.text(
        'Each Zcash block takes about 75 seconds to create, but timing can '
        'vary with network conditions.',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('app_carousel_indicator_1'))),
      const Size(40, 6),
    );
  });
}

Widget _harness(WidgetBuilder builder) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.dark,
      child: Builder(builder: builder),
    ),
  );
}
