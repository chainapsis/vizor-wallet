@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/donation/donation_config.dart';
import 'package:zcash_wallet/src/features/donation/screens/donation_screen.dart';
import 'package:zcash_wallet/src/features/donation/screens/mobile/mobile_donation_review_screen.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_state_provider.dart';
import 'package:zcash_wallet/src/features/send/services/send_proving_key_warmup.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../fakes/fake_sync_notifier.dart';

class _Api extends RustLibApi {
  String? recipient;
  @override
  Future<BigInt> crateApiSyncEstimateFee({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) async {
    recipient = toAddress;
    return BigInt.from(10000);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/settings',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app({
  BigInt? balance,
  double? price = 800,
  ValueChanged<MobileDonationReviewArgs>? onReview,
  double textScale = 1,
  double keyboardInset = 0,
}) {
  final router = GoRouter(
    initialLocation: '/donation',
    routes: [
      GoRoute(
        path: '/donation',
        builder: (_, _) =>
            DonationScreen(loadWalletDbPath: () async => '/test/wallet.db'),
      ),
      GoRoute(
        path: '/donation/review',
        builder: (_, state) {
          onReview?.call(state.extra! as MobileDonationReviewArgs);
          return const Scaffold(body: Text('Review fixture'));
        },
      ),
      GoRoute(path: '/settings', builder: (_, _) => const Text('Settings')),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      sendProvingKeyWarmupProvider.overrideWithValue(() {}),
      ironwoodHomeMigrationCtaProvider.overrideWithValue(
        const AsyncData(IronwoodHomeMigrationCtaState.hidden()),
      ),
      zecLiveUsdUnitPriceProvider.overrideWithValue(price),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            spendableBalance: balance ?? BigInt.from(42000000),
            displaySpendableBalance: balance ?? BigInt.from(42000000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: router,
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
      ),
    ),
  );
}

AppButton _continue(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('donation_continue_button')),
);

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));
  tearDownAll(RustLib.dispose);
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(393, 852);
    view.devicePixelRatio = 1;
  });

  testWidgets(
    'presets estimate a donation fee and carry the exact amount to review',
    (tester) async {
      MobileDonationReviewArgs? draft;
      await tester.pumpWidget(_app(onReview: (args) => draft = args));
      await tester.pumpAndSettle();
      expect(_continue(tester).onPressed, isNull);
      await tester.tap(find.text('0.02 ZEC'));
      await tester.pumpAndSettle();
      expect(api.recipient, kVizorDonationAddress);
      expect(_continue(tester).onPressed, isNotNull);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(draft?.amountText, '0.02');
      expect(draft?.sendFlowId, isNotEmpty);
      GoRouter.of(tester.element(find.text('Review fixture'))).pop();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('donation_amount_field')),
            )
            .controller!
            .text,
        '0.02',
      );
    },
  );

  testWidgets(
    'USD preset converts to canonical ZEC and balance includes the fee',
    (tester) async {
      MobileDonationReviewArgs? draft;
      await tester.pumpWidget(_app(onReview: (args) => draft = args));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'$ 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'$15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(draft?.amountText, '0.01875');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app(balance: BigInt.from(2000000)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.02 ZEC').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Insufficient shielded balance including fee'),
        findsOneWidget,
      );
      expect(_continue(tester).onPressed, isNull);
    },
  );

  testWidgets('unavailable fiat price leaves ZEC donations available', (
    tester,
  ) async {
    await tester.pumpWidget(_app(price: null));
    await tester.pumpAndSettle();
    expect(find.text('Price unavailable'), findsOneWidget);
    await tester.tap(find.text('0.02 ZEC'));
    await tester.pumpAndSettle();
    expect(_continue(tester).onPressed, isNotNull);
    expect(find.text(r'$15'), findsNothing);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('320px composer and keyboard fit at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      await tester.pumpWidget(_app(textScale: scale, keyboardInset: 250));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('donation_amount_field')),
        '12345678.12345678',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('donation_continue_button')))
            .bottom,
        lessThanOrEqualTo(390),
      );
    });
  }

  testWidgets('shared donation artwork is present in the mobile manifest', (
    tester,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets(),
      containsAll([
        'assets/illustrations/donation_vizor_badge.webp',
        'assets/illustrations/donation_vizor_heart.webp',
      ]),
    );
  });
}
