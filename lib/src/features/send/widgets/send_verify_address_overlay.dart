import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../../providers/account_models.dart';
import 'send_recipient_resolver.dart';
import 'send_review_layout.dart';
import 'verify_address_modal.dart';

class _PreviousTransactionCountRequest {
  const _PreviousTransactionCountRequest({
    required this.accountUuid,
    required this.address,
  });

  final String accountUuid;
  final String address;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PreviousTransactionCountRequest &&
          accountUuid == other.accountUuid &&
          address == other.address;

  @override
  int get hashCode => Object.hash(accountUuid, address);
}

final _previousTransactionCountForAddressProvider = FutureProvider.autoDispose
    .family<int, _PreviousTransactionCountRequest>((ref, request) async {
      final address = request.address.trim();
      if (address.isEmpty) return 0;

      try {
        final network = ref.watch(rpcEndpointProvider).networkName;
        final dbPath = await getWalletDbPath();
        return rust_sync.getPreviousTransactionCountForAddress(
          dbPath: dbPath,
          network: network,
          accountUuid: request.accountUuid,
          address: address,
        );
      } catch (e) {
        debugPrint('previousTransactionCountForAddress: failed: $e');
        rethrow;
      }
    });

/// The "Show full address" overlay on the send review/status screens.
///
/// Hosts [VerifyAddressModal] inside an `AppPaneModalOverlay` (the same
/// presentation as the Keystone signing modal). The variant tracks the live
/// address book AND the user's own accounts: a saved contact or an own
/// account renders the known-recipient header, anything else the
/// unknown-address header. Verification is display-only; the design
/// dropped the add-to-contacts flow from this modal.
class SendVerifyAddressOverlay extends ConsumerWidget {
  const SendVerifyAddressOverlay({
    required this.accountUuid,
    required this.address,
    required this.isShieldedAddress,
    required this.onClose,
    super.key,
  });

  /// Account whose send history is being reviewed.
  final String accountUuid;

  /// Full recipient address (trimmed by the caller).
  final String address;

  /// Whether an unknown address should render as shielded or transparent.
  final bool isShieldedAddress;

  /// Dismiss handler — scrim tap, Escape, and the Close button.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final savedContact = sendRecipientContactFor(
      contacts: contacts,
      address: address,
    );
    final recipient = sendReviewRecipientFor(
      contacts: contacts,
      address: address,
      ownAccounts: ownAccounts,
    );
    final loadedPreviousTransactionCount = savedContact == null
        ? null
        : ref
              .watch(
                _previousTransactionCountForAddressProvider(
                  _PreviousTransactionCountRequest(
                    accountUuid: accountUuid,
                    address: address.trim(),
                  ),
                ),
              )
              .asData
              ?.value;
    final previousTransactionCount =
        loadedPreviousTransactionCount != null &&
            loadedPreviousTransactionCount > 0
        ? loadedPreviousTransactionCount
        : null;

    return AppPaneModalOverlay(
      onDismiss: onClose,
      child: VerifyAddressModal(
        address: address,
        variant: switch (recipient) {
          SendReviewContactRecipient() =>
            VerifyAddressModalVariant.knownContact,
          SendReviewAddressRecipient() => VerifyAddressModalVariant.unknown,
        },
        unknownAddressKind: isShieldedAddress
            ? VerifyAddressModalAddressKind.shielded
            : VerifyAddressModalAddressKind.transparent,
        contactName: switch (recipient) {
          SendReviewContactRecipient(:final name) => name,
          SendReviewAddressRecipient() => null,
        },
        contactProfilePictureId: switch (recipient) {
          SendReviewContactRecipient(:final profilePictureId) =>
            profilePictureId,
          SendReviewAddressRecipient() => null,
        },
        previousTransactionCount: previousTransactionCount,
        onClose: onClose,
      ),
    );
  }
}
