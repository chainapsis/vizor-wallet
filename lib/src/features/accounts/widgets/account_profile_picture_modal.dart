import 'package:flutter/widgets.dart';

import '../../../core/widgets/app_profile_picture_picker_modal.dart';

/// Accounts-facing wrapper around the shared
/// [AppProfilePicturePickerModal].
///
/// Keeps the established accounts keys (`profile_picture_option_*`,
/// `account_modal_cancel_button`, `account_modal_action_button`) and the
/// async submit behavior ('Updating...' label, inline error) intact.
class AccountProfilePictureModal extends StatelessWidget {
  const AccountProfilePictureModal({
    required this.currentProfilePictureId,
    required this.onCancel,
    required this.onUpdate,
    super.key,
  });

  final String currentProfilePictureId;
  final VoidCallback onCancel;
  final Future<void> Function(String profilePictureId) onUpdate;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicturePickerModal(
      title: 'Select profile picture',
      currentProfilePictureId: currentProfilePictureId,
      onCancel: onCancel,
      onUpdate: onUpdate,
      cancelKey: const ValueKey('account_modal_cancel_button'),
      actionKey: const ValueKey('account_modal_action_button'),
    );
  }
}
