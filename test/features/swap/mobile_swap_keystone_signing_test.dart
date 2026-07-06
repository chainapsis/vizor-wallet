@Tags(['mobile'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_deposit_sender.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_keystone_sign_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_review_screen.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../fakes/fake_sync_notifier.dart';

final _hardwareIntent = SwapIntent(
  id: 'swap-mobile-hardware',
  pair: 'ZEC -> USDC',
  sellAmount: '0.0030 ZEC',
  receiveEstimate: '0.21 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Sign and send the ZEC deposit with Keystone.',
  sellAmountBaseUnits: BigInt.from(300000),
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  depositAddress: 't1mobile-deposit',
  accountUuid: 'account-1',
);

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('hardware ZEC deposit opens mobile Keystone signing route', (
    tester,
  ) async {
    Object? capturedExtra;
    final router = GoRouter(
      initialLocation: '/activity/swap/${_hardwareIntent.id}',
      routes: [
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, state) => SwapActivityDetailSurface(
            intentId: state.pathParameters['swapId'] ?? '',
            returnTarget: SwapActivityReturnTarget.activity,
            layout: SwapActivityDetailLayout.mobile,
          ),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (_, state) {
            capturedExtra = state.extra;
            return const SizedBox(
              key: ValueKey('mobile_swap_keystone_sign_route'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('Deposit ZEC'), findsOneWidget);
    expect(find.text('Get signature'), findsNothing);

    await tester.tap(find.text('Deposit ZEC'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_swap_keystone_sign_route')),
      findsOneWidget,
    );
    expect(capturedExtra, isA<MobileSwapKeystoneSignArgs>());
    final args = capturedExtra! as MobileSwapKeystoneSignArgs;
    expect(args.intent.id, _hardwareIntent.id);
  });

  testWidgets('auto-sign skips the mobile ZEC deposit page', (tester) async {
    Object? capturedExtra;
    final router = GoRouter(
      initialLocation:
          '/activity/swap/${_hardwareIntent.id}?$swapActivitySignQueryKey=$swapActivitySignZecDepositValue',
      routes: [
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, state) => SwapActivityDetailSurface(
            intentId: state.pathParameters['swapId'] ?? '',
            returnTarget: SwapActivityReturnTarget.activity,
            autoSignZecDeposit:
                state.uri.queryParameters[swapActivitySignQueryKey] ==
                swapActivitySignZecDepositValue,
            layout: SwapActivityDetailLayout.mobile,
          ),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (_, state) {
            capturedExtra = state.extra;
            return const SizedBox(
              key: ValueKey('mobile_swap_keystone_sign_route'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(_app(router));
    await tester.pumpAndSettle();

    expect(find.text('Deposit ZEC'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_swap_keystone_sign_route')),
      findsOneWidget,
    );
    expect(capturedExtra, isA<MobileSwapKeystoneSignArgs>());
    final args = capturedExtra! as MobileSwapKeystoneSignArgs;
    expect(args.intent.id, _hardwareIntent.id);
  });

  testWidgets('review-start hardware ZEC swap goes directly to signing route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    Object? capturedExtra;
    final router = GoRouter(
      initialLocation: '/swap/review',
      routes: [
        GoRoute(
          path: '/swap/review',
          builder: (_, _) => const MobileSwapReviewScreen(),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (_, state) {
            capturedExtra = state.extra;
            return const SizedBox(
              key: ValueKey('mobile_swap_keystone_sign_route'),
            );
          },
        ),
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, _) => const SizedBox(
            key: ValueKey('mobile_swap_activity_detail_route'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        router,
        swapNotifier: () => _ReviewStartSwapNotifier(_hardwareIntent),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm & swap'), findsOneWidget);

    await tester.tap(find.text('Confirm & swap'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_swap_keystone_sign_route')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_swap_activity_detail_route')),
      findsNothing,
    );
    expect(capturedExtra, isA<MobileSwapKeystoneSignArgs>());
    final args = capturedExtra! as MobileSwapKeystoneSignArgs;
    expect(args.intent.id, _hardwareIntent.id);
    expect(args.startedFromReview, isTrue);
    expect(args.returnTarget, SwapActivityReturnTarget.swap);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/swap/keystone-sign',
    );
  });

  testWidgets('review-start signing cancel clears pending intent and returns', (
    tester,
  ) async {
    late _PendingSigningSwapNotifier swapNotifier;
    final router = GoRouter(
      initialLocation: '/swap/keystone-sign',
      routes: [
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (_, _) => MobileSwapKeystoneSignScreen(
            args: MobileSwapKeystoneSignArgs.fromReview(
              intent: _hardwareIntent,
            ),
          ),
        ),
        GoRoute(
          path: '/swap',
          builder: (_, _) => const SizedBox(key: ValueKey('mobile_swap_route')),
        ),
      ],
    );

    await tester.pumpWidget(
      _app(
        router,
        swapNotifier: () {
          swapNotifier = _PendingSigningSwapNotifier(_hardwareIntent);
          return swapNotifier;
        },
        hardwareSigningService: _FakeSwapHardwareSigningService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(swapNotifier.pendingCleared, isTrue);
    expect(find.byKey(const ValueKey('mobile_swap_route')), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.toString(), '/swap');
  });

  testWidgets(
    'review-start signing success records activity and opens detail',
    (tester) async {
      ValueChanged<ScanResult>? completeScan;
      late _ReviewSuccessSwapNotifier swapNotifier;
      final router = GoRouter(
        initialLocation: '/swap/keystone-sign',
        routes: [
          GoRoute(
            path: '/swap/keystone-sign',
            builder: (_, _) => MobileSwapKeystoneSignScreen(
              args: MobileSwapKeystoneSignArgs.fromReview(
                intent: _hardwareIntent,
              ),
              scannerBuilder: (_, onComplete, _, _) {
                completeScan = onComplete;
                return const SizedBox(
                  key: ValueKey('fake_mobile_swap_keystone_scanner'),
                );
              },
              forceScannerActiveForTesting: true,
              signedPcztDecoder: (_) async =>
                  Uint8List.fromList(const [10, 11]),
            ),
          ),
          GoRoute(
            path: '/activity/swap/:swapId',
            builder: (_, state) => SizedBox(
              key: const ValueKey('mobile_swap_activity_detail_route'),
              child: Text(state.pathParameters['swapId'] ?? ''),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        _app(
          router,
          swapNotifier: () {
            swapNotifier = _ReviewSuccessSwapNotifier(_hardwareIntent);
            return swapNotifier;
          },
          hardwareSigningService: _FakeSwapHardwareSigningService(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next step'));
      await tester.pump();

      completeScan!(const ScanResult(urType: 'zcash-pczt', data: [1, 2, 3]));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(swapNotifier.recordedBroadcast?.txHash, 'hardware-broadcast-txid');
      expect(swapNotifier.pendingCleared, isTrue);
      expect(
        find.byKey(const ValueKey('mobile_swap_activity_detail_route')),
        findsOneWidget,
      );
      expect(find.text(_hardwareIntent.id), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/activity/swap/${_hardwareIntent.id}?from=swap',
      );
    },
  );

  testWidgets('mobile Keystone broadcast failure shows toast without submit', (
    tester,
  ) async {
    const failureMessage = 'Keystone signature could not be applied.';
    final swapProvider = _FakeSwapProvider();
    final router = GoRouter(
      initialLocation: '/activity/swap/${_hardwareIntent.id}',
      routes: [
        GoRoute(
          path: '/activity/swap/:swapId',
          builder: (_, state) => SwapActivityDetailSurface(
            intentId: state.pathParameters['swapId'] ?? '',
            returnTarget: SwapActivityReturnTarget.activity,
            layout: SwapActivityDetailLayout.mobile,
          ),
        ),
        GoRoute(
          path: '/swap/keystone-sign',
          builder: (context, _) => Center(
            child: TextButton(
              key: const ValueKey('fail_mobile_swap_keystone_signing'),
              onPressed: () => context.pop(
                const MobileSwapKeystoneSignFailure(failureMessage),
              ),
              child: const Text('Fail signing'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(_app(router, swapProvider: swapProvider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deposit ZEC'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('fail_mobile_swap_keystone_signing')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(failureMessage), findsOneWidget);
    expect(swapProvider.submitDepositTransactionCalls, 0);
  });
}

Widget _app(
  GoRouter router, {
  _FakeSwapProvider? swapProvider,
  SwapNotifier Function()? swapNotifier,
  SwapHardwareSigningService? hardwareSigningService,
}) {
  final activityStore = _FakeSwapActivityStore([_hardwareIntent]);
  final preferencesStore = _FakeSwapComposerPreferencesStore();
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      swapFeatureEnabledProvider.overrideWithValue(true),
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(),
      ),
      if (swapNotifier != null) swapStateProvider.overrideWith(swapNotifier),
      swapInitialIntentsProvider.overrideWithValue([_hardwareIntent]),
      swapActivityStoreProvider.overrideWithValue(activityStore),
      swapComposerPreferencesStoreProvider.overrideWithValue(preferencesStore),
      swapIntentProvider.overrideWithValue(swapProvider ?? _FakeSwapProvider()),
      swapDepositSenderProvider.overrideWithValue(_FakeSwapDepositSender()),
      swapHardwareSigningServiceProvider.overrideWithValue(
        hardwareSigningService ?? _FakeSwapHardwareSigningService(),
      ),
      swapStatusPollIntervalProvider.overrideWithValue(
        const Duration(hours: 1),
      ),
      swapPriceRefreshIntervalProvider.overrideWithValue(
        const Duration(hours: 1),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            spendableBalance: BigInt.from(100000000),
            totalBalance: BigInt.from(100000000),
          ),
        ),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _reviewQuote = SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  sellAmount: 0.003,
  receiveAmount: 0.21,
  minimumReceiveAmount: 0.20,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included in shown rate',
  expiryLabel: '07:12',
  sellAmountBaseUnits: BigInt.from(300000),
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 't1mobile-deposit',
    expiresInLabel: '07:12',
    reuseWarning: 'Do not reuse this address',
  ),
);

const _reviewAddressPlan = SwapAddressPlan(
  direction: SwapDirection.zecToExternal,
  externalAsset: SwapAsset.usdc,
  userExternalAddress: '0xrecipient',
  walletZecAddress: 'u1mobilehardware',
  oneClickRecipient: '0xrecipient',
  oneClickRefundTo: 'u1mobilehardware',
);

class _ReviewStartSwapNotifier extends SwapNotifier {
  _ReviewStartSwapNotifier(this.intent);

  final SwapIntent intent;

  @override
  SwapState build() {
    return const SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '0.003',
      receiveAmountText: '',
      destinationText: '0xrecipient',
      externalAsset: SwapAsset.usdc,
      reviewVisible: true,
      intents: [],
    ).copyWith(
      reviewQuote: _reviewQuote,
      reviewAddressPlan: _reviewAddressPlan,
      reviewAccountUuid: 'account-1',
    );
  }

  @override
  Future<SwapStartResult?> startIntent() async {
    state = state.copyWith(
      reviewVisible: false,
      pendingKeystoneSigningIntent: intent,
      startSubmitting: false,
      clearReview: true,
      clearStatusError: true,
      clearSelectedIntent: true,
    );
    return SwapStartedKeystoneSigning(intent.id);
  }
}

class _PendingSigningSwapNotifier extends SwapNotifier {
  _PendingSigningSwapNotifier(this.intent);

  final SwapIntent intent;
  bool pendingCleared = false;

  @override
  SwapState build() {
    return const SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '',
      destinationText: '',
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
    ).copyWith(pendingKeystoneSigningIntent: intent);
  }

  @override
  void clearPendingKeystoneSigningIntent(String intentId) {
    if (intentId == intent.id) pendingCleared = true;
    state = state.copyWith(clearPendingKeystoneSigningIntent: true);
  }
}

class _ReviewSuccessSwapNotifier extends _PendingSigningSwapNotifier {
  _ReviewSuccessSwapNotifier(super.intent);

  SwapDepositBroadcastResult? recordedBroadcast;

  @override
  Future<void> recordKeystoneDepositBroadcast({
    required SwapIntent intent,
    required SwapDepositBroadcastResult broadcast,
  }) async {
    recordedBroadcast = broadcast;
    clearPendingKeystoneSigningIntent(intent.id);
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity/swap/${_hardwareIntent.id}',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Keystone',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1mobilehardware',
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

class _FakeSwapProvider implements SwapProvider {
  int submitDepositTransactionCalls = 0;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return const [SwapAsset.usdc];
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo}) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    submitDepositTransactionCalls += 1;
    return SwapIntentSnapshot(
      id: _hardwareIntent.id,
      providerLabel: providerLabel,
      pairText: _hardwareIntent.pair,
      sellAmountText: _hardwareIntent.sellAmount,
      receiveEstimateText: _hardwareIntent.receiveEstimate,
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Waiting for swap provider confirmation.',
      originChainTxHash: txHash,
      depositInstruction: const SwapDepositInstruction(
        asset: SwapAsset.zec,
        address: 't1mobile-deposit',
        expiresInLabel: '1 hour',
        reuseWarning: 'Use this deposit address only once.',
      ),
    );
  }
}

class _FakeSwapDepositSender implements SwapDepositSender {
  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    return BigInt.from(10000);
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    return const SwapDepositBroadcastResult(
      txHash: 'mobile-zec-deposit-tx',
      status: SwapDepositBroadcastStatus.broadcasted,
    );
  }
}

class _FakeSwapHardwareSigningService implements SwapHardwareSigningService {
  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    return SwapHardwarePcztDraft(
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-pczt/test'];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const [7, 8, 9];
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const rust_sync.ExtractAndBroadcastPcztResult(
      txid: 'hardware-broadcast-txid',
      status: SwapDepositBroadcastStatus.broadcasted,
      message: null,
    );
  }
}

class _FakeAddressBookRepository implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async {
    return const [];
  }

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _FakeSwapActivityStore implements SwapActivityStore {
  _FakeSwapActivityStore(List<SwapIntent> initialIntents)
    : _records = [
        for (final intent in initialIntents)
          SwapIntentRecord.fromIntent(intent),
      ];

  List<SwapIntentRecord> _records;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return _records;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    _records = records;
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    _records = [];
  }
}

class _FakeSwapComposerPreferencesStore
    implements SwapComposerPreferencesStore {
  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    return null;
  }

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {}
}
