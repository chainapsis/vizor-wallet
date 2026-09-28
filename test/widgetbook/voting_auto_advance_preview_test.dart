import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';

const mobile = kAppFormFactor == AppFormFactor.mobile;

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('auto advance preview dark=$dark text=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = mobile
            ? Size(scale == 1 ? 393 : 320, 852)
            : const Size(1080, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: (dark ? buildLegacyDarkTheme() : buildLegacyLightTheme())
                .copyWith(
                  platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
                ),
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
        Future<void> choose(int id) async {
          final option = find.byKey(ValueKey('voting_proposal_${id}_option_0'));
          await Scrollable.ensureVisible(
            tester.element(option),
            alignment: .75,
          );
          await tester.pumpAndSettle();
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byType(SingleChildScrollView).first,
              )
              .controller!;
          final offset = scroll.offset;
          await tester.tap(option);
          await tester.pump();
          expect(scroll.offset, closeTo(offset, .1));
        }

        // First-time answers advance forward, never wrap to an earlier gap.
        await choose(19);
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('jump-highlight-37')), findsOneWidget);
        if (!mobile) {
          final card = find.byWidgetPredicate(
            (widget) =>
                widget is VotingProposalCard && widget.proposal.id == 37,
          );
          final viewport = tester.getRect(
            find.byType(SingleChildScrollView).first,
          );
          expect(
            tester.getTopLeft(card).dy,
            greaterThanOrEqualTo(viewport.top + AppSpacing.sm - .1),
          );
        }

        await choose(37);
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).first,
            )
            .controller!;
        final before = scroll.offset;
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(scroll.offset, before);

        await tester.tap(find.byKey(const ValueKey('answer-progress')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            ValueKey(mobile ? 'mobile-unanswered-item-0' : 'unanswered-item-0'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('jump-highlight-1')), findsOneWidget);
        if (!mobile) {
          final card = find.byWidgetPredicate(
            (widget) => widget is VotingProposalCard && widget.proposal.id == 1,
          );
          final viewport = tester.getRect(
            find.byType(SingleChildScrollView).first,
          );
          expect(
            tester.getTopLeft(card).dy,
            closeTo(viewport.top + AppSpacing.sm, .1),
          );
        }

        await choose(1);
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();
        expect(find.text('Review your answers'), findsNothing);
        expect(find.textContaining('Next unanswered'), findsNothing);

        expect(tester.takeException(), isNull);
      });
    }
  }
}
