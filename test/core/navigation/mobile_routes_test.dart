@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_adaptive_frame.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_sidebar_exit.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav_account.dart';
import 'package:zcash_wallet/src/services/native_mobile_navigation_geometry.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_wallet_sidebar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_sync_status.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_page_viewport.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_window_policy.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_sidebar_route_observer.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_submitted_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/go_route_descendants.dart';
import '../../features/swap/support/static_near_intents_swap_provider.dart';

class _NativeGeometryFixture extends NativeMobileNavigationGeometry {
  _NativeGeometryFixture(this.value);
  MobileNavigationGeometry value;
  final events = StreamController<MobileNavigationGeometry?>.broadcast();
  @override
  bool get supportedHost => true;
  @override
  Future<MobileNavigationGeometry?> read() async => value;
  @override
  Stream<MobileNavigationGeometry?> get changes => events.stream;
  void change(MobileNavigationGeometry next) {
    value = next;
    events.add(next);
  }
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1routeraddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: buildMobileRoutes(entryRoutes: const []),
);

Widget _app(
  GoRouter router, {
  bool swapFeatureEnabled = true,
  AppThemeData theme = AppThemeData.dark,
  SyncState? initialSyncState,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    swapFeatureEnabledProvider.overrideWithValue(swapFeatureEnabled),
    // The coin bob loops forever, which would break pumpAndSettle here;
    // Funded so the home tab shows the Send action used by the push
    // test.
    syncProvider.overrideWith(
      () => FakeSyncNotifier(
        initialSyncState ??
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              orchardBalance: BigInt.from(100000000),
            ),
      ),
    ),
    ...overrides,
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: theme, child: child!),
  ),
);

LocalKey? _sendPageKey(WidgetTester tester) =>
    (ModalRoute.of(tester.element(find.byType(MobileSendScreen)))!.settings
            as Page<dynamic>)
        .key;

Iterable<GoRoute> _leafRoutes() =>
    goRouteDescendants(buildMobileRoutes(entryRoutes: const []));

// Read the rendered pill fill and inherited text color, rather than just
// the enabled-color overrides (which stay unchanged even when disabled).
List<({Color? fill, Color? label})> _sidebarPaints(WidgetTester tester) => [
  for (final button
      in find
          .descendant(
            of: find.byType(MobileWalletSidebar),
            matching: find.byType(AppButton),
          )
          .evaluate())
    (
      fill:
          (tester
                      .widget<AnimatedContainer>(
                        find
                            .descendant(
                              of: find.byWidget(button.widget),
                              matching: find.byType(AnimatedContainer),
                            )
                            .first,
                      )
                      .decoration
                  as ShapeDecoration)
              .color,
      label:
          (tester
                      .widget<RichText>(
                        find
                            .descendant(
                              of: find.byWidget(button.widget),
                              matching: find.byType(RichText),
                            )
                            .first,
                      )
                      .text
                  as TextSpan)
              .style!
              .color,
    ),
];

void main() {
  testWidgets('the wide layout sidebar shows a short catch-up without a '
      'percentage', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 720);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              MobileAdaptiveFrame(router: GoRouter.of(context), child: child),
          routes: [
            GoRoute(
              path: '/activity',
              builder: (_, _) => const Scaffold(body: Text('Activity pane')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        initialSyncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncing: true,
          phase: 'scan',
          scannedHeight: 3000000,
          chainTipHeight: 3000003,
          remainingScanBlocks: 3,
          lastSyncStartedAt: DateTime.now(),
          startedFromCompletedSync: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sidebar = tester.widget<MobileWalletSidebar>(
      find.byType(MobileWalletSidebar),
    );
    expect(sidebar.status.label, kSyncStatusCatchingUpLabel);
    expect(
      find.descendant(
        of: find.byType(MobileWalletSidebar),
        matching: find.textContaining('% Syncing'),
      ),
      findsNothing,
    );
  });

  for (final interrupted in ['none', 'different', 'same']) {
    testWidgets(
      'sidebar waits for cleanup, serializes input and respects route changes ($interrupted)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(900, 720);
        addTearDown(tester.view.reset);
        var cleanup = Completer<bool>();
        var calls = 0;
        final router = GoRouter(
          initialLocation: '/pay',
          routes: [
            ShellRoute(
              builder: (context, state, child) => MobileAdaptiveFrame(
                router: GoRouter.of(context),
                child: child,
              ),
              routes: [
                GoRoute(
                  path: '/pay',
                  pageBuilder: (_, state) => NoTransitionPage(
                    key: ValueKey(state.extra ?? 'original'),
                    child: MobileSidebarExitScope(
                      onExit: () {
                        calls++;
                        return cleanup.future;
                      },
                      child: const Scaffold(body: Text('Editor')),
                    ),
                  ),
                ),
                GoRoute(
                  path: '/activity',
                  builder: (_, _) =>
                      const Scaffold(body: Text('Activity pane')),
                ),
                GoRoute(
                  path: '/settings',
                  builder: (_, _) =>
                      const Scaffold(body: Text('Settings pane')),
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();
        final sidebar = tester.widget<MobileWalletSidebar>(
          find.byType(MobileWalletSidebar),
        );
        expect(sidebar.onSelect, isNotNull);
        expect(sidebar.onAccountTap, isNull);
        final paints = _sidebarPaints(tester);
        sidebar.onSelect!('/activity');
        sidebar.onSelect!('/settings');
        await tester.pump();
        expect(calls, 1);
        expect(mobileVisiblePath(router), '/pay');
        expect(_sidebarPaints(tester), paints);
        // Input is blocked without changing the button appearance. Stale
        // callbacks are also guarded while cancellation is still pending.
        final pending = tester.widget<MobileWalletSidebar>(
          find.byType(MobileWalletSidebar),
        );
        expect(pending.onSelect, isNotNull);
        expect(pending.onAccountTap, isNull);
        pending.onSelect!('/settings');
        await tester.tap(
          find.descendant(
            of: find.byType(MobileWalletSidebar),
            matching: find.text('Settings'),
          ),
          warnIfMissed: false,
        );
        await tester.pump();
        expect(calls, 1);
        expect(mobileVisiblePath(router), '/pay');
        expect(_sidebarPaints(tester), paints);
        if (interrupted == 'none') {
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MobileWalletSidebar)),
          );
          final hold = container
              .read(externalActionGuardProvider.notifier)
              .acquire(blocks: {ExternalAction.navigation});
          await tester.pump();
          expect(
            tester
                .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
                .onSelect,
            isNull,
          );
          expect(
            _sidebarPaints(tester).last.label,
            AppThemeData.dark.colors.button.ghost.label,
          );
          expect(
            find.byKey(const ValueKey('mobile_sidebar_controls_veil')),
            findsOneWidget,
          );
          hold.release();
          await tester.pump();
          expect(
            find.byKey(const ValueKey('mobile_sidebar_controls_veil')),
            findsNothing,
          );
          expect(_sidebarPaints(tester), paints);
          expect(
            tester
                .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
                .inputBlocked,
            isTrue,
          );
        }
        if (interrupted != 'none') {
          final nextPath = interrupted == 'same' ? '/pay' : '/settings';
          router.go(nextPath, extra: 'replacement');
          await tester.pumpAndSettle();
          cleanup.complete(true);
          await tester.pumpAndSettle();
          expect(mobileVisiblePath(router), nextPath);
        } else {
          cleanup.complete(false);
          await tester.pumpAndSettle();
          expect(mobileVisiblePath(router), '/pay');
          cleanup = Completer<bool>();
          tester
              .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
              .onSelect!('/activity');
          cleanup.complete(true);
          await tester.pumpAndSettle();
          expect(mobileVisiblePath(router), '/activity');
          expect(calls, 2);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(393, 852);
    addTearDown(view.resetDevicePixelRatio);
    addTearDown(view.resetPhysicalSize);
  });
  testWidgets(
    'closed native side placement changes only tabs and retains the home header',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(492, 720);
      tester.view.padding = const FakeViewPadding(right: 84);
      tester.view.viewPadding = const FakeViewPadding(right: 84);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      const closed = MobileNavigationGeometry(
        edge: MobileNavigationEdge.right,
        viewSize: Size(492, 720),
        safeRect: Rect.fromLTWH(0, 0, 408, 720),
        occlusions: [Rect.fromLTWH(408, 0, 84, 180)],
      );
      final native = _NativeGeometryFixture(
        const MobileNavigationGeometry(
          edge: MobileNavigationEdge.none,
          viewSize: Size(492, 720),
          safeRect: Rect.fromLTWH(0, 0, 408, 720),
          occlusions: [],
        ),
      );
      addTearDown(native.events.close);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          router,
          swapFeatureEnabled: false,
          overrides: [
            mobileNavigationGeometryServiceProvider.overrideWithValue(native),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final home = tester.element(find.byType(MobileHomeScreen));
      final header = tester.getRect(find.byType(MobileTopNavAccount));
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        tester.widget<AppMobileTabBar>(find.byType(AppMobileTabBar)).axis,
        Axis.horizontal,
      );
      native.change(closed);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<AppMobileTabBar>(find.byType(AppMobileTabBar)).axis,
        Axis.vertical,
      );
      expect(
        tester.getRect(find.byType(AppMobileTabBar)).left,
        greaterThanOrEqualTo(408),
      );
      expect(
        tester.getRect(find.byType(AppMobileTabBar)).bottom,
        closeTo(712, 0.01),
      );
      expect(tester.getRect(find.byType(MobileTopNavAccount)), header);
      expect(
        tester.widget<ListView>(find.byType(ListView).first).padding,
        list.padding,
      );
      expect(tester.element(find.byType(MobileHomeScreen)), same(home));
      expect(find.byType(MobileWalletSidebar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wide home scrolls to screen bottom and keeps foreground within native inset',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      // Deliberately omit Flutter padding: native safety must still reach panes.
      final native = _NativeGeometryFixture(
        const MobileNavigationGeometry(
          edge: MobileNavigationEdge.right,
          viewSize: Size(951, 669),
          safeRect: Rect.fromLTWH(0, 0, 867, 635),
          occlusions: [],
        ),
      );
      addTearDown(native.events.close);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          router,
          overrides: [
            mobileNavigationGeometryServiceProvider.overrideWithValue(native),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(MobileHomeScreen)).bottom, 669);
      final homeList = find
          .descendant(
            of: find.byType(MobileHomeScreen),
            matching: find.byType(ListView),
          )
          .first;
      expect(tester.getRect(homeList).bottom, 669);
      expect(
        tester
            .widget<ListView>(homeList)
            .padding!
            .resolve(TextDirection.ltr)
            .bottom,
        34,
      );
      final sidebar = find.byType(MobileWalletSidebar);
      expect(tester.getRect(sidebar).top, 16);
      expect(tester.getRect(sidebar).bottom, 653);
      final sync = find.descendant(
        of: sidebar,
        matching: find.byType(MobileSyncStatus),
      );
      // No native corner mock here: the 24pt fallback plus 16pt glow gap.
      expect(tester.getRect(sync).bottom, 653 - AppRadii.large - AppSpacing.sm);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'wide transitions include both margins and back swipes can cancel or complete',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      final sidebar = tester.getRect(find.byType(MobileWalletSidebar));
      final home = find.byType(MobileHomeScreen);
      final homeRect = tester.getRect(home);
      expect(homeRect.width, 440);
      showAppToast(tester.element(home), 'Pane toast');
      await tester.pump();
      expect(tester.getCenter(find.byType(AppToast)).dx, homeRect.center.dx);
      final pushed = router.push<void>('/receive');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final receive = find.byType(MobileReceiveScreen);
      final page = find
          .ancestor(of: receive, matching: find.byType(MobilePageViewport))
          .first;
      final navigator = Navigator.of(tester.element(receive));
      final viewport = tester.getRect(find.byWidget(navigator.widget));
      expect(viewport.width, greaterThan(homeRect.width));
      expect(viewport.right, 951);
      expect(tester.getRect(page).size, viewport.size);
      expect(tester.getRect(page).left, greaterThan(viewport.left));
      expect(tester.getRect(page).left, lessThan(viewport.right));
      // Receive alone expands into the contiguous native-safe pane. The
      // branch beneath it retains its ordinary 440px content geometry.
      const receiveRect = Rect.fromLTWH(288, 0, 563, 669);
      expect(tester.getRect(receive).width, receiveRect.width);
      expect(tester.getRect(find.byType(MobileWalletSidebar)), sidebar);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.getRect(receive), receiveRect);
      final start = Offset(viewport.left + 2, viewport.center.dy);
      var drag = await tester.startGesture(start);
      await drag.moveBy(Offset(viewport.width * .25, 0));
      await tester.pump(const Duration(milliseconds: 400));
      final route = ModalRoute.of(tester.element(receive))!;
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(tester.getRect(page).left, greaterThan(viewport.left));
      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(receive, findsOneWidget);
      expect(tester.getRect(receive), receiveRect);
      drag = await tester.startGesture(start);
      await drag.moveBy(Offset(viewport.width * .75, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await drag.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await pushed;
      expect(receive, findsNothing);
      expect(tester.getRect(home), homeRect);
      expect(tester.getRect(find.byType(MobileWalletSidebar)), sidebar);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'adaptive frame preserves branch state and pushed pages through resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final observer = MobileSidebarRouteObserver();
      final router = GoRouter(
        initialLocation: '/home',
        observers: [observer],
        routes: buildMobileRoutes(entryRoutes: const []),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          router,
          swapFeatureEnabled: false,
          overrides: [
            mobileSidebarRouteObserverProvider.overrideWithValue(observer),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      final home = tester.element(find.byType(MobileHomeScreen));
      final navigator = router.routerDelegate.navigatorKey.currentState;
      final sidebar = find.byType(MobileWalletSidebar);
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text('Activity')),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/activity');
      await tester.tap(
        find.descendant(of: sidebar, matching: find.text('Home')),
      );
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(MobileHomeScreen)), same(home));
      router.push('/receive');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      final receive = tester.element(find.byType(MobileReceiveScreen));
      for (final size in [
        const Size(393, 852),
        const Size(690, 829),
        const Size(800, 800),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        expect(find.byType(MobileWalletSidebar), findsNothing);
        expect(tester.element(find.byType(MobileReceiveScreen)), same(receive));
        expect(
          router.routerDelegate.navigatorKey.currentState,
          same(navigator),
        );
      }
      tester.view.physicalSize = const Size(900, 720);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      expect(tester.element(find.byType(MobileReceiveScreen)), same(receive));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'root policy remains stable inside the pane and with a keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(690, 829);
      addTearDown(tester.view.reset);
      late MobileWindowPolicy policy;
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          ShellRoute(
            builder: (context, _, child) =>
                MobileAdaptiveFrame(router: GoRouter.of(context), child: child),
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => Builder(
                  builder: (context) {
                    policy = MobileWindowPolicyScope.of(context);
                    return const Scaffold(body: Text('Settings body'));
                  },
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      expect(policy.usesWideLayout, isFalse);
      expect(find.byType(MobileWalletSidebar), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      await tester.pumpAndSettle();
      expect(policy.safeRect.size, const Size(690, 829));
      expect(policy.usesWideLayout, isFalse);
      expect(find.byType(MobileWalletSidebar), findsNothing);
      tester.view.resetViewInsets();
      tester.view.physicalSize = const Size(829, 690);
      await tester.pumpAndSettle();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      expect(policy.safeRect.size, const Size(829, 690));
      expect(policy.usesWideLayout, isTrue);
      expect(
        MediaQuery.sizeOf(tester.element(find.text('Settings body'))).width,
        lessThan(829),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 350);
      await tester.pumpAndSettle();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      expect(policy.safeRect.size, const Size(829, 690));
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in [AppThemeData.light, AppThemeData.dark]) {
    testWidgets(
      'sidebar keeps its appearance in intermediate navigation frames (${theme == AppThemeData.dark ? 'dark' : 'light'})',
      (tester) async {
        tester.view.physicalSize = const Size(900, 720);
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _app(router, theme: theme, swapFeatureEnabled: false),
        );
        await tester.pumpAndSettle();
        final sidebar = find.byType(MobileWalletSidebar);
        final accountPaint = _sidebarPaints(tester).first;
        final unselectedPaint = _sidebarPaints(tester).last;
        for (final destination in ['/activity', '/settings', '/home']) {
          final before = tester.widget<MobileWalletSidebar>(sidebar);
          // Two callbacks before the next frame must only accept the first.
          before.onSelect!(destination);
          before.onSelect!(destination == '/home' ? '/settings' : '/home');
          before.onAccountTap!();
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final paints = _sidebarPaints(tester);
            final current = tester
                .widget<MobileWalletSidebar>(sidebar)
                .currentPath;
            expect(current, destination);
            expect(paints.first, accountPaint);
            for (var item = 0; item < 3; item++) {
              final selected =
                  ['/home', '/activity', '/settings'][item] == current;
              expect(
                paints[item + 1].label,
                selected
                    ? theme.colors.navPanel.activeIcon
                    : unselectedPaint.label,
              );
              expect(
                paints[item + 1].fill,
                selected
                    ? theme.colors.navPanel.activeBg
                    : unselectedPaint.fill,
              );
            }
            expect(find.byType(MobileAccountsSheet), findsNothing);
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'sidebar blocks modals and protected work but can leave send input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final observer = MobileSidebarRouteObserver();
      final router = GoRouter(
        initialLocation: '/home',
        observers: [observer],
        routes: buildMobileRoutes(entryRoutes: const []),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          router,
          swapFeatureEnabled: false,
          overrides: [
            mobileSidebarRouteObserverProvider.overrideWithValue(observer),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(MobileWalletSidebar);
      AppButton settings() => tester.widget<AppButton>(
        find
            .ancestor(
              of: find.descendant(of: sidebar, matching: find.text('Settings')),
              matching: find.byType(AppButton),
            )
            .first,
      );
      final context =
          router.routerDelegate.navigatorKey.currentState!.overlay!.context;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Modal')),
        ),
      );
      await tester.pumpAndSettle();
      expect(settings().onPressed, isNotNull);
      settings().onPressed!();
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      router.pop();
      await tester.pumpAndSettle();
      expect(settings().onPressed, isNotNull);
      final container = ProviderScope.containerOf(tester.element(sidebar));
      final hold = container
          .read(externalActionGuardProvider.notifier)
          .tryProtect()!;
      await tester.pump();
      expect(settings().onPressed, isNull);
      hold.release();
      await tester.pump();
      router.push('/send');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(MobileWalletSidebar), findsOneWidget);
      expect(settings().onPressed, isNotNull);
      settings().onPressed!();
      await tester.pumpAndSettle();
      expect(mobileVisiblePath(router), '/settings');
      expect(find.byType(MobileSendScreen), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'profile modal covers the window and preserves sidebar across resize',
    (tester) async {
      tester.view.physicalSize = const Size(982, 654);
      final observer = MobileSidebarRouteObserver();
      final router = GoRouter(
        initialLocation: '/home',
        observers: [observer],
        routes: buildMobileRoutes(entryRoutes: const []),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          router,
          swapFeatureEnabled: false,
          overrides: [
            mobileSidebarRouteObserverProvider.overrideWithValue(observer),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final sidebar = find.byType(MobileWalletSidebar);
      final sidebarElement = tester.element(sidebar);
      final sidebarRect = tester.getRect(sidebar);
      final home = tester.element(find.byType(MobileHomeScreen));
      final settingsPoint = tester.getCenter(
        find.descendant(of: sidebar, matching: find.text('Settings')),
      );
      final buttons = tester
          .widgetList<AppButton>(
            find.descendant(of: sidebar, matching: find.byType(AppButton)),
          )
          .toList();
      Future<void> open() async {
        await tester.tap(
          find.descendant(of: sidebar, matching: find.text('Account1')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MobileAccountsSheet), findsOneWidget);
        expect(
          tester.getRect(find.byType(ModalBarrier).last),
          const Rect.fromLTWH(0, 0, 982, 654),
        );
        expect(tester.getSize(find.byType(MobileModalCard)).width, 440);
      }

      await open();
      expect(tester.element(sidebar), same(sidebarElement));
      expect(tester.getRect(sidebar), sidebarRect);
      final after = tester
          .widgetList<AppButton>(
            find.descendant(of: sidebar, matching: find.byType(AppButton)),
          )
          .toList();
      for (var i = 0; i < buttons.length; i++) {
        expect(after[i].onPressed, isNotNull);
        expect(
          after[i].enabledBackgroundColor,
          buttons[i].enabledBackgroundColor,
        );
        expect(after[i].enabledLabelColor, buttons[i].enabledLabelColor);
      }
      // A sidebar tap hits the root barrier, dismissing without navigating.
      await tester.tapAt(settingsPoint);
      await tester.pumpAndSettle();
      expect(find.byType(MobileAccountsSheet), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/home');
      await open();
      final sheet = tester.element(find.byType(MobileAccountsSheet));
      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(MobileAccountsSheet)), same(sheet));
      expect(
        tester.getRect(find.byType(ModalBarrier).last),
        const Rect.fromLTWH(0, 0, 393, 852),
      );
      expect(tester.getSize(find.byType(MobileModalCard)).width, 393);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(MobileAccountsSheet)).bottom,
        lessThanOrEqualTo(852 - 280),
      );
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.physicalSize = const Size(982, 654);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(MobileHomeScreen)), same(home));
      // The root modal retains GoRouter context for account management.
      await tester.tap(find.text('Manage accounts'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileAccountsSheet), findsNothing);
      expect(mobileVisiblePath(router), '/accounts');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  for (final size in [const Size(393, 852), const Size(951, 669)]) {
    testWidgets('home opens shielding over a frozen pane backdrop ($size)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      final router = _router();
      await tester.pumpWidget(
        _app(
          router,
          initialSyncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            percentage: 1,
            orchardBalance: BigInt.from(1492000000),
            transparentBalance: BigInt.from(1412000000),
            canShieldTransparentBalance: true,
            shieldTransparentAmount: BigInt.from(1411990000),
            shieldTransparentFee: BigInt.from(10000),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_home_shield_balance_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final fade = find
          .ancestor(
            of: find.byType(MobileShieldScene),
            matching: find.byType(FadeTransition),
          )
          .first;
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(0.5, 0.01),
      );
      expect(
        find.descendant(
          of: find.byType(MobileShieldScene),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 120));
      final scene = tester.widget<MobileShieldScene>(
        find.byType(MobileShieldScene),
      );
      expect(scene.backdrop, isNotNull);
      expect(
        scene.backdrop!.image.width,
        tester.getSize(find.byType(MobileShieldScene)).width,
      );
      expect(scene.backdrop!.image.height, tester.view.physicalSize.height);
      final route = ModalRoute.of(
        tester.element(find.byType(MobileShieldScene)),
      );
      expect(route!.opaque, isFalse);
      expect(route.transitionDuration, const Duration(milliseconds: 240));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 180),
      );
      expect(find.byType(ImageFiltered), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(0.5, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(0, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(MobileShieldScene), findsNothing);
      expect(find.byType(MobileHomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final path in ['/home/keystone-shield', '/home/ledger-shield']) {
      testWidgets('$path is a transparent pane route ($size)', (tester) async {
        tester.view.physicalSize = size;
        final router = _router();
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();
        unawaited(router.push<void>(path));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final route = ModalRoute.of(
          tester.element(find.byType(MobileShieldScene)),
        );
        expect(route!.opaque, isFalse);
        expect(route.transitionDuration, const Duration(milliseconds: 240));
        expect(
          route.reverseTransitionDuration,
          const Duration(milliseconds: 180),
        );
        expect(find.text('Transparent Balance'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  test('registers the mobile payment-link intake route', () {
    final paths = _leafRoutes().map((route) => route.path);

    expect(paths, contains('/payment-links'));
  });

  test('does not register the removed private review route', () {
    final paths = _leafRoutes().map((route) => route.path);

    expect(paths, isNot(contains('/migration/private/review')));
  });

  test('registers the complete mobile coinholder voting route tree', () {
    final paths = _leafRoutes().map((route) => route.path).toSet();

    expect(
      paths,
      containsAll({
        '/voting',
        '/voting/poll/:roundId',
        '/voting/poll/:roundId/review',
        '/voting/poll/:roundId/status',
        '/voting/poll/:roundId/submitted',
        '/voting/poll/:roundId/results',
      }),
    );
  });

  test('shows migration options while guarding private-only routes', () {
    final routes = _leafRoutes();
    final options = routes.singleWhere(
      (route) => route.path == '/migration/options',
    );
    final notifications = routes.singleWhere(
      (route) => route.path == '/migration/private/notifications',
    );

    expect(options.redirect, isNull);
    expect(notifications.redirect, isNotNull);
  });

  testWidgets('tab shell renders all four tabs and switches branches', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    expect(find.byType(MobileHomeScreen), findsOneWidget);
    final shellRoute = ModalRoute.of(
      tester.element(find.byType(AppMobileShell)),
    );
    expect(shellRoute, isA<CupertinoRouteTransitionMixin<dynamic>>());
    for (final label in ['Home', 'Swap', 'Activity', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }

    await tester.tap(find.bySemanticsLabel('Activity').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileActivityScreen), findsOneWidget);
    expect(find.byType(MobileHomeScreen), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.bySemanticsLabel('Close'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.byType(AppMobileShell), findsOneWidget);
  });

  testWidgets('swap tab is hidden when the swap feature is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router(), swapFeatureEnabled: false));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Swap'), findsNothing);
    for (final label in ['Home', 'Activity', 'Settings']) {
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
  });

  testWidgets('home error shortcut switches to the settings tab', (
    tester,
  ) async {
    // This long failure label needs a larger phone viewport (the previous
    // harness used an 800-point viewport without the adaptive shell).
    tester.view.physicalSize = const Size(568, 852);
    final router = _router();
    await tester.pumpWidget(
      _app(
        router,
        initialSyncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(100000000),
          failure: classifySyncFailure('private status coverage incomplete'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_private_status_coverage_settings')),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(router.canPop(), isFalse);
    expect(find.byType(AppMobileShell), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Home').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  for (final path in ['/swap/keystone-sign', '/swap/ledger-sign']) {
    for (final extra in [null, 'invalid signing arguments']) {
      testWidgets('$path with invalid arguments returns to the swap tab '
          '($extra)', (tester) async {
        final router = GoRouter(
          initialLocation: path,
          initialExtra: extra,
          routes: buildMobileRoutes(entryRoutes: const []),
        );
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/swap');
        expect(find.byType(MobileSwapScreen), findsOneWidget);
        expect(find.byType(AppMobileShell), findsOneWidget);
        expect(find.bySemanticsLabel('Back'), findsNothing);
        expect(router.canPop(), isFalse);
        await tester.tap(find.bySemanticsLabel('Home').last);
        await tester.pumpAndSettle();
        expect(find.byType(MobileHomeScreen), findsOneWidget);
      });
    }
  }

  testWidgets('send pushes over the shell with a swipe-back capable page', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileSendScreen), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(MobileSendScreen)));
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileSendScreen), findsNothing);
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  testWidgets(
    'a ZIP-321 SendPrefillArgs on /send populates the mobile send screen',
    (tester) async {
      final router = _router();
      await tester.pumpWidget(
        _app(
          router,
          // The amount step's price placeholder shimmers forever while the
          // live ZEC/USD price is null, which would hang pumpAndSettle.
          overrides: [zecLiveUsdUnitPriceProvider.overrideWithValue(210)],
        ),
      );
      await tester.pumpAndSettle();

      unawaited(
        router.push<void>(
          '/send',
          extra: const SendPrefillArgs(
            id: 'payment-uri-1',
            source: 'zcash-uri',
            address: 'u1routeraddress',
            amountText: '0.25',
            memoText: '  coffee  ',
            preserveMemoText: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The mobile /send route must unpack SendPrefillArgs (a ZIP-321 payment
      // URI) into the recipient + amount + memo, not drop it like a bare
      // recipient string would.
      final sendScreen = tester.widget<MobileSendScreen>(
        find.byType(MobileSendScreen),
      );
      expect(sendScreen.initialRecipient, 'u1routeraddress');
      expect(sendScreen.initialAmount, '0.25');
      expect(sendScreen.initialMemo, '  coffee  ');
      expect(sendScreen.preserveInitialMemoWhitespace, isTrue);
    },
  );

  testWidgets(
    'a second payment request answered onto /send re-seeds the composer',
    (tester) async {
      final router = _router();
      await tester.pumpWidget(
        _app(
          router,
          overrides: [zecLiveUsdUnitPriceProvider.overrideWithValue(210)],
        ),
      );
      await tester.pumpAndSettle();

      router.go(
        '/send',
        extra: const SendPrefillArgs(
          id: 'payment-uri-1',
          source: kPaymentUriPrefillSource,
          address: 'u1firstrequestaddress',
        ),
      );
      await tester.pumpAndSettle();

      final firstPageKey = _sendPageKey(tester);
      expect(find.text('u1firstrequestaddress'), findsOneWidget);

      // What the payment-request card's Edit does when the user is already
      // standing on /send. A shared page key would update the page in place,
      // and `_MobileSendScreenState` only reads the prefill in `initState`.
      router.go(
        '/send',
        extra: const SendPrefillArgs(
          id: 'payment-uri-2',
          source: kPaymentUriPrefillSource,
          address: 'u1secondrequestaddress',
        ),
      );
      await tester.pumpAndSettle();

      expect(_sendPageKey(tester), isNot(firstPageKey));
      expect(find.text('u1secondrequestaddress'), findsOneWidget);
      expect(find.text('u1firstrequestaddress'), findsNothing);
    },
  );
  testWidgets('send amount and review routes push Cupertino pages', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/send/amount',
        extra: const MobileSendAmountArgs(
          sendFlowId: 'flow-1',
          recipient: 'u1routeraddress',
          addressType: 'unified',
          amountText: '0.25',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileSendAmountScreen), findsOneWidget);
    var route = ModalRoute.of(
      tester.element(find.byType(MobileSendAmountScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
    // An amount already composed on the recipient step (a ZIP-321 deep link
    // that stepped back in place) has to reach the pushed amount page.
    final amountScreen = tester.widget<MobileSendScreen>(
      find.descendant(
        of: find.byType(MobileSendAmountScreen),
        matching: find.byType(MobileSendScreen),
      ),
    );
    expect(amountScreen.initialAmount, '0.25');

    unawaited(
      router.push<void>(
        '/send/review',
        extra: MobileSendReviewDraftArgs(
          sendFlowId: 'flow-1',
          recipient: 'u1routeraddress',
          addressType: 'unified',
          amountText: '0.25',
          feeZatoshi: BigInt.from(10000),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileSendReviewScreen), findsOneWidget);
    route = ModalRoute.of(tester.element(find.byType(MobileSendReviewScreen)));
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
  });

  testWidgets('swap Keystone signing route pushes a Cupertino page', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          swapHardwareSigningServiceProvider.overrideWithValue(
            const _FakeSwapHardwareSigningService(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/swap/keystone-sign',
        extra: MobileSwapKeystoneSignArgs(intent: _hardwareSwapIntent),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileSwapKeystoneSignScreen), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.byType(MobileSwapKeystoneSignScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
    expect(route?.opaque, isTrue);
  });

  testWidgets('receive pushes over a Cupertino shell page', (tester) async {
    await tester.pumpWidget(_app(_router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobileReceiveScreen), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.byType(MobileReceiveScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MobileReceiveScreen), findsNothing);
    expect(find.byType(MobileHomeScreen), findsOneWidget);
  });

  testWidgets('payment submitted route pushes a Cupertino page', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(router.push<void>('/pay/submitted/intent-123'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(MobilePaySubmittedScreen), findsOneWidget);
    final screen = tester.widget<MobilePaySubmittedScreen>(
      find.byType(MobilePaySubmittedScreen),
    );
    expect(screen.intentId, 'intent-123');
    final route = ModalRoute.of(
      tester.element(find.byType(MobilePaySubmittedScreen)),
    );
    expect(route, isA<CupertinoRouteTransitionMixin<dynamic>>());
  });

  testWidgets('pay route forwards prepared-composer navigation state', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    unawaited(
      router.push<void>(
        '/pay',
        extra: const PayComposerNavigationArgs(preservePreparedComposer: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final screen = tester.widget<MobilePayScreen>(find.byType(MobilePayScreen));
    expect(screen.preservePreparedComposer, isTrue);
  });

  testWidgets('home Pay waits only for its saved live asset', (tester) async {
    final router = _router();
    final savedAsset = SwapAsset.live(
      assetId: 'base-usdc',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );
    final payAssetStore = _DeferredPaySelectedAssetStore(savedAsset);
    final swapProvider = _DeferredSupportedAssetsSwapProvider();
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
          swapIntentProvider.overrideWithValue(swapProvider),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(payAssetStore.loadStarted, isTrue);
    expect(payAssetStore.loadCount, 1);
    expect(swapProvider.loadStarted, isTrue);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byType(MobilePayScreen), findsNothing);

    payAssetStore.completeLoad();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileHomeScreen)),
      listen: false,
    );
    expect(container.read(paySelectedAssetProvider), savedAsset);
    expect(container.read(swapStateProvider).payMode, isTrue);
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
    expect(container.read(swapStateProvider).pricingLoading, isTrue);
    expect(find.byType(MobilePayScreen), findsOneWidget);
    final assetSelector = find.byKey(
      const ValueKey('mobile_pay_asset_selector'),
    );
    expect(
      find.descendant(of: assetSelector, matching: find.text('Base')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assetSelector, matching: find.text('Ethereum')),
      findsNothing,
    );

    await tester.pump();
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
    expect(payAssetStore.loadCount, 1);

    swapProvider.completeSupportedAssets([savedAsset]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(swapStateProvider).pricingLoading, isFalse);
    expect(container.read(swapStateProvider).externalAsset, savedAsset);
  });

  testWidgets(
    'home Pay does not treat a periodic catalog refresh as initial loading',
    (tester) async {
      final router = _router();
      final savedAsset = SwapAsset.live(
        assetId: 'removed-base-usdc',
        symbol: 'USDC',
        blockchain: 'base',
        decimals: 6,
      );
      final payAssetStore = _DeferredPaySelectedAssetStore(savedAsset);
      final swapProvider = _DeferredRefreshSupportedAssetsSwapProvider(const [
        SwapAsset.usdc,
      ]);
      await tester.pumpWidget(
        _app(
          router,
          overrides: [
            paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
            swapIntentProvider.overrideWithValue(swapProvider),
            swapPriceRefreshIntervalProvider.overrideWithValue(
              const Duration(seconds: 5),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(swapProvider.loadCount, 1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump();
      expect(swapProvider.loadCount, 2);

      payAssetStore.completeLoad();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHomeScreen)),
        listen: false,
      );
      expect(container.read(swapStateProvider).pricingLoading, isTrue);
      expect(container.read(swapStateProvider).externalAsset, SwapAsset.usdc);
      final assetSelector = find.byKey(
        const ValueKey('mobile_pay_asset_selector'),
      );
      expect(
        find.descendant(of: assetSelector, matching: find.text('Ethereum')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: assetSelector, matching: find.text('Base')),
        findsNothing,
      );

      swapProvider.completeRefresh(const [SwapAsset.usdc]);
      await tester.pump();
    },
  );

  testWidgets('home Pay restore does not navigate after leaving Home', (
    tester,
  ) async {
    final router = _router();
    final payAssetStore = _DeferredPaySelectedAssetStore(SwapAsset.sol);
    await tester.pumpWidget(
      _app(
        router,
        overrides: [
          paySelectedAssetStoreProvider.overrideWithValue(payAssetStore),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_home_pay')));
    await tester.pump();
    expect(payAssetStore.loadStarted, isTrue);

    await tester.tap(find.bySemanticsLabel('Swap').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSwapScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Home').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileHomeScreen), findsOneWidget);

    payAssetStore.completeLoad();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(MobileHomeScreen), findsOneWidget);
    expect(find.byType(MobilePayScreen), findsNothing);
  });
}

final _hardwareSwapIntent = SwapIntent(
  id: 'swap-route-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.003 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Deposit ZEC',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1route-deposit',
  accountUuid: 'account-1',
);

class _FakeSwapHardwareSigningService implements SwapHardwareSigningService {
  const _FakeSwapHardwareSigningService();

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    return SwapHardwarePcztDraft(
      accountUuid: accountUuid,
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.zero,
      proposalId: BigInt.one,
      sendFlowId: 'test-swap-hardware',
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-sign-batch/route-test'];
  }

  @override
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async {
    return const [7, 8, 9];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const [4, 5, 6];
  }

  @override
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {}

  @override
  Future<void> settlePcztDraftAfterLedgerBroadcast({
    required SwapHardwarePcztDraft draft,
    required String? status,
  }) async {}

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    throw UnimplementedError();
  }
}

class _DeferredPaySelectedAssetStore implements PaySelectedAssetStore {
  _DeferredPaySelectedAssetStore(this.asset);

  final SwapAsset? asset;
  final _loadCompleter = Completer<void>();
  int loadCount = 0;

  bool get loadStarted => loadCount > 0;

  void completeLoad() => _loadCompleter.complete();

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    loadCount += 1;
    await _loadCompleter.future;
    return asset;
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}

class _DeferredSupportedAssetsSwapProvider
    extends StaticNearIntentsSwapProvider {
  final _supportedAssetsCompleter = Completer<List<SwapAsset>>();
  var loadCount = 0;

  bool get loadStarted => loadCount > 0;

  void completeSupportedAssets(List<SwapAsset> assets) {
    _supportedAssetsCompleter.complete(assets);
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() {
    loadCount += 1;
    return _supportedAssetsCompleter.future;
  }
}

class _DeferredRefreshSupportedAssetsSwapProvider
    extends StaticNearIntentsSwapProvider {
  _DeferredRefreshSupportedAssetsSwapProvider(this.initialAssets);

  final List<SwapAsset> initialAssets;
  final _refreshCompleter = Completer<List<SwapAsset>>();
  var loadCount = 0;

  void completeRefresh(List<SwapAsset> assets) {
    _refreshCompleter.complete(assets);
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() {
    loadCount += 1;
    if (loadCount == 1) return Future.value(initialAssets);
    return _refreshCompleter.future;
  }
}
