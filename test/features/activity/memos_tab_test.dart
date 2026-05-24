import 'package:flutter/material.dart'
    show MaterialApp, Scaffold, TextField, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/memos_tab.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart';
import 'package:zcash_wallet/src/providers/memo_repository.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeMemoRepository implements MemoRepository {
  _FakeMemoRepository(this._memos);

  final List<rust_sync.ReceivedMemo> _memos;
  String? lastQuery;

  @override
  Future<List<rust_sync.ReceivedMemo>> receivedMemos({
    required String accountUuid,
    String? query,
  }) async {
    lastQuery = query;
    if (query == null || query.isEmpty) return _memos;
    return _memos
        .where(
          (m) => m.memo.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Canned memos
// ---------------------------------------------------------------------------

final _memo1 = rust_sync.ReceivedMemo(
  txidHex: 'aabbcc1100000000000000000000000000000000000000000000000000000000',
  memo: 'Hello from Alice',
  amountZatoshi: BigInt.from(100000000), // 1 ZEC
  blockTime: BigInt.from(1700000000),
  minedHeight: BigInt.from(2000000),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
);

final _memo2 = rust_sync.ReceivedMemo(
  txidHex: 'ddeeff2200000000000000000000000000000000000000000000000000000000',
  memo: 'Payment for coffee',
  amountZatoshi: BigInt.from(50000000), // 0.5 ZEC
  blockTime: BigInt.from(1700001000),
  minedHeight: BigInt.from(2000001),
  txKind: 'received',
  outputPool: 3,
  outputIndex: 0,
);

// ---------------------------------------------------------------------------
// Fake security notifier helpers
// ---------------------------------------------------------------------------

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  _FakeAppSecurityNotifier({required bool requiresUnlock})
    : _requiresUnlock = requiresUnlock;

  final bool _requiresUnlock;

  @override
  AppSecurityState build() => AppSecurityState(
    isPasswordConfigured: _requiresUnlock,
    isUnlocked: !_requiresUnlock,
  );
}

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
  AppSecurityNotifier Function()? securityNotifier,
}) {
  // Each test gets a fresh in-memory store so hiddenMemosProvider works without
  // calling the real FlutterSecureStorage.
  final store = AppSecureStore.testing(storage: InMemorySecureStorage());

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
      if (securityNotifier != null)
        appSecurityProvider.overrideWith(securityNotifier),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('shows two memo rows when repository returns two memos', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump(); // provider resolves
    await tester.pump(); // frame

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Payment for coffee'), findsOneWidget);
  });

  testWidgets('each memo row shows amount text', (tester) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump();
    await tester.pump();

    // Verify the exact formatted amount strings rendered by MemoRow.
    final memo1Amount = ZecAmount.fromZatoshi(_memo1.amountZatoshi).activity.toString();
    final memo2Amount = ZecAmount.fromZatoshi(_memo2.amountZatoshi).activity.toString();
    expect(find.text(memo1Amount), findsOneWidget); // e.g. "1.00 ZEC"
    expect(find.text(memo2Amount), findsOneWidget); // e.g. "0.50 ZEC"
  });

  testWidgets('no-memos empty state shows "No memos yet"', (tester) async {
    final repo = _FakeMemoRepository([]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump();
    await tester.pump();

    expect(find.text('No memos yet'), findsOneWidget);
    expect(find.text('No memos match'), findsNothing);
  });

  testWidgets('search miss shows "No memos match" not "No memos yet"', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump();
    await tester.pump();

    // Type a query that won't match anything
    await tester.enterText(find.byType(TextField), 'xyznotfound');
    // Wait for debounce + provider
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    expect(find.text('No memos match'), findsOneWidget);
    expect(find.text('No memos yet'), findsNothing);
  });

  testWidgets('search narrows results when query matches one memo', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Hello from Alice'), findsOneWidget);
    expect(find.textContaining('Payment for coffee'), findsNothing);
  });

  testWidgets('clears on lock: shows empty when wallet requires unlock', (
    tester,
  ) async {
    final repo = _FakeMemoRepository([_memo1, _memo2]);

    await tester.pumpWidget(
      _harness(
        memoRepo: repo,
        securityNotifier: () =>
            _FakeAppSecurityNotifier(requiresUnlock: true),
      ),
    );
    await tester.pump();
    await tester.pump();

    // When locked, receivedMemosProvider returns [] and empty-state shows
    expect(find.textContaining('Hello from Alice'), findsNothing);
    expect(find.textContaining('Payment for coffee'), findsNothing);
    expect(find.text('No memos yet'), findsOneWidget);
  });

  testWidgets('memo row truncates very long memo text', (tester) async {
    final longMemo =
        'A' * 150; // longer than the 100-char truncation threshold
    final repo = _FakeMemoRepository([
      rust_sync.ReceivedMemo(
        txidHex:
            'ff00000000000000000000000000000000000000000000000000000000000000',
        memo: longMemo,
        amountZatoshi: BigInt.from(1000),
        blockTime: BigInt.from(1700000000),
        minedHeight: BigInt.from(2000000),
        txKind: 'received',
        outputPool: 3,
        outputIndex: 0,
      ),
    ]);

    await tester.pumpWidget(_harness(memoRepo: repo));
    await tester.pump();
    await tester.pump();

    // Displayed text should be truncated (contains '...')
    expect(
      find.textContaining('...'),
      findsWidgets,
    );
    // Full text should NOT appear verbatim
    expect(find.text(longMemo), findsNothing);
  });
}
