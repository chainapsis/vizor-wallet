import 'dart:io';

import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_onboarding_flow.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';
const _bip39Passphrase = 'TREZOR';
const _password = 'Vizor123!';
const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');
const _reuseMigratedWallet = bool.fromEnvironment(
  'ZCASH_E2E_REUSE_MIGRATED_WALLET',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'imports an Ironwood wallet and completes a real regtest vote',
    (tester) async {
      if (_roundId.length != 64) {
        fail('ZCASH_E2E_VOTE_ROUND_ID must be a 64-character round id.');
      }
      addTearDown(_cleanupE2eWalletState);
      if (!_reuseMigratedWallet) {
        await _cleanupE2eWalletState();
      }

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      if (_reuseMigratedWallet) {
        _log('opening wallet preserved by the Orchard-to-Ironwood E2E');
        await tester.pump(const Duration(milliseconds: 500));
        if (tester.any(find.byKey(const ValueKey('unlock_password_field')))) {
          await _enterText(
            tester,
            const ValueKey('unlock_password_field'),
            _password,
          );
          await _tapButton(tester, const ValueKey('unlock_submit_button'));
        }
      } else {
        _log('importing deterministic Ironwood-funded wallet');
        await _tapButton(
          tester,
          const ValueKey('welcome_import_wallet_button'),
        );
        await _enterText(
          tester,
          const ValueKey('import_mnemonic_first_word_field'),
          _mnemonic,
        );
        await _tapButton(tester, const ValueKey('bip39_passphrase_action'));
        await _enterText(
          tester,
          const ValueKey('bip39_passphrase_field'),
          _bip39Passphrase,
        );
        await _tapButton(
          tester,
          const ValueKey('bip39_passphrase_save_button'),
        );
        await _tapButton(tester, const ValueKey('import_secret_submit_button'));
        await _tapButton(tester, const ValueKey('import_birthday_skip_button'));
        await _tapButton(
          tester,
          const ValueKey('unknown_birthday_confirm_button'),
        );
        await _enterText(
          tester,
          const ValueKey('set_password_password_field'),
          _password,
        );
        await _enterText(
          tester,
          const ValueKey('set_password_confirm_field'),
          _password,
        );
        await _tapButton(tester, const ValueKey('set_password_submit_button'));
        await finishDesktopAccountCustomisation(tester);
      }

      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
        description: 'Ironwood balance to sync',
        timeout: const Duration(minutes: 5),
      );

      _log('opening signed regtest voting round $_roundId');
      await _tap(tester, const ValueKey('sidebar_voting_button'));
      await _tapButton(
        tester,
        ValueKey('voting_poll_action_$_roundId'),
        timeout: const Duration(minutes: 2),
      );

      final providerContainer = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('sidebar_voting_button'))),
      );
      await _pumpUntil(
        tester,
        () {
          final session = providerContainer.read(
            votingSessionProvider(_roundId),
          );
          return session.hasError || session.value?.round != null;
        },
        description: 'voting session round to load',
        timeout: const Duration(minutes: 2),
      );
      var session = providerContainer.read(votingSessionProvider(_roundId));
      if (session.hasError) {
        fail('Voting session failed to load: ${session.error}');
      }
      await _pumpUntil(
        tester,
        () {
          session = providerContainer.read(votingSessionProvider(_roundId));
          final value = session.value;
          return session.hasError ||
              value?.error != null ||
              value?.hasConfirmedVotingEligibility == true;
        },
        description: 'Ironwood voting eligibility to confirm',
        timeout: const Duration(minutes: 10),
      );
      if (session.hasError) {
        fail('Voting eligibility failed: ${session.error}');
      }
      final eligibleSession = session.value!;
      if (!eligibleSession.hasConfirmedVotingEligibility) {
        fail(
          'Voting eligibility was rejected: '
          '${eligibleSession.error?.message ?? 'unknown error'}',
        );
      }
      _log(
        'eligibility confirmed at '
        '${eligibleSession.eligibleWeightZatoshi} zatoshi',
      );

      final accountUuid = eligibleSession.accountUuid;
      expect(accountUuid, isNotNull);
      final draftKey = VotingSessionKey(
        roundId: _roundId,
        accountUuid: accountUuid!,
      );

      for (var proposalId = 1; proposalId <= 4; proposalId++) {
        await _scrollUntilVisible(
          tester,
          ValueKey('voting_proposal_${proposalId}_option_0'),
        );
        await _tap(
          tester,
          ValueKey('voting_proposal_${proposalId}_option_0'),
          timeout: const Duration(minutes: 10),
        );
        await _pumpUntil(
          tester,
          () =>
              providerContainer
                  .read(votingDraftProvider(draftKey))
                  .choices[proposalId] ==
              0,
          description: 'proposal $proposalId selection to persist',
        );
        _log('selected proposal $proposalId');
      }
      expect(providerContainer.read(votingDraftProvider(draftKey)).choices, {
        1: 0,
        2: 0,
        3: 0,
        4: 0,
      });
      await _scrollUntilVisible(
        tester,
        const ValueKey('voting_review_answers_button'),
      );
      await _tapButton(tester, const ValueKey('voting_review_answers_button'));
      await _tapButton(tester, const ValueKey('voting_confirm_submit_button'));

      _log('waiting for real delegation, commitment, and share proofs');
      await _pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('voting_submission_done_button')),
        ),
        description: 'confirmed voting receipt',
        timeout: const Duration(minutes: 40),
      );
      final done = find.byKey(const ValueKey('voting_submission_done_button'));
      final button = tester.widget<AppButton>(done);
      expect(button.onPressed, isNotNull);
      _log('vote completed and confirmation receipt is actionable');
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}

Future<void> _scrollUntilVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  if (tester.any(finder)) {
    await tester.ensureVisible(finder);
    return;
  }
  final scrollable = find.byType(Scrollable).last;
  await _pumpUntil(
    tester,
    () => tester.any(scrollable),
    description: 'poll list for $key',
  );
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _cleanupE2eWalletState() async {
  if (kZcashDefaultNetworkName != ZcashNetwork.regtest.name) {
    throw StateError('Refusing cleanup outside regtest.');
  }
  rust_sync.setSyncMode(mode: 0);
  rust_sync.cancelFullSync();
  rust_sync.stopMempoolObserver();
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((rust_sync.isSyncRunning() || rust_sync.isMempoolObserverRunning()) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final dbName = await getWalletDbName();
  await AppSecureStore.instance.deleteAll();
  final supportDir = await getWalletSupportDirectory();
  if (!supportDir.existsSync()) return;
  for (final name in [
    dbName,
    '$dbName-shm',
    '$dbName-wal',
    '$dbName.voting',
    '$dbName.voting-journal',
    '$dbName.voting-shm',
    '$dbName.voting-wal',
  ]) {
    final file = File('${supportDir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) file.deleteSync();
  }
}

Future<void> _tapButton(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () {
      if (!tester.any(finder)) return false;
      final widget = tester.widget(finder);
      return widget is! AppButton || widget.onPressed != null;
    },
    description: '$key button to enable',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  final inkWell = find.descendant(of: finder, matching: find.byType(InkWell));
  final hitTestable = tester.any(inkWell)
      ? inkWell.hitTestable()
      : finder.hitTestable();
  await _pumpUntil(
    tester,
    () => tester.any(hitTestable),
    description: '$key button to become hit-testable',
    timeout: timeout,
  );
  await tester.tap(hitTestable);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _tap(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final finder = find.byKey(key);
  await _pumpUntil(
    tester,
    () => tester.any(finder),
    description: '$key to appear',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  final inkWell = find.descendant(of: finder, matching: find.byType(InkWell));
  if (tester.any(inkWell)) {
    await _pumpUntil(
      tester,
      () => tester.widget<InkWell>(inkWell).onTap != null,
      description: '$key InkWell to enable',
      timeout: timeout,
    );
    final hitTestable = inkWell.hitTestable();
    if (tester.any(hitTestable)) {
      await tester.tap(hitTestable);
    } else {
      tester.widget<InkWell>(inkWell).onTap!.call();
    }
  } else {
    final hitTestable = finder.hitTestable();
    await _pumpUntil(
      tester,
      () => tester.any(hitTestable),
      description: '$key to become hit-testable',
      timeout: timeout,
    );
    await tester.tap(hitTestable);
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _enterText(WidgetTester tester, Key key, String text) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  await _pumpUntil(
    tester,
    () => tester.any(editable),
    description: '$key text field',
  );
  await tester.tap(editable);
  await tester.enterText(editable, text);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description.');
}

void _log(String message) {
  debugPrint('[voting-regtest-e2e] $message');
}
