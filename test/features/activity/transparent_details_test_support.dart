import 'dart:async';

import 'package:flutter/material.dart'
    show ThemeMode, SizedBox, ValueKey, GestureDetector;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

/// Fixtures for the transparent details receipt tests, desktop and mobile.
const transparentDetailsTxid =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const transparentRecipientAddress = 't1Ku2KLyndDPsR32jwnrTMd3yvi9tfFP8ML';
const transparentOwnAddress = 't1PV7nyJ3J6pZBh6sCrd5dSDd6uhXGVSpEX';

rust_sync.TransactionInfo transparentSend() => rust_sync.TransactionInfo(
  txidHex: transparentDetailsTxid,
  minedHeight: BigInt.from(3460000),
  expiredUnmined: false,
  accountBalanceDelta: -228440040,
  fee: BigInt.from(20000),
  feeState: rust_sync.TransactionFeeState.known,
  detailsComplete: false,
  provisional: false,
  amountIncludesFee: false,
  blockTime: BigInt.from(1764150000),
  isTransparent: true,
  txKind: 'sent',
  displayAmount: BigInt.from(228420040),
  displayPool: 'transparent',
  createdTime: BigInt.from(1764150000),
);

rust_sync.TransactionDetail transparentDetail(
  rust_sync.TransparentDetailsState? state, {
  List<rust_sync.TransparentRecipient> recipients = const [],
}) => rust_sync.TransactionDetail(
  txidHex: transparentDetailsTxid,
  txKind: 'sent',
  outputs: const [],
  detailsComplete: false,
  provisional: false,
  transparentDetailsState: state,
  transparentRecipients: recipients,
);

final transparentRecipients = [
  rust_sync.TransparentRecipient(
    outputIndex: 0,
    address: transparentRecipientAddress,
    amountZatoshi: BigInt.from(228420040),
    isOwn: false,
  ),
  rust_sync.TransparentRecipient(
    outputIndex: 1,
    address: transparentOwnAddress,
    amountZatoshi: BigInt.from(1000000),
    isOwn: true,
  ),
];

/// A detail loader that answers from [states] in order, repeating the last,
/// and counts its calls.
class ScriptedDetails {
  ScriptedDetails(this.details);

  final List<rust_sync.TransactionDetail> details;
  int calls = 0;

  Future<rust_sync.TransactionDetail?> load(
    String _,
    rust_sync.TransactionInfo _,
  ) async {
    final detail = details[calls < details.length ? calls : details.length - 1];
    calls++;
    return detail;
  }
}

/// Resolves individual reads on demand to exercise overlapping refreshes.
class ControlledDetails extends ScriptedDetails {
  ControlledDetails(this.answers) : super(const []);

  final List<Future<rust_sync.TransactionDetail?>> answers;

  @override
  Future<rust_sync.TransactionDetail?> load(
    String account,
    rust_sync.TransactionInfo transaction,
  ) {
    final index = calls++;
    return answers[index < answers.length ? index : answers.length - 1];
  }
}

/// The desktop and mobile receipts must serialize polls and reject reads
/// superseded by a full receipt refresh, including a sync completion.
void transparentDetailsRefreshTests({
  required Future<void> Function(
    WidgetTester,
    ScriptedDetails,
    FakeSyncNotifier?,
  )
  pump,
}) {
  final pending = transparentDetail(rust_sync.TransparentDetailsState.pending);
  final available = transparentDetail(
    rust_sync.TransparentDetailsState.available,
    recipients: transparentRecipients,
  );
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('transparent detail polls do not overlap', (tester) async {
    final delayed = Completer<rust_sync.TransactionDetail?>();
    final details = ControlledDetails([
      Future.value(pending),
      delayed.future,
      Future.value(available),
    ]);
    await pump(tester, details, null);
    await tester.pump(kTransparentDetailsPollInterval);
    await flush(tester);
    expect(details.calls, 2);
    await tester.pump(kTransparentDetailsPollInterval * 3);
    expect(details.calls, 2, reason: 'one detail read may be in flight');
    delayed.complete(available);
    await flush(tester);
    expect(find.text('Recipient'), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval * 2);
    expect(details.calls, 2, reason: 'available details stop polling');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sync refresh supersedes an older pending poll', (tester) async {
    final delayedPoll = Completer<rust_sync.TransactionDetail?>();
    final refreshed = Completer<rust_sync.TransactionDetail?>();
    final details = ControlledDetails([
      Future.value(pending),
      delayedPoll.future,
      refreshed.future,
    ]);
    final sync = FakeSyncNotifier(
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
    );
    await pump(tester, details, sync);
    await tester.pump(kTransparentDetailsPollInterval);
    await flush(tester);
    expect(details.calls, 2);
    sync.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await flush(tester);
    expect(details.calls, 3);
    await tester.pump(kTransparentDetailsPollInterval * 2);
    expect(details.calls, 3, reason: 'the full refresh owns its detail read');
    refreshed.complete(available);
    await flush(tester);
    expect(find.text('Recipient'), findsOneWidget);
    delayedPoll.complete(pending);
    await flush(tester);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
    await tester.pump(kTransparentDetailsPollInterval * 2);
    expect(details.calls, 3, reason: 'stale results cannot restart polling');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed transparent poll permits the next attempt', (
    tester,
  ) async {
    final failed = Completer<rust_sync.TransactionDetail?>();
    final details = ControlledDetails([
      Future.value(pending),
      failed.future,
      Future.value(available),
    ]);
    await pump(tester, details, null);
    await tester.pump(kTransparentDetailsPollInterval);
    await flush(tester);
    failed.completeError(StateError('read failed'));
    await flush(tester);
    expect(find.text(kTransparentDetailsUnavailableText), findsOneWidget);
    await tester.pump(kTransparentDetailsPollInterval);
    await flush(tester);
    expect(details.calls, 3);
    expect(find.text('Recipient'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disposed receipt ignores an outstanding poll', (tester) async {
    final delayed = Completer<rust_sync.TransactionDetail?>();
    final details = ControlledDetails([Future.value(pending), delayed.future]);
    await pump(tester, details, null);
    await tester.pump(kTransparentDetailsPollInterval);
    await flush(tester);
    await tester.pumpWidget(const SizedBox());
    delayed.complete(available);
    await flush(tester);
    expect(tester.takeException(), isNull);
    await tester.pump(kTransparentDetailsPollInterval * 2);
    expect(details.calls, 2);
  });
}

AppBootstrapState transparentDetailsBootstrap() => AppBootstrapState(
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

class EmptyAddressBook implements AddressBookRepository {
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class PrivacyOff extends PrivacyModeNotifier {
  @override
  bool build() => false;
}

class PrivacySetting extends PrivacyModeNotifier {
  PrivacySetting(this.enabled);
  final bool enabled;
  @override
  bool build() => enabled;
}

void transparentDetailsDebugTests({
  required Future<void> Function(
    WidgetTester,
    ScriptedDetails,
    FakeSyncNotifier?,
    bool,
    Future<String> Function(rust_sync.TransactionInfo),
  )
  pump,
}) {
  const summary = '1 outputs · fee 0.0002 ZEC · 1 inputs';
  final button = find.byKey(const ValueKey('transparent_details_debug_lookup'));
  ScriptedDetails pendingDetails() => ScriptedDetails([
    transparentDetail(rust_sync.TransparentDetailsState.notCovered),
  ]);
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('private lookup summary respects hidden amounts', (tester) async {
    await pump(tester, pendingDetails(), null, true, (_) async => summary);
    await tester.tap(
      find.descendant(of: button, matching: find.byType(GestureDetector)),
    );
    await flush(tester);
    expect(find.text(summary), findsNothing);
    expect(
      find.descendant(of: button, matching: find.text('******')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final fails in [false, true]) {
    testWidgets(
      'receipt refresh supersedes private lookup ${fails ? 'failure' : 'success'}',
      (tester) async {
        final delayed = Completer<String>();
        final sync = FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        );
        await pump(
          tester,
          pendingDetails(),
          sync,
          false,
          (_) => delayed.future,
        );
        await tester.tap(
          find.descendant(of: button, matching: find.byType(GestureDetector)),
        );
        await flush(tester);
        expect(find.text('Looking up…'), findsOneWidget);
        sync.emit(
          SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            isSyncComplete: true,
          ),
        );
        await flush(tester);
        if (fails) {
          delayed.completeError(StateError('old lookup'));
        } else {
          delayed.complete(summary);
        }
        await flush(tester);
        expect(find.text(summary), findsNothing);
        expect(find.text('Failed: Bad state: old lookup'), findsNothing);
        expect(find.text('Looking up…'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('latest private lookup supersedes an older lookup', (
    tester,
  ) async {
    final first = Completer<String>();
    final second = Completer<String>();
    var calls = 0;
    await pump(
      tester,
      pendingDetails(),
      null,
      false,
      (_) => ++calls == 1 ? first.future : second.future,
    );
    await tester.tap(
      find.descendant(of: button, matching: find.byType(GestureDetector)),
    );
    await flush(tester);
    expect(find.text('Looking up…'), findsOneWidget);
    await tester.tap(
      find.descendant(of: button, matching: find.byType(GestureDetector)),
    );
    await flush(tester);
    second.complete('latest result');
    await flush(tester);
    first.complete(summary);
    await flush(tester);
    expect(find.text('latest result'), findsOneWidget);
    expect(find.text(summary), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
