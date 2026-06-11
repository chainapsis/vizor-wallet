import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import 'send_review_layout.dart';

/// Current unified and transparent address of every local account, keyed by the
/// trimmed address. Used by the send review/status screens to recognize a
/// recipient as one of the user's own accounts (self-transfer).
///
/// Address rotation caveat: only each account's CURRENT addresses are matched;
/// an older rotated address of the same account is not recognized.
final ownAccountAddressesProvider = FutureProvider<Map<String, AccountInfo>>((
  ref,
) async {
  final accounts = ref.watch(
    accountProvider.select((state) => state.value?.accounts ?? const []),
  );
  if (accounts.isEmpty) return const {};

  final network = ref.watch(rpcEndpointProvider).networkName;
  final dbPath = await getWalletDbPath();
  final byAddress = <String, AccountInfo>{};
  for (final account in accounts) {
    await _addOwnAccountAddress(
      byAddress: byAddress,
      account: account,
      loadAddress: () => rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      ),
      addressKind: 'unified',
    );
    await _addOwnAccountAddress(
      byAddress: byAddress,
      account: account,
      loadAddress: () => rust_wallet.getTransparentAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      ),
      addressKind: 'transparent',
    );
  }
  return byAddress;
});

Future<void> _addOwnAccountAddress({
  required Map<String, AccountInfo> byAddress,
  required AccountInfo account,
  required Future<String> Function() loadAddress,
  required String addressKind,
}) async {
  try {
    final address = (await loadAddress()).trim();
    if (address.isNotEmpty) {
      byAddress[address] = account;
    }
  } catch (e) {
    // Best-effort: an account whose address fails to load simply is not
    // recognized as a self-transfer target for that address kind.
    log(
      'ownAccountAddresses: $addressKind address load failed for '
      '${account.uuid}: $e',
    );
  }
}

/// Resolves the Zcash address-book contact for a send recipient [address].
///
/// Delegates to the canonical [addressBookContactFor] on the Zcash network
/// (trimmed, case-sensitive exact match with a non-empty label). Returns
/// `null` when no contact matches, which selects the raw-address variant.
AddressBookContact? sendRecipientContactFor({
  required Iterable<AddressBookContact> contacts,
  required String address,
}) {
  return addressBookContactFor(
    contacts: contacts,
    network: AddressBookNetwork.zcash,
    address: address,
  );
}

/// Maps a send recipient [address] to its review/status presentation:
/// * the contact variant (avatar + name) when the address book resolves a
///   labeled Zcash contact,
/// * the contact variant with the account name/avatar when the address is
///   one of the user's own accounts ([ownAccounts], keyed by trimmed
///   address — see [ownAccountAddressesProvider]),
/// * the raw-address variant otherwise.
///
/// A saved contact wins over the own-account match: when the user labeled
/// their own address in the address book, that label is the chosen display.
SendReviewRecipient sendReviewRecipientFor({
  required Iterable<AddressBookContact> contacts,
  required String address,
  Map<String, AccountInfo> ownAccounts = const {},
}) {
  final contact = sendRecipientContactFor(contacts: contacts, address: address);
  if (contact != null) {
    return SendReviewContactRecipient(
      address: address,
      name: contact.label.trim(),
      profilePictureId: contact.profilePictureId,
    );
  }
  final ownAccount = ownAccounts[address.trim()];
  if (ownAccount != null) {
    return SendReviewContactRecipient(
      address: address,
      name: ownAccount.name.trim(),
      profilePictureId: ownAccount.profilePictureId,
    );
  }
  return SendReviewAddressRecipient(address: address);
}
