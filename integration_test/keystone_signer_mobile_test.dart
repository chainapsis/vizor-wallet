@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/keystone/widgets/keystone_pczt_qr_stage.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'support/keystone_signing_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(initializeZcashWalletRuntime);
  setUp(installFixtureCamera);
  tearDownAll(releaseKeystoneWallet);

  testWidgets(
    'sends to TEX after two Keystone firmware signatures',
    (tester) => _runSend(tester, tex: true),
    timeout: const Timeout(Duration(minutes: 6)),
  );
  testWidgets(
    'broadcasts a send after one Keystone batch signature',
    (tester) => _runSend(tester, tex: false),
    timeout: const Timeout(Duration(minutes: 6)),
  );
  testWidgets(
    'signs two delegation bundles in one Keystone voting batch',
    _runVoting,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _runSend(WidgetTester tester, {required bool tex}) async {
  final fixture = await KeystoneSendFixture.create(tex: tex);
  final args = fixture.args;
  final router = GoRouter(
    initialLocation: '/send',
    routes: [
      GoRoute(
        path: '/send',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              child: const Text('Sign'),
              onPressed: () async {
                final result = await context.push<KeystoneBroadcastArgs>(
                  '/send/keystone-sign',
                );
                if (context.mounted && result != null) {
                  fixture.recordSigned(result);
                  context.go('/send/status', extra: result);
                }
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/send/keystone-sign',
        builder: (_, _) => MobileKeystoneSignScreen(args: args),
      ),
      GoRoute(
        path: '/send/status',
        builder: (_, state) => MobileSendStatusScreen(
          args: args,
          keystone: state.extra! as KeystoneBroadcastArgs,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    fixture.withWallet(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.tap(find.text('Sign'));

  for (var round = 0; round < fixture.approvals; round++) {
    final qr = find.descendant(
      of: find.byKey(ValueKey('mobile_keystone_sign_round_$round')),
      matching: find.byType(KeystonePcztQrStage),
    );
    await waitForWidget(tester, qr);
    final frames = tester.widget<KeystonePcztQrStage>(qr).urParts;
    await Scrollable.ensureVisible(tester.element(qr), alignment: 0.5);
    final scanner = find.byKey(
      const ValueKey('mobile_keystone_sign_scanner_card'),
    );
    await exchangeKeystoneSignature(
      tester,
      frames,
      batch: !tex,
      openScanner: () async {
        await tapWhenReady(
          tester,
          find.byKey(const ValueKey('mobile_keystone_sign_get_signature')),
        );
        await waitForWidget(tester, scanner);
        await fixture.expectNoBroadcast();
      },
      scanComplete: () => !tester.any(scanner),
    );
  }
  await waitForWidget(
    tester,
    find.byKey(const ValueKey('mobile_send_status_succeeded')),
  );
  await fixture.verifyBroadcast();
}

Future<void> _runVoting(WidgetTester tester) async {
  final fixture = await KeystoneVoteFixture.create();
  final round = fixture.round;
  final scanned = Completer<List<int>>();
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        home: AppTheme(
          data: AppThemeData.light,
          child: MobileKeystoneVotingSigningScreen(
            presentation: VotingKeystoneStatusPresentation(
              bundleIndex: round.requests.first.bundleIndex,
              urParts: round.batchRequest.urParts,
              batchMessageCount: round.requests.length,
              batchTotalCount: fixture.requests.length,
              batchMemos: fixture.memos,
              onSigned: (cbor) async => scanned.complete(cbor),
            ),
          ),
        ),
      ),
    ),
  );
  final qr = find.byType(KeystonePcztQrStage);
  await waitForWidget(tester, qr);
  expect(find.text('Bundle 1 of 2'), findsOneWidget);
  await tapWhenReady(tester, find.bySemanticsLabel('Next voting bundle'));
  await tester.pump();
  expect(find.text('Bundle 2 of 2'), findsOneWidget);
  await Scrollable.ensureVisible(tester.element(qr), alignment: 0.5);
  await exchangeKeystoneSignature(
    tester,
    tester.widget<KeystonePcztQrStage>(qr).urParts,
    batch: true,
    voting: true,
    openScanner: () async {
      await tapWhenReady(
        tester,
        find.byKey(const ValueKey('mobile_voting_keystone_get_signature')),
      );
      await waitForWidget(
        tester,
        find.byKey(const ValueKey('mobile_voting_keystone_scanner_card')),
      );
    },
    scanComplete: () => scanned.isCompleted,
  );
  await fixture.verifySignatures(
    await scanned.future.timeout(const Duration(seconds: 15)),
  );
}
