import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import 'account_modal_card.dart';

class AccountProfilePictureModal extends StatefulWidget {
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
  State<AccountProfilePictureModal> createState() =>
      _AccountProfilePictureModalState();
}

class _AccountProfilePictureModalState
    extends State<AccountProfilePictureModal> {
  static const _optionSize = AppProfilePictureSize.large;
  static const _gridWidth = 189.0;

  late String _selectedId = _initialSelectedId();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate =>
      !_isSubmitting &&
      isKnownProfilePictureId(_selectedId) &&
      _selectedId != _currentResolvedId;

  String get _currentResolvedId {
    return resolveProfilePictureOption(widget.currentProfilePictureId).id;
  }

  String _initialSelectedId() {
    return _currentResolvedId;
  }

  Future<void> _submit() async {
    if (!_canUpdate) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await widget.onUpdate(_selectedId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitError = "Couldn't update profile picture.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _select(String id) {
    if (_isSubmitting) return;
    setState(() {
      _selectedId = id;
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewOption = resolveProfilePictureOption(_selectedId);

    return AccountModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AccountProfilePictureModalHeader(profilePictureId: previewOption.id),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: _gridWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (final option in kProfilePictureOptions)
                    _ProfilePictureOptionButton(
                      key: ValueKey('profile_picture_option_${option.id}'),
                      option: option,
                      size: _optionSize,
                      selected: option.id == _selectedId,
                      enabled: !_isSubmitting,
                      onTap: () => _select(option.id),
                    ),
                ],
              ),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppButton(
                onPressed: _isSubmitting ? null : widget.onCancel,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                height: kAccountModalButtonHeight,
                child: const Text('Cancel'),
              ),
              const Spacer(),
              AppButton(
                onPressed: _canUpdate ? _submit : null,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.medium,
                height: kAccountModalButtonHeight,
                minWidth: kAccountModalButtonMinWidth,
                child: Text(_isSubmitting ? 'Updating...' : 'Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountProfilePictureModalHeader extends StatelessWidget {
  const _AccountProfilePictureModalHeader({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.xLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Select Profile Picture',
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfilePictureOptionButton extends StatefulWidget {
  const _ProfilePictureOptionButton({
    required this.option,
    required this.size,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final ProfilePictureOption option;
  final AppProfilePictureSize size;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ProfilePictureOptionButton> createState() =>
      _ProfilePictureOptionButtonState();
}

class _ProfilePictureOptionButtonState
    extends State<_ProfilePictureOptionButton> {
  static const _focusRingWidth = 2.0;
  static const _checkBadgeSize = 14.0;
  static const _checkIconSize = 9.0;
  static const _checkRight = -2.0;
  static const _checkBottom = -2.0;

  bool _isHovered = false;
  bool _isFocused = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }

  void _setFocused(bool value) {
    if (_isFocused == value) return;
    setState(() {
      _isFocused = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showFocusRing = widget.enabled && (_isHovered || _isFocused);
    final outerDimension = widget.size.dimension;

    return FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: _setFocused,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: SizedBox(
            width: outerDimension,
            height: outerDimension,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (showFocusRing)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: _focusRingWidth,
                        ),
                        borderRadius: BorderRadius.circular(widget.size.radius),
                      ),
                    ),
                  ),
                AppProfilePicture(
                  profilePictureId: widget.option.id,
                  size: widget.size,
                ),
                if (widget.selected)
                  Positioned(
                    right: _checkRight,
                    bottom: _checkBottom,
                    child: Container(
                      width: _checkBadgeSize,
                      height: _checkBadgeSize,
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: _checkIconSize,
                          color: colors.icon.inverse,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
