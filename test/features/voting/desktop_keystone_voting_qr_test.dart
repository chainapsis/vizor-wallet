@Tags(['desktop'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import '../../support/app_test_fonts.dart';
import '../../support/voting_display_profiles.dart';
import '../../support/voting_qr_capture.dart';
import '../../support/voting_qr_frames.dart';

void main() {
  setUpAll(loadAppTestFonts);
  testWidgets(
    'an open enlargement follows DPR changes without resetting playback',
    (tester) async {
      await desktopVotingProfiles.first.apply(tester);
      final key = GlobalKey();
      await _pumpDesktopVoting(tester, key);
      await tester.tap(find.byKey(const ValueKey('voting_enlarge_qr')));
      await tester.pump();
      final qr = find.byKey(const ValueKey('voting_qr_enlarged'));
      final playback = tester.widget<KeystonePcztQrStage>(qr).playback;
      await desktopVotingProfiles[1].apply(tester);
      await tester.pump();
      expect(tester.widget<KeystonePcztQrStage>(qr).playback, same(playback));
      await checkVotingQrFrames(
        tester,
        key,
        1.25,
        qr: qr,
        minimumPatternSize: 426,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final profile in desktopVotingProfiles) {
    testWidgets(
      'normal and enlarged QR preserve pattern size on ${profile.name}',
      (tester) async {
        await profile.apply(tester);
        final key = GlobalKey();
        await _pumpDesktopVoting(tester, key);
        await checkVotingQrFrames(
          tester,
          key,
          profile.ratio,
          qr: find.byKey(const ValueKey('voting_qr_normal')),
          minimumPatternSize: 360,
        );
        final enlarge = find.byKey(const ValueKey('voting_enlarge_qr'));
        await tester.ensureVisible(enlarge);
        await tester.tap(enlarge);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await checkVotingQrFrames(
          tester,
          key,
          profile.ratio,
          qr: find.byKey(const ValueKey('voting_qr_enlarged')),
          minimumPatternSize: 426,
        );
        expect(tester.takeException(), isNull);
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
