@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('scroll header dark=$dark at text $scale', (tester) async {
        tester.view.physicalSize = Size(scale == 1 ? 393 : 320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: (dark ? buildLegacyDarkTheme() : buildLegacyLightTheme())
                .copyWith(platform: TargetPlatform.iOS),
            builder: (context, child) => AppTheme(
              data: dark ? AppThemeData.dark : AppThemeData.light,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: scale == 2,
                ),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(builder: buildRetroactiveVotingPartialUseCase),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final semantics = tester.ensureSemantics();

        final progress = find.byKey(const ValueKey('answer-progress'));
        expect(progress.hitTestable(), findsNothing);
        expect(find.text('Coinholder voting').hitTestable(), findsOneWidget);

        final scroll = tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!;
        final first = find.byType(VotingProposalCard).first;
        await Scrollable.ensureVisible(tester.element(first));
        await tester.pumpAndSettle();
        final threshold = scroll.offset;
        final firstTop = tester.getTopLeft(first).dy;
        expect(progress.hitTestable(), findsOneWidget);
        expect(find.text('Voting').hitTestable(), findsOneWidget);
        expect(find.text('Coinholder voting').hitTestable(), findsNothing);

        scroll.jumpTo(threshold - 8);
        await tester.pumpAndSettle();
        expect(progress.hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(first).dy, closeTo(firstTop + 8, .1));
        scroll.jumpTo(threshold - 24);
        await tester.pumpAndSettle();
        expect(progress.hitTestable(), findsNothing);
        expect(tester.getTopLeft(first).dy, closeTo(firstTop + 24, .1));
        scroll.jumpTo(threshold);
        await tester.pumpAndSettle();
        await tester.tap(progress);
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(progress.hitTestable(), findsNothing);
        expect(find.text('Coinholder voting').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
