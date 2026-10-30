@Tags(['mobile'])
library;

// Exercise the actual mobile signing and camera widgets through incoming intake.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import 'fakes/fake_gift_link_rust_api.dart';
import 'fakes/fake_sync_notifier.dart';
import 'support/payment_links_screen_support.dart';

void main() {
  final api = _ProbeApi();
  late Directory directory;
  setUpAll(() async {
    await loadPaymentLinksTestFonts();
    RustLib.initMock(api: api);
  });
  tearDownAll(RustLib.dispose);
  setUp(() async {
    api.discardCalls = 0;
    directory = await Directory.systemTemp.createTemp('pr827-home-link-probe-');
    PathProviderPlatform.instance = _ProbePaths(directory.path);
    addTearDown(() => directory.delete(recursive: true));
    const camera = {
      'id': 'probe-camera',
      'name': 'Probe camera',
      'facing': 2,
      'isDefault': true,
    };
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

  for (final voting in [false, true]) {
    testWidgets(
      'home link preserves the actual mobile ${voting ? 'voting' : 'send'} scanner',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final incoming = _ProbeIncomingUris();
        addTearDown(incoming.dispose);
        final results = <Object?>[];
        final parentPath = voting ? '/voting' : '/send/review';
        final path = voting
            ? '/voting/poll/round-1/status'
            : '/send/keystone-sign';
        var votingSigned = 0;
        final router = GoRouter(
          initialLocation: parentPath,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home route')),
            ),
            GoRoute(
              path: parentPath,
              // Home and other production pages have their own toast host.
              // Once this route is covered, app-level incoming notices must
              // target the host above the router rather than this offstage one.
              builder: (context, _) => AppToastHost(
                child: Scaffold(
                  body: TextButton(
                    onPressed: () async =>
                        results.add(await context.push<Object?>(path)),
                    child: const Text('Open signing'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: path,
              builder: (_, _) => voting
                  ? MobileKeystoneVotingSigningScreen(
                      presentation: VotingKeystoneStatusPresentation(
                        bundleIndex: 0,
                        urParts: const ['ur:zcash-vote/test-fixture'],
                        batchMemos: const [],
                        batchMessageCount: 1,
                        batchTotalCount: 1,
                        onSigned: (_) async {
                          votingSigned++;
                        },
                      ),
                      forceScannerActiveForTesting: true,
                    )
                  : MobileKeystoneSignScreen(
                      args: SendReviewArgs(
                        proposalId: BigInt.one,
                        sendFlowId: 'probe-tex-flow',
                        proposalAccountUuid: 'account-1',
                        address: 'tex1probe',
                        addressType: 'tex',
                        amountZatoshi: BigInt.one,
                        feeZatoshi: BigInt.one,
                        needsSaplingParams: false,
                      ),
                      loadWalletDbPath: () async =>
                          '${directory.path}/wallet.db',
                    ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appBootstrapProvider.overrideWithValue(paymentLinksBootstrap),
              incomingUriServiceProvider.overrideWithValue(incoming),
              syncProvider.overrideWith(FakeSyncNotifier.new),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (_, child) => AppTheme(
                data: AppThemeData.dark,
                child: buildIncomingLinkHostForTest(
                  router: router,
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open signing'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await tester.pumpAndSettle();
        final keyPrefix = voting
            ? 'mobile_voting_keystone'
            : 'mobile_keystone_sign';
        await tester.tap(find.byKey(ValueKey('${keyPrefix}_get_signature')));
        await tester.pumpAndSettle();
        expect(find.byType(AnimatedUrScannerView), findsOneWidget);
        expect(find.byType(MobileScanner), findsOneWidget);
        expect(find.text('Step 2/2'), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AnimatedUrScannerView)),
        );
        final scannerState = tester.state(find.byType(AnimatedUrScannerView));
        final guard = container.read(externalActionGuardProvider);
        expect(guard.blocks(ExternalAction.paymentRequest), isTrue);
        expect(guard.blocks(ExternalAction.navigation), isFalse);

        // Controls: both financial link lanes preserve the camera and park intake.
        incoming.emit(incomingLink.toUri().toString());
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Finish or cancel your current task to open this gift card.',
          ),
          findsOneWidget,
        );
        incoming.emit('zcash:u1recipient?amount=0.5');
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Finish or cancel your current task to open this payment request.',
          ),
          findsOneWidget,
        );
        expect(router.state.matchedLocation, path);
        expect(
          tester.state(find.byType(AnimatedUrScannerView)),
          same(scannerState),
        );
        expect(
          container.read(paymentLinkIntakeProvider).pendingLink,
          isNotNull,
        );
        expect(container.read(paymentUriPrefillProvider), isNotNull);
        expect(results, isEmpty);
        // Clear parked controls so they cannot determine the next destination.
        container.read(paymentLinkIntakeProvider.notifier).takePending();
        container.read(paymentUriPrefillProvider.notifier).clear();

        incoming.emit('https://link.vizor.cash');
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, path);
        expect(
          tester.state(find.byType(AnimatedUrScannerView)),
          same(scannerState),
        );
        expect(
          find.text('Finish or cancel your task, then reopen the link.'),
          findsOneWidget,
        );
        expect(
          results,
          isEmpty,
          reason: 'the caller received no signed result',
        );
        expect(
          container.read(externalActionGuardProvider).activeHoldCount,
          greaterThan(0),
        );
        expect(votingSigned, 0);
        expect(api.discardCalls, 0);
        // Deliberate user navigation remains available and releases the hold.
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
        expect(router.state.matchedLocation, parentPath);
        expect(
          api.discardCalls,
          0,
          reason: 'the parent review still owns the proposal',
        );
        if (!voting) expect(results, [null]);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}

class _ProbeIncomingUris extends IncomingUriService {
  final _uris = StreamController<String>.broadcast();
  @override
  Stream<String> get uriStream => _uris.stream;
  @override
  Future<void> initialize() async {}
  void emit(String uri) => _uris.add(uri);
  @override
  Future<void> dispose() => _uris.close();
}

class _ProbePaths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _ProbePaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _ProbeApi extends FakeGiftLinkRustApi {
  int discardCalls = 0;
  @override
  void crateApiKeystoneResetUrSession() {}
  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls++;
  }

  @override
  Future<TexPcztPairResult> crateApiSyncCreateTexPcztsFromProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) async => TexPcztPairResult(
    pczts: [
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
    ],
    signerPczts: [
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
    ],
  );
  @override
  Future<Uint8List> crateApiSyncAddProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => Uint8List.fromList(pcztBytes);
  @override
  Future<List<String>> crateApiKeystoneEncodePcztUrParts({
    required List<int> pcztBytes,
    required BigInt maxFragmentLen,
  }) async => ['ur:zcash-pczt/test-fixture'];
}
