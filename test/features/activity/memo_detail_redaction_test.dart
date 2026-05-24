import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/models/memo_hide_key.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/providers/hidden_memos_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../helpers/in_memory_secure_storage.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

const _txidHex = 'abc';
const _memoOutputKey = '2:0';
const _accountUuid = 'test-account-uuid';

// The canonical hide-key for the test memo.
final _hideKey = memoHideKeyFromDetail(
  txidHex: _txidHex,
  memoOutputKey: _memoOutputKey,
);

// A minimal TransactionDetail that carries a memo and a memoOutputKey.
const _detail = rust_sync.TransactionDetail(
  txidHex: _txidHex,
  txKind: 'received',
  memo: 'secret memo',
  memoOutputKey: _memoOutputKey,
  outputs: [],
);

// ---------------------------------------------------------------------------
// Pre-seeded HiddenMemosNotifier for "already hidden" scenarios
// ---------------------------------------------------------------------------

/// Starts with [_hideKey] already in the hidden set for [_accountUuid].
class _PreHiddenNotifier extends HiddenMemosNotifier {
  @override
  HiddenMemosState build() {
    return HiddenMemosState({
      _accountUuid: {_hideKey},
    });
  }
}

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

/// Renders [MemoDetailSection] in isolation so we can test the redaction /
/// restore behavior independently of [ActivityTransactionStatusScreen].
///
/// The expand/collapse toggle is intentionally NOT part of this widget — it
/// lives in the screen's message-block `titleTrailing` — so this harness only
/// exercises the memo-text-vs-placeholder branch.
class _TestSection extends ConsumerWidget {
  const _TestSection({
    required this.detail,
    required this.memo,
  });

  final rust_sync.TransactionDetail detail;
  final String memo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MemoDetailSection(
      txidHex: _txidHex,
      detail: detail,
      accountUuid: _accountUuid,
      memo: memo,
      expanded: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared app wrapper
// ---------------------------------------------------------------------------

Widget _themed(Widget child) => MaterialApp(
      home: Scaffold(
        body: AppTheme(data: AppThemeData.light, child: child),
      ),
    );

// ---------------------------------------------------------------------------
// Settle helper
// ---------------------------------------------------------------------------

Future<void> _settle(WidgetTester tester) async {
  // Flush HiddenMemosNotifier.build()'s Future.microtask(load) chain.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
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

  // ---- Control case --------------------------------------------------------

  testWidgets(
    'control: memo text shown when key is NOT hidden',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSecureStoreProvider.overrideWithValue(store)],
          child: _themed(
            const _TestSection(detail: _detail, memo: 'secret memo'),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('secret memo'), findsOneWidget);
      expect(find.text('Memo hidden'), findsNothing);
      expect(find.text('Restore'), findsNothing);
    },
  );

  // ---- Hidden case ---------------------------------------------------------

  testWidgets(
    'memo is redacted and Restore shown when hide-key is in hidden set',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSecureStoreProvider.overrideWithValue(store),
            hiddenMemosProvider.overrideWith(_PreHiddenNotifier.new),
          ],
          child: _themed(
            const _TestSection(detail: _detail, memo: 'secret memo'),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Memo hidden'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('secret memo'), findsNothing);
    },
  );

  // ---- Restore action ------------------------------------------------------

  testWidgets(
    'tapping Restore makes memo text visible again',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSecureStoreProvider.overrideWithValue(store),
            hiddenMemosProvider.overrideWith(_PreHiddenNotifier.new),
          ],
          child: _themed(
            const _TestSection(detail: _detail, memo: 'secret memo'),
          ),
        ),
      );
      await _settle(tester);

      // Precondition: hidden.
      expect(find.text('Memo hidden'), findsOneWidget);
      expect(find.text('secret memo'), findsNothing);

      // Tap Restore.
      await tester.tap(find.text('Restore'));
      await tester.pump();
      await _settle(tester);

      // Memo text is back, placeholder gone.
      expect(find.text('secret memo'), findsOneWidget);
      expect(find.text('Memo hidden'), findsNothing);
      expect(find.text('Restore'), findsNothing);
    },
  );

  // ---- null memoOutputKey case ---------------------------------------------

  testWidgets(
    'memo with null memoOutputKey is always shown without hide check',
    (tester) async {
      const detailNoKey = rust_sync.TransactionDetail(
        txidHex: _txidHex,
        txKind: 'received',
        memo: 'visible memo',
        memoOutputKey: null,
        outputs: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSecureStoreProvider.overrideWithValue(store)],
          child: _themed(
            const _TestSection(detail: detailNoKey, memo: 'visible memo'),
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('visible memo'), findsOneWidget);
      expect(find.text('Memo hidden'), findsNothing);
    },
  );
}
