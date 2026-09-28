import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/legacy_material_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

void votingWalkthroughTests() {
  for (final skipped in [
    <int>{},
    {0, 18, 36},
  ]) {
    testWidgets(
      skipped.isEmpty
          ? 'walkthrough: answer all 37 in order, review answers'
          : 'walkthrough: skip three, review directly, find and answer each missing proposal',
      (tester) async {
        tester.view.physicalSize = _mobile
            ? const Size(393, 852)
            : const Size(1080, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildLegacyDarkTheme(),
            builder: (context, child) =>
                AppTheme(data: AppThemeData.dark, child: child!),
            home: Scaffold(
              body: Builder(builder: buildRetroactiveVotingUseCase),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sticky = find.byKey(const ValueKey('sticky-review-action'));
        final progress = find.byKey(const ValueKey('answer-progress'));
        final scroll = tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!;
        if (_mobile) {
          expect(progress.hitTestable(), findsNothing);

          await Scrollable.ensureVisible(
            tester.element(find.byType(VotingProposalCard).first),
          );
          await tester.pumpAndSettle();
        }
        final controlsBefore = tester.getRect(
          find.byKey(const ValueKey('navigation-controls')),
        );
        expect(find.byKey(const ValueKey('next-question')), findsNothing);
        expect(find.byKey(const ValueKey('previous-question')), findsNothing);
        expect(sticky, findsNothing);
        expect(progress.hitTestable(), findsOneWidget);

        for (var index = 0; index < 37; index++) {
          if (skipped.contains(index)) continue;
          final option = find.byKey(
            ValueKey('voting_proposal_${index + 1}_option_0'),
          );
          await Scrollable.ensureVisible(
            tester.element(option),
            alignment: .25,
          );
          await tester.pumpAndSettle();
          await tester.tap(option);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 750));
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widgetList<VotingProposalCard>(find.byType(VotingProposalCard))
              .where((c) => c.selectedChoice == 0)
              .length,
          37 - skipped.length,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('navigation-controls'))),
          controlsBefore,
        );
        expect(find.text('All answered'), findsNothing);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          progress.hitTestable(),
          skipped.isEmpty ? findsNothing : findsOneWidget,
        );
        expect(sticky.hitTestable(), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('voting_review_answers_button')),
        );
        await tester.pumpAndSettle();
        if (skipped.isNotEmpty) {
          await tester.tap(find.text('Continue to review'));
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const ValueKey('review-answer-summary')),
          findsNothing,
        );
        expect(find.text('Go to unanswered'), findsNothing);
        expect(
          find.text('Unanswered questions won’t be submitted.'),
          findsNothing,
        );

        if (skipped.isNotEmpty) {
          for (final index in skipped) {
            await tester.tap(find.byTooltip('Back to voting'));
            await tester.pumpAndSettle();
            await tester.tap(progress);
            await tester.pumpAndSettle();
            final item = find.byKey(
              ValueKey(
                '${_mobile ? "mobile-unanswered-item" : "unanswered-item"}-$index',
              ),
            );
            await tester.ensureVisible(item);
            await tester.pumpAndSettle();

            await tester.tap(item);
            await tester.pumpAndSettle();
            expect(
              find.byKey(ValueKey('jump-highlight-${index + 1}')),
              findsOneWidget,
            );
            final highlight = tester.widget<Positioned>(
              find.byKey(ValueKey('jump-highlight-${index + 1}')),
            );
            expect(highlight.top, 0);
            expect(highlight.bottom, 0);

            final option = find.byKey(
              ValueKey('voting_proposal_${index + 1}_option_0'),
            );
            await Scrollable.ensureVisible(
              tester.element(option),
              alignment: .25,
            );
            await tester.pumpAndSettle();
            await tester.tap(option);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 750));
            await tester.pumpAndSettle();
            if (_mobile) {
              await Scrollable.ensureVisible(
                tester.element(find.byType(VotingProposalCard).first),
              );
            } else {
              scroll.jumpTo(0);
            }
            await tester.pumpAndSettle();
            if (index == skipped.last) {
              expect(progress, findsNothing);
              expect(sticky.hitTestable(), findsOneWidget);

              await tester.tap(sticky);
            } else {
              expect(progress.hitTestable(), findsOneWidget);
              expect(sticky, findsNothing);
              expect(
                find.byKey(const ValueKey('menu-review-action')),
                findsNothing,
              );
              scroll.jumpTo(scroll.position.maxScrollExtent);
              await tester.pumpAndSettle();
              await tester.tap(
                find.byKey(const ValueKey('voting_review_answers_button')),
              );
            }
            await tester.pumpAndSettle();
            if (index != skipped.last) {
              await tester.tap(find.text('Continue to review'));
              await tester.pumpAndSettle();
            }
          }
          expect(find.text('Review your answers'), findsOneWidget);
        }
        expect(find.text('Review your answers'), findsOneWidget);
        await tester.tap(find.byTooltip('Back to voting'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<VotingProposalCard>(find.byType(VotingProposalCard))
              .every((card) => card.selectedChoice == 0),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
