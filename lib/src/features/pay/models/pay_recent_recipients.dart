import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/models/address_format_validator.dart';
import '../../swap/domain/swap_direction.dart';
import '../../swap/domain/swap_intent_status.dart';
import '../../swap/models/swap_intent.dart';
import '../../swap/models/swap_token_amount_formatting.dart';
import '../../swap/widgets/swap_amount_text.dart';

/// An external address this wallet previously paid or swapped to, surfaced in
/// the pay recipient step's "Recently sent" list — Figma 6241:85245.
class PayRecentRecipient {
  const PayRecentRecipient({
    required this.address,
    this.amountText,
    this.lastUsedAt,
  });

  final String address;
  final String? amountText;
  final DateTime? lastUsedAt;
}

/// Derives the "Recently sent" list for [network] from past swap/pay intents:
/// outgoing (ZEC -> external) recipients whose address is valid on [network],
/// deduplicated using the destination network's address semantics, most recent
/// first.
List<PayRecentRecipient> payRecentRecipients({
  required List<SwapIntent> intents,
  required AddressBookNetwork network,
  int limit = 5,
}) {
  final byAddress = <String, PayRecentRecipient>{};
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
    final key = normalizedAddressBookAddress(network, address);
    final existing = byAddress[key];
    if (existing != null &&
        (usedAt == null ||
            (existing.lastUsedAt != null &&
                !usedAt.isAfter(existing.lastUsedAt!)))) {
      continue;
    }
    final payoutAmount = _payRecentAmountText(intent.receiveEstimate);
    byAddress[key] = PayRecentRecipient(
      address: address,
      amountText: payoutAmount.isEmpty ? null : payoutAmount,
      lastUsedAt: usedAt,
    );
  }
  final entries = byAddress.values.toList()
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
      intent.destinationChainTxHash?.trim().isNotEmpty ?? false,
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => false,
  };
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

/// The saved contact matching [address] on [network], if any.
AddressBookContact? payContactForAddress(
  Iterable<AddressBookContact> contacts,
  AddressBookNetwork network,
  String address,
) {
  final needle = normalizedAddressBookAddress(network, address);
  if (needle.isEmpty) return null;
  for (final contact in payCompatibleContacts(contacts, network)) {
    if (normalizedAddressBookAddress(contact.network, contact.address) ==
        needle) {
      return contact;
    }
  }
  return null;
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
