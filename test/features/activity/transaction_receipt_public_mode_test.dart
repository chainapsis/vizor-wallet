import 'package:flutter/material.dart' show MaterialApp, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/activity/widgets/received_receipt_view.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_status_content_view.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_enhance_pir_notifier.dart';
import '../../fakes/fake_sync_notifier.dart';
import 'transparent_details_test_support.dart';

/// Receipts with private queries OFF (public mode) must behave as on main
/// (d7279650c): main had no transparent-details state and never polled a
/// receipt. The shielded expectations below are main's, taken from main's
/// `activity_transaction_status_screen_test.dart` fixtures.

const _txidHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _recipientAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

final _blockTime = BigInt.from(1764150000);

/// Main's shielded Activity row.
rust_sync.TransactionInfo _shielded({
  required String txKind,
  BigInt? fee,
  BigInt? displayAmount,
}) => rust_sync.TransactionInfo(
  txidHex: _txidHex,
  minedHeight: BigInt.from(2500000),
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: fee ?? BigInt.zero,
  feeState: rust_sync.TransactionFeeState.known,
  detailsComplete: true,
  provisional: false,
  amountIncludesFee: false,
  blockTime: _blockTime,
  isTransparent: false,
  txKind: txKind,
  displayAmount: displayAmount ?? BigInt.from(12000000000),
  displayPool: 'shielded',
  createdTime: _blockTime,
);

/// A shielded-only detail: no transparent details state at all.
rust_sync.TransactionDetail _shieldedDetail({
  required String txKind,
  String? primaryAddress,
  String? sourcePool,
  String? memo,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
}) => rust_sync.TransactionDetail(
  txidHex: _txidHex,
  detailsComplete: true,
  provisional: false,
  txKind: txKind,
  primaryAddress: primaryAddress,
  sourcePool: sourcePool,
  memo: memo,
  outputs: outputs,
  transparentRecipients: const [],
  transparentOmissions: const [],
);

String _expectedTimestamp(BigInt seconds) {
  const months = <String>[
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = DateTime.fromMillisecondsSinceEpoch(
    seconds.toInt() * 1000,
  ).toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month]}, $hh:$mm';
}

class _Loads {
  int history = 0;
  int detail = 0;
  final prioritized = <String>[];
}

/// The desktop receipt with private queries off, loaders counted.
Future<_Loads> _pump(
  WidgetTester tester, {
  required rust_sync.TransactionInfo transaction,
  required Future<rust_sync.TransactionDetail?> Function() detail,
  rust_sync.TransactionDetail? initialDetail,
}) async {
  final loads = _Loads();
  await tester.binding.setSurfaceSize(const Size(1512, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/activity/tx/${transaction.txidHex}',
    routes: [
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => ActivityTransactionStatusScreen(
          args: ActivityTransactionStatusArgs(
            txidHex: transaction.txidHex,
            txKind: transaction.txKind,
            initialTransaction: transaction,
            initialDetail: initialDetail,
          ),
          historyLoader: (_) async {
            loads.history++;
            return [transaction];
          },
          detailLoader: (_, _) {
            loads.detail++;
            return detail();
          },
          transparentDetailsPrioritizer: (txid) async =>
              loads.prioritized.add(txid),
          showPrivateLookupDiagnostics: false,
        ),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        swapFeatureEnabledProvider.overrideWithValue(true),
        privacyModeProvider.overrideWith(PrivacyOff.new),
        enhancePirProvider.overrideWith(() => FakeEnhancePirNotifier(false)),
        appBootstrapProvider.overrideWithValue(_bootstrap),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(
              accountUuid: 'account-1',
              hasAccountScopedData: true,
              percentage: 1,
            ),
          ),
        ),
        addressBookRepositoryProvider.overrideWithValue(_NoContacts()),
        ownAccountAddressesProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return loads;
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _NoContacts implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

/// No transparent-details poll runs: several poll intervals pass with no
/// further detail read.
Future<void> _expectNoPolling(WidgetTester tester, _Loads loads) async {
  final reads = loads.detail;
  await tester.pump(kTransparentDetailsPollInterval * 4);
  await tester.pump();
  expect(loads.detail, reads, reason: 'no transparent-details polling');
  expect(loads.prioritized, isEmpty);
}

void main() {
  group('public mode receipt', () {
    testWidgets('pending then unavailable transparent details stop polling', (
      tester,
    ) async {
      final pending = transparentDetail(
        rust_sync.TransparentDetailsState.pending,
      );
      final unavailable = transparentDetail(
        rust_sync.TransparentDetailsState.unavailable,
      );
      var reads = 0;
      final loads = await _pump(
        tester,
        transaction: transparentSend(),
        detail: () async => reads++ == 0 ? pending : unavailable,
      );
      expect(loads.detail, 1);
      // Pending details are polled.
      await tester.pump(kTransparentDetailsPollInterval);
      await tester.pump();
      expect(loads.detail, 2);
      expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);

      // In public mode a failed lookup is final: the receipt stops
      // re-reading, as on main.
      await tester.pump(kTransparentDetailsPollInterval * 4);
      await tester.pump();
      expect(
        loads.detail,
        2,
        reason: 'no detail read after the unavailable state',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a shielded send renders as on main and is never polled', (
      tester,
    ) async {
      const memo = 'Zcash is a privacy-focused message for the recipient.';
      final detail = _shieldedDetail(
        txKind: 'sent',
        primaryAddress: _recipientAddress,
        memo: memo,
      );
      final loads = await _pump(
        tester,
        transaction: _shielded(txKind: 'sent', fee: BigInt.from(10000)),
        detail: () async => detail,
      );
      expect(loads.history, 1);
      expect(loads.detail, 1);

      // Main: 'renders the send status view for a confirmed send'.
      expect(find.byType(SendStatusContentView), findsOneWidget);
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('120.00 ZEC'), findsOneWidget);
      expect(find.text('u195091 ... 190591'), findsOneWidget);
      expect(find.text('0.0001 ZEC'), findsOneWidget);
      expect(find.text(memo), findsOneWidget);
      expect(
        find.text(
          truncatedTxid(
            'efcdab8967452301efcdab8967452301'
            'efcdab8967452301efcdab8967452301',
          ),
        ),
        findsOneWidget,
      );
      // Nothing main did not have.
      expect(find.text(kUnknownRecipientText), findsNothing);
      expect(find.text(kUnknownFeeText), findsNothing);
      expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
      expect(find.text(kTransparentDetailsNotCoveredText), findsNothing);
      expect(find.text(kTransactionOutputsText), findsNothing);
      expect(find.text(kLoadDetailsPubliclyText), findsNothing);

      await _expectNoPolling(tester, loads);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a shielded receive renders as on main and is never polled', (
      tester,
    ) async {
      const memo = 'Thanks for lunch';
      final detail = _shieldedDetail(
        txKind: 'received',
        sourcePool: 'shielded',
        memo: memo,
        outputs: [
          rust_sync.TransactionDetailOutput(
            usesOrchardReceiver: false,
            address: _recipientAddress,
            amountZatoshi: BigInt.from(12000000000),
            pool: 'shielded',
          ),
        ],
      );
      final loads = await _pump(
        tester,
        transaction: _shielded(txKind: 'received'),
        detail: () async => detail,
      );

      // Main: 'renders the redesigned receipt for a confirmed receive' and
      // 'labels shielded-source receives as shielded sender'.
      expect(find.byType(ReceivedReceiptView), findsOneWidget);
      expect(find.text('Received successfully'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('120.00 ZEC'), findsOneWidget);
      expect(find.text('From'), findsOneWidget);
      expect(find.text('Shielded sender'), findsOneWidget);
      expect(find.text('Unknown sender'), findsNothing);
      expect(find.text('Shielded'), findsOneWidget);
      expect(find.text('Show full address'), findsNothing);
      expect(find.text(memo), findsOneWidget);
      expect(find.text(_expectedTimestamp(_blockTime)), findsOneWidget);
      expect(find.text('Network fee'), findsNothing);
      expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
      expect(find.text(kLoadDetailsPubliclyText), findsNothing);

      await _expectNoPolling(tester, loads);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a shielded receive with a known fee shows no fee row, as on '
        'main', (tester) async {
      final detail = _shieldedDetail(
        txKind: 'received',
        sourcePool: 'shielded',
      );
      final loads = await _pump(
        tester,
        transaction: _shielded(txKind: 'received', fee: BigInt.from(10000)),
        detail: () async => detail,
      );
      expect(find.byType(ReceivedReceiptView), findsOneWidget);
      // As on main, a receive shows no fee row: the sender paid it.
      expect(find.text('Network fee'), findsNothing);
      expect(find.text('0.0001 ZEC'), findsNothing);
      await _expectNoPolling(tester, loads);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
