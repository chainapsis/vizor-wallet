import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/gallery/gift_cards_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/migration_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

// Compare visible copy and text styling after live knob edits with a fresh mount of
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
      .map(
        (text) =>
            '${text.data ?? text.textSpan!.toPlainText()} | ${text.style}',
      )
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
  testWidgets('migration schedule follows live rows and data', (tester) async {
    await expectLiveStates(tester, buildMigrationScheduleGalleryCase, [
      {
        'Layout': wbLayoutLabel(wbCompiledLaneLayout),
        'Row status': 'Scheduled',
        'Data': 'Schedule',
      },
      {
        'Layout': wbLayoutLabel(wbCompiledLaneLayout),
        'Row status': 'Completed',
        'Data': 'Schedule',
      },
      {
        'Layout': wbLayoutLabel(wbCompiledLaneLayout),
        'Row status': 'Completed',
        'Data': 'Loading',
      },
      {
        'Layout': wbLayoutLabel(wbCompiledLaneLayout),
        'Row status': 'Completed',
        'Data': 'Unavailable',
      },
    ]);
  });
  testWidgets('preparation schedule follows live outputs', (tester) async {
    await expectLiveStates(
      tester,
      buildMigrationPreparationScheduleGalleryCase,
      [
        for (final output in [
          'For migration',
          'Stays in Orchard',
          'Used in next round',
        ])
          {'Layout': wbLayoutLabel(wbCompiledLaneLayout), 'Output': output},
      ],
    );
  });
  testWidgets('desktop fallback flow follows live steps', (tester) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    await expectLiveStates(tester, buildMigrationFlowGalleryCase, [
      for (final step in ['How it works', 'Migration options'])
        {'Layout': 'Desktop', 'Flow data': 'No account yet', 'Step': step},
    ]);
  });
  testWidgets('mobile live migration follows step and account changes', (
    tester,
  ) async {
    await expectLiveStates(tester, buildMigrationMobileLiveStepsGalleryCase, [
      {'Step': 'Preparing', 'Account': 'Software', 'Part status': 'Active'},
      {'Step': 'Migrating', 'Account': 'Software', 'Part status': 'Active'},
      {'Step': 'Migrating', 'Account': 'Keystone', 'Part status': 'Needs input'},
    ]);
  });
  testWidgets('gift-card body follows live page changes', (tester) async {
    await expectLiveStates(tester, buildGiftCardsMobileBodyGalleryCase, [
      for (final page in ['Home', 'Amount', 'Message', 'Review'])
        {'Page': page},
    ]);
  });
  testWidgets('gift-card body follows live metadata changes', (tester) async {
    await expectLiveStates(tester, buildGiftCardsMobileBodyGalleryCase, [
      for (final metadata in ['Saved', 'Retry saving'])
        {'Page': 'Review', 'Funding metadata': metadata},
    ]);
  });
  testWidgets('mobile migration resets its mounted flow on knob changes', (
    tester,
  ) async {
    await expectLiveStates(tester, buildMigrationFlowGalleryCase, [
      for (final step in [
        'About Ironwood',
        'Ironwood steps',
        'Migration type',
        'Fast review',
      ])
        {'Layout': 'Mobile', 'Step': step, 'Private option': 'Available'},
      {
        'Layout': 'Mobile',
        'Step': 'Migration type',
        'Private option': 'Unavailable',
      },
    ]);
  });
  testWidgets('desktop migration follows live Step changes', (tester) async {
    if (wbCompiledLaneLayout != WbLayout.desktop) return;
    await expectLiveStates(tester, buildMigrationFlowGalleryCase, [
      for (final step in [
        'About Ironwood',
        'How it works',
        'What to expect',
        'Migration options',
      ])
        {'Layout': 'Desktop', 'Step': step},
    ]);
  });
  testWidgets('voting status resets progress on backward Step changes', (
    tester,
  ) async {
    await expectLiveStates(tester, buildVotingStatusCase, [
      for (final step in [
        'Preparing',
        // Mobile groups preparing and delegating into the same visible step.
        if (wbCompiledLaneLayout == WbLayout.desktop) 'Delegating',
        'Casting votes',
        'Submitting shares',
        'Finalizing',
      ])
        {'Layout': wbLayoutLabel(wbCompiledLaneLayout), 'Step': step},
    ]);
  });
  testWidgets('voting confirmation refresh follows live Outcome changes', (
    tester,
  ) async {
    await expectLiveStates(tester, buildVotingConfirmationCase, [
      for (final outcome in [
        'Checking eligibility',
        'Eligibility not confirmed',
        'Refresh failed (Retry)',
      ])
        {'Layout': wbLayoutLabel(wbCompiledLaneLayout), 'Outcome': outcome},
    ]);
  });
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
