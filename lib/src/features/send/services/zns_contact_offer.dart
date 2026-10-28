/// After a send to a Zcash name, the status screen offers to add the
/// recipient to contacts. The contact keeps the address that was paid, with
/// the name beside it, so later sends and the contacts list show the name
/// without a new lookup and without a separate store for sent names.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/naming/zns_name_resolver.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_models.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../widgets/send_recipient_resolver.dart';
import '../widgets/send_review_layout.dart' show SendReviewContactRecipient;

/// The address book's label limit.
const _contactLabelMaxLength = 20;

/// The contact label for [znsName]: the bare name (`alice` for
/// `alice.zcash`), cut to the address book's limit.
String znsContactLabel(String znsName) {
  final bare = znsNameFromRecipientInput(znsName) ?? znsName.trim();
  return bare.length <= _contactLabelMaxLength
      ? bare
      : bare.substring(0, _contactLabelMaxLength);
}

/// Whether a send to [address] that was entered as [znsName] should offer
/// to add a contact: only when a name was used and the address is not
/// already a contact or one of the user's own accounts.
bool shouldOfferZnsContact({
  required String? znsName,
  required String address,
  required Iterable<AddressBookContact> contacts,
  required Map<String, AccountInfo> ownAccounts,
}) {
  if (znsName == null || znsName.isEmpty) return false;
  final recipient = sendReviewRecipientFor(
    contacts: contacts,
    address: address,
    ownAccounts: ownAccounts,
  );
  return recipient is! SendReviewContactRecipient;
}

/// Adds the recipient to contacts and confirms with a toast. Returns whether
/// the contact was saved.
Future<bool> addZnsRecipientToContacts(
  BuildContext context,
  WidgetRef ref, {
  required String znsName,
  required String address,
}) async {
  try {
    await ref
        .read(addressBookProvider.notifier)
        .addContact(
          label: znsContactLabel(znsName),
          network: AddressBookNetwork.zcash,
          address: address,
          profilePictureId: kDefaultProfilePictureId,
          znsName: znsName,
        );
  } catch (e) {
    log('Send: add ZNS contact failed: $e');
    if (context.mounted) {
      showAppToast(
        context,
        "Couldn't save the contact. Try again.",
        iconName: AppIcons.warning,
        tone: AppToastTone.destructive,
      );
    }
    return false;
  }
  if (context.mounted) showAppToast(context, 'Added $znsName to contacts');
  return true;
}
