@Tags(['desktop'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/send/screens/keystone_send_scan_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_review_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/keystone_voting_scan_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

import 'support/keystone_signing_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);
  tearDownAll(releaseKeystoneWallet);
  setUp(installFixtureCamera);

  for (final tex in [true, false]) {
    testWidgets(
      tex
          ? 'sends TEX after two desktop approvals'
          : 'sends after one desktop batch approval',
      (tester) => _runSend(tester, tex: tex),
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }
  testWidgets(
    'signs two delegation bundles from the desktop voting screen',
    _runVoting,
  );
}

Widget _app(GoRouter router) => MaterialApp.router(
  routerConfig: router,
  localizationsDelegates: appLocalizationsDelegates,
  builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
);

Future<void> _prepareViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _runSend(WidgetTester tester, {required bool tex}) async {
  await _prepareViewport(tester);
  final fixture = await KeystoneSendFixture.create(tex: tex);
  final router = GoRouter(
    initialLocation: '/send/review',
    routes: [
      GoRoute(
        path: '/send/review',
        builder: (_, _) => SendReviewScreen(args: fixture.args),
      ),
      GoRoute(
        path: '/send/keystone/scan',
        builder: (_, state) =>
            KeystoneSendScanScreen(args: state.extra! as KeystoneSendScanArgs),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) => SendStatusScreen(
          args: fixture.args,
          keystone: state.extra! as KeystoneBroadcastArgs,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(fixture.withWallet(_app(router)));
  await tapWhenReady(tester, find.byKey(const ValueKey('send_confirm_button')));
  for (var index = 0; index < fixture.approvals; index++) {
    if (tex) {
      await waitForWidget(tester, find.text('Transaction ${index + 1} of 2'));
    }
    final action = find.text('Get signature');
    await waitForWidget(tester, action.hitTestable());
    final stage = tester.widget<KeystonePcztQrStage>(
      find.byType(KeystonePcztQrStage),
    );
    final signed = await signWithFirmware(stage.urParts, batch: !tex);
    await tapWhenReady(tester, action);
    await fixture.expectNoBroadcast();
    await scanFirmwareFrames(tester, signed);
    // A popped scan route remains mounted until its exit animation completes.
    // Wait for it to leave before opening the next TEX scanner.
    final scanRoute = find.byType(KeystoneSendScanScreen, skipOffstage: false);
    final elapsed = Stopwatch()..start();
    while (tester.any(scanRoute) &&
        elapsed.elapsed < const Duration(seconds: 15)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(scanRoute, findsNothing);
  }
  await waitForWidget(tester, find.text('Sent successfully'));
  fixture.recordSigned(
    tester.widget<SendStatusScreen>(find.byType(SendStatusScreen)).keystone!,
  );
  await fixture.verifyBroadcast();
}

Future<void> _runVoting(WidgetTester tester) async {
  await _prepareViewport(tester);
  final fixture = await KeystoneVoteFixture.create();
  final scanned = Completer<List<int>>();
  final router = GoRouter(
    initialLocation: '/voting',
    routes: [
      GoRoute(
        path: '/voting',
        builder: (context, _) => AppDesktopShell(
          sidebar: const SizedBox.expand(),
          pane: AppDesktopPane(
            padding: EdgeInsets.zero,
            child: VotingStatusContent(
              phase: VotingSessionPhase.keystoneSigning,
              isHardwareAccount: true,
              keystoneSigningBundleIndex: fixture.requests.first.bundleIndex,
              keystoneUrParts: fixture.round.batchRequest.urParts,
              keystoneBatchMemos: fixture.memos,
              keystoneBatchMessageCount: fixture.requests.length,
              keystoneBatchTotalCount: fixture.requests.length,
              onScanKeystone: () async {
                final bytes = await context.push<List<int>>(
                  '/voting/keystone/scan',
                );
                if (bytes != null) scanned.complete(bytes);
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/voting/keystone/scan',
        builder: (_, _) => const KeystoneVotingScanScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ],
      child: _app(router),
    ),
  );
  final qr = find.byType(KeystonePcztQrStage);
  await waitForWidget(tester, qr);
  expect(find.text('Bundle 1 of 2 memo'), findsOneWidget);
  await tapWhenReady(tester, find.byTooltip('Next bundle memo'));
  await tester.pump();
  expect(find.text('Bundle 2 of 2 memo'), findsOneWidget);
  final signed = await signWithFirmware(
    tester.widget<KeystonePcztQrStage>(qr).urParts,
    batch: true,
    voting: true,
  );
  await tapWhenReady(tester, find.text('Scan signature'));
  await scanFirmwareFrames(tester, signed);
  await tester.pump();
  await fixture.verifySignatures(
    await scanned.future.timeout(const Duration(seconds: 15)),
  );
}
