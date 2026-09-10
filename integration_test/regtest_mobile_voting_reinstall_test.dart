import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/voting/voting_participation_provider.dart';
import 'support/mobile_regtest_flow.dart';
import 'support/mobile_voting_regtest_flow.dart';

const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeMobileVotingRegtestRuntime);
  testWidgets(
    'restored wallet discovers used voting rights and hides Home',
    (tester) async {
      tolerateRenderOverflows();
      final directory = await getWalletSupportDirectory();
      final dbName = await getWalletDbName();
      expect(
        File('${directory.path}/$dbName').existsSync(),
        isFalse,
        reason: 'Reinstall must remove the prior wallet DB',
      );
      expect(File('${directory.path}/$dbName.voting').existsSync(), isFalse);
      expect(
        await Directory('${directory.path}/$dbName.voting-cache').exists(),
        false,
        reason: 'Reinstall must remove Home summaries and note observations',
      );
      final requestsBeforeRestore = await participationRequestCount();
      // iOS uninstall preserves Keychain. Deliberately model restoration without
      // ANY old local hints; only this regtest app's storage is cleared.
      await cleanupE2eWalletState();
      addTearDown(cleanupE2eWalletState);
      await tester.pumpWidget(await buildMobileVotingRegtestApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForHome(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('mobile_home_send'))),
      );
      await expectVotingHomeHidden(tester, container, restored: true);
      await captureVotingRegtest(tester, 'restored-home');
      final requests = await participationRequestCount();
      expect(
        requests,
        greaterThan(requestsBeforeRestore),
        reason: 'This restored install must discover participation itself',
      );
      await expectVotingNoteCachePersisted(tester, container, used: true);
      await expectVotingRecheckUsesDiskCache(container);
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Settings'),
        outcome: find.byKey(
          const ValueKey('mobile_settings_coinholder_voting_row'),
        ),
        description: 'Settings permanent voting entry',
      );
      await openHomeTab(tester);
      await expectVotingHomeHidden(tester, container, restored: true);
      await container.read(votingParticipationProvider).checkHomeCandidates();
      expect(
        await participationRequestCount(),
        requests,
        reason:
            'Successful participation check must be cached across Home reentry',
      );
      await tapUntilVisible(
        tester,
        trigger: find.bySemanticsLabel('Settings'),
        outcome: find.byKey(
          const ValueKey('mobile_settings_coinholder_voting_row'),
        ),
        description: 'Settings voting entry',
      );
      await tapWidget(
        tester,
        const ValueKey('mobile_settings_coinholder_voting_row'),
      );
      await tapAppButton(
        tester,
        ValueKey('voting_poll_action_$_roundId'),
        timeout: const Duration(minutes: 2),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('voting_participation_unavailable')),
        ),
        description: 'restored participation notice in detail',
        timeout: const Duration(minutes: 3),
      );
      await captureVotingRegtest(tester, 'restored-detail');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
