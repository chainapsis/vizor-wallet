import 'package:flutter/material.dart'
    show DropdownButton, MaterialApp, Scaffold, TextField, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/memos_tab.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/address_labels_provider.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart'
    show appSecureStoreProvider;
import 'package:zcash_wallet/src/providers/memo_repository.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeMemoRepository implements MemoRepository {
  _FakeMemoRepository(this._memos);
  final List<rust_sync.ReceivedMemo> _memos;

  @override
  Future<List<rust_sync.ReceivedMemo>> receivedMemos({
    required String accountUuid,
    String? query,
  }) async {
    if (query == null || query.isEmpty) return _memos;
    return _memos
        .where((m) => m.memo.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Canned memos with toAddress
// ---------------------------------------------------------------------------

const _addrA =
    'u1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _addrB =
    'u1bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final _memoA1 = rust_sync.ReceivedMemo(
  txidHex: 'aabbcc1100000000000000000000000000000000000000000000000000000000',
  memo: 'Hello from Alice',
  amountZatoshi: BigInt.from(100000000),
  blockTime: BigInt.from(1700000000),
  minedHeight: BigInt.from(2000000),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
  toAddress: _addrA,
);

final _memoA2 = rust_sync.ReceivedMemo(
  txidHex: 'aabbcc2200000000000000000000000000000000000000000000000000000000',
  memo: 'Second memo to A',
  amountZatoshi: BigInt.from(200000000),
  blockTime: BigInt.from(1700001000),
  minedHeight: BigInt.from(2000001),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
  toAddress: _addrA,
);

final _memoB1 = rust_sync.ReceivedMemo(
  txidHex: 'bbccdd1100000000000000000000000000000000000000000000000000000000',
  memo: 'Payment to B',
  amountZatoshi: BigInt.from(50000000),
  blockTime: BigInt.from(1700002000),
  minedHeight: BigInt.from(2000002),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
  toAddress: _addrB,
);

// ---------------------------------------------------------------------------
// Bootstrap + harness
// ---------------------------------------------------------------------------

const _accountUuid = 'test-account-uuid';

final _bootstrap = AppBootstrapState(
  initialLocation: '/memos-test',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: _accountUuid,
        name: 'Test Account',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: _accountUuid,
    activeAddress: 'u1testaddress',
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

Widget _harness({
  required MemoRepository memoRepo,
  AppSecureStore? store,
  AddressLabelsState? initialLabels,
}) {
  final effectiveStore =
      store ?? AppSecureStore.testing(storage: InMemorySecureStorage());

  final router = GoRouter(
    initialLocation: '/memos-test',
    routes: [
      GoRoute(
        path: '/memos-test',
        builder: (context, state) => const Scaffold(body: MemosTab()),
      ),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (context, state) => const Scaffold(body: Text('tx detail')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      memoRepositoryProvider.overrideWithValue(memoRepo),
      appSecureStoreProvider.overrideWithValue(effectiveStore),
      if (initialLabels != null)
        addressLabelsProvider.overrideWith(
          () => _PreloadedLabelsNotifier(initialLabels),
        ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

/// A notifier that starts with a pre-seeded state (skips async storage load).
class _PreloadedLabelsNotifier extends AddressLabelsNotifier {
  _PreloadedLabelsNotifier(this._initial);
  final AddressLabelsState _initial;

  @override
  AddressLabelsState build() => _initial;
}

/// Pump until all providers and async storage reads settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

Future<void> _tapInList(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dropdown present when 2+ distinct addresses', (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    expect(find.byType(DropdownButton<String?>), findsOneWidget);
  });

  testWidgets('dropdown hidden when only one distinct address', (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    expect(find.byType(DropdownButton<String?>), findsNothing);
  });

  testWidgets('dropdown shows "All addresses" and both truncated addresses',
      (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    // "All addresses" is the selected value — visible in closed state
    expect(find.text('All addresses'), findsOneWidget);

    // Open dropdown to see all items
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();

    expect(find.text('u1aaaaaaaa...aaaaaaaaaa'), findsWidgets);
    expect(find.text('u1bbbbbbbb...bbbbbbbbbb'), findsWidgets);
  });

  testWidgets('labeled address shows its label in dropdown', (tester) async {
    final labels = AddressLabelsState({
      _accountUuid: {_addrA: 'My Main Address'},
    });
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(
      _harness(memoRepo: repo, initialLabels: labels),
    );
    await _settle(tester);

    // Open dropdown to see all items
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();

    // Label appears in dropdown for addrA
    expect(find.text('My Main Address'), findsWidgets);
    // Unlabeled addrB shows truncated form
    expect(find.text('u1bbbbbbbb...bbbbbbbbbb'), findsWidgets);
  });

  testWidgets('selecting addrA narrows to 2 memos', (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Second memo to A'), findsOneWidget);
    expect(find.textContaining('Payment to B'), findsOneWidget);

    // Open dropdown
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();
    // Select addrA option (use .last in case multiple text matches due to
    // dropdown overlay rendering both the button value and the menu item)
    await _tap(tester, find.text('u1aaaaaaaa...aaaaaaaaaa').last);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Second memo to A'), findsOneWidget);
    expect(find.textContaining('Payment to B'), findsNothing);
  });

  testWidgets('selecting addrB narrows to 1 memo', (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();
    await _tap(tester, find.text('u1bbbbbbbb...bbbbbbbbbb').last);

    expect(find.textContaining('Hello from Alice'), findsNothing);
    expect(find.textContaining('Second memo to A'), findsNothing);
    expect(find.textContaining('Payment to B'), findsOneWidget);
  });

  testWidgets('search + address filter both narrow results', (tester) async {
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo));
    await _settle(tester);

    // Select addrA — 2 memos visible
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();
    await _tap(tester, find.text('u1aaaaaaaa...aaaaaaaaaa').last);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Second memo to A'), findsOneWidget);

    // Now search for 'Alice' — narrows to 1
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Second memo to A'), findsNothing);
  });

  testWidgets('address filter applies in hidden view', (tester) async {
    final store = AppSecureStore.testing(storage: InMemorySecureStorage());
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Hide memoA1
    await _tapInList(
      tester,
      find.byKey(ValueKey(
        'hide_memo_${_memoA1.txidHex}:${_memoA1.outputPool}:${_memoA1.outputIndex}',
      )),
    );

    // Switch to hidden view
    await _tap(tester, find.byKey(const ValueKey('memos_hidden_toggle')));
    await _settle(tester);

    // Hidden view shows memoA1 (only hidden memo)
    expect(find.textContaining('Hello from Alice'), findsOneWidget);

    // Select addrA in filter — memoA1 is addrA so still visible
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();
    await _tap(tester, find.text('u1aaaaaaaa...aaaaaaaaaa').last);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
  });

  testWidgets(
    'selected address resets to All when absent from new search results',
    (tester) async {
      final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
      await tester.pumpWidget(_harness(memoRepo: repo));
      await _settle(tester);

      // Select addrB
      await _tap(tester, find.byType(DropdownButton<String?>));
      await tester.pump();
      await _tap(tester, find.text('u1bbbbbbbb...bbbbbbbbbb').last);

      expect(find.textContaining('Payment to B'), findsOneWidget);

      // Search for 'Alice' — only addrA memos match; addrB disappears from set
      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      // post-frame callback needs extra pump
      await tester.pump();
      await tester.pump();

      // addrB is no longer in the address list; filter reset to All
      // Alice memo is visible, and no "No memos for this address" message
      expect(find.textContaining('Hello from Alice'), findsOneWidget);
      expect(find.text('No memos for this address'), findsNothing);
    },
  );

  testWidgets('empty inbox for selected address shows specific message',
      (tester) async {
    final store = AppSecureStore.testing(storage: InMemorySecureStorage());
    final repo = _FakeMemoRepository([_memoA1, _memoA2, _memoB1]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Select addrB (has 1 inbox memo)
    await _tap(tester, find.byType(DropdownButton<String?>));
    await tester.pump();
    await _tap(tester, find.text('u1bbbbbbbb...bbbbbbbbbb').last);
    expect(find.textContaining('Payment to B'), findsOneWidget);

    // Hide the only addrB memo
    await _tapInList(
      tester,
      find.byKey(ValueKey(
        'hide_memo_${_memoB1.txidHex}:${_memoB1.outputPool}:${_memoB1.outputIndex}',
      )),
    );

    // Inbox for addrB is empty → specific message
    expect(find.text('No memos for this address'), findsOneWidget);
  });
}
