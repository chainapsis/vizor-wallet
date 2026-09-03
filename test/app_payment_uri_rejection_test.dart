import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';

// A refused `zcash:` link is answered with one of two sentences, never with
// the parser's own message: that text is spec wording written for us, and it
// echoes back up to 32 characters of the link's own string.
//
// The split the payer cares about is what to do next — wait for Vizor to
// support the feature, or ask the sender for a link that works — so the two
// buckets are pinned end to end, from the native push to the snackbar.
void main() {
  const account = AccountInfo(
    uuid: 'account-1',
    name: 'Account 1',
    order: 0,
    isSeedAnchor: true,
  );

  const walletState = AccountState(
    accounts: [account],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
  );

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/send', '/welcome', '/unlock'])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('screen $path')),
          ),
      ],
    );
    addTearDown(router.dispose);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _unlockedBootstrapWithWallet(walletState),
          ),
          accountProvider.overrideWith(
            () => _ControllableAccountNotifier(walletState),
          ),
          syncProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => buildPaymentUriLinkListenerForTest(
                router: router,
                child: child!,
              ),
            );
          },
        ),
      ),
    );
    await PaymentUriService.initialize();
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a multiple-recipient link reads as an unsupported feature', (
    tester,
  ) async {
    final container = await pumpApp(tester);

    await _pushNativeUris(tester, const [
      'zcash:?address=u1firstaddress&amount=1'
          '&address.1=u1secondaddress&amount.1=2',
    ]);
    await tester.pumpAndSettle();

    expect(find.text(kPaymentUriUnsupportedMessage), findsOneWidget);
    expect(find.text(kPaymentUriMalformedMessage), findsNothing);
    expect(
      container.read(paymentUriPrefillProvider),
      isNull,
      reason: 'a refused link parks nothing',
    );
  });

  testWidgets('a malformed link reads as an invalid link', (tester) async {
    final container = await pumpApp(tester);

    await _pushNativeUris(tester, const [
      'zcash:u1recipient?amount=not-a-number',
    ]);
    await tester.pumpAndSettle();

    expect(find.text(kPaymentUriMalformedMessage), findsOneWidget);
    expect(find.text(kPaymentUriUnsupportedMessage), findsNothing);
    expect(container.read(paymentUriPrefillProvider), isNull);
  });

  testWidgets('the parser wording never reaches the payer', (tester) async {
    await pumpApp(tester);

    await _pushNativeUris(tester, const ['zcash:u1recipient?req-secret=1']);
    await tester.pumpAndSettle();

    expect(find.textContaining('ZIP-321'), findsNothing);
    expect(
      find.textContaining('req-secret'),
      findsNothing,
      reason: 'the link must not echo its own text back at the payer',
    );
    expect(find.text(kPaymentUriMalformedMessage), findsOneWidget);
  });
}

/// Delivers [uris] the way the native runner does: an `onUris` method call on
/// the payment-URI channel, which PaymentUriService forwards to its stream.
Future<void> _pushNativeUris(WidgetTester tester, List<String> uris) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'com.zcash.wallet/payment_uri',
    codec.encodeMethodCall(MethodCall('onUris', uris)),
    (_) {},
  );
}

AppBootstrapState _unlockedBootstrapWithWallet(AccountState accountState) =>
    AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.dark,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );

class _ControllableAccountNotifier extends AccountNotifier {
  _ControllableAccountNotifier(this._initial);

  final AccountState _initial;

  @override
  FutureOr<AccountState> build() => _initial;
}
