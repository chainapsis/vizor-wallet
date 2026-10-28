@Tags(['mobile'])
library;

import 'package:zcash_wallet/src/core/navigation/mobile_shield_page.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_adaptive_frame.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_wallet_sidebar.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_destinations.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_sidebar_route_observer.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';

// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_keystone_shield_screen.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/slide_to_shield.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' hide ScanResult;
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';
import '../../fakes/fake_sync_notifier.dart';

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  late Directory directory;
  late PathProviderPlatform originalPaths;
  setUp(() async {
    api.decodes = 0;
    api.broadcasts = 0;
    api.pendingDecode = null;
    api.pendingCreation = null;
    api.pendingProofs = null;
    api.pendingDiscard = null;
    api.pendingBroadcast = null;
    api.failDiscard = false;
    api.discards.clear();
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('keystone-morph-scan-');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const camera = {
      'id': 'mock-camera',
      'name': 'Mock camera',
      'facing': 2,
      'isDefault': true,
    };
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
      (call) async => switch (call.method) {
        'state' => 1,
        'request' => true,
        'getAvailableCameras' => [camera],
        'start' => {
          'textureId': 1,
          'camera': camera,
          'cameraDirection': 2,
          'numberOfCameras': 1,
          'size': {'width': 640.0, 'height': 480.0},
        },
        _ => null,
      },
    );
    for (final suffix in ['event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/$suffix'),
        (_) async => null,
      );
    }
  });
  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final suffix in ['method', 'event', 'deviceOrientation']) {
      messenger.setMockMethodCallHandler(
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/$suffix'),
        null,
      );
    }
    await directory.delete(recursive: true);
  });

  for (final action in ['Show QR', 'Cancel']) {
    testWidgets('ignores a scanner result during the $action exit', (
      tester,
    ) async {
      await _startScanner(tester);
      final scanner = tester.widget<AnimatedUrScannerView>(
        find.byType(AnimatedUrScannerView),
      );
      await tester.tap(find.text(action));
      await tester.pump();
      scanner.onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
      await _flush(tester);
      expect(api.decodes, 0);
      expect(api.broadcasts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
  for (final privacyModeEnabled in [false, true]) {
    testWidgets('review amount with privacy mode $privacyModeEnabled', (
      tester,
    ) async {
      tester.view.physicalSize =
          const Size(393, 852) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap),
          privacyModeProvider.overrideWith(() => _Privacy(privacyModeEnabled)),
          walletProvider.overrideWith(_Wallet.new),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                transparentBalance: BigInt.from(1412000000),
                canShieldTransparentBalance: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(walletProvider.future);
      await container.read(syncProvider.future);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppTheme(
            data: AppThemeData.dark,
            child: const MaterialApp(home: MobileKeystoneShieldScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      final amount = privacyModeEnabled ? '******' : '14.12';
      expect(
        tester.widget<MobileShieldScene>(find.byType(MobileShieldScene)).amount,
        amount,
      );
      expect(find.bySemanticsLabel('$amount ZEC'), findsOneWidget);
      if (privacyModeEnabled) {
        expect(find.bySemanticsLabel(RegExp(r'14\.12')), findsNothing);
      }
      expect(find.bySemanticsLabel(RegExp('ZEC ZEC')), findsNothing);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a reopened camera accepts only its current scan session', (
    tester,
  ) async {
    await _startScanner(tester);
    final old = tester.widget<AnimatedUrScannerView>(
      find.byType(AnimatedUrScannerView),
    );
    await tester.tap(find.text('Show QR'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Next step'));
    await tester.pump();
    await _flush(tester);
    await tester.pump(const Duration(seconds: 1));
    final current = tester.widget<AnimatedUrScannerView>(
      find.byType(AnimatedUrScannerView),
    );
    old.onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
    await _flush(tester);
    expect(api.decodes, 0);
    current.onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
    await _flush(tester);
    expect(api.decodes, 1);
    expect(api.broadcasts, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileKeystoneShieldScreen)),
    );
    expect(
      container.read(pendingActivityEvidenceProvider).observedAt.keys,
      contains(('account-1', 'ab')),
    );
    container.read(pendingActivityEvidenceProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('cancel discards an already-started signature decode', (
    tester,
  ) async {
    await _startScanner(tester);
    api.pendingDecode = Completer<Uint8List>();
    tester
        .widget<AnimatedUrScannerView>(find.byType(AnimatedUrScannerView))
        .onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
    await tester.pump();
    expect(api.decodes, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    api.pendingDecode!.complete(Uint8List.fromList([4]));
    await _flush(tester);
    expect(api.broadcasts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'sidebar awaits release, blocks duplicate input and retries a failed discard',
    (tester) async {
      final router = await _startScanner(tester, sidebar: true);
      final sidebar = tester.widget<MobileWalletSidebar>(
        find.byType(MobileWalletSidebar),
      );
      final scanner = tester.widget<AnimatedUrScannerView>(
        find.byType(AnimatedUrScannerView),
      );
      final cancel = tester
          .widget<MobileShieldScene>(find.byType(MobileShieldScene))
          .onClose!;
      api.pendingDiscard = Completer<void>();
      api.failDiscard = true;
      sidebar.onSelect!('/activity');
      await _flush(tester);
      expect(mobileVisiblePath(router), '/home/keystone-shield');
      expect(api.discards.length, 1);
      sidebar.onSelect!('/settings');
      cancel();
      scanner.onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
      await _flush(tester);
      expect(api.discards.length, 1);
      expect(api.decodes, 0);
      api.pendingDiscard!.complete();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await _flush(tester);
      }
      expect(api.discards.length, 3);
      expect(mobileVisiblePath(router), '/home/keystone-shield');
      expect(
        find.text('Could not finish cancelling. Please try again.'),
        findsOneWidget,
      );
      final owner = api.discards.first;
      expect(api.discards.every((entry) => entry == owner), isTrue);
      api.pendingDiscard = null;
      api.failDiscard = false;
      tester
          .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
          .onSelect!('/activity');
      await _flush(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(mobileVisiblePath(router), '/activity');
      expect(api.discards.length, 4);
      expect(api.discards.last, owner);
      expect(api.broadcasts, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(api.discards.length, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sidebar waits for balance refresh and retries its failure', (
    tester,
  ) async {
    final sync = _ExitSync();
    final router = await _startScanner(tester, sidebar: true, sync: sync);
    sync.pendingRefresh = Completer<void>();
    sync.failRefresh = true;
    tester
        .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
        .onSelect!('/activity');
    await _flush(tester);
    expect(mobileVisiblePath(router), '/home/keystone-shield');
    expect(api.discards.length, 1);
    expect(sync.releases, 1);
    sync.pendingRefresh!.complete();
    await _flush(tester);
    expect(mobileVisiblePath(router), '/home/keystone-shield');
    sync.pendingRefresh = null;
    sync.failRefresh = false;
    tester
        .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
        .onSelect!('/activity');
    await _flush(tester);
    expect(mobileVisiblePath(router), '/activity');
    expect(sync.releases, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar cancellation ignores a late signature decode after cleanup failure',
    (tester) async {
      final sync = _ExitSync();
      final router = await _startScanner(tester, sidebar: true, sync: sync);
      api.pendingDecode = Completer<Uint8List>();
      tester
          .widget<AnimatedUrScannerView>(find.byType(AnimatedUrScannerView))
          .onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
      await tester.pump();
      expect(api.decodes, 1);
      sync.failRefresh = true;
      tester
          .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
          .onSelect!('/activity');
      await _flush(tester);
      expect(mobileVisiblePath(router), '/home/keystone-shield');
      api.pendingDecode!.complete(Uint8List.fromList([4]));
      await _flush(tester);
      expect(api.broadcasts, 0);
      expect(
        find.text('Could not finish cancelling. Please try again.'),
        findsOneWidget,
      );
      sync.failRefresh = false;
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'sidebar drains late creation and rejects its continuation (failure=$fail)',
      (tester) async {
        api.pendingCreation = Completer<ShieldTransparentPcztResult>();
        final sync = _ExitSync()..failRefresh = fail;
        final router = await _startScanner(
          tester,
          sidebar: true,
          scan: false,
          waitForQr: false,
          sync: sync,
        );
        await _flush(tester);
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onSelect!('/activity');
        await _flush(tester);
        expect(mobileVisiblePath(router), '/home/keystone-shield');
        expect(api.discards, isEmpty);
        api.pendingCreation!.complete(_preparedShield());
        await _flush(tester);
        expect(api.discards.length, 1);
        expect(api.broadcasts, 0);
        if (fail) {
          expect(mobileVisiblePath(router), '/home/keystone-shield');
          expect(
            find.text('Could not finish cancelling. Please try again.'),
            findsOneWidget,
          );
        } else {
          expect(mobileVisiblePath(router), '/activity');
        }
        sync.failRefresh = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await _flush(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('Cancel also awaits cleanup failure and retries before popping', (
    tester,
  ) async {
    final sync = _ExitSync();
    final router = await _startScanner(tester, sync: sync);
    sync.pendingRefresh = Completer<void>();
    sync.failRefresh = true;
    await tester.tap(find.text('Cancel'));
    await _flush(tester);
    expect(mobileVisiblePath(router), '/home/keystone-shield');
    sync.pendingRefresh!.complete();
    await _flush(tester);
    expect(
      find.text('Could not finish cancelling. Please try again.'),
      findsOneWidget,
    );
    sync.pendingRefresh = null;
    sync.failRefresh = false;
    await tester.tap(find.text('Back to wallet'));
    await _flush(tester);
    expect(mobileVisiblePath(router), '/home');
    expect(sync.releases, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final proofFails in [false, true]) {
    testWidgets(
      'late proof completion cannot overwrite a failed exit (proofFails=$proofFails)',
      (tester) async {
        api.pendingProofs = Completer<Uint8List>();
        final sync = _ExitSync();
        final router = await _startScanner(tester, sidebar: true, sync: sync);
        sync.failRefresh = true;
        tester
            .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
            .onSelect!('/activity');
        await _flush(tester);
        expect(mobileVisiblePath(router), '/home/keystone-shield');
        expect(api.discards.length, 1);
        if (proofFails) {
          api.pendingProofs!.completeError(StateError('late proof failure'));
        } else {
          api.pendingProofs!.complete(Uint8List.fromList([2]));
        }
        await _flush(tester);
        expect(api.discards.length, 1);
        expect(api.broadcasts, 0);
        expect(
          find.text('Could not finish cancelling. Please try again.'),
          findsOneWidget,
        );
        sync.failRefresh = false;
        await tester.pumpWidget(const SizedBox.shrink());
        await _flush(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sidebar and Cancel cannot abandon an accepted broadcast', (
    tester,
  ) async {
    final router = await _startScanner(tester, sidebar: true);
    final sidebar = tester.widget<MobileWalletSidebar>(
      find.byType(MobileWalletSidebar),
    );
    final cancel = tester
        .widget<MobileShieldScene>(find.byType(MobileShieldScene))
        .onClose!;
    api.pendingBroadcast = Completer<StoreAndBroadcastPcztsResult>();
    tester
        .widget<AnimatedUrScannerView>(find.byType(AnimatedUrScannerView))
        .onComplete(const ScanResult(urType: 'zcash-pczt', data: [4]));
    await _flush(tester);
    expect(api.broadcasts, 1);
    expect(
      tester
          .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
          .onSelect,
      isNull,
    );
    sidebar.onSelect!('/activity');
    cancel();
    await _flush(tester);
    expect(mobileVisiblePath(router), '/home/keystone-shield');
    expect(api.discards, isEmpty);
    api.pendingBroadcast!.complete(
      const StoreAndBroadcastPcztsResult(
        broadcastedCount: 1,
        totalCount: 1,
        txids: 'ab',
        status: 'broadcasted',
      ),
    );
    await _flush(tester);
    ProviderScope.containerOf(
      tester.element(find.byType(MobileKeystoneShieldScreen)),
    ).read(pendingActivityEvidenceProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a popup interrupting the completed exit leaves a usable return action',
    (tester) async {
      final sync = _ExitSync();
      final router = await _startScanner(tester, sidebar: true, sync: sync);
      sync.pendingRefresh = Completer<void>();
      tester
          .widget<MobileWalletSidebar>(find.byType(MobileWalletSidebar))
          .onSelect!('/activity');
      await _flush(tester);
      final context = tester.element(find.byType(MobileShieldScene));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Exit interrupted')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      sync.pendingRefresh!.complete();
      await _flush(tester);
      expect(mobileVisiblePath(router), '/home/keystone-shield');
      expect(api.discards.length, 1);
      Navigator.of(context, rootNavigator: true).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Shielding was cancelled.'), findsOneWidget);
      await tester.tap(find.text('Back to wallet'));
      await _flush(tester);
      expect(mobileVisiblePath(router), '/home');
      expect(api.discards.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cancel preserves signing visuals during the return transition', (
    tester,
  ) async {
    final router = await _startScanner(tester);
    final before = tester
        .widget<MobileShieldScene>(find.byType(MobileShieldScene))
        .phase;
    api.pendingDiscard = Completer<void>();
    await tester.tap(find.text('Cancel'));
    await _flush(tester);
    api.pendingDiscard!.complete();
    await tester.pump();
    expect(mobileVisiblePath(router), '/home');
    expect(
      tester.widget<MobileShieldScene>(find.byType(MobileShieldScene)).phase,
      before,
    );
    expect(find.text('Shielding was cancelled.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<GoRouter> _startScanner(
  WidgetTester tester, {
  bool sidebar = false,
  bool scan = true,
  bool waitForQr = true,
  FakeSyncNotifier? sync,
}) async {
  if (sidebar) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(951, 669);
    addTearDown(tester.view.reset);
  }
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      walletProvider.overrideWith(_Wallet.new),
      syncProvider.overrideWith(
        () =>
            sync ??
            FakeSyncNotifier(
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                transparentBalance: BigInt.from(1412000000),
                canShieldTransparentBalance: true,
              ),
            ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(walletProvider.future);
  await container.read(syncProvider.future);
  final routes = <RouteBase>[
    GoRoute(
      path: '/activity',
      builder: (_, _) => const Scaffold(body: Text('Activity destination')),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const Scaffold(body: Text('Settings destination')),
    ),

    GoRoute(
      path: '/home',
      builder: (context, _) => Scaffold(
        body: TextButton(
          onPressed: () => context.push('/home/keystone-shield'),
          child: const Text('Open shield'),
        ),
      ),
    ),
    GoRoute(
      path: '/home/keystone-shield',
      pageBuilder: (_, state) => MobileShieldPage(
        key: state.pageKey,
        child: const MobileKeystoneShieldScreen(),
      ),
    ),
  ];
  final router = GoRouter(
    observers: [container.read(mobileSidebarRouteObserverProvider)],
    initialLocation: '/home',
    routes: sidebar
        ? [
            ShellRoute(
              builder: (context, state, child) => MobileAdaptiveFrame(
                router: GoRouter.of(context),
                child: child,
              ),
              routes: routes,
            ),
          ]
        : routes,
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      ),
    ),
  );
  await tester.tap(find.text('Open shield'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  final slider = find.byType(SlideToShield);
  final gesture = await tester.startGesture(
    tester.getTopLeft(slider) + const Offset(30, 25),
  );
  await gesture.moveBy(Offset(tester.getSize(slider).width - 60, 0));
  await gesture.up();
  if (!waitForQr) return router;
  for (var i = 0; i < 35; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final next = find.ancestor(
      of: find.text('Next step'),
      matching: find.byType(AppButton),
    );
    if (next.evaluate().isNotEmpty &&
        tester.widget<AppButton>(next).onPressed != null) {
      break;
    }
  }
  if (!scan) return router;
  await tester.tap(find.text('Next step'));
  await tester.pump();
  await _flush(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(AnimatedUrScannerView), findsOneWidget);
  return router;
}

class _Api extends RustLibApi {
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discards.add((proposalId, sendFlowId));
    await pendingDiscard?.future;
    if (failDiscard) throw StateError('release unavailable');
  }

  final discards = <(BigInt, String)>[];
  Completer<void>? pendingDiscard;
  Completer<ShieldTransparentPcztResult>? pendingCreation;
  Completer<Uint8List>? pendingProofs;
  Completer<StoreAndBroadcastPcztsResult>? pendingBroadcast;
  bool failDiscard = false;
  int decodes = 0, broadcasts = 0;
  Completer<Uint8List>? pendingDecode;
  @override
  void crateApiKeystoneResetUrSession() {}
  @override
  Future<ShieldTransparentPcztResult> crateApiSyncCreateShieldTransparentPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String sendFlowId,
  }) async => pendingCreation?.future ?? _preparedShield();

  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => pendingProofs?.future ?? Uint8List.fromList([2]);
  @override
  Future<Uint8List> crateApiSyncRedactPcztForSigner({
    required List<int> pcztBytes,
  }) async => Uint8List.fromList([3]);
  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async => ['ur:zcash-pczt/fixture'];
  @override
  Future<Uint8List> crateApiKeystoneDecodePcztFromCbor({
    required List<int> cbor,
  }) {
    decodes++;
    return pendingDecode?.future ?? Future.value(Uint8List.fromList([4]));
  }

  @override
  Future<StoreAndBroadcastPcztsResult>
  crateApiSyncStoreAndBroadcastSignedPcztsForProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required List<Uint8List> pcztWithProofs,
    required List<Uint8List> pcztWithSignatures,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts++;
    return pendingBroadcast?.future ??
        const StoreAndBroadcastPcztsResult(
          broadcastedCount: 1,
          totalCount: 1,
          txids: 'ab',
          status: 'broadcasted',
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _Wallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(
    hasWallet: true,
    unifiedAddress: 'u1test',
    network: 'main',
    activeAccountUuid: 'account-1',
  );
}

class _Privacy extends PrivacyModeNotifier {
  _Privacy(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
        hardwareSignerKind: HardwareSignerKind.keystone,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1test',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

ShieldTransparentPcztResult _preparedShield() => ShieldTransparentPcztResult(
  proposalId: BigInt.from(77),
  pcztBytes: Uint8List.fromList([1]),
  feeZatoshi: BigInt.from(10000),
  shieldedZatoshi: BigInt.from(1411990000),
  needsSaplingParams: false,
);

class _ExitSync extends FakeSyncNotifier {
  Completer<void>? pendingRefresh;
  bool failRefresh = false;
  int releases = 0;
  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {
    releases++;
    await pendingRefresh?.future;
    if (failRefresh) throw StateError('balance refresh unavailable');
    await super.refreshAfterProposalRelease(accountUuid);
  }
}
