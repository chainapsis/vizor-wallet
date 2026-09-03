import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

// A bare-origin Vizor link means no more than "open Vizor", and Vizor is
// already open by the time the host sees one. It therefore loses to anything
// the user is part-way through: onboarding, import, and add-account hold a
// typed seed phrase or a freshly generated mnemonic in the widget tree alone,
// and `go('/home')` would throw that away with no way back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kIncomingUriChannelName);
  const homeLink = 'https://link.vizor.cash';

  // No `debugDefaultTargetPlatformOverride` here: widget tests already report
  // `TargetPlatform.android`, which is one of the five platforms
  // `IncomingUriService` installs its channel handler on, and setting the
  // override would have to be unwound before the test body ends.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'takePendingUris' => const <String>[],
            'ready' => null,
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pushLink(WidgetTester tester, String uri) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kIncomingUriChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onUris', <String>[uri]),
          ),
          (_) {},
        );
    await tester.pumpAndSettle();
  }

  Future<GoRouter> pumpHost(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        for (final path in const [
          '/home',
          '/activity',
          '/settings',
          '/welcome',
          '/add-account',
          '/onboarding/secret-passphrase',
          '/import/secret-passphrase',
        ])
          GoRoute(
            path: path,
            builder: (context, state) => Text(path, key: ValueKey(path)),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSecurityProvider.overrideWith(_UnlockedSecurityNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => buildIncomingLinkHostForTest(
            router: router,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  for (final origin in const [
    '/welcome',
    '/add-account',
    '/onboarding/secret-passphrase',
    '/import/secret-passphrase',
  ]) {
    testWidgets('a home link on $origin does not navigate', (tester) async {
      final router = await pumpHost(tester, initialLocation: origin);
      expect(locationOf(router), origin);

      await pushLink(tester, homeLink);

      expect(
        locationOf(router),
        origin,
        reason: 'the in-progress screen must survive a bare-origin link',
      );
    });
  }

  for (final origin in const ['/activity', '/settings']) {
    testWidgets('a home link on $origin goes home', (tester) async {
      final router = await pumpHost(tester, initialLocation: origin);
      expect(locationOf(router), origin);

      await pushLink(tester, homeLink);

      expect(locationOf(router), '/home');
    });
  }

  testWidgets('a home link goes home once onboarding is left behind', (
    tester,
  ) async {
    // The gate is on where the user is now, not on where the app started: the
    // same link that was dropped during onboarding must work afterwards.
    final router = await pumpHost(
      tester,
      initialLocation: '/onboarding/secret-passphrase',
    );

    await pushLink(tester, homeLink);
    expect(locationOf(router), '/onboarding/secret-passphrase');

    router.go('/activity');
    await tester.pumpAndSettle();

    await pushLink(tester, homeLink);
    expect(locationOf(router), '/home');
  });
}

class _UnlockedSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}
