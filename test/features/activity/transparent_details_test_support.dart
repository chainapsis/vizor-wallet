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
  String txKind = 'sent',
  String? primaryAddress,
  String? sourceAddress,
  String? sourcePool,
  List<rust_sync.TransactionDetailOutput> outputs = const [],
}) => rust_sync.TransactionDetail(
  txidHex: transparentDetailsTxid,
  txKind: txKind,
  primaryAddress: primaryAddress,
  sourceAddress: sourceAddress,
  sourcePool: sourcePool,
  outputs: outputs,
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
    expect(find.text('Show full address'), findsOneWidget);
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
    expect(find.text('Show full address'), findsOneWidget);
    delayedPoll.complete(pending);
    await flush(tester);
    expect(find.text('Show full address'), findsOneWidget);
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
    expect(find.text('Show full address'), findsOneWidget);
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

/// The send of [transparentSend]: a public wallet records the recipient;
/// private queries know output 0 pays it and output 1 is the change.
rust_sync.TransactionDetail transparentSendDetail({required bool private}) =>
    transparentDetail(
      rust_sync.TransparentDetailsState.available,
      primaryAddress: private ? null : transparentRecipientAddress,
      outputs: private
          ? const []
          : [
              rust_sync.TransactionDetailOutput(
                address: transparentRecipientAddress,
                amountZatoshi: BigInt.from(228420040),
                pool: 'transparent',
                activityPool: 'transparent',
                usesOrchardReceiver: false,
              ),
            ],
      recipients: transparentRecipients,
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
  });

  final String received;
  final String receiving;
  final String receiveFailed;
  final String shielded;
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
      } else {
        expect(_showsAddress(transparentSenderAddress), findsOneWidget);
        expect(find.text('Show full address'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode single-recipient send names its payee', (tester) async {
      await pump(
        tester,
        ScriptedDetails([transparentSendDetail(private: private)]),
        transaction: transparentSend(),
        privateQueries: private,
      );
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(_showsAddress(transparentRecipientAddress), findsWidgets);
      expect(find.text('Show full address'), findsOneWidget);
      // The account's change is not a payment.
      expect(_showsAddress(transparentOwnAddress), findsNothing);
      expect(_supplementalCard, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode multi-recipient send lists payees in order', (
      tester,
    ) async {
      final recipients = [
        ...transparentRecipients,
        rust_sync.TransparentRecipient(
          outputIndex: 2,
          address: transparentSecondRecipientAddress,
          amountZatoshi: BigInt.from(3000000),
          isOwn: false,
        ),
      ];
      final detail = transparentDetail(
        rust_sync.TransparentDetailsState.available,
        primaryAddress: private ? null : transparentRecipientAddress,
        // Out of order on purpose: the list follows the transaction.
        recipients: recipients.reversed.toList(),
      );
      await pump(
        tester,
        ScriptedDetails([detail]),
        transaction: transparentSend(),
        privateQueries: private,
        privacy: true,
      );
      expect(find.text('Sent successfully'), findsOneWidget);
      expect(_supplementalCard, findsOneWidget);
      final first = find.byKey(const ValueKey('transparent_recipient_0'));
      final second = find.byKey(const ValueKey('transparent_recipient_2'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(
        find.byKey(const ValueKey('transparent_recipient_1')),
        findsNothing,
        reason: 'change is filtered',
      );
      expect(
        tester.getTopLeft(first).dy,
        lessThan(tester.getTopLeft(second).dy),
      );
      // Hidden amounts stay hidden in the list.
      expect(find.textContaining('0.03', findRichText: true), findsNothing);
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
