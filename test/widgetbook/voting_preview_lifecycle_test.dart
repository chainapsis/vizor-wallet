import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/widgets/mobile/mobile_voting_config_settings_sheet.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/support/wb_voting_dates.dart';
import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('mobile settings closes locally and reopens after source change', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildVotingSettingsSheetCase,
      knobs: {'Layout': 'Mobile', 'Sources': 'Custom selected'},
    );
    await settle(tester);
    final sheet = find.byType(MobileVotingConfigSettingsSheet);
    final hostNavigator = Navigator.of(
      tester.element(sheet),
      rootNavigator: true,
    );
    final hostRoute = hostNavigator.widget;
    await tester.tap(find.text('Token holder voting'));
    await settle(tester);
    expect(sheet, findsNothing);
    expect(find.text('Reopen voting settings'), findsOneWidget);
    expect(hostNavigator.mounted, isTrue);
    expect(hostNavigator.widget, same(hostRoute));
    await tester.tap(find.text('Reopen voting settings'));
    await settle(tester);
    expect(sheet, findsOneWidget);
    await tester.tap(find.text('Add custom source'));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_voting_source_name')),
        matching: find.byType(EditableText),
      ),
      'Preview source',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_voting_source_url')),
        matching: find.byType(EditableText),
      ),
      'https://vote.example.org/static.json?checksum=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final save = find.byKey(const ValueKey('mobile_voting_source_save'));
    await tester.ensureVisible(save);
    await tester.pump();
    await tester.tap(save);
    await settle(tester);
    expect(
      find.text(
        "Couldn't update voting config. Check the source and try again.",
      ),
      findsOneWidget,
    );
    expect(sheet, findsOneWidget);
    await tester.ensureVisible(find.text('Close'));
    await tester.pump();
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(sheet, findsNothing);
    expect(find.text('Reopen voting settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('active poll dates remain future and agree across fixtures', (
    tester,
  ) async {
    expect(wbVotingActiveEndDate.isAfter(DateTime.now()), isTrue);
    expect(
      DateTime.parse(wbVotingActiveEndTime),
      wbVotingActiveEndDate.toUtc(),
    );
    for (final builder in [
      buildVotingActivePollCase,
      buildVotingProposalDetailCase,
    ]) {
      await pumpUseCase(
        tester,
        builder,
        knobs: {'Layout': wbLayoutLabel(wbCompiledLaneLayout)},
      );
      await settle(tester);
      final contents = tester.widgetList<VotingActivePollContent>(
        find.byType(VotingActivePollContent),
      );
      expect(contents, isNotEmpty);
      for (final content in contents) {
        expect(
          content.endDate!.isAtSameMomentAs(wbVotingActiveEndDate),
          isTrue,
        );
      }
      expect(find.text('Ends today'), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    }
  });
}
