import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_screens.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final entry in <String, (WidgetBuilder, Type)>{
    'Active poll': (buildVotingActivePollCase, MobileVotingScaffold),
    'Voted poll': (buildVotingVotedPollCase, MobileVotingScaffold),
    'Settings': (buildVotingSettingsSheetCase, MobileModalOverlay),
    'Keystone': (
      buildVotingKeystoneSigningGalleryCase,
      MobileKeystoneVotingSigningScreen,
    ),
  }.entries) {
    testWidgets('${entry.key} uses phone geometry on a wide canvas', (
      tester,
    ) async {
      await pumpUseCase(tester, entry.value.$1, knobs: {'Layout': 'Mobile'});
      if (wbCompiledLaneLayout != WbLayout.mobile &&
          (entry.key == 'Active poll' || entry.key == 'Voted poll')) {
        expect(find.byType(WbLaneOnly), findsOneWidget);
      } else {
        final surface = find.byType(entry.value.$2);
        expect(surface, findsOneWidget);
        expect(tester.getSize(surface), kWbPhoneSize);
        expect(MediaQuery.sizeOf(tester.element(surface)), kWbPhoneSize);
      }
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    });
  }
}
