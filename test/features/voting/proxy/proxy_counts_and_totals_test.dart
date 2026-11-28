import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_route_table.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/voting_routes.dart';

import 'support/proxy_test_harness.dart';

void main() {
  final round = kProxyTestRoundId;

  testWidgets('no delegator screen shows a delegation count or ZEC total', (
    tester,
  ) async {
    final scenario = proxyTestScenario();
    final harness = await pumpProxyRoute(
      tester,
      proxyDelegateDirectoryRoute(round),
      scenario: scenario,
    );
    expectNoProxyCountsOrTotals(tester);
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
      kProxyAllocationPath: proxyAllocationRoute('r 1'),
    };
    expect(routes.map((r) => r.path).toSet(), built.keys.toSet());
    for (final MapEntry(key: pattern, value: location) in built.entries) {
      final regex = RegExp(
        '^${pattern.replaceAll(RegExp(r':\w+'), r'[^/]+')}\$',
      );
      expect(regex.hasMatch(location), isTrue, reason: location);
    }
  });
}
