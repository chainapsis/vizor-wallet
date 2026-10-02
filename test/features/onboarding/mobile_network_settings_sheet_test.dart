@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_network_settings_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/providers/welcome_network_settings_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';
import '../../figma_compare/figma_compare_font_loader.dart';
import '../../support/payment_link_navigation_support.dart';

class _Privacy extends NetworkPrivacyNotifier {
  _Privacy([this.initial = const NetworkPrivacyState.off()]);
  final NetworkPrivacyState initial;
  final connecting = Completer<void>();
  @override
  NetworkPrivacyState build() => initial;
  void publish(NetworkPrivacyState next) => state = next;
  @override
  Future<void> setTorEnabled(bool enabled) async {
    state = enabled
        ? const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connecting,
          )
        : const NetworkPrivacyState.off();
    if (enabled) await connecting.future;
  }
}

class _Endpoint extends RpcEndpointNotifier {
  final pending = Completer<void>();
  int submissions = 0;
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
  @override
  Future<void> setCustom(String input) async {
    submissions++;
    await pending.future;
    state = state.copyWith(
      lightwalletdUrl: normalizeRpcEndpointUrl(input, allowDefaultPort: true),
      presetId: kCustomRpcEndpointPresetId,
    );
  }
}

class _Uris extends IncomingUriService {
  @override
  Stream<String> get uriStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
}

Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester,
  _Privacy privacy,
  _Endpoint endpoint, {
  bool additional = false,
  bool incoming = false,
  double keyboard = 0,
  double scale = 1,
}) async {
  final router = GoRouter(
    initialLocation: additional ? '/add-account' : '/welcome',
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const MobileWelcomeScreen(animateBackground: false),
      ),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const MobileWelcomeScreen(
          animateBackground: false,
          showBackButton: true,
        ),
      ),
      GoRoute(
        path: '/gift',
        builder: (_, _) => const Scaffold(body: Text('gift-route')),
      ),
      GoRoute(
        path: '/onboarding/intro',
        builder: (_, _) => const Scaffold(body: Text('create-route')),
      ),
    ],
  );
  addTearDown(router.dispose);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        networkPrivacyProvider.overrideWith(() => privacy),
        rpcEndpointProvider.overrideWith(() => endpoint),
        incomingUriServiceProvider.overrideWithValue(_Uris()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => AppTheme(
              data: AppThemeData.dark,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                  textScaler: TextScaler.linear(scale),
                ),
                child: AppToastHost(
                  child: incoming
                      ? buildIncomingLinkHostForTest(
                          router: router,
                          child: child!,
                        )
                      : child!,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('mobile_welcome_network_settings')),
  );
  await tester.pumpAndSettle();
}

Future<void> _tryDismiss(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Close'));
  await tester.pumpAndSettle();
  await tester.tapAt(const Offset(3, 3));
  await tester.pumpAndSettle();
  await tester.drag(find.text('Network settings'), const Offset(0, 450));
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      '$platform blocks every exit while connecting and cancellation unlocks the sheet',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final privacy = _Privacy();
        final (container, _) = await _pump(tester, privacy, _Endpoint());
        await _open(tester);
        expect(find.text('Private queries'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('mobile_settings_tor_row')));
        await tester.pumpAndSettle();
        expect(container.read(welcomeNetworkSettingsPresentedProvider), isTrue);
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
          isFalse,
        );
        await _tryDismiss(tester);
        expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('mobile_settings_tor_row')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
          isTrue,
        );
        // The superseded enable is still pending. It must not hold the direct
        // route hostage or clear the newer operation's state when it finishes.
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileNetworkSettingsSheet), findsNothing);
        expect(
          container.read(welcomeNetworkSettingsPresentedProvider),
          isFalse,
        );
        privacy.connecting.complete();
        await tester.pump();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('connected Tor stays open; RPC verifies then closes once', (
    tester,
  ) async {
    final privacy = _Privacy();
    final endpoint = _Endpoint();
    await _pump(tester, privacy, endpoint);
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_settings_tor_row')));
    await tester.pumpAndSettle();
    privacy.publish(
      const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connected,
      ),
    );
    privacy.connecting.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('welcome_endpoint_input')),
      'rpc.example:443',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('welcome_endpoint_update')));
    await tester.pumpAndSettle();
    expect(find.text('Checking endpoint…'), findsOneWidget);
    await _tryDismiss(tester);
    expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
    expect(endpoint.submissions, 1);
    endpoint.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MobileNetworkSettingsSheet), findsNothing);
    expect(find.text('Endpoint updated'), findsOneWidget);
    expect(endpoint.state.hostPort, 'rpc.example:443');
  });

  for (final error in [
    const FormatException('Endpoint is for test, but this wallet uses main.'),
    const RpcEndpointSaveException('storage unavailable'),
  ]) {
    testWidgets('RPC error keeps draft and distinguishes $error', (
      tester,
    ) async {
      final endpoint = _Endpoint();
      await _pump(tester, _Privacy(), endpoint);
      await _open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('welcome_endpoint_input')),
        'rpc.example:443',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('welcome_endpoint_update')));
      await tester.pump();
      endpoint.pending.completeError(error);
      await tester.pumpAndSettle();
      expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('welcome_endpoint_input')),
      );
      expect(field.controller!.text, 'rpc.example:443');
      expect(
        find.text(
          error is FormatException
              ? error.message
              : "Couldn't save the endpoint. Try again.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'saved Tor opens a single sheet; Gift waits until ready and closed',
    (tester) async {
      final privacy = _Privacy(
        const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connecting,
        ),
      );
      final (container, router) = await _pump(
        tester,
        privacy,
        _Endpoint(),
        incoming: true,
      );
      expect(find.byType(MobileNetworkSettingsSheet), findsOneWidget);
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(paymentLinkNavigationLink.toUri().toString());
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/welcome');
      privacy.publish(
        const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
        ),
      );
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/welcome');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('gift-route'), findsOneWidget);
      expect(find.byType(MobileNetworkSettingsSheet), findsNothing);
    },
  );

  testWidgets('additional account does not expose network settings', (
    tester,
  ) async {
    await _pump(tester, _Privacy(), _Endpoint(), additional: true);
    expect(
      find.byKey(const ValueKey('mobile_welcome_network_settings')),
      findsNothing,
    );
  });

  testWidgets('short keyboard viewport keeps the editor and action reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      _Privacy(
        const NetworkPrivacyState(
          torEnabled: false,
          status: NetworkPrivacyConnectionStatus.failed,
          targetTorEnabled: true,
        ),
      ),
      _Endpoint(),
      keyboard: 240,
      scale: 1.4,
    );
    await _open(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('welcome_endpoint_input')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('welcome_endpoint_input')),
      'rpc.example:443',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('welcome_endpoint_update')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
