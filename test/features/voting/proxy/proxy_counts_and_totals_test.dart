import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_models.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_route_table.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';

import 'support/mock_proxy_delegation_repository.dart';
import 'support/proxy_test_harness.dart';
import 'support/proxy_values.dart';

/// A wallet that delegated to alice and dana, handed off and counted.
ProxyMockScenario _delegated() {
  final scenario = proxyTestScenario();
  scenario.status = proxyStatus(scenario, [
    'alice_votes',
    'dana_research',
  ], ballot: proxyBallot(ApiDelegateBallotKind.counted, [0, 1, 0]));
  return scenario;
}

void main() {
  final round = kProxyTestRoundId;
  final screens = <String, (String, ProxyMockScenario Function())>{
    'round line, available': ('/voting/poll/$round', proxyTestScenario),
    'round line, committed': ('/voting/poll/$round', _delegated),
    'PD-2 browse': (proxyDelegateDirectoryRoute(round), proxyTestScenario),
    'PD-3 listed profile': (
      proxyDelegateProfileRoute(round, 1),
      proxyTestScenario,
    ),
  };

  group('no delegator screen shows a delegation count or ZEC total', () {
    for (final MapEntry(key: name, value: (location, scenario))
        in screens.entries) {
      testWidgets(name, (tester) async {
        await pumpProxyRoute(tester, location, scenario: scenario());
        expectNoProxyCountsOrTotals(tester);
      });
    }

    testWidgets('PD-2 search results', (tester) async {
      await pumpProxyRoute(
        tester,
        proxyDelegateDirectoryRoute(round),
        scenario: proxyTestScenario(),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('proxy_directory_search')),
          matching: find.byType(EditableText),
        ),
        'kofi_m',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleProxy(tester);
      expectNoProxyCountsOrTotals(tester);
    });

    testWidgets('PD-5 editor and the vote review', (tester) async {
      final scenario = proxyTestScenario();
      final harness = await pumpProxyRoute(
        tester,
        proxyDelegateDirectoryRoute(round),
        scenario: scenario,
      );
      final draft = harness.container.read(
        proxyAllocationDraftProvider(kProxyTestKey).notifier,
      );
      draft.toggle(proxyEntry(scenario, 'alice_votes'));
      draft.setPercent(0, 5000);
      harness.router.push(proxyAllocationRoute(round));
      await settleProxy(tester);
      expectNoProxyCountsOrTotals(tester);
      harness.router.go(votingReviewRoute(round));
      await settleProxy(tester);
      expectNoProxyCountsOrTotals(tester);
    });
  });

  test('delegate pictures never use a platform image decoder', () {
    // CMP-14: pictures are decoded in Rust and drawn from pixels.
    final banned = RegExp(
      r'Image\.network|Image\.memory|Image\.file|NetworkImage|MemoryImage|'
      r'FileImage|instantiateImageCodec|decodeImageFromList|'
      r'ImageDescriptor\.encoded',
    );
    final files = Directory('lib/src/features/voting')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      expect(
        banned.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} uses a banned image API',
      );
    }
    final pictures = File(
      'lib/src/features/voting/proxy/delegate_picture.dart',
    ).readAsStringSync();
    expect(pictures, contains('rust.decodeDelegatePicture('));
    expect(pictures, contains('decodeImageFromPixels('));
  });

  test('route builders match the registered patterns', () {
    final routes = proxyDelegationDesktopRoutes(guard: (child) => child);
    final mobile = proxyDelegationMobileRoutes(guard: (child) => child);
    expect(routes.map((r) => r.path), mobile.map((r) => r.path));
    final built = {
      kProxyDelegateDirectoryPath: proxyDelegateDirectoryRoute('r 1'),
      kProxyDelegateProfilePath: proxyDelegateProfileRoute('r 1', 17),
      kProxyAllocationPath: proxyAllocationRoute('r 1'),
    };
    expect(routes.map((r) => r.path).toSet(), built.keys.toSet());
    for (final MapEntry(key: pattern, value: location) in built.entries) {
      final regex = RegExp(
        '^${pattern.replaceAll(RegExp(r':\w+'), r'[^/]+')}\$',
      );
      expect(regex.hasMatch(location), isTrue, reason: location);
    }
    expect(
      proxyDelegateProfileRoute('r 1', 17),
      '/voting/poll/r%201/delegates/17',
    );
  });
}
