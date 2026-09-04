import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_host.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const _accountUuid = '550e8400-e29b-41d4-a716-446655440000';
const _address =
    'ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez';
const _prefill = SendPrefillArgs(
  id: 'payment-uri-e2e',
  source: kPaymentUriPrefillSource,
  address: _address,
  amountText: '0.12345678',
  memoText: 'CP-C6CDB775',
  label: 'Coffee shop',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeZcashWalletRuntime();
  });

  testWidgets('a payment request is answered on the card, then edited', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final router = _router();
    await tester.pumpWidget(_harness(router));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PaymentRequestHost)),
    );

    // The link arrives as a card over the wallet, not as a jump into the
    // composer.
    container
        .read(paymentRequestFlowProvider.notifier)
        .present(_prefill, source: PaymentRequestSource.link);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('payment_request_continue')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('payment_request_amount')))
          .data,
      startsWith('0.12345678'),
    );

    // Edit hands the untouched request to the composer.
    await tester.tap(find.byKey(const ValueKey('payment_request_edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('payment_request_continue')),
      findsNothing,
    );
    await _waitForFieldText(
      tester,
      const ValueKey('send_address_field'),
      _address,
      description: 'payment request address prefill',
    );
    expect(
      _fieldText(tester, const ValueKey('send_amount_field')),
      '0.12345678',
    );
    expect(
      _fieldText(tester, const ValueKey('send_memo_field')),
      'CP-C6CDB775',
    );
  });

  testWidgets('payment URI prefill survives send route refresh', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final router = _router(initialLocation: '/send', initialExtra: _prefill);
    await tester.pumpWidget(_harness(router));

    await _waitForFieldText(
      tester,
      const ValueKey('send_address_field'),
      _address,
      description: 'payment URI address prefill',
    );
    expect(
      _fieldText(tester, const ValueKey('send_amount_field')),
      '0.12345678',
    );
    expect(
      _fieldText(tester, const ValueKey('send_memo_field')),
      'CP-C6CDB775',
    );

    router.go('/send');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(_fieldText(tester, const ValueKey('send_address_field')), _address);
    expect(
      _fieldText(tester, const ValueKey('send_amount_field')),
      '0.12345678',
    );
    expect(
      _fieldText(tester, const ValueKey('send_memo_field')),
      'CP-C6CDB775',
    );
  });
}

GoRouter _router({String initialLocation = '/home', Object? initialExtra}) {
  return GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
    routes: [
      GoRoute(
        path: '/send',
        builder: (_, state) {
          final extra = state.extra;
          return SendScreen(prefill: extra is SendPrefillArgs ? extra : null);
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );
}

Widget _harness(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(_syncState)),
      // The card's pre-check would otherwise reach for the wallet DB this
      // harness does not have. The card flow, not the proposal, is under test.
      paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.light,
        child: PaymentRequestHost(router: router, child: child!),
      ),
    ),
  );
}

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  spendableIsAuthoritativeNow: () => true,
  readNetworkName: () => kZcashDefaultNetworkName,
  validateAddress: ({required String address, required String network}) async =>
      const rust_sync.AddressValidationResult(
        isValid: true,
        addressType: 'sapling',
        wrongNetwork: false,
      ),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => SendReviewArgs(
        proposalId: BigInt.from(11),
        sendFlowId: sendFlowId,
        proposalAccountUuid: accountUuid,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
        isPaymentRequest: isPaymentRequest,
        requestedBy: requestedBy,
        requestedAmountZatoshi: requestedAmountZatoshi,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async => true,
);

Future<void> _waitForFieldText(
  WidgetTester tester,
  Key key,
  String expected, {
  required String description,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (tester.any(find.byKey(key)) && _fieldText(tester, key) == expected) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $description.');
}

String _fieldText(WidgetTester tester, Key key) {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editable).controller.text;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
    activeAddress: 'u1paymenturiprefillwalletaddress',
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

final _syncState = SyncState(
  accountUuid: _accountUuid,
  hasAccountScopedData: true,
  scannedHeight: 1,
  chainTipHeight: 1,
  spendableBalance: BigInt.from(100000000),
  totalBalance: BigInt.from(100000000),
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
