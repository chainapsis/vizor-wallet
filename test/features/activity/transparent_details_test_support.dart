import 'package:flutter/material.dart' show ThemeMode;
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

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
