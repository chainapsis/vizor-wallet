@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/activity/widgets/public_details_lookup_dialog.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_enhance_pir_notifier.dart';
import '../../fakes/fake_sync_notifier.dart';
import 'transparent_details_test_support.dart';

Future<List<String>> _pump(
  WidgetTester tester,
  ScriptedDetails details, {
  FakeSyncNotifier? sync,
  bool privacy = false,
  bool showPrivateLookupDiagnostics = false,
  Future<String> Function(rust_sync.TransactionInfo)? debugLookup,
  Future<void> Function(rust_sync.TransactionInfo)? publicLookup,
  Future<bool> Function(BuildContext)? confirmPublicLookup,
  rust_sync.TransactionInfo? transaction,
  bool privateQueries = true,
  Map<String, AccountInfo> ownAccounts = const {},
}) async {
  final tx = transaction ?? transparentSend();
  await tester.binding.setSurfaceSize(const Size(393, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prioritized = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        swapFeatureEnabledProvider.overrideWithValue(false),
        privacyModeProvider.overrideWith(() => PrivacySetting(privacy)),
        enhancePirProvider.overrideWith(
          () => FakeEnhancePirNotifier(privateQueries),
        ),
        appBootstrapProvider.overrideWithValue(transparentDetailsBootstrap()),
        syncProvider.overrideWith(
          () =>
              sync ??
              FakeSyncNotifier(
                SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
              ),
        ),
        addressBookRepositoryProvider.overrideWithValue(EmptyAddressBook()),
        ownAccountAddressesProvider.overrideWith((ref) async => ownAccounts),
        giftCardActivityIndexProvider.overrideWith(
          (ref, _) async => GiftCardActivityIndex.empty,
        ),
      ],
      child: MaterialApp(
        // Above the navigator, as in the app, so dialogs see the theme.
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: MobileTransactionStatusScreen(
          args: MobileTransactionStatusArgs(
            txidHex: transparentDetailsTxid,
            txKind: tx.txKind,
            initialTransaction: tx,
          ),
          historyLoader: (_) async => [tx],
          detailLoader: details.load,
          transparentDetailsPrioritizer: (txid) async => prioritized.add(txid),
          showPrivateLookupDiagnostics: showPrivateLookupDiagnostics,
          transparentDetailsDebugLookup: debugLookup,
          transparentDetailsPublicLookup: publicLookup,
          publicLookupConfirmation:
              confirmPublicLookup ?? confirmPublicDetailsLookup,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return prioritized;
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  transparentDetailsDebugTests(
    pump: (tester, details, sync, privacy, lookup) async {
      await _pump(
        tester,
        details,
        sync: sync,
        privacy: privacy,
        showPrivateLookupDiagnostics: true,
        debugLookup: lookup,
      );
    },
  );
  transparentDetailsPublicLookupTests(
    pump: (tester, details, {required lookup, confirm, sync}) async {
      await _pump(
        tester,
        details,
        sync: sync,
        publicLookup: lookup,
        confirmPublicLookup: confirm,
      );
    },
  );
  transparentDetailsCompletionTests(
    pump: (tester, details, {required lookup, confirm, sync}) async {
      await _pump(tester, details, sync: sync, publicLookup: lookup);
    },
  );
  transparentDetailsRefreshTests(
    pump: (tester, details, sync) async {
      await _pump(tester, details, sync: sync);
    },
  );
  transparentReceiptParityTests(
    pump:
        (
          tester,
          details, {
          required transaction,
          required privateQueries,
          ownAccounts = const {},
          privacy = false,
        }) => _pump(
          tester,
          details,
          transaction: transaction,
          privateQueries: privateQueries,
          ownAccounts: ownAccounts,
          privacy: privacy,
        ),
    titles: const ReceiptTitles(
      received: 'Received',
      receiving: 'Receiving...',
      receiveFailed: 'Receive failed',
      shielded: 'Shielded',
      sending: 'Sending...',
    ),
  );
  testWidgets('mobile receipt never names an output its recipient', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    final prioritized = await _pump(tester, details);
    expect(find.text('Sent successfully'), findsOneWidget);
    expect(find.text(kUnknownRecipientText), findsOneWidget);
    expect(find.text('Show full address'), findsNothing);
    // The other party's output is listed as the transaction's; the change is
    // never listed.
    expect(transactionOutputShown, findsOneWidget);
    expect(find.byKey(const ValueKey('transaction_output_1')), findsNothing);
    expect(find.text('Your address'), findsNothing);
    expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
    expect(
      prioritized,
      isEmpty,
      reason: 'available details are not prioritized',
    );
    await _close(tester);
  });

  testWidgets('mobile receipt shows the unavailable notice', (tester) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.unavailable),
    ]);
    final prioritized = await _pump(tester, details);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    expect(prioritized, [transparentDetailsTxid]);
    await _close(tester);
  });

  testWidgets('mobile receipt says not covered in private mode', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.notCovered),
    ]);
    await _pump(tester, details);
    expect(find.text(kTransparentDetailsNotCoveredText), findsOneWidget);
    await _close(tester);
  });

  testWidgets('mobile receipt polls while pending and stops once available', (
    tester,
  ) async {
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.pending),
      transparentDetail(
        rust_sync.TransparentDetailsState.available,
        recipients: transparentRecipients,
      ),
    ]);
    await _pump(tester, details);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval);
    await tester.pump();
    expect(details.calls, 2);
    expect(transactionOutputShown, findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval * 4);
    expect(details.calls, 2, reason: 'polling stopped');
    await _close(tester);
  });
}
