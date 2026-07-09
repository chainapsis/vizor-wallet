import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_profile_picture_picker_modal.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/widgets/address_book_network_icon.dart';
import '../../swap/models/swap_address_formatting.dart';

/// "Add to Contacts" modal on the pay recipient step — Figma 6241:105199.
/// Collects a label (1-20 chars) and profile picture for the typed address;
/// the chain and address themselves are fixed by the pay flow.
class PayAddContactModal extends StatefulWidget {
  const PayAddContactModal({
    required this.network,
    required this.address,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final AddressBookNetwork network;
  final String address;
  final VoidCallback onCancel;

  /// Persists the contact. Called with the cleaned label and the selected
  /// profile picture id.
  final Future<void> Function(String label, String profilePictureId) onSave;

  @override
  State<PayAddContactModal> createState() => _PayAddContactModalState();
}

class _PayAddContactModalState extends State<PayAddContactModal> {
  late final TextEditingController _labelController;
  var _profilePictureId = kDefaultProfilePictureId;
  var _pickingPicture = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _labelController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  bool get _canSave {
    final label = _labelController.text.trim();
    return !_saving && label.isNotEmpty && label.length <= 20;
  }

  void _save() {
    if (!_canSave) return;
    setState(() => _saving = true);
    widget.onSave(_labelController.text.trim(), _profilePictureId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_pickingPicture) {
      return AppProfilePicturePickerModal(
        title: 'Select contact picture',
        currentProfilePictureId: _profilePictureId,
        onCancel: () => setState(() => _pickingPicture = false),
        onUpdate: (id) async {
          setState(() {
            _profilePictureId = id;
            _pickingPicture = false;
          });
        },
      );
    }
    return AppModalCard(
      child: Column(
        key: const ValueKey('pay_add_contact_modal'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AppProfilePicture(
                  profilePictureId: _profilePictureId,
                  size: AppProfilePictureSize.xxLarge,
                ),
                Positioned(
                  bottom: -4,
                  right: -4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: const ValueKey('pay_add_contact_edit_picture'),
                      onTap: () => setState(() => _pickingPicture = true),
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.background.inverse,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.background.base,
                            width: 3,
                          ),
                        ),
                        child: AppIcon(
                          AppIcons.edit,
                          size: 14,
                          color: colors.icon.inverse,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            key: const ValueKey('pay_add_contact_label_field'),
            label: 'Address Label',
            controller: _labelController,
            hintText: 'Add label 1-20 characters',
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Chain & Address',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                Row(
                  children: [
                    AddressBookNetworkIcon(network: widget.network, size: 16),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      widget.network.label,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          AppTextField(
            key: const ValueKey('pay_add_contact_address_field'),
            label: '',
            showLabel: false,
            initialValue: compactSwapAddress(
              widget.address,
              maxLength: 23,
              prefixLength: 12,
              suffixLength: 8,
              separator: '...',
            ),
            enabled: false,
            readOnly: true,
            textStyle: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppModalActions(
            cancelKey: const ValueKey('pay_add_contact_cancel_button'),
            actionKey: const ValueKey('pay_add_contact_save_button'),
            onCancel: widget.onCancel,
            actionLabel: 'Save',
            onAction: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}
