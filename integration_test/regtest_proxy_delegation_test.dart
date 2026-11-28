// Proxy delegation through the real app on a full local stack: Ironwood
// regtest, a PIR server, a PROXY=1 vote chain and the attester's dev
// stack. Run it with scripts/e2e/flutter-macos-regtest-proxy-delegation.sh,
// which brings the stack up, funds this wallet through the real migration
// and passes every define read here.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_presentation.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_session_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_job_provider.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/proxy_delegation_regtest.dart';

const _roundId = String.fromEnvironment('ZCASH_E2E_VOTE_ROUND_ID');
const _delegateA = String.fromEnvironment('ZCASH_E2E_PROXY_DELEGATE_A');
const _delegateB = String.fromEnvironment('ZCASH_E2E_PROXY_DELEGATE_B');

/// A folder name under the app's temp directory (the sandbox allows no
/// other) to save a screenshot of each delegation screen in, for reviewing
/// the screens by eye; unset saves none.
const _screenshotDir = String.fromEnvironment('ZCASH_E2E_SCREENSHOT_DIR');

/// Delegate A's share of the wallet's ballots, in percent.
const _percentA = 25;

/// Delegate B's share.
const _percentB = 50;

/// The option the wallet's own vote picks on every proposal.
const _keptOption = 0;

/// The English copy the app shows, which the test finds widgets by.
final _l10n = lookupAppLocalizations(const ui.Locale('en'));

/// A delegate the harness registered, listed in its signed wallet list and
/// ballots for: `<index>:<o1,o2,…>:<handle>:<zvdk1 key>`.
class _HarnessDelegate {
  factory _HarnessDelegate(String define) {
    final parts = define.split(':');
    if (parts.length != 4) {
      fail('A harness delegate is <index>:<options>:<handle>:<key>: $define');
    }
    return _HarnessDelegate._(
      int.parse(parts[0]),
      parts[1].split(',').map(int.parse).toList(growable: false),
      parts[2],
      parts[3],
    );
  }

  _HarnessDelegate._(this.index, this.options, this.handle, this.key);

  /// Registry index `d`.
  final int index;

  /// The ballot the harness posts for it, one option per proposal.
  final List<int> options;

  /// The handle its registry entry carries.
  final String handle;

  /// Its one `zvdk1…` key.
  final String key;

  /// The key's fingerprint: the first 16 data characters, grouped by four.
  String get fingerprint {
    final data = key.substring('zvdk1'.length, 'zvdk1'.length + 16);
    return [for (var i = 0; i < 16; i += 4) data.substring(i, i + 4)].join('-');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
    await prepareProxyDelegationRegtest();
  });

  testWidgets(
    'delegates to a listed and a searched delegate, votes the rest and sees them counted',
    (tester) async {
      if (_roundId.length != 64) {
        fail('ZCASH_E2E_VOTE_ROUND_ID must be a 64-character round id.');
      }
      final a = _HarnessDelegate(_delegateA);
      final b = _HarnessDelegate(_delegateB);
      addTearDown(cleanupDesktopRegtestWallet);

      await tester.pumpWidget(
        await buildBootstrappedZcashWalletApp(
          overrides: proxyDelegationRegtestOverrides(),
        ),
      );
      const unlock = ValueKey('unlock_password_field');
      const welcome = ValueKey('welcome_import_wallet_button');
      const home = ValueKey('home_desktop_balance_amount_text');
      await pumpUntil(
        tester,
        () => [unlock, welcome, home].any((key) => tester.any(find.byKey(key))),
        description: 'the app to open',
      );
      if (tester.any(find.byKey(unlock))) {
        _log('opening the wallet funded by the migration run');
        await unlockDesktopRegtestWallet(tester);
      } else if (tester.any(find.byKey(welcome))) {
        // An earlier run's teardown removed the wallet; its funds are still
        // on the chain under the same seed.
        _log('importing the funded wallet');
        await importDesktopRegtestWallet(tester);
      }
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(home)),
        description: 'the desktop home',
        timeout: const Duration(minutes: 5),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(home)),
      );
      await pumpUntil(
        tester,
        () => container.read(syncProvider).value?.isSyncComplete == true,
        description: 'the Ironwood balance to sync',
        timeout: const Duration(minutes: 5),
      );
      await container.read(votingHomeRefreshProvider).refresh();

      _log('opening proxy round $_roundId');
      await tapAppWidget(tester, const ValueKey('sidebar_voting_button'));
      await _scrollToPoll(tester, ValueKey('voting_poll_action_$_roundId'));
      await _tapButton(
        tester,
        ValueKey('voting_poll_action_$_roundId'),
        timeout: const Duration(minutes: 2),
      );
      final session = await _waitForEligibility(tester, container);
      final accountUuid = session.accountUuid!;
      final draftKey = VotingSessionKey(
        roundId: _roundId,
        accountUuid: accountUuid,
      );
      _log('eligible for ${session.eligibleWeightZatoshi} zatoshi');

      // The round's delegation line → PD-2: browse Vizor's signed list,
      // which the harness signs with the regtest list key and which lists
      // both delegates with the key, provider and handle of their entries.
      await _tapButton(
        tester,
        const ValueKey('proxy_let_delegate_vote'),
        timeout: const Duration(minutes: 2),
      );
      for (final delegate in [a, b]) {
        await _waitFor(
          tester,
          () => tester.any(
            find.byKey(ValueKey('proxy_delegate_row_${delegate.index}')),
          ),
          failIf: () => _anyText(tester, _l10n.proxyNotReviewed)
              ? 'a harness delegate is listed as not reviewed'
              : null,
          description: 'listed delegate ${delegate.index} in browse',
          timeout: const Duration(minutes: 2),
        );
      }
      final listed = container
          .read(proxyDirectoryProvider(draftKey))
          .value!
          .browse
          .listed;
      expect(
        listed.map((entry) => entry.index),
        containsAll([a.index, b.index]),
      );
      expect(
        listed.where((entry) => entry.reviewed).map((e) => e.index),
        containsAll([a.index, b.index]),
        reason: "both delegates' entries match their rows in the signed list",
      );
      _log('browse lists ${listed.length} delegates');
      await _shot(tester, '01-browse');

      // PD-2: A from the list.
      await _tap(tester, ValueKey('proxy_delegate_row_${a.index}'));

      // The add dialog: a pasted key the registry cache holds finds its
      // entry, and a handle finds B by exact search over the cache.
      await _tapButton(tester, const ValueKey('proxy_directory_add_unlisted'));
      await enterAppText(tester, const ValueKey('proxy_add_field'), a.key);
      _submit(tester, const ValueKey('proxy_add_field'));
      await _waitFor(
        tester,
        () => switch (container
            .read(proxyDirectoryProvider(draftKey))
            .value
            ?.lookup) {
          ProxyLookupDone(answer: ApiDelegateLookup(:final listing?)) =>
            listing.index == a.index,
          _ => false,
        },
        failIf: () => switch (container
            .read(proxyDirectoryProvider(draftKey))
            .value
            ?.lookup) {
          ProxyLookupDone(:final answer) when answer.listing == null =>
            'pasting delegate ${a.index}\'s key answered ${answer.kind}',
          ProxyLookupFailed(:final error) => 'the lookup failed: $error',
          _ => null,
        },
        description: "delegate ${a.index} found by its pasted key",
        timeout: const Duration(minutes: 2),
      );
      _log('the pasted key found delegate ${a.index}');
      await _shot(tester, '02-pasted-key');

      await enterAppText(tester, const ValueKey('proxy_add_field'), b.handle);
      _submit(tester, const ValueKey('proxy_add_field'));
      await _waitFor(
        tester,
        () => switch (container
            .read(proxyDirectoryProvider(draftKey))
            .value
            ?.search) {
          ProxySearchResults(:final entries) => entries.any(
            (entry) =>
                entry.index == b.index &&
                entry.reviewed &&
                entry.handle == b.handle,
          ),
          _ => false,
        },
        failIf: () => switch (container
            .read(proxyDirectoryProvider(draftKey))
            .value
            ?.search) {
          ProxySearchResults(:final entries)
              when !entries.any((entry) => entry.index == b.index) =>
            'searching @${b.handle} found ${entries.map((e) => e.index)}',
          _ => null,
        },
        description: 'delegate ${b.index} found by @${b.handle}',
        timeout: const Duration(minutes: 2),
      );
      _log('handle search found delegate ${b.index} as @${b.handle}');
      await _shot(tester, '03-handle-search');
      await _tap(tester, ValueKey('proxy_delegate_row_${b.index}'));
      await _tapButton(tester, const ValueKey('proxy_add_done'));
      final draft = container.read(proxyAllocationDraftProvider(draftKey));
      expect(draft.delegates.map((d) => d.entry.index), [a.index, b.index]);
      // A choice carries what the user picked: the entry's key and handle.
      expect(draft.delegates.map((d) => d.entry.key.dk), [a.key, b.key]);
      expect(draft.delegates.map((d) => d.entry.handle), [a.handle, b.handle]);

      // PD-5: two delegates with percentages; the wallet keeps the rest.
      await _tapButton(tester, const ValueKey('proxy_picker_continue'));
      await enterAppText(
        tester,
        ValueKey('proxy_allocation_percent_${a.index}'),
        '$_percentA',
      );
      await enterAppText(
        tester,
        ValueKey('proxy_allocation_percent_${b.index}'),
        '$_percentB',
      );
      final preview = await _waitForValue(
        tester,
        () => container.read(proxyAllocationPreviewProvider(draftKey)),
        description: 'the planner preview',
      );
      final planned = {
        for (final delegation in preview.delegations)
          delegation.delegateIndex: delegation.ballots,
      };
      _log(
        'planned: ${planned[a.index]} to ${a.index}, ${planned[b.index]} to '
        '${b.index}, ${preview.keptBallots} kept, ${preview.dcCount} DCs',
      );
      expect(planned.keys, unorderedEquals([a.index, b.index]));
      expect(preview.keptBallots, greaterThan(BigInt.zero));
      await _shot(tester, '04-allocation');

      // Done returns to the round's questions, which now show the split.
      // A delegation that keeps a share is submitted with its answers.
      await _tapButton(tester, const ValueKey('proxy_allocation_done'));
      await _waitFor(
        tester,
        () => tester.any(find.byKey(const ValueKey('proxy_line_edit'))),
        description: 'the round to show the split',
        timeout: const Duration(minutes: 2),
      );
      await _shot(tester, '05-questions-split');
      // Kept here: the provider is disposed once the voting screens close.
      final round = await _waitForValue(
        tester,
        () => container.read(proxyRoundContextProvider(draftKey)),
        description: 'the round context',
      );
      final proposalIds = round.proposals
          .map((proposal) => proposal.id)
          .toList();
      for (final proposalId in proposalIds) {
        await _tap(
          tester,
          ValueKey('voting_proposal_${proposalId}_option_$_keptOption'),
          timeout: const Duration(minutes: 5),
        );
        await pumpUntil(
          tester,
          () =>
              container
                  .read(votingDraftProvider(draftKey))
                  .choices[proposalId] ==
              _keptOption,
          description: 'proposal $proposalId selection to persist',
        );
      }
      await _shot(tester, '06-questions-answered');
      await _tapButton(tester, const ValueKey('voting_review_answers_button'));

      // One review: the pre-proving check proves both registry entries
      // from the proof hosts, then one submit commits the delegation and
      // starts the vote job, which sends it before the kept share's casts.
      await _waitFor(
        tester,
        () {
          final checks = container
              .read(proxyDelegateChecksProvider(draftKey))
              .value;
          // One check per chosen delegate, in the draft's order.
          return checks != null &&
              checks.length == 2 &&
              checks.every((checked) => checked.check == DelegateCheck.ok);
        },
        failIf: () {
          if (tester.any(
            find.byKey(const ValueKey('proxy_review_cannot_verify')),
          )) {
            return 'the registry check could not verify the delegates';
          }
          for (final index in [a.index, b.index]) {
            if (tester.any(
              find.byKey(ValueKey('proxy_review_refused_$index')),
            )) {
              return 'delegate $index was refused at review';
            }
          }
          return null;
        },
        description: 'both delegates to pass the registry check',
        timeout: const Duration(minutes: 3),
      );
      // Confirm shows each delegate's index and key from the proven entry.
      for (final delegate in [a, b]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('proxy_review_row_${delegate.index}')),
            matching: find.text(
              formatProxyDelegateId(delegate.index, delegate.fingerprint),
            ),
          ),
          findsOne,
        );
      }
      _log('both delegates passed the registry check');
      await _shot(tester, '07-review');
      await tapAppWidget(tester, const ValueKey('proxy_finality_checkbox'));
      await _tapButton(tester, const ValueKey('voting_confirm_submit_button'));

      // One progress screen: the 0x09 batch and its shares, then the kept
      // ballot's casts, through the vote receipt.
      _log('waiting for the delegation and the kept vote to land');
      await _shot(tester, '08-progress');
      await _waitFor(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('voting_submission_done_button')),
        ),
        failIf: () {
          for (final key in const [
            'proxy_confirm_error',
            'proxy_progress_not_counted',
            'proxy_progress_refused',
          ]) {
            if (tester.any(find.byKey(ValueKey(key)))) {
              return '$key: ${_textUnder(tester, ValueKey(key))}';
            }
          }
          final job = container.read(votingSubmissionJobProvider(draftKey));
          if (job.errorMessage != null) return '${job.errorMessage}';
          return container
              .read(votingSessionProvider(_roundId))
              .value
              ?.error
              ?.message
              .toString();
        },
        description: 'the vote receipt',
        timeout: const Duration(minutes: 30),
      );
      final status = await _waitForValue(
        tester,
        // The status screen watches its own account's allocation.
        () => container.read(proxyAllocationStatusProvider(draftKey)),
        description: 'the committed delegation',
      );
      expect(
        status.delegations.map((view) => view.stage).toSet(),
        {ProxyDelegationStage.handedOff},
        reason: 'the vote job completes only once the delegation is handed off',
      );
      _log('delegation sent and kept vote confirmed');
      await _shot(tester, '09-done');

      // The delegates ballot through the chain's delegate API.
      await _gatewayPost('/delegate-ballots');
      _log('the delegates posted their ballots');

      // Done returns to the poll list; the voted round shows each question
      // with the kept vote and both delegates' ballots.
      await _tapButton(tester, const ValueKey('voting_submission_done_button'));
      await _scrollToPoll(tester, ValueKey('voting_poll_action_$_roundId'));
      await _tapButton(tester, ValueKey('voting_poll_action_$_roundId'));
      await _waitFor(
        tester,
        () =>
            tester.any(find.byKey(const ValueKey('proxy_delegation_summary'))),
        description: 'the round status with the delegation',
        timeout: const Duration(minutes: 2),
      );
      await _waitForBallots(
        tester,
        container,
        draftKey,
        (ballot) => ballot.kind == ApiDelegateBallotKind.submitted,
        description: 'both ballots listed',
        timeout: const Duration(minutes: 2),
      );
      await _shot(tester, '10-status-ballots');
      final untilClose = round.voteEndTime.difference(DateTime.now());
      _log(
        'both ballots listed; waiting ${untilClose.inSeconds}s for the close',
      );
      await _waitForBallots(
        tester,
        container,
        draftKey,
        (ballot) => ballot.kind == ApiDelegateBallotKind.counted,
        description: 'both delegations to read Counted',
        timeout: untilClose + const Duration(minutes: 20),
      );
      expect(
        tester.any(find.textContaining('· ${_l10n.proxyCountedLabel}')),
        isTrue,
        reason: 'the round status says the delegated part counted',
      );
      _log('both delegations show Counted');
      await _shot(tester, '11-status-counted');

      // The tally matches a plaintext model of the delegation and the vote.
      final model = <(int, int), BigInt>{};
      void add(int proposal, int option, BigInt ballots) {
        model.update(
          (proposal, option),
          (sum) => sum + ballots,
          ifAbsent: () => ballots,
        );
      }

      for (final (position, proposalId) in proposalIds.indexed) {
        add(proposalId, _keptOption, preview.keptBallots);
        add(proposalId, a.options[position], planned[a.index]!);
        add(proposalId, b.options[position], planned[b.index]!);
      }
      // Counted shows once the round closes, which includes tallying, so the
      // validators may still be committing the tally here.
      final summary = await _tallied();
      final tallied = <(int, int), BigInt>{};
      for (final proposal in summary['proposals'] as List) {
        for (final option in proposal['options'] as List) {
          final value = BigInt.parse('${option['total_value'] ?? 0}');
          if (value == BigInt.zero) continue;
          tallied[(
                int.parse('${proposal['id']}'),
                int.parse('${option['index'] ?? 0}'),
              )] =
              value;
        }
      }
      _log('tally: $tallied; model: $model');
      expect(tallied, model);
    },
    timeout: const Timeout(Duration(minutes: 120)),
  );
}

/// Waits for the session to confirm the wallet's voting eligibility.
Future<VotingSessionState> _waitForEligibility(
  WidgetTester tester,
  ProviderContainer container,
) async {
  late VotingSessionState session;
  await _waitFor(
    tester,
    () {
      final value = container.read(votingSessionProvider(_roundId)).value;
      if (value?.hasConfirmedVotingEligibility != true) return false;
      session = value!;
      return true;
    },
    failIf: () {
      final state = container.read(votingSessionProvider(_roundId));
      if (state.hasError) return 'session failed: ${state.error}';
      return state.value?.error?.message.toString();
    },
    description: 'Ironwood voting eligibility',
    timeout: const Duration(minutes: 10),
  );
  return session;
}

/// Waits on the round status until every delegate's ballot satisfies
/// [reads], reloading the status as the app does when it is reopened.
Future<void> _waitForBallots(
  WidgetTester tester,
  ProviderContainer container,
  VotingSessionKey draftKey,
  bool Function(ApiDelegateBallotView ballot) reads, {
  required String description,
  required Duration timeout,
}) async {
  var polls = 0;
  await _waitFor(
    tester,
    () {
      if (++polls % 100 == 0) {
        container.invalidate(proxyAllocationStatusProvider(draftKey));
      }
      final status = container
          .read(proxyAllocationStatusProvider(draftKey))
          .value;
      return status != null &&
          status.delegations.every((view) => reads(view.ballot));
    },
    failIf: () {
      final status = container
          .read(proxyAllocationStatusProvider(draftKey))
          .value;
      for (final view in status?.delegations ?? const []) {
        if (view.stage == ProxyDelegationStage.notCounted ||
            view.ballot.kind == ApiDelegateBallotKind.notCounted) {
          return 'delegate ${view.delegateIndex} was not counted';
        }
      }
      return null;
    },
    description: description,
    timeout: timeout,
  );
}

/// The value of an async provider once it has one, failing on an error.
Future<T> _waitForValue<T>(
  WidgetTester tester,
  AsyncValue<T?> Function() read, {
  required String description,
}) async {
  late T value;
  await _waitFor(
    tester,
    () {
      final current = read().value;
      if (current == null) return false;
      value = current;
      return true;
    },
    failIf: () => read().hasError ? '${read().error}' : null,
    description: description,
    timeout: const Duration(minutes: 3),
  );
  return value;
}

/// Pumps until [condition] holds, failing at once when [failIf] names a
/// reason or when [timeout] passes.
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  String? Function()? failIf,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  var polls = 0;
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    final reason = failIf?.call();
    if (reason != null) fail('$description: $reason');
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (++polls % 300 == 0) _log('still waiting for $description');
  }
  fail('Timed out waiting for $description.');
}

/// Taps the enabled, hit-testable button keyed [key].
Future<void> _tapButton(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final finder = find.byKey(key);
  await _waitFor(
    tester,
    () {
      if (!tester.any(finder)) return false;
      final widget = tester.widget(finder);
      return widget is! AppButton || widget.onPressed != null;
    },
    description: '$key to enable',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  final inkWell = find.descendant(of: finder, matching: find.byType(InkWell));
  final target = tester.any(inkWell)
      ? inkWell.hitTestable()
      : finder.hitTestable();
  await _waitFor(
    tester,
    () => tester.any(target),
    description: '$key to become hit-testable',
    timeout: timeout,
  );
  await tester.tap(target.first);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Scrolls the lazily built poll list until the card action keyed [key]
/// is built, since `round` leaves earlier rounds of the stack listed too.
Future<void> _scrollToPoll(WidgetTester tester, Key key) async {
  final anyPoll = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'voting_poll_action_',
        ),
  );
  await _waitFor(
    tester,
    () => tester.any(anyPoll),
    description: 'the poll list',
    timeout: const Duration(minutes: 2),
  );
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    scrollable: find
        .ancestor(of: anyPoll.first, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 100,
  );
}

/// Taps the widget keyed [key] once it renders.
Future<void> _tap(
  WidgetTester tester,
  Key key, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final finder = find.byKey(key);
  await _waitFor(
    tester,
    () => tester.any(finder),
    description: '$key to appear',
    timeout: timeout,
  );
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  final inkWell = find.descendant(of: finder, matching: find.byType(InkWell));
  if (tester.any(inkWell)) {
    tester.widget<InkWell>(inkWell.first).onTap?.call();
  } else {
    await tester.tap(finder.hitTestable().first);
  }
  await tester.pump(const Duration(milliseconds: 250));
}

/// Whether any text reads [text].
bool _anyText(WidgetTester tester, String text) => tester.any(find.text(text));

/// The first text under the widget keyed [key].
String _textUnder(WidgetTester tester, Key key) =>
    textForKey(tester, key) ?? '<no text>';

/// Submits the text field keyed [key] as its keyboard action would.
void _submit(WidgetTester tester, Key key) {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  final field = tester.widget<EditableText>(editable);
  expect(field.textInputAction, TextInputAction.search);
  field.onSubmitted?.call(field.controller.text);
}

/// Polls the round's vote summary until it reads tallied (status 3), for up
/// to two minutes.
Future<Map<String, dynamic>> _tallied() async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (true) {
    final summary = await _gatewayGet(
      '/vote.vizor-vote.invalid/shielded-vote/v1/vote-summary/$_roundId',
    );
    if (summary['status'] == 3) return summary;
    if (DateTime.now().isAfter(deadline)) {
      fail('the round is not tallied: status ${summary['status']}');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// GETs a JSON object from the harness gateway.
Future<Map<String, dynamic>> _gatewayGet(String path) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('$proxyRegtestGatewayUrl$path'),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      fail('GET $path answered ${response.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

/// POSTs an empty body to one of the harness gateway's control routes.
Future<void> _gatewayPost(String path) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('$proxyRegtestGatewayUrl$path'),
    );
    request.contentLength = 0;
    final response = await request.close().timeout(const Duration(minutes: 6));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      fail('POST $path answered ${response.statusCode}: $body');
    }
  } finally {
    client.close(force: true);
  }
}

/// Saves the app's current frame as `<name>.png` in [_screenshotDir] under
/// the app's temp directory, when it is set.
Future<void> _shot(WidgetTester tester, String name) async {
  if (_screenshotDir.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 300));
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final png = await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.flutterView.physicalSize,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  });
  final file = File('${Directory.systemTemp.path}/$_screenshotDir/$name.png');
  file
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!);
  _log('saved screenshot ${file.path}');
}

/// Logs one test step.
void _log(String message) {
  debugPrint('[proxy-delegation-e2e] $message');
}
