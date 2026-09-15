import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/gallery/gift_cards_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/migration_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

// Compare the visible copy reached by live knob edits with a fresh mount of
// that same state. The second pass never unmounts the gallery between edits.
Future<void> expectLiveStates(
  WidgetTester tester,
  WidgetBuilder builder,
  List<Map<String, String>> states,
) async {
  Future<void> advance() async {
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  }

  List<String> copy() => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan!.toPlainText())
      .toList();

  final expected = <List<String>>[];
  for (final knobs in states) {
    await pumpUseCase(tester, builder, knobs: knobs);
    await advance();
    expected.add(copy());
  }
  // Ensure the selected states really have distinct on-screen outcomes.
  expect(
    expected.map((texts) => texts.join('\n')).toSet(),
    hasLength(states.length),
  );
  final host = await pumpUseCase(tester, builder, knobs: states.first);
  for (final index in [
    for (var i = 0; i < states.length; i++) i,
    for (var i = states.length - 2; i >= 0; i--) i,
  ]) {
    for (final knob in states[index].entries) {
      host.updateQueryField(group: 'knobs', field: knob.key, value: knob.value);
    }
    await advance();
    expect(copy(), expected[index], reason: 'Live knobs: ${states[index]}');
  }
  await disposeTree(tester);
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  testWidgets('mobile migration status returns from redirecting route knobs', (
    tester,
  ) async {
    await expectLiveStates(tester, buildMigrationMobileStatusGalleryCase, [
      for (final route in [
        'Status',
        'Loading',
        'Sent home',
        'Sent to About Ironwood',
      ])
        {'Route': route},
    ]);
  });
  testWidgets('gift-card signer follows live phase and error knobs', (
    tester,
  ) async {
    await expectLiveStates(tester, buildGiftCardsKeystoneSigningGalleryCase, [
      {'Phase': 'Preparing'},
      {'Phase': 'Ready to scan'},
      {'Phase': 'Failed', 'Error': 'Could not be completed'},
      {'Phase': 'Failed', 'Error': 'Expired'},
    ]);
  });

  final signing = {
    'combined': buildMigrationKeystoneCombinedSignGalleryCase,
    'immediate': buildMigrationKeystoneImmediateSignGalleryCase,
    'denomination': buildMigrationKeystoneDenominationSignGalleryCase,
    'batch': buildMigrationKeystoneBatchSignGalleryCase,
  };
  for (final entry in signing.entries) {
    testWidgets('migration ${entry.key} follows live signing knobs', (
      tester,
    ) async {
      await expectLiveStates(tester, entry.value, [
        for (final stage in [
          'Preparing',
          if (wbCompiledLaneLayout == WbLayout.mobile ||
              entry.key == 'combined' ||
              entry.key == 'immediate')
            'Request QR',
          'Signing failed',
        ])
          {'Layout': wbLayoutLabel(wbCompiledLaneLayout), 'Stage': stage},
      ]);
    });
  }

  testWidgets('voting detail returns from a live results redirect', (
    tester,
  ) async {
    await expectLiveStates(tester, buildVotingProposalDetailCase, [
      for (final content in ['Active poll', 'Redirect to results'])
        {'Layout': wbLayoutLabel(wbCompiledLaneLayout), 'Content': content},
    ]);
  });

  testWidgets('migration signing updates live round count', (tester) async {
    await expectLiveStates(
      tester,
      buildMigrationKeystoneCombinedSignGalleryCase,
      [
        for (final rounds in ['Single round', 'Multi-round'])
          {
            'Layout': wbLayoutLabel(wbCompiledLaneLayout),
            'Stage': 'Request QR',
            'Rounds': rounds,
          },
      ],
    );
  });
}
