@Tags(['mobile'])
library;

import 'package:zcash_wallet/src/core/navigation/mobile_shield_page.dart';

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
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _startScanner(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
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
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/shield'),
            child: const Text('Open shield'),
          ),
        ),
      ),
      GoRoute(
        path: '/shield',
        pageBuilder: (_, state) => MobileShieldPage(
          key: state.pageKey,
          child: const MobileKeystoneShieldScreen(),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
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
  await tester.tap(find.text('Next step'));
  await tester.pump();
  await _flush(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(AnimatedUrScannerView), findsOneWidget);
}

class _Api extends RustLibApi {
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {}

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
  }) async => ShieldTransparentPcztResult(
    proposalId: BigInt.from(77),
    pcztBytes: Uint8List.fromList([1]),
    feeZatoshi: BigInt.from(10000),
    shieldedZatoshi: BigInt.from(1411990000),
    needsSaplingParams: false,
  );
  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => Uint8List.fromList([2]);
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
    return const StoreAndBroadcastPcztsResult(
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
