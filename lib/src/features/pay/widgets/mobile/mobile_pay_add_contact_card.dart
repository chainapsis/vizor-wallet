import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_tappable.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel, showProfilePictureSheet;
import '../../../address_book/contact_label_generator.dart';
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/widgets/address_book_network_icon.dart';
import '../../../swap/models/swap_address_formatting.dart';

// The Figma fields reserve a 16px sub-label slot with a 4px gap even when
// there is no helper copy. Express those empty slots as spacing so the modal
// keeps the shared field widgets while retaining the Figma field rhythm.
const _fieldToNextContentGap = AppSpacing.xxs + AppSpacing.sm + AppSpacing.xxs;
const _addressFieldToButtonsGap =
    AppSpacing.xxs + AppSpacing.sm + AppSpacing.md;

/// Mobile add-contact surface for the Pay recipient flow.
///
/// Figma: `6261:129939`.
class MobilePayAddContactCard extends StatefulWidget {
  const MobilePayAddContactCard({
    required this.network,
    required this.address,
    required this.onCancel,
    required this.onSave,
    this.profilePictureIdGenerator,
    super.key,
  });

  final AddressBookNetwork network;
  final String address;
  final VoidCallback onCancel;
  final Future<void> Function(String label, String profilePictureId) onSave;

  /// Overrides the random picture generator for deterministic tests.
  final String Function()? profilePictureIdGenerator;

  @override
  State<MobilePayAddContactCard> createState() =>
      _MobilePayAddContactCardState();
}

class _MobilePayAddContactCardState extends State<MobilePayAddContactCard> {
  final _labelController = TextEditingController();
  final _labelFocusNode = FocusNode();
  late String _profilePictureId;
  var _saving = false;
  String? _saveError;
  var _lastLabelText = '';

  @override
  void initState() {
    super.initState();
    _profilePictureId =
        widget.profilePictureIdGenerator?.call() ??
        randomContactProfilePictureId();
    _labelController.addListener(_onLabelChanged);
    _labelFocusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    _labelController.removeListener(_onLabelChanged);
    _labelFocusNode.removeListener(_refresh);
    _labelController.dispose();
    _labelFocusNode.dispose();
    super.dispose();
  }

  void _onLabelChanged() {
    if (!mounted) return;
    final textChanged = _labelController.text != _lastLabelText;
    _lastLabelText = _labelController.text;
    setState(() {
      if (textChanged) _saveError = null;
    });
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
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(_labelController.text.trim(), _profilePictureId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = "Couldn't save this contact. Try again.";
      });
      return;
    }
    if (mounted) setState(() => _saving = false);
  }

  void _clearLabel() {
    _labelController.clear();
    _labelFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    // Keep the sheet usable on compact devices with the keyboard open. The
    // route's empty area must remain outside this scroll view so barrier taps
    // still dismiss; only the card body scrolls, matching Address Book.
    final maxBodyHeight =
        (media.size.height - media.viewInsets.bottom - media.padding.top - 120)
            .clamp(180.0, 620.0)
            .toDouble();
    return MobileModalScaffold(
      title: '',
      showTitle: false,
      onClose: widget.onCancel,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxBodyHeight),
        child: SingleChildScrollView(
          child: Column(
            key: const ValueKey('mobile_pay_add_contact_card'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: AppTappable(
                  key: const ValueKey('mobile_pay_add_contact_picture'),
                  semanticsLabel: 'Change contact picture',
                  onTap: _pickPicture,
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: AppProfilePictureSize.xxLarge.dimension,
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Address label',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              MobileTextField(
                controller: _labelController,
                focusNode: _labelFocusNode,
                fieldKey: const ValueKey('mobile_pay_add_contact_label'),
                hintText: 'Add label 1-20 characters',
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(20)],
                onSubmitted: (_) => _save(),
                trailing:
                    (_labelFocusNode.hasFocus &&
                        _labelController.text.isNotEmpty)
                    ? Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: AppIconHoverButton(
                          icon: AppIcons.cross,
                          semanticLabel: 'Clear contact label',
                          onTap: _clearLabel,
                          size: 32,
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          hoverColor: colors.background.ground,
                          iconColor: colors.icon.muted,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: _fieldToNextContentGap),
              SizedBox(
                key: const ValueKey('mobile_pay_add_contact_chain_row'),
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
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AddressBookNetworkIcon(
                          network: widget.network,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          widget.network.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Semantics(
                label: 'Address ${widget.address}',
                readOnly: true,
                child: ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('mobile_pay_add_contact_address'),
                    height: AppInputSizing.height,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface.input.primary,
                      borderRadius: BorderRadius.circular(
                        AppInputSizing.radius,
                      ),
                      boxShadow: [
                        BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
                        BoxShadow(
                          color: colors.shadows.subtle,
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                        ),
                        BoxShadow(
                          color: colors.shadows.subtle,
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                        BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
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
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  _saveError!,
                  key: const ValueKey('mobile_pay_add_contact_save_error'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
              ],
              SizedBox(
                height: _saveError == null
                    ? _addressFieldToButtonsGap
                    : AppSpacing.md,
              ),
              AppButton(
                key: const ValueKey('mobile_pay_add_contact_save'),
                expand: true,
                constrainContent: true,
                onPressed: _canSave ? _save : null,
                child: Text(_saving ? 'Saving' : 'Save contact'),
              ),
              const SizedBox(height: AppSpacing.s),
              MobileSheetCancel(
                key: const ValueKey('mobile_pay_add_contact_cancel'),
                onTap: widget.onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
