import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/models/address_format_validator.dart';
import '../../swap/domain/swap_direction.dart';
import '../../swap/domain/swap_intent_status.dart';
import '../../swap/models/swap_deposit_broadcast_result.dart';
import '../../swap/models/swap_intent.dart';
import '../../swap/models/swap_token_amount_formatting.dart';
import '../../swap/widgets/swap_amount_text.dart';

/// An external address this wallet previously paid or swapped to, surfaced in
/// the pay recipient step's "Recently sent" list — Figma 6241:85245.
class PayRecentRecipient {
  const PayRecentRecipient({
    required this.address,
    this.contactId,
    this.amountText,
    this.lastUsedAt,
  });

  final String address;
  final String? contactId;
  final String? amountText;
  final DateTime? lastUsedAt;
}

/// The payment destination plus the optional address-book identity explicitly
/// selected by the user.
///
/// The address is the payment contract. [contactId] is presentation metadata
/// and stays null when a directly entered address matches more than one
/// contact, so the UI never chooses an arbitrary label.
class PayRecipientSelection {
  const PayRecipientSelection({required this.address, this.contactId});

  final String address;
  final String? contactId;
}

/// Derives the "Recently sent" list for [network] from past swap/pay intents:
/// outgoing (ZEC -> external) recipients whose address is valid on [network],
/// deduplicated using the destination network's address semantics plus known
/// contact identity, most recent first. Legacy entries coalesce with a single
/// current contact, but remain address-only when the match is ambiguous.
List<PayRecentRecipient> payRecentRecipients({
  required List<SwapIntent> intents,
  required AddressBookNetwork network,
  required Iterable<AddressBookContact> contacts,
  int limit = 5,
}) {
  final uniqueContactIds = _payUniqueContactIdsByAddress(contacts, network);
  final byRecipient = <(String, String?), PayRecentRecipient>{};
  for (final intent in intents) {
    if (intent.direction != SwapDirection.zecToExternal) continue;
    if (!_hasPayPayoutEvidence(intent)) continue;
    final sourceAsset = intent.externalAsset;
    final sourceNetwork = sourceAsset == null
        ? null
        : AddressBookNetwork.tryFromChainTicker(sourceAsset.chainTicker);
    if (sourceNetwork == null ||
        !_payNetworksAreCompatible(sourceNetwork, network)) {
      continue;
    }
    final address = intent.oneClickRecipient?.trim() ?? '';
    if (address.isEmpty) continue;
    if (addressFormatIssue(network, address) != null) continue;
    final usedAt = intent.completedAt ?? intent.updatedAt ?? intent.createdAt;
    final normalizedAddress = normalizedAddressBookAddress(network, address);
    final storedContactId = intent.userExternalContactId?.trim();
    final contactId = storedContactId == null || storedContactId.isEmpty
        ? uniqueContactIds[normalizedAddress]
        : storedContactId;
    final key = (normalizedAddress, contactId);
    final existing = byRecipient[key];
    if (existing != null &&
        (usedAt == null ||
            (existing.lastUsedAt != null &&
                !usedAt.isAfter(existing.lastUsedAt!)))) {
      continue;
    }
    final payoutAmount = _payRecentAmountText(intent.receiveEstimate);
    byRecipient[key] = PayRecentRecipient(
      address: address,
      contactId: contactId,
      amountText: payoutAmount.isEmpty ? null : payoutAmount,
      lastUsedAt: usedAt,
    );
  }
  final entries = byRecipient.values.toList()
    ..sort((a, b) {
      final at = a.lastUsedAt;
      final bt = b.lastUsedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
  return entries.take(limit).toList();
}

Map<String, String?> _payUniqueContactIdsByAddress(
  Iterable<AddressBookContact> contacts,
  AddressBookNetwork network,
) {
  final result = <String, String?>{};
  for (final contact in payCompatibleContacts(contacts, network)) {
    final address = normalizedAddressBookAddress(network, contact.address);
    if (address.isEmpty) continue;
    if (!result.containsKey(address)) {
      result[address] = contact.id;
    } else if (result[address] != contact.id) {
      result[address] = null;
    }
  }
  return result;
}

bool _payNetworksAreCompatible(
  AddressBookNetwork source,
  AddressBookNetwork destination,
) {
  return source == destination || (source.isEvm && destination.isEvm);
}

String _payRecentAmountText(String value) {
  final compact = compactSwapAmountText(value.trim());
  if (compact.isEmpty) return '';
  final separator = compact.indexOf(' ');
  final formatted = separator < 0
      ? swapTrimDecimal(compact)
      : '${swapTrimDecimal(compact.substring(0, separator))}'
            '${compact.substring(separator)}';
  // This list represents outgoing payouts. Keep the direction visible while
  // using the final receive asset/amount (for example, `-24 USDC` for a
  // ZEC -> USDC Pay), rather than the deposited ZEC amount.
  return formatted.startsWith('-') ? formatted : '-$formatted';
}

bool _hasPayPayoutEvidence(SwapIntent intent) {
  return switch (intent.status) {
    SwapIntentStatus.complete => true,
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown =>
      (intent.destinationChainTxHash?.trim().isNotEmpty ?? false) ||
          _hasBroadcastedPayDeposit(intent),
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => false,
  };
}

bool _hasBroadcastedPayDeposit(SwapIntent intent) {
  final status = intent.broadcastStatus;
  return intent.payMode &&
      (status == SwapDepositBroadcastStatus.broadcasted ||
          status == SwapDepositBroadcastStatus.broadcastedStorageFailed) &&
      (intent.depositTxHash?.trim().isNotEmpty ?? false);
}

/// Contacts whose network can receive on [network]: the same chain, or any
/// EVM chain when [network] is EVM (EVM addresses are interchangeable —
/// see [AddressBookNetwork.isEvm]).
List<AddressBookContact> payCompatibleContacts(
  Iterable<AddressBookContact> contacts,
  AddressBookNetwork network,
) {
  return [
    for (final contact in contacts)
      if (contact.network == network ||
          (contact.network.isEvm && network.isEvm))
        contact,
  ];
}

/// All compatible saved contacts matching [address].
List<AddressBookContact> payContactsForAddress(
  Iterable<AddressBookContact> contacts,
  String address,
) {
  return [
    for (final contact in contacts)
      if (_payContactHasAddress(contact, address)) contact,
  ];
}

/// Builds the selection produced by the field CTA.
///
/// A unique address-book match is safe to attach automatically. Duplicate
/// contacts keep the address only until the user explicitly chooses a row.
PayRecipientSelection payRecipientSelectionForAddress(
  Iterable<AddressBookContact> contacts,
  String address,
) {
  final matches = payContactsForAddress(contacts, address);
  return PayRecipientSelection(
    address: address.trim(),
    contactId: matches.length == 1 ? matches.single.id : null,
  );
}

/// Restores a recent recipient's explicit contact identity when it is still
/// valid. Legacy records without an identity may use an unambiguous address
/// match; stale explicit identities stay address-only instead of rebinding.
PayRecipientSelection payRecipientSelectionForRecent(
  Iterable<AddressBookContact> contacts,
  PayRecentRecipient recent,
) {
  final storedContactId = recent.contactId?.trim();
  if (storedContactId == null || storedContactId.isEmpty) {
    return payRecipientSelectionForAddress(contacts, recent.address);
  }
  final explicitSelection = PayRecipientSelection(
    address: recent.address,
    contactId: storedContactId,
  );
  if (payContactForSelection(contacts, explicitSelection) != null) {
    return explicitSelection;
  }
  return PayRecipientSelection(address: recent.address.trim());
}

/// Resolves the selection used for quote review from the current address and
/// an optional row selection.
///
/// A missing or re-addressed explicit contact degrades to address-only instead
/// of silently rebinding to another contact that happens to share the address.
PayRecipientSelection resolvePayRecipientSelection(
  Iterable<AddressBookContact> contacts,
  String address, {
  PayRecipientSelection? explicitSelection,
}) {
  if (explicitSelection == null) {
    return payRecipientSelectionForAddress(contacts, address);
  }
  final currentSelection = PayRecipientSelection(
    address: address.trim(),
    contactId: explicitSelection.contactId,
  );
  if (payContactForSelection(contacts, currentSelection) != null) {
    return currentSelection;
  }
  return PayRecipientSelection(address: address.trim());
}

/// Resolves the exact contact carried by [selection], if it still exists and
/// still owns that address.
AddressBookContact? payContactForSelection(
  Iterable<AddressBookContact> contacts,
  PayRecipientSelection selection,
) {
  final contactId = selection.contactId;
  if (contactId == null) return null;
  for (final contact in contacts) {
    if (contact.id == contactId &&
        _payContactHasAddress(contact, selection.address)) {
      return contact;
    }
  }
  return null;
}

bool _payContactHasAddress(AddressBookContact contact, String address) {
  final needle = normalizedAddressBookAddress(contact.network, address);
  return needle.isNotEmpty &&
      normalizedAddressBookAddress(contact.network, contact.address) == needle;
}

const _payMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "2d ago" style label for recent recipients; falls back to "April 27" for
/// anything older than a week, matching the Figma list rows.
String? payRecentTimeLabel(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return null;
  final local = timestamp.toLocal();
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(local);
  if (elapsed.isNegative) return null;
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${_payMonthNames[local.month - 1]} ${local.day}';
}
