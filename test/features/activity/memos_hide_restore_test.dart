import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, ThemeMode;
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
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart';
import 'package:zcash_wallet/src/providers/memo_repository.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fake MemoRepository
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
// Canned memos
// ---------------------------------------------------------------------------

final _memo1 = rust_sync.ReceivedMemo(
  txidHex: 'aabbcc1100000000000000000000000000000000000000000000000000000000',
  memo: 'Hello from Alice',
  amountZatoshi: BigInt.from(100000000),
  blockTime: BigInt.from(1700000000),
  minedHeight: BigInt.from(2000000),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
);

final _memo2 = rust_sync.ReceivedMemo(
  txidHex: 'ddeeff2200000000000000000000000000000000000000000000000000000000',
  memo: 'Payment for coffee',
  amountZatoshi: BigInt.from(50000000),
  blockTime: BigInt.from(1700001000),
  minedHeight: BigInt.from(2000001),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
);

// ---------------------------------------------------------------------------
// Hide/restore key helpers (matching memoHideKey output)
// ---------------------------------------------------------------------------

const _txid1 =
    'aabbcc1100000000000000000000000000000000000000000000000000000000';
const _txid2 =
    'ddeeff2200000000000000000000000000000000000000000000000000000000';

// ---------------------------------------------------------------------------
// Test bootstrap
// ---------------------------------------------------------------------------

final _bootstrap = AppBootstrapState(
  initialLocation: '/memos-test',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'test-account-uuid',
        name: 'Test Account',
        order: 0,
        isSeedAnchor: true,
      ),
    ],
    activeAccountUuid: 'test-account-uuid',
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
  required AppSecureStore store,
}) {
  final router = GoRouter(
    initialLocation: '/memos-test',
    routes: [
      GoRoute(
        path: '/memos-test',
        builder: (context, state) => const Scaffold(body: MemosTab()),
      ),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (context, state) =>
            const Scaffold(body: Text('tx detail')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      memoRepositoryProvider.overrideWithValue(memoRepo),
      appSecureStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

// Pump all async work: provider resolution + any microtask storage reads.
Future<void> _settle(WidgetTester tester) async {
  // Three rounds of pumping ensures:
  // 1. Provider async operations start.
  // 2. HiddenMemosNotifier.build()'s Future.microtask(load) fires and storage
  //    reads complete (each async step needs one pump to flush its Future).
  // 3. Widget tree re-renders with all resolved data.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

// Tap a widget that is rendered inside a ListView. Advances the fake clock by
// 500 ms so that the gesture disambiguation between tap and scroll resolves
// promptly (the ListView's drag recognizer needs time to lose the arena).
Future<void> _tapInList(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

// Tap a widget that is NOT inside a ListView (e.g., a toggle chip).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppSecureStore store;

  setUp(() {
    store = AppSecureStore.testing(storage: InMemorySecureStorage());
  });

  testWidgets('inbox initially shows both memos', (tester) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Payment for coffee'), findsOneWidget);
  });

  testWidgets('hide action removes memo from inbox, other memo remains', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Tap the hide button for memo1.
    await _tapInList(
      tester,
      find.byKey(const ValueKey('hide_memo_$_txid1:3:0')),
    );

    // memo1 is gone from inbox.
    expect(find.textContaining('Hello from Alice'), findsNothing);
    // memo2 remains.
    expect(find.textContaining('Payment for coffee'), findsOneWidget);
  });

  testWidgets(
    'when all memos are hidden, inbox shows all-hidden empty state',
    (tester) async {
      final repo = _FakeMemoRepository([_memo1, _memo2]);
      await tester.pumpWidget(_harness(memoRepo: repo, store: store));
      await _settle(tester);

      await _tapInList(
        tester,
        find.byKey(const ValueKey('hide_memo_$_txid1:3:0')),
      );
      await _tapInList(
        tester,
        find.byKey(const ValueKey('hide_memo_$_txid2:3:0')),
      );

      expect(find.textContaining('All memos hidden'), findsOneWidget);
      expect(find.text('No memos yet'), findsNothing);
    },
  );

  testWidgets('hidden view shows hidden memo with restore action', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Hide memo1.
    await _tapInList(
      tester,
      find.byKey(const ValueKey('hide_memo_$_txid1:3:0')),
    );

    // Switch to hidden view.
    await _tap(tester, find.byKey(const ValueKey('memos_hidden_toggle')));

    // Hidden view shows memo1.
    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    // memo2 is not in hidden view.
    expect(find.textContaining('Payment for coffee'), findsNothing);

    // Restore action is visible.
    expect(
      find.byKey(const ValueKey('restore_memo_$_txid1:3:0')),
      findsOneWidget,
    );
  });

  testWidgets('restore action returns memo to inbox', (tester) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Hide memo1.
    await _tapInList(
      tester,
      find.byKey(const ValueKey('hide_memo_$_txid1:3:0')),
    );

    // Switch to hidden view.
    await _tap(tester, find.byKey(const ValueKey('memos_hidden_toggle')));

    // Restore memo1.
    await _tapInList(
      tester,
      find.byKey(const ValueKey('restore_memo_$_txid1:3:0')),
    );

    // Switch back to inbox.
    await _tap(tester, find.byKey(const ValueKey('memos_inbox_toggle')));

    // memo1 is back in inbox.
    expect(find.textContaining('Hello from Alice'), findsOneWidget);
  });

  testWidgets('hidden view shows "No hidden memos" when empty', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);
    await tester.pumpWidget(_harness(memoRepo: repo, store: store));
    await _settle(tester);

    // Switch to hidden view without hiding anything.
    await _tap(tester, find.byKey(const ValueKey('memos_hidden_toggle')));

    expect(find.text('No hidden memos'), findsOneWidget);
  });
}
