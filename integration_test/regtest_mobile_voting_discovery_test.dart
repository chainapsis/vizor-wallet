import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_config_source_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_cache_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_home_entry_provider.dart';
import 'support/mobile_regtest_flow.dart';
import 'support/mobile_voting_regtest_flow.dart';

const _gateway = String.fromEnvironment('ZCASH_E2E_VOTING_GATEWAY_URL');
const _nextRound = String.fromEnvironment('ZCASH_E2E_VOTE_NEXT_ROUND_ID');
const _cardKey = ValueKey('mobile_home_coinholder_voting');

Future<Map<String, dynamic>> _get(String path) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(
      Uri.parse('$_gateway$path'),
    )).close();
    expect(response.statusCode, 200);
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

VotingHomeRoundList _list(ProviderContainer container) {
  final source = container
      .read(votingConfigSourceProvider)
      .requireValue
      .sourceUrl;
  return container
      .read(votingHomeCacheProvider.notifier)
      .list(votingHomeListKey('regtest', source))!;
}

Future<void> _leaveHome(WidgetTester tester) => tapUntilVisible(
  tester,
  trigger: find.bySemanticsLabel('Settings'),
  outcome: find.byKey(const ValueKey('mobile_settings_coinholder_voting_row')),
  description: 'Settings before Home reentry',
);

Future<void> _waitForRevision(
  WidgetTester tester,
  ProviderContainer container,
  String revision,
) => pumpUntil(
  tester,
  () => _list(container).discoveryRevision == revision,
  description: 'new discovery revision committed by full refresh',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeMobileVotingRegtestRuntime);
  testWidgets(
    'completed Home hides, then discovery reveals a new eligible round',
    (tester) async {
      expect(_nextRound, matches(RegExp(r'^[0-9a-f]{64}$')));
      await completeMobileRegtestVote(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('mobile_home_send'))),
      );
      final initial = _list(container);
      expect(initial.discoveryRevision, isNotNull);
      expect(initial.isFresh(DateTime.now()), true);
      expect(initial.rounds.any((r) => r.roundId == _nextRound), false);
      final before = await _get('/metrics');
      // No forced refresh, cache invalidation or clock jump: use real tab navigation.
      await _leaveHome(tester);
      await openHomeTab(tester);
      await pumpUntil(
        tester,
        () => container.read(votingHomeEntryVisibleProvider) == false,
        description: 'completed entry remains hidden',
      );
      // Wait until the probe actually completed (the response body may arrive later
      // than the metrics increment), before comparing full-refresh request counts.
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          if ((await _get('/metrics'))['discovery_requests'] >
              before['discovery_requests']) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('Home did not probe discovery');
      });
      await tester.pump(const Duration(seconds: 1));
      final unchanged = await _get('/metrics');
      expect(unchanged['config_requests'], before['config_requests']);
      expect(unchanged['round_list_requests'], before['round_list_requests']);
      expect(find.byKey(_cardKey), findsNothing);

      // Change only a server label: a new revision alone must NOT show the entry.
      await _leaveHome(tester);
      await postDriver('/publish-discovery', {
        'stage': 'same-round',
      }, baseUrl: _gateway);
      final labelRevision =
          (await _get('/v1/voting/discovery/prod'))['revision'] as String;
      expect(labelRevision, isNot(initial.discoveryRevision));
      await openHomeTab(tester);
      await _waitForRevision(tester, container, labelRevision);
      await expectVotingHomeHidden(tester, container, restored: false);
      final labelMetrics = await _get('/metrics');
      expect(
        labelMetrics['config_requests'],
        greaterThan(unchanged['config_requests']),
      );
      expect(
        labelMetrics['round_list_requests'],
        greaterThan(unchanged['round_list_requests']),
      );

      await _leaveHome(tester);
      await postDriver('/publish-discovery', {
        'stage': 'new-round',
        'holdConfig': true,
      }, baseUrl: _gateway);
      final newRevision =
          (await _get('/v1/voting/discovery/prod'))['revision'] as String;
      expect(newRevision, isNot(labelRevision));
      var prematureVisibility = false;
      final subscription = container.listen(votingHomeEntryVisibleProvider, (
        _,
        visible,
      ) {
        if (visible) prematureVisibility = true;
      });
      try {
        await openHomeTab(tester);
        var waiting = false;
        for (var i = 0; i < 100 && !waiting; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          waiting = (await _get('/metrics'))['config_waiting'] > 0;
        }
        expect(
          waiting,
          true,
          reason: 'Changed revision must trigger a real config request',
        );
        expect(
          prematureVisibility,
          false,
          reason: 'Revision is a hint, not verified eligibility',
        );
        expect(find.byKey(_cardKey), findsNothing);
        expect(_list(container).discoveryRevision, labelRevision);
      } finally {
        subscription.close();
        await postDriver('/release-discovery-config', {}, baseUrl: _gateway);
      }
      await _waitForRevision(tester, container, newRevision);
      await pumpUntil(
        tester,
        () => tester.any(find.byKey(_cardKey)),
        description: 'new eligible round shows Home entry',
      );
      final list = _list(container);
      final account = container
          .read(accountProvider)
          .requireValue
          .activeAccountUuid!;
      final fact = container
          .read(votingHomeCacheProvider.notifier)
          .fact(
            votingHomeFactKey('regtest', list.fingerprint, account, _nextRound),
          );
      expect(fact.decision, VotingHomeDecision.show);
      expect(fact.participation?.remainingEligible, true);
      expect(fact.participation?.localState, false);
      expect(list.isFresh(DateTime.now()), true);
      final beforeReentry = await _get('/metrics');
      await _leaveHome(tester);
      await openHomeTab(tester);
      await tester.pump(const Duration(seconds: 1));
      final afterReentry = await _get('/metrics');
      expect(
        afterReentry['discovery_requests'],
        greaterThan(beforeReentry['discovery_requests']),
      );
      expect(afterReentry['config_requests'], beforeReentry['config_requests']);
      expect(
        afterReentry['round_list_requests'],
        beforeReentry['round_list_requests'],
      );
      expect(
        afterReentry['participation_requests'],
        beforeReentry['participation_requests'],
      );
      expect(find.byKey(_cardKey), findsOneWidget);
      final stored = await container
          .read(votingFileCacheProvider)
          .read(votingHomeCacheKey);
      expect(stored, contains(newRevision));
      await tapWidget(tester, _cardKey);
      await tapAppButton(
        tester,
        ValueKey('voting_poll_action_$_nextRound'),
        timeout: const Duration(minutes: 2),
      );
      // The new round's action must be navigable, not just a stale Home card.
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('voting_proposal_1_option_0')),
        ),
        description: 'new round detail',
      );
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
