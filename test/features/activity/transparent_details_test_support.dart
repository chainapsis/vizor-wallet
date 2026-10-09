import 'dart:async';

import 'package:flutter/material.dart'
    show BuildContext, ThemeMode, SizedBox, ValueKey, GestureDetector;
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
  String txKind = 'sent',
  String? primaryAddress,
  String? sourceAddress,
  String? sourcePool,
  String? sourceAccountUuid,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
  bool provisional = false,
  List<String> omissions = const [],
  int? outputCount,
  bool detailsComplete = false,
}) => rust_sync.TransactionDetail(
  txidHex: transparentDetailsTxid,
  txKind: txKind,
  primaryAddress: primaryAddress,
  sourceAddress: sourceAddress,
  sourcePool: sourcePool,
  sourceAccountUuid: sourceAccountUuid,
  outputs: outputs,
  detailsComplete: detailsComplete,
  provisional: provisional,
  transparentDetailsState: state,
  transparentRecipients: recipients,
  transparentOutputCount: outputCount,
  transparentOmissions: omissions,
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

/// The first transparent output listed as the transaction's, attributed to no
/// one.
final transactionOutputShown = find.byKey(
  const ValueKey('transaction_output_0'),
);

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

  testWidgets('a follow-up completion refreshes an older receipt', (
    tester,
  ) async {
    final completedAt = DateTime.utc(2026, 10, 9);
    final sync = FakeSyncNotifier(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
        lastSyncCompletedAt: completedAt,
      ),
    );
    // Not-covered details do not poll. The transaction is also absent from
    // recentTransactions, so only a new completion can refresh this receipt.
    final details = ScriptedDetails([
      transparentDetail(rust_sync.TransparentDetailsState.notCovered),
      available,
    ]);
    await pump(tester, details, sync);
    expect(find.text(kTransparentDetailsNotCoveredText), findsOneWidget);
    final initialReads = details.calls;
    final followup = SyncState(
      accountUuid: 'account-1',
      hasAccountScopedData: true,
      isSyncComplete: true,
      lastSyncCompletedAt: completedAt.add(const Duration(seconds: 1)),
    );
    sync.emit(followup);
    await flush(tester);
    expect(details.calls, initialReads + 1);
    expect(transactionOutputShown, findsOneWidget);
    expect(find.text(kTransparentDetailsNotCoveredText), findsNothing);
    // An unrelated balance update retaining that completion is not a new run.
    sync.emit(followup.copyWith(transparentBalance: BigInt.one));
    await flush(tester);
    expect(details.calls, initialReads + 1);
    await tester.pumpWidget(const SizedBox());
  });

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
    expect(transactionOutputShown, findsOneWidget);
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
    expect(transactionOutputShown, findsOneWidget);
    delayedPoll.complete(pending);
    await flush(tester);
    expect(transactionOutputShown, findsOneWidget);
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
    expect(transactionOutputShown, findsOneWidget);
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
    accounts: [
      AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
      AccountInfo(uuid: 'account-2', name: 'Savings', order: 1),
    ],
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

/// A receipt hook for the public load: [confirm] answers the confirmation
/// (null shows the real dialog), and [lookup] stands in for the request.
typedef PublicLookupPump =
    Future<void> Function(
      WidgetTester tester,
      ScriptedDetails details, {
      required Future<void> Function(rust_sync.TransactionInfo) lookup,
      Future<bool> Function(BuildContext)? confirm,
      FakeSyncNotifier? sync,
    });

/// The desktop and mobile receipts name what private details leave out and
/// load the full details publicly only after the user confirms.
void transparentDetailsPublicLookupTests({required PublicLookupPump pump}) {
  final load = find.byKey(const ValueKey('transparent_details_load_publicly'));
  final omitted = find.byKey(const ValueKey('transparent_details_omissions'));
  final partial = transparentDetail(
    rust_sync.TransparentDetailsState.available,
    recipients: transparentRecipients,
    outputCount: 3,
    omissions: const ['more_than_two_outputs', 'multiple_source_scripts'],
  );
  final complete = transparentDetail(
    rust_sync.TransparentDetailsState.available,
    recipients: transparentRecipients,
  );
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapLoad(WidgetTester tester) async {
    await tester.ensureVisible(load);
    await tester.tap(
      find.descendant(of: load, matching: find.byType(GestureDetector)).first,
    );
    await flush(tester);
  }

  testWidgets('omissions are named and a public load is offered', (
    tester,
  ) async {
    var lookups = 0;
    await pump(
      tester,
      ScriptedDetails([partial]),
      lookup: (_) async => lookups++,
      confirm: (_) async => false,
    );
    expect(omitted, findsOneWidget);
    expect(find.text('1 more output, other sending addresses'), findsOneWidget);
    expect(load, findsOneWidget);
    expect(find.text(kLoadDetailsPubliclyText), findsOneWidget);
    expect(lookups, 0, reason: 'nothing is loaded without a tap');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('omissions a public load cannot show offer no load', (
    tester,
  ) async {
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(
          rust_sync.TransparentDetailsState.available,
          recipients: transparentRecipients,
          omissions: const ['multiple_source_scripts'],
        ),
      ]),
      lookup: (_) async => fail('no public load'),
    );
    expect(find.text('other sending addresses'), findsOneWidget);
    expect(load, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('complete private details offer no public load', (tester) async {
    await pump(
      tester,
      ScriptedDetails([complete]),
      lookup: (_) async => fail('no public load'),
    );
    expect(transactionOutputShown, findsOneWidget);
    expect(omitted, findsNothing);
    expect(load, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a transaction private mode cannot cover offers a public load', (
    tester,
  ) async {
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(rust_sync.TransparentDetailsState.notCovered),
      ]),
      lookup: (_) async {},
    );
    expect(find.text(kTransparentDetailsNotCoveredText), findsOneWidget);
    expect(load, findsOneWidget);
    expect(omitted, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dialog must be confirmed; cancel sends nothing', (
    tester,
  ) async {
    final looked = <String>[];
    final details = ScriptedDetails([partial, complete]);
    await pump(tester, details, lookup: (tx) async => looked.add(tx.txidHex));
    final reads = details.calls;
    await tapLoad(tester);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('public_details_lookup_dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('public_details_lookup_cancel')),
    );
    await tester.pumpAndSettle();
    expect(looked, isEmpty, reason: 'cancel sends no request');
    expect(details.calls, reads);
    expect(load, findsOneWidget);

    await tapLoad(tester);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('public_details_lookup_confirm')),
    );
    await tester.pumpAndSettle();
    expect(looked, [transparentDetailsTxid]);
    expect(details.calls, reads + 1, reason: 'the receipt is read again');
    expect(omitted, findsNothing);
    expect(load, findsNothing);
    expect(transactionOutputShown, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a running public load ignores further taps', (tester) async {
    final pending = Completer<void>();
    var lookups = 0;
    var asked = 0;
    await pump(
      tester,
      ScriptedDetails([partial, complete]),
      lookup: (_) {
        lookups++;
        return pending.future;
      },
      confirm: (_) async {
        asked++;
        return true;
      },
    );
    await tapLoad(tester);
    expect(find.text(kLoadDetailsPubliclyLoadingText), findsOneWidget);
    await tapLoad(tester);
    expect((asked, lookups), (1, 1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(load, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed public load says so and can be retried', (
    tester,
  ) async {
    var lookups = 0;
    await pump(
      tester,
      ScriptedDetails([partial, complete]),
      lookup: (_) async {
        if (lookups++ == 0) throw StateError('route failed');
      },
      confirm: (_) async => true,
    );
    await tapLoad(tester);
    expect(find.text(kLoadDetailsPubliclyFailedText), findsOneWidget);
    expect(omitted, findsOneWidget);
    await tapLoad(tester);
    await tester.pumpAndSettle();
    expect(lookups, 2);
    expect(load, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a refresh while a public load runs keeps it and its result', (
    tester,
  ) async {
    final pending = Completer<void>();
    var asked = 0;
    final sync = FakeSyncNotifier(
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
    );
    final details = ScriptedDetails([partial, partial, complete]);
    await pump(
      tester,
      details,
      lookup: (_) => pending.future,
      confirm: (_) async {
        asked++;
        return true;
      },
      sync: sync,
    );
    await tapLoad(tester);
    sync.emit(
      SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    await flush(tester);
    expect(details.calls, 2, reason: 'the sync refreshed the receipt');
    expect(find.text(kLoadDetailsPubliclyLoadingText), findsOneWidget);
    await tapLoad(tester);
    expect(asked, 1, reason: 'the running load is not offered again');
    pending.complete();
    await tester.pumpAndSettle();
    expect(details.calls, 3);
    expect(omitted, findsNothing);
    expect(load, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

/// A receipt whose detail establishes every payee drops the incomplete
/// notice its activity entry would show.
void transparentDetailsCompletionTests({required PublicLookupPump pump}) {
  for (final complete in [false, true]) {
    testWidgets('a ${complete ? 'complete' : 'partial'} receipt detail '
        '${complete ? 'hides' : 'keeps'} the incomplete notice', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([
          transparentDetail(
            rust_sync.TransparentDetailsState.available,
            recipients: transparentRecipients,
            primaryAddress: complete ? transparentRecipientAddress : null,
            detailsComplete: complete,
          ),
        ]),
        lookup: (_) async {},
      );
      expect(find.text('Incomplete'), complete ? findsNothing : findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

// One transparent transaction as public and private queries record it, after
// the private-mode receipt that showed every output in a separate card. A
// public wallet stores the raw transaction, so it knows the sender and the
// recipient it paid; private queries know only the ordered outputs.
const transparentSenderAddress = 't1Z9N3oVYrYDpnbqDcXJpuLrGpcSLDgHXyo';
const transparentSecondRecipientAddress = 't1MXdTk5rHyN9FfVc1mTt8YKbnDp7Jq9hJx';
final _received = BigInt.from(901410);
final _senderChange = BigInt.from(5480831);

rust_sync.TransactionInfo transparentReceive({
  bool pending = false,
  bool expired = false,
}) => rust_sync.TransactionInfo(
  txidHex: transparentDetailsTxid,
  minedHeight: pending || expired ? BigInt.zero : BigInt.from(3460000),
  expiredUnmined: expired,
  accountBalanceDelta: _received.toInt(),
  fee: BigInt.zero,
  feeState: rust_sync.TransactionFeeState.notApplicable,
  detailsComplete: true,
  provisional: false,
  amountIncludesFee: false,
  blockTime: BigInt.from(1764150000),
  isTransparent: true,
  txKind: 'received',
  displayAmount: _received,
  displayPool: 'transparent',
  createdTime: BigInt.from(1764150000),
);

/// The receive: output 0 pays the account, output 1 returns the sender's
/// change. Only a stored transaction names the sender.
rust_sync.TransactionDetail transparentReceiveDetail({
  required bool private,
  rust_sync.TransparentDetailsState state =
      rust_sync.TransparentDetailsState.available,
}) => transparentDetail(
  state,
  txKind: 'received',
  sourceAddress: private ? null : transparentSenderAddress,
  sourcePool: private ? 'unknown' : 'transparent',
  outputs: [
    rust_sync.TransactionDetailOutput(
      address: transparentOwnAddress,
      amountZatoshi: _received,
      pool: 'transparent',
      activityPool: 'transparent',
      usesOrchardReceiver: false,
    ),
  ],
  recipients: state == rust_sync.TransparentDetailsState.available
      ? [
          rust_sync.TransparentRecipient(
            outputIndex: 0,
            address: transparentOwnAddress,
            amountZatoshi: _received,
            isOwn: true,
          ),
          rust_sync.TransparentRecipient(
            outputIndex: 1,
            address: transparentSenderAddress,
            amountZatoshi: _senderChange,
            isOwn: false,
          ),
        ]
      : const [],
);

/// The send of [transparentSend]. Output 0 pays another party and output 1
/// returns the account's change. Only a recorded send (a public wallet's, or
/// one this wallet built) names its recipient; private queries recover the
/// outputs, which say nothing about which of them the account paid.
rust_sync.TransactionDetail transparentSendDetail({
  required bool recorded,
  String recipient = transparentRecipientAddress,
  List<rust_sync.TransparentRecipient>? recipients,
}) => transparentDetail(
  rust_sync.TransparentDetailsState.available,
  primaryAddress: recorded ? recipient : null,
  outputs: recorded
      ? [
          rust_sync.TransactionDetailOutput(
            address: recipient,
            amountZatoshi: BigInt.from(228420040),
            pool: 'transparent',
            activityPool: 'transparent',
            usesOrchardReceiver: false,
          ),
        ]
      : const [],
  recipients: recipients ?? transparentRecipients,
);

typedef TransparentReceiptPump =
    Future<List<String>> Function(
      WidgetTester tester,
      ScriptedDetails details, {
      required rust_sync.TransactionInfo transaction,
      required bool privateQueries,
      Map<String, AccountInfo> ownAccounts,
      bool privacy,
    });

/// The form factor's receipt titles.
class ReceiptTitles {
  const ReceiptTitles({
    required this.received,
    required this.receiving,
    required this.receiveFailed,
    required this.shielded,
    required this.sending,
  });

  final String received;
  final String receiving;
  final String receiveFailed;
  final String shielded;
  final String sending;
}

const _shieldedRecipientAddress =
    'u1qx6w4zr2vn8gk3dfa9yhc5tlm0ps7ej2ruw8kz4qn5d6vf3hg9al2cxs8ty7mwe0pjr';

final _threeOutputs = [
  ...transparentRecipients,
  rust_sync.TransparentRecipient(
    outputIndex: 2,
    address: transparentSecondRecipientAddress,
    amountZatoshi: BigInt.from(3000000),
    isOwn: false,
  ),
];

/// Another party's transparent output and the account's change.
final _unrelatedTransparentOutput = transparentRecipients;

/// A send from the account's shielded funds whose transaction also carries
/// transparent outputs.
rust_sync.TransactionInfo mixedSend() {
  final sent = transparentSend();
  return rust_sync.TransactionInfo(
    txidHex: sent.txidHex,
    minedHeight: sent.minedHeight,
    expiredUnmined: false,
    accountBalanceDelta: sent.accountBalanceDelta,
    fee: sent.fee,
    feeState: sent.feeState,
    detailsComplete: false,
    provisional: false,
    amountIncludesFee: false,
    blockTime: sent.blockTime,
    isTransparent: true,
    txKind: 'sent',
    displayAmount: sent.displayAmount,
    displayPool: 'shielded',
    createdTime: sent.createdTime,
  );
}

/// The send shell with a To row naming no one and nothing to verify.
void _expectUnknownRecipientShell({required String title}) {
  expect(find.text(title), findsOneWidget);
  expect(find.text('To'), findsOneWidget);
  expect(find.text(kUnknownRecipientText), findsOneWidget);
  expect(find.text('Show full address'), findsNothing);
  expect(find.text('Recipient'), findsNothing);
}

/// The transaction's outputs [listed] as such, never as recipients; the
/// account's own outputs [hidden].
void _expectNeutralOutputs({
  required List<int> listed,
  required List<int> hidden,
}) {
  expect(_supplementalCard, findsOneWidget);
  expect(find.text(kTransactionOutputsText), findsOneWidget);
  expect(find.text(kTransactionOutputsUnattributedText), findsOneWidget);
  expect(find.text('Output'), findsNWidgets(listed.length));
  for (final index in listed) {
    expect(find.byKey(ValueKey('transaction_output_$index')), findsOneWidget);
  }
  for (final index in hidden) {
    expect(find.byKey(ValueKey('transaction_output_$index')), findsNothing);
  }
}

Finder _showsAddress(String address) =>
    find.textContaining(address.substring(0, 6), findRichText: true);

final _supplementalCard = find.byKey(
  const ValueKey('transparent_details_section'),
);

/// Public and private receipts of the same transaction share one shell; only
/// what private queries cannot know (the sender) differs.
void transparentReceiptParityTests({
  required TransparentReceiptPump pump,
  required ReceiptTitles titles,
}) {
  for (final private in [false, true]) {
    final mode = private ? 'private' : 'public';
    testWidgets('$mode transparent receive uses the shared receipt', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([transparentReceiveDetail(private: private)]),
        transaction: transparentReceive(),
        privateQueries: private,
      );
      expect(find.text(titles.received), findsOneWidget);
      expect(find.text('From'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(_showsAddress(transparentOwnAddress), findsWidgets);
      // The sender's change is not the account's and is never listed.
      expect(_supplementalCard, findsNothing);
      expect(find.textContaining('0.0548', findRichText: true), findsNothing);
      expect(find.text('Your address'), findsNothing);
      expect(find.text('Recipient'), findsNothing);
      if (private) {
        expect(find.text('Unknown sender'), findsOneWidget);
        expect(find.text('Show full address'), findsNothing);
        // A transparent receiving output says nothing about the sender's
        // pool, and neither output is the sender.
        expect(find.text('Transparent'), findsNothing);
        expect(_showsAddress(transparentSenderAddress), findsNothing);
      } else {
        expect(_showsAddress(transparentSenderAddress), findsOneWidget);
        expect(find.text('Transparent'), findsOneWidget);
        expect(find.text('Show full address'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    // Recorded recipient data is the same in both modes, and so is the
    // receipt: private mode still records the sends this wallet built.
    testWidgets('$mode send names its recorded recipient', (tester) async {
      await pump(
        tester,
        ScriptedDetails([transparentSendDetail(recorded: true)]),
        transaction: transparentSend(),
        privateQueries: private,
      );
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(_showsAddress(transparentRecipientAddress), findsWidgets);
      expect(find.text('Show full address'), findsOneWidget);
      expect(find.text(kUnknownRecipientText), findsNothing);
      // The account's change is not a payment.
      expect(_showsAddress(transparentOwnAddress), findsNothing);
      expect(_supplementalCard, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode recorded recipient wins over the first output', (
      tester,
    ) async {
      // The account recorded its payment to output 2; output 0 belongs to
      // another party funding the same transaction.
      await pump(
        tester,
        ScriptedDetails([
          transparentSendDetail(
            recorded: true,
            recipient: transparentSecondRecipientAddress,
            recipients: _threeOutputs,
          ),
        ]),
        transaction: transparentSend(),
        privateQueries: private,
      );
      expect(find.text('To'), findsOneWidget);
      expect(_showsAddress(transparentSecondRecipientAddress), findsWidgets);
      expect(_showsAddress(transparentRecipientAddress), findsNothing);
      expect(find.text('Show full address'), findsOneWidget);
      // A recorded recipient needs no list of the transaction's outputs.
      expect(_supplementalCard, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode mixed send keeps its recorded shielded recipient', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([
          transparentDetail(
            rust_sync.TransparentDetailsState.available,
            primaryAddress: _shieldedRecipientAddress,
            recipients: _unrelatedTransparentOutput,
          ),
        ]),
        transaction: mixedSend(),
        privateQueries: private,
      );
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(_showsAddress(_shieldedRecipientAddress), findsWidgets);
      expect(_showsAddress(transparentRecipientAddress), findsNothing);
      expect(find.text('Show full address'), findsOneWidget);
      expect(_supplementalCard, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('private send with only outputs names no recipient', (
    tester,
  ) async {
    await pump(
      tester,
      ScriptedDetails([transparentSendDetail(recorded: false)]),
      transaction: transparentSend(),
      privateQueries: true,
    );
    _expectUnknownRecipientShell(title: 'Sent successfully');
    // The other party's output stays listed, attributed to no one, and the
    // receipt says its details are incomplete.
    _expectNeutralOutputs(listed: [0], hidden: [1]);
    expect(find.text('Incomplete'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('private mixed send never names its transparent output', (
    tester,
  ) async {
    // A shielded payee private queries cannot see, next to another party's
    // transparent output.
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(
          rust_sync.TransparentDetailsState.available,
          recipients: _unrelatedTransparentOutput,
        ),
      ]),
      transaction: mixedSend(),
      privateQueries: true,
    );
    _expectUnknownRecipientShell(title: 'Sent successfully');
    _expectNeutralOutputs(listed: [0], hidden: [1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('private shared funding lists counterparty change neutrally', (
    tester,
  ) async {
    // Output 0 is the account's change, output 1 the other funder's change,
    // output 2 the payment; nothing says which one the account paid.
    final recipients = [
      rust_sync.TransparentRecipient(
        outputIndex: 0,
        address: transparentOwnAddress,
        amountZatoshi: BigInt.from(1000000),
        isOwn: true,
      ),
      rust_sync.TransparentRecipient(
        outputIndex: 1,
        address: transparentSenderAddress,
        amountZatoshi: _senderChange,
        isOwn: false,
      ),
      rust_sync.TransparentRecipient(
        outputIndex: 2,
        address: transparentRecipientAddress,
        amountZatoshi: BigInt.from(228420040),
        isOwn: false,
      ),
    ];
    await pump(
      tester,
      ScriptedDetails([
        transparentSendDetail(recorded: false, recipients: recipients),
      ]),
      transaction: transparentSend(),
      privateQueries: true,
    );
    _expectUnknownRecipientShell(title: 'Sent successfully');
    _expectNeutralOutputs(listed: [1, 2], hidden: [0]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('private send lists several outputs in order, amounts hidden', (
    tester,
  ) async {
    await pump(
      tester,
      ScriptedDetails([
        transparentSendDetail(
          recorded: false,
          // Out of order on purpose: the list follows the transaction.
          recipients: _threeOutputs.reversed.toList(),
        ),
      ]),
      transaction: transparentSend(),
      privateQueries: true,
      privacy: true,
    );
    _expectUnknownRecipientShell(title: 'Sent successfully');
    _expectNeutralOutputs(listed: [0, 2], hidden: [1]);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('transaction_output_0'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('transaction_output_2')))
            .dy,
      ),
    );
    // Hidden amounts stay hidden in the list.
    expect(find.textContaining('0.03', findRichText: true), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (label, expired) in [('pending', false), ('failed', true)]) {
    testWidgets('private $label send keeps its status without a recipient', (
      tester,
    ) async {
      final sent = transparentSend();
      final tx = rust_sync.TransactionInfo(
        txidHex: sent.txidHex,
        minedHeight: BigInt.zero,
        expiredUnmined: expired,
        accountBalanceDelta: sent.accountBalanceDelta,
        fee: sent.fee,
        feeState: sent.feeState,
        detailsComplete: sent.detailsComplete,
        provisional: false,
        amountIncludesFee: false,
        blockTime: sent.blockTime,
        isTransparent: true,
        txKind: 'sent',
        displayAmount: sent.displayAmount,
        displayPool: 'transparent',
        createdTime: sent.createdTime,
      );
      await pump(
        tester,
        ScriptedDetails([transparentSendDetail(recorded: false)]),
        transaction: tx,
        privateQueries: true,
      );
      _expectUnknownRecipientShell(
        title: expired ? 'Send failed' : titles.sending,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a provisional entry names no recipient', (tester) async {
    final sent = transparentSend();
    final tx = rust_sync.TransactionInfo(
      txidHex: sent.txidHex,
      minedHeight: sent.minedHeight,
      expiredUnmined: false,
      accountBalanceDelta: sent.accountBalanceDelta,
      fee: sent.fee,
      feeState: sent.feeState,
      detailsComplete: false,
      provisional: true,
      amountIncludesFee: true,
      blockTime: sent.blockTime,
      isTransparent: true,
      txKind: 'sent',
      displayAmount: sent.displayAmount,
      displayPool: 'transparent',
      createdTime: sent.createdTime,
    );
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(
          rust_sync.TransparentDetailsState.available,
          provisional: true,
          recipients: transparentRecipients,
        ),
      ]),
      transaction: tx,
      privateQueries: true,
    );
    // Its role may still change, so it has no To row at all.
    expect(find.text('To'), findsNothing);
    expect(find.text(kUnknownRecipientText), findsNothing);
    expect(find.text('Show full address'), findsNothing);
    _expectNeutralOutputs(listed: [0], hidden: [1]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a net change that includes its fee keeps the neutral receipt', (
    tester,
  ) async {
    // The amount is the account's balance change with the fee in it, and its
    // payment role is not established: it is neither a payment to an
    // unknown recipient nor a second fee line.
    final sent = transparentSend();
    final tx = rust_sync.TransactionInfo(
      txidHex: sent.txidHex,
      minedHeight: sent.minedHeight,
      expiredUnmined: false,
      accountBalanceDelta: -228440040,
      fee: BigInt.from(20000),
      feeState: rust_sync.TransactionFeeState.known,
      detailsComplete: false,
      provisional: false,
      amountIncludesFee: true,
      blockTime: sent.blockTime,
      isTransparent: true,
      txKind: 'sent',
      displayAmount: BigInt.from(228440040),
      displayPool: 'transparent',
      createdTime: sent.createdTime,
    );
    expect(
      transactionFeePresentation(tx),
      TransactionFeePresentation.includedInAmount,
    );
    await pump(
      tester,
      ScriptedDetails([transparentSendDetail(recorded: false)]),
      transaction: tx,
      privateQueries: true,
    );
    expect(find.text(kNetChangeText), findsOneWidget);
    expect(find.text('Amount'), findsNothing);
    expect(find.text(kUnknownRecipientText), findsNothing);
    expect(find.text('To'), findsNothing);
    expect(find.text('Show full address'), findsNothing);
    expect(find.text('0.0002 ZEC'), findsOneWidget, reason: 'one fee line');
    await tester.pumpWidget(const SizedBox());
  });

  for (final private in [false, true]) {
    final mode = private ? 'private' : 'public';
    testWidgets('$mode transfer from an own transparent address names it', (
      tester,
    ) async {
      // The stored transaction's input pays from an address of another
      // account in this wallet.
      await pump(
        tester,
        ScriptedDetails([transparentReceiveDetail(private: false)]),
        transaction: transparentReceive(),
        privateQueries: private,
        ownAccounts: const {
          transparentSenderAddress: AccountInfo(
            uuid: 'account-2',
            name: 'Savings',
            order: 1,
          ),
        },
      );
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Unknown sender'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode own unshielding names its pool, not an address', (
      tester,
    ) async {
      // The stored transaction has no transparent input: the funds came from
      // the shielded pool. Which shielded address paid is never known.
      await pump(
        tester,
        ScriptedDetails([
          transparentDetail(
            rust_sync.TransparentDetailsState.available,
            txKind: 'received',
            sourcePool: 'shielded',
            outputs: [
              rust_sync.TransactionDetailOutput(
                address: transparentOwnAddress,
                amountZatoshi: _received,
                pool: 'transparent',
                activityPool: 'transparent',
                usesOrchardReceiver: false,
              ),
            ],
            recipients: [
              rust_sync.TransparentRecipient(
                outputIndex: 0,
                address: transparentOwnAddress,
                amountZatoshi: _received,
                isOwn: true,
              ),
            ],
          ),
        ]),
        transaction: transparentReceive(),
        privateQueries: private,
      );
      expect(find.text('Shielded sender'), findsOneWidget);
      expect(find.text('Unknown sender'), findsNothing);
      expect(find.text('Show full address'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final private in [false, true]) {
    final mode = private ? 'private' : 'public';
    // The wallet recorded another of its accounts as sending the received
    // output; a public wallet also knows the shielded source pool.
    rust_sync.TransactionDetail fromAccount({
      String? sourceAddress,
      String accountUuid = 'account-2',
    }) => transparentDetail(
      rust_sync.TransparentDetailsState.available,
      txKind: 'received',
      sourceAddress: sourceAddress,
      sourcePool: private ? 'unknown' : 'shielded',
      sourceAccountUuid: accountUuid,
      outputs: transparentReceiveDetail(private: true).outputs,
    );

    testWidgets('$mode receive names the recorded sending account', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([fromAccount()]),
        transaction: transparentReceive(),
        privateQueries: private,
      );
      expect(find.byKey(const ValueKey('received_from_account')), findsOne);
      expect(find.text('Savings'), findsOneWidget);
      expect(find.text('Unknown sender'), findsNothing);
      expect(find.text('Shielded sender'), findsNothing);
      // An account is not an address: nothing to show or verify.
      expect(find.text('Show full address'), findsNothing);
      // The pool appears only when the stored transaction established it.
      expect(find.text('Shielded'), private ? findsNothing : findsOneWidget);
      expect(find.text('Transparent'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode exact source address wins over the account', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([fromAccount(sourceAddress: transparentSenderAddress)]),
        transaction: transparentReceive(),
        privateQueries: private,
      );
      expect(find.byKey(const ValueKey('received_from_account')), findsNothing);
      expect(_showsAddress(transparentSenderAddress), findsOneWidget);
      expect(find.text('Show full address'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode receive from an unlisted account stays unknown', (
      tester,
    ) async {
      await pump(
        tester,
        ScriptedDetails([fromAccount(accountUuid: 'removed-account')]),
        transaction: transparentReceive(),
        privateQueries: private,
      );
      expect(find.byKey(const ValueKey('received_from_account')), findsNothing);
      expect(
        find.text(private ? 'Unknown sender' : 'Shielded sender'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('private receive keeps a known sender and its account name', (
    tester,
  ) async {
    // Private mode still has the raw transaction of one the wallet built.
    await pump(
      tester,
      ScriptedDetails([transparentReceiveDetail(private: false)]),
      transaction: transparentReceive(),
      privateQueries: true,
      ownAccounts: const {
        transparentSenderAddress: AccountInfo(
          uuid: 'account-2',
          name: 'Savings',
          order: 1,
        ),
      },
    );
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Unknown sender'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('private receive never infers a sender from its outputs', (
    tester,
  ) async {
    // The other output pays an address the wallet knows; that still says
    // nothing about who funded the transaction.
    await pump(
      tester,
      ScriptedDetails([transparentReceiveDetail(private: true)]),
      transaction: transparentReceive(),
      privateQueries: true,
      ownAccounts: const {
        transparentSenderAddress: AccountInfo(
          uuid: 'account-2',
          name: 'Savings',
          order: 1,
        ),
      },
    );
    expect(find.text('Unknown sender'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (label, tx, title) in [
    ('pending', transparentReceive(pending: true), titles.receiving),
    ('failed', transparentReceive(expired: true), titles.receiveFailed),
  ]) {
    testWidgets('private $label receive titles its status', (tester) async {
      await pump(
        tester,
        ScriptedDetails([transparentReceiveDetail(private: true)]),
        transaction: tx,
        privateQueries: true,
      );
      expect(find.text(title), findsOneWidget);
      expect(_supplementalCard, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final state in [
    rust_sync.TransparentDetailsState.pending,
    rust_sync.TransparentDetailsState.unavailable,
    rust_sync.TransparentDetailsState.notCovered,
  ]) {
    testWidgets('private receive is whole while outputs are $state', (
      tester,
    ) async {
      final details = ScriptedDetails([
        transparentReceiveDetail(private: true, state: state),
      ]);
      final prioritized = await pump(
        tester,
        details,
        transaction: transparentReceive(),
        privateQueries: true,
      );
      expect(find.text(titles.received), findsOneWidget);
      expect(find.text('Unknown sender'), findsOneWidget);
      expect(_showsAddress(transparentOwnAddress), findsWidgets);
      expect(_supplementalCard, findsNothing);
      expect(find.text(kTransparentDetailsUnavailableText), findsNothing);
      expect(find.text(kTransparentDetailsNotCoveredText), findsNothing);
      // Awaited details are still asked for first and polled.
      final awaited = state != rust_sync.TransparentDetailsState.notCovered;
      expect(prioritized, awaited ? [transparentDetailsTxid] : isEmpty);
      final before = details.calls;
      await tester.pump(kTransparentDetailsPollInterval);
      await tester.pump();
      expect(details.calls, awaited ? before + 1 : before);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a fee-only self-transfer lists no payees', (tester) async {
    final fee = BigInt.from(20000);
    final tx = rust_sync.TransactionInfo(
      txidHex: transparentDetailsTxid,
      minedHeight: BigInt.from(3460000),
      expiredUnmined: false,
      accountBalanceDelta: -fee.toInt(),
      fee: fee,
      feeState: rust_sync.TransactionFeeState.known,
      detailsComplete: true,
      provisional: false,
      amountIncludesFee: true,
      blockTime: BigInt.from(1764150000),
      isTransparent: true,
      txKind: 'sent',
      displayAmount: fee,
      displayPool: 'transparent',
      createdTime: BigInt.from(1764150000),
    );
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(
          rust_sync.TransparentDetailsState.available,
          recipients: [
            rust_sync.TransparentRecipient(
              outputIndex: 0,
              address: transparentOwnAddress,
              amountZatoshi: BigInt.from(1000000),
              isOwn: true,
            ),
          ],
        ),
      ]),
      transaction: tx,
      privateQueries: true,
    );
    expect(find.text('Transaction'), findsOneWidget);
    expect(find.text('To'), findsNothing);
    expect(find.text(kUnknownRecipientText), findsNothing);
    // The fee is the entry's one line.
    expect(find.text(kNetChangeText), findsOneWidget);
    expect(_supplementalCard, findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a shielding lists no transparent outputs', (tester) async {
    final tx = rust_sync.TransactionInfo(
      txidHex: transparentDetailsTxid,
      minedHeight: BigInt.from(3460000),
      expiredUnmined: false,
      accountBalanceDelta: -20000,
      fee: BigInt.from(20000),
      feeState: rust_sync.TransactionFeeState.known,
      detailsComplete: true,
      provisional: false,
      amountIncludesFee: false,
      blockTime: BigInt.from(1764150000),
      isTransparent: true,
      txKind: 'shielded',
      displayAmount: BigInt.from(1000000),
      displayPool: 'shielded',
      createdTime: BigInt.from(1764150000),
    );
    await pump(
      tester,
      ScriptedDetails([
        transparentDetail(
          rust_sync.TransparentDetailsState.available,
          txKind: 'shielded',
          recipients: [
            rust_sync.TransparentRecipient(
              outputIndex: 0,
              address: transparentRecipientAddress,
              amountZatoshi: BigInt.from(3000000),
              isOwn: false,
            ),
          ],
        ),
      ]),
      transaction: tx,
      privateQueries: true,
    );
    // Mobile repeats "Shielded" as the destination's pool badge.
    expect(find.text(titles.shielded), findsWidgets);
    expect(_supplementalCard, findsNothing);
    expect(_showsAddress(transparentRecipientAddress), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
