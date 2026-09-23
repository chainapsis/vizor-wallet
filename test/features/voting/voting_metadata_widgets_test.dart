import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/widgetbook/fixtures/retroactive_q3_2026.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final readOnly in [false, true]) {
      testWidgets(
        'real ZIP proposal fits 420px at 200 percent: $direction, review=$readOnly',
        (tester) async {
          tester.view.physicalSize = const Size(420, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              home: AppTheme(
                data: AppThemeData.light,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(420, 900),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: VotingProposalCard(
                          proposal: retroactiveQ3Proposals.last,
                          readOnly: readOnly,
                          statusLabel: readOnly ? 'Skipped' : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final link = find.byType(VotingForumLinkButton);
          final card = tester.getRect(find.byType(VotingProposalCard));
          final linkRect = tester.getRect(link);
          expect(linkRect.left, greaterThanOrEqualTo(card.left));
          expect(linkRect.right, lessThanOrEqualTo(card.right));
          expect(link.hitTestable(), findsOneWidget);
          expect(
            tester
                .widget<AppButton>(
                  find.descendant(of: link, matching: find.byType(AppButton)),
                )
                .onPressed,
            isNotNull,
          );
          final titleTop = tester
              .getTopLeft(find.text(retroactiveQ3Proposals.last.title))
              .dy;
          expect(linkRect.bottom, lessThanOrEqualTo(titleTop));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('forum-only metadata wraps long labels instead of clipping', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        child: Center(
          child: SizedBox(
            width: 160,
            child: VotingProposalMetadataRow(
              zipBadges: const [],
              forumUri: Uri.parse('https://forum.z.cash'),
              forumLabel:
                  'Read the complete proposal discussion on the community forum',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(VotingForumLinkButton)).width,
      lessThanOrEqualTo(160),
    );
    expect(
      tester.getSize(find.byType(VotingForumLinkButton)).height,
      greaterThan(24),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only proposal card shows stale selected choice fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemedHarness(
        child: Center(
          child: SizedBox(
            width: 420,
            child: VotingProposalCard(
              proposal: VotingProposalView(
                id: 1,
                title: 'Issuance timing',
                description: 'Select the fee reissuance schedule.',
                options: [
                  VotingOptionView(index: 0, label: 'Immediately'),
                  VotingOptionView(index: 1, label: 'Later'),
                ],
              ),
              selectedChoice: 4,
              readOnly: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Choice 4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_selected_choice_indicator')),
      findsOneWidget,
    );
    expect(find.text('Choose'), findsNothing);
  });
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: Directionality(textDirection: TextDirection.ltr, child: child),
        ),
      ),
    );
  }
}
