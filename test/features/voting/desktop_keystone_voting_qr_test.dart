@Tags(['desktop'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';
import '../../support/app_test_fonts.dart';
import '../../support/widget_test_viewport.dart';
import '../../support/voting_qr_capture.dart';
import '../../support/voting_display_profiles.dart';

void main() {
  setUpAll(loadAppTestFonts);
  testWidgets(
    'scan help fits beside the QR at the minimum desktop window and dismisses',
    (tester) async {
      final profile = desktopVotingProfiles.first;
      await profile.apply(tester);
      await _pumpDesktopVoting(tester, GlobalKey());
      final qr = tester.getRect(find.byType(KeystonePcztQrStage));
      expect(qr.size, const Size(372, 372));
      final card = find.byKey(const ValueKey('keystone_scan_help_tooltip'));
      final close = find.byKey(const ValueKey('keystone_scan_help_close'));
      final bounds = Offset.zero & profile.size;
      final cardRect = tester.getRect(card);
      expect(cardRect.intersect(bounds), cardRect);
      expect(tester.getRect(close).intersect(bounds), tester.getRect(close));
      expect(cardRect.right, lessThan(qr.left));
      // The open card tracks the same QR through a resize without reopening.
      await setWidgetTestViewport(
        tester,
        const Size(1512, 982),
        devicePixelRatio: 1,
      );
      await tester.pump();
      expect(
        tester.getRect(card).left,
        greaterThan(tester.getRect(find.byType(KeystonePcztQrStage)).right),
      );
      await profile.apply(tester);
      await tester.pump();
      expect(tester.getRect(card), cardRect);
      await tester.tap(close);
      await tester.pump();
      expect(card, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final profile in desktopVotingProfiles) {
    testWidgets(
      'desktop voting renders scannable whole-pixel frames on ${profile.name}',
      (tester) async {
        await profile.apply(tester);
        final key = GlobalKey();
        await _pumpDesktopVoting(tester, key);
        await checkVotingQrFrames(
          tester,
          key,
          profile.ratio,
          wholePixels: true,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

Future<void> _pumpDesktopVoting(WidgetTester tester, GlobalKey key) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) => RepaintBoundary(key: key, child: child!),
        home: AppTheme(
          data: AppThemeData.light,
          child: const AppDesktopShell(
            sidebar: SizedBox.expand(),
            pane: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: VotingStatusContent(
                phase: VotingSessionPhase.keystoneSigning,
                isHardwareAccount: true,
                keystoneSigningBundleIndex: 0,
                keystoneUrParts: votingQrFrames,
                keystoneBatchMemos: [
                  VotingKeystoneBatchMemo(
                    bundleIndex: 0,
                    bundleCount: 1,
                    displayMemo:
                        'Authorize voting power for this round.\nAmount: 1.25000000 ZEC.',
                  ),
                ],
                keystoneBatchMessageCount: 1,
                keystoneBatchTotalCount: 1,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
