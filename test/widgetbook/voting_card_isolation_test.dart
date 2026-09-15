import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_screens.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final entry in <String, WidgetBuilder>{
    'Proposal': buildVotingProposalCardCase,
    'Result': buildVotingResultCardCase,
  }.entries) {
    testWidgets(
      '${entry.key} mobile card keeps phone geometry on wide canvas',
      (tester) async {
        await pumpUseCase(tester, entry.value, knobs: {'Layout': 'Mobile'});
        if (wbCompiledLaneLayout != WbLayout.mobile) {
          expect(find.byType(WbLaneOnly), findsOneWidget);
          expect(find.byType(MobileVotingScaffold), findsNothing);
          await disposeTree(tester);
          return;
        }
        final scaffold = find.byType(MobileVotingScaffold);
        expect(tester.getSize(scaffold), kWbPhoneSize);
        expect(MediaQuery.sizeOf(tester.element(scaffold)), kWbPhoneSize);
        // The static card's back affordance must not navigate the workbench.
        tester.widget<MobileVotingScaffold>(scaffold).onBack!();
        await tester.pump();
        expect(scaffold, findsOneWidget);
        expect(tester.takeException(), isNull);
        await disposeTree(tester);
      },
    );

    for (final layout in [wbLayoutLabel(wbCompiledLaneLayout)]) {
      testWidgets('${entry.key} $layout forum link stays isolated', (
        tester,
      ) async {
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        final launches = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          launches.add(call);
          return true;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await pumpUseCase(tester, entry.value, knobs: {'Layout': layout});
        final link = find.byType(VotingForumLinkButton);
        expect(link, findsOneWidget);
        expect(
          VotingExternalUriLauncherScope.maybeOf(tester.element(link)),
          isNotNull,
        );
        await tester.tap(find.text('Forum discussion'));
        await tester.pump();
        expect(launches, isEmpty);
        expect(tester.takeException(), isNull);
        await disposeTree(tester);
      });
    }
  }
}
