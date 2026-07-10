import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart'
    show showProfilePictureSheet;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/widgets/address_book_network_icon.dart';
import '../../../swap/models/swap_address_formatting.dart';

/// Mobile add-contact surface for the Pay recipient flow.
///
/// Figma: light `6261:129310`, dark `6261:131143`.
class MobilePayAddContactCard extends StatefulWidget {
  const MobilePayAddContactCard({
    required this.network,
    required this.address,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final AddressBookNetwork network;
  final String address;
  final VoidCallback onCancel;
  final Future<void> Function(String label, String profilePictureId) onSave;

  @override
  State<MobilePayAddContactCard> createState() =>
      _MobilePayAddContactCardState();
}

class _MobilePayAddContactCardState extends State<MobilePayAddContactCard> {
  final _labelController = TextEditingController();
  final _labelFocusNode = FocusNode();
  var _profilePictureId = kDefaultProfilePictureId;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController.addListener(_refresh);
  }

  @override
  void dispose() {
    _labelController.removeListener(_refresh);
    _labelController.dispose();
    _labelFocusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _canSave {
    final label = _labelController.text.trim();
    return !_saving && label.isNotEmpty && label.length <= 20;
  }

  Future<void> _pickPicture() async {
    final selected = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (!mounted || selected == null) return;
    setState(() => _profilePictureId = selected);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_labelController.text.trim(), _profilePictureId);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: '',
      showTitle: false,
      onClose: widget.onCancel,
      child: Column(
        key: const ValueKey('mobile_pay_add_contact_card'),
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
                  right: -4,
                  bottom: -4,
                  child: GestureDetector(
                    key: const ValueKey('mobile_pay_add_contact_picture'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickPicture,
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
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Address label',
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          MobileTextField(
            controller: _labelController,
            focusNode: _labelFocusNode,
            fieldKey: const ValueKey('mobile_pay_add_contact_label'),
            hintText: 'Add a label',
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Text(
                      'Chain & address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AddressBookNetworkIcon(network: widget.network, size: 16),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    widget.network.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Container(
            key: const ValueKey('mobile_pay_add_contact_address'),
            height: AppInputSizing.height,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.surface.input.primary,
              borderRadius: BorderRadius.circular(AppInputSizing.radius),
              boxShadow: [
                BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
                BoxShadow(
                  color: colors.shadows.subtle,
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              compactSwapAddress(
                widget.address,
                maxLength: 30,
                prefixLength: 16,
                suffixLength: 10,
                separator: '...',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            key: const ValueKey('mobile_pay_add_contact_save'),
            expand: true,
            constrainContent: true,
            onPressed: _canSave ? _save : null,
            child: Text(_saving ? 'Saving' : 'Save contact'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_pay_add_contact_cancel'),
            expand: true,
            constrainContent: true,
            variant: AppButtonVariant.ghost,
            onPressed: widget.onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
