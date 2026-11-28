import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/config/proxy_delegation_feature_config.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/features/voting/proxy/delegate_mode_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_providers.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegation_routes.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_ballot_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_key_import_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_mode_home_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_registration_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/screens/delegate_retire_screen.dart';
import 'package:zcash_wallet/src/features/voting/proxy/widgets/delegate_reauth_gate.dart';

import 'delegate_mode_test_scenarios.dart';
import 'mock_delegate_mode_repository.dart';
import 'proxy_test_harness.dart';

export 'delegate_mode_test_scenarios.dart';
export 'proxy_test_harness.dart' show renderedTexts, settleProxy;

/// Records re-auth prompts and answers them with [allow].
class FakeDelegateReauth {
  /// Creates the fake.
  FakeDelegateReauth({this.allow = true});

  /// The answer to the next prompts.
  bool allow;

  /// When set, prompts wait for it instead of answering [allow] at once.
  Completer<bool>? hold;

  /// Every prompt, in order.
  final List<DelegateReauthPurpose> prompts = [];

  /// The [DelegateReauth] implementation.
  Future<bool> call(BuildContext context, DelegateReauthPurpose purpose) async {
    prompts.add(purpose);
    final hold = this.hold;
    if (hold != null) return hold.future;
    return allow;
  }
}

/// What a pumped delegate-mode route hands back to a test.
class DelegateTestHarness {
  /// Creates the harness.
  DelegateTestHarness(
    this.repository,
    this.router,
    this.container,
    this.reauth,
  );

  /// The mock behind every screen.
  final MockDelegateModeRepository repository;

  /// The router hosting the delegate-mode views.
  final GoRouter router;

  /// The provider container.
  final ProviderContainer container;

  /// The re-auth stand-in.
  final FakeDelegateReauth reauth;

  /// The scenario behind [repository].
  DelegateModeMockScenario get scenario => repository.scenario;

  /// Location of the top route, pushed or not.
  String get location => topRouteLocation(router);
}

/// The delegate-mode views hosted without the desktop shell, with their
/// desktop toolbars.
List<RouteBase> _delegateTestRoutes() {
  /// Hosts [child] in a [Scaffold] for Material ancestors.
  Widget page(Widget child) => Scaffold(body: child);
  return [
    GoRoute(path: '/voting', builder: (_, _) => page(const Text('voting'))),
    GoRoute(
      path: kDelegateModePath,
      builder: (_, _) => page(DelegateModeHomeView(showDesktopToolbar: true)),
    ),
    GoRoute(
      path: kDelegateKeyImportPath,
      builder: (_, _) => page(DelegateKeyImportView(showDesktopToolbar: true)),
    ),
    GoRoute(
      path: kDelegateRegistrationPath,
      builder: (_, _) =>
          page(DelegateRegistrationView(showDesktopToolbar: true)),
    ),
    GoRoute(
      path: kDelegateBallotPath,
      builder: (_, state) => page(
        DelegateRoundBallotView(
          roundId: state.pathParameters['roundId'] ?? '',
          showDesktopToolbar: true,
        ),
      ),
    ),
    GoRoute(
      path: kDelegateRetirePath,
      builder: (_, _) => page(DelegateRetireView(showDesktopToolbar: true)),
    ),
  ];
}

/// Pumps [location] with the delegate-mode views on a mock. [routes]
/// replaces the default hosts, for example with the
/// production route table.
Future<DelegateTestHarness> pumpDelegateRoute(
  WidgetTester tester,
  String location, {
  DelegateModeMockScenario? scenario,
  DateTime? now,
  Size size = const Size(1000, 2400),
  List<RouteBase>? routes,
  double textScale = 1,
  FakeDelegateReauth? reauth,
  List<Override> overrides = const [],
}) async {
  final clockNow = now ?? kProxyTestNow;
  final repository = MockDelegateModeRepository(
    scenario ?? delegateFreshScenario(),
    clock: () => clockNow,
  );
  // A scenario that starts with a key holds its export.
  if (repository.scenario.status.key != null) {
    repository.secret = kDelegateTestSecret;
  }
  final fakeReauth = reauth ?? FakeDelegateReauth();
  final router = GoRouter(
    initialLocation: location,
    routes: routes ?? _delegateTestRoutes(),
  );
  final container = await pumpProxyApp(
    tester,
    router,
    size: size,
    textScale: textScale,
    overrides: [
      proxyDelegationFeatureEnabledProvider.overrideWithValue(true),
      delegateModeRepositoryProvider.overrideWithValue(repository),
      proxyClockProvider.overrideWithValue(() => clockNow),
      delegateReauthProvider.overrideWithValue(fakeReauth.call),
      delegatePrivacyControllerFactoryProvider.overrideWithValue(
        SensitivePrivacyOverlayController.new,
      ),
      ...overrides,
    ],
  );
  return DelegateTestHarness(repository, router, container, fakeReauth);
}

/// The editable text inside the field keyed [key].
Finder delegateField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

/// Taps the widget keyed [key], scrolling it into view first.
Future<void> tapDelegateKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settleProxy(tester);
}

/// A rendered amount of ZEC, such as "12.5 ZEC". No delegate-mode screen
/// shows one: there are no ZEC totals in delegate mode.
final kDelegateZecAmount = RegExp(r'\d[\d,.]*\s*ZEC');

/// A delegation count, which only DG-8 may show.
final kDelegateCount = RegExp(
  r'\bat least \d|\b\d[\d,]*\s+(delegations?|delegators?)\b',
  caseSensitive: false,
);

/// Fails when a rendered text shows a ZEC amount, or, unless
/// [countAllowed], a delegation count.
void expectNoDelegateTotals(WidgetTester tester, {bool countAllowed = false}) {
  final texts = renderedTexts(tester);
  expect(texts, isNotEmpty);
  for (final text in texts) {
    expect(
      kDelegateZecAmount.hasMatch(text),
      isFalse,
      reason: '"$text" shows a ZEC amount',
    );
    if (!countAllowed) {
      expect(
        kDelegateCount.hasMatch(text),
        isFalse,
        reason: '"$text" shows a delegation count',
      );
    }
  }
}
