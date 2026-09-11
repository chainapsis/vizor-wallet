@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// The hold belongs to the screen rather than to the signing flow inside it:
/// the flow is keyed per signing round, so a hold taken there would fall back
/// to zero between rounds and let a parked link through in the gap.
void main() {
  final api = _ReleaseCountingApi();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() => api.releaseCalls = 0);

  testWidgets('the mobile send signing screen holds the payment-URI busy '
      'latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: MobileKeystoneSignScreen(args: _reviewArgs),
      drainExceptions: true,
      postUnmountSettle: const Duration(seconds: 2),
    );
    expect(
      api.releaseCalls,
      1,
      reason: 'abnormal unmount still releases inputs',
    );
  });

  for (final systemBack in [false, true]) {
    testWidgets('signing cancellation returns cleanup ownership to review '
        '(systemBack=$systemBack)', (tester) async {
      final container = _container();
      final dbPath = Completer<String>();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push<void>('/review'),
                child: const Text('Open review'),
              ),
            ),
          ),
          GoRoute(
            path: '/review',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push<void>('/sign'),
                child: const Text('Open signing'),
              ),
            ),
          ),
          GoRoute(
            path: '/sign',
            builder: (_, _) => MobileKeystoneSignScreen(
              args: _reviewArgs,
              loadWalletDbPath: () => dbPath.future,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: AppTheme(
            data: AppThemeData.dark,
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open signing'));
      // The preparing screen deliberately animates until its platform-backed
      // work completes. Cancellation must also work during that stage.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (systemBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.text('Cancel'));
      }
      // Resolve preparation after pop while the outgoing screen is still
      // mounted for its route animation. Its abort must not pop Review too.
      dbPath.complete('/tmp/mobile-sign-cancel-test');
      await tester.pumpAndSettle();
      expect(find.text('Open signing'), findsOneWidget);
      expect(api.releaseCalls, 0);
    });
  }
}

class _ReleaseCountingApi implements RustLibApi {
  int releaseCalls = 0;

  @override
  Future<void> crateApiSyncDiscardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    releaseCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget Function(Widget) _host(ProviderContainer container) =>
    (child) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: AppThemeData.dark,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

final _reviewArgs = SendReviewArgs(
  proposalId: BigInt.one,
  sendFlowId: 'busy-surface-flow',
  proposalAccountUuid: 'account-1',
  address: 'u1recipient',
  addressType: 'unified',
  amountZatoshi: BigInt.from(100000),
  feeZatoshi: BigInt.from(10000),
  needsSaplingParams: false,
);

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1mobilesend',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/send/keystone-sign',
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
