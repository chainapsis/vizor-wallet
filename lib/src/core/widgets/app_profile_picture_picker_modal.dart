import 'package:flutter/widgets.dart';

import '../profile_pictures.dart';
import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'app_modal_card.dart';
import 'app_profile_picture.dart';

/// Shared profile-picture picker modal used by the accounts/settings profile
/// flows and the address-book contact form.
///
/// Renders the design-system picker: a large preview of the pending
/// selection, a title, the option grid (hover/focus ring + selected check
/// badge), and the standard cancel/update action row. Selection is local
/// until the user confirms with the update action, which calls [onUpdate]
/// with the chosen id. While [onUpdate] is pending the action label flips to
/// 'Updating...', cancel is disabled, and a failure surfaces an inline error
/// without closing the modal. Synchronous callers (e.g. the contact draft
/// flow) simply resolve immediately.
///
/// Option buttons are keyed `'$optionKeyPrefix${option.id}'` so each feature
/// can keep its established test keys.
class AppProfilePicturePickerModal extends StatefulWidget {
  const AppProfilePicturePickerModal({
    required this.title,
    required this.currentProfilePictureId,
    required this.onCancel,
    required this.onUpdate,
    this.optionKeyPrefix = 'profile_picture_option_',
    this.optionSize = AppProfilePictureSize.navLarge,
    this.gridWidth = 280.0,
    this.cancelKey = const ValueKey('modal_cancel_button'),
    this.actionKey = const ValueKey('modal_action_button'),
    super.key,
  });

  /// Modal title, e.g. 'Select profile picture' / 'Select contact picture'.
  final String title;

  /// Currently persisted picture id; the update action stays disabled until
  /// the local selection differs from this.
  final String currentProfilePictureId;

  final VoidCallback onCancel;

  /// Confirms the selection. May be async (accounts persistence) or resolve
  /// immediately (contact draft updates).
  final Future<void> Function(String profilePictureId) onUpdate;

  /// Prefix for the per-option [ValueKey]s in the grid.
  final String optionKeyPrefix;

  /// Size of each option avatar in the grid.
  final AppProfilePictureSize optionSize;

  /// Width of the wrapping option grid.
  final double gridWidth;

  final Key cancelKey;
  final Key actionKey;

  @override
  State<AppProfilePicturePickerModal> createState() =>
      _AppProfilePicturePickerModalState();
}

class _AppProfilePicturePickerModalState
    extends State<AppProfilePicturePickerModal> {
  late String _selectedId = _currentResolvedId;
  bool _isSubmitting = false;
  String? _submitError;

  bool get _canUpdate =>
      !_isSubmitting &&
      isKnownProfilePictureId(_selectedId) &&
      _selectedId != _currentResolvedId;

  String get _currentResolvedId {
    return resolveProfilePictureOption(widget.currentProfilePictureId).id;
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

    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfilePicturePickerHeader(
            profilePictureId: previewOption.id,
            title: widget.title,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: widget.gridWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  for (final option in kProfilePictureOptions)
                    _ProfilePictureOptionButton(
                      key: ValueKey('${widget.optionKeyPrefix}${option.id}'),
                      option: option,
                      size: widget.optionSize,
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
          AppModalActions(
            cancelKey: widget.cancelKey,
            actionKey: widget.actionKey,
            onCancel: _isSubmitting ? null : widget.onCancel,
            actionLabel: _isSubmitting ? 'Updating...' : 'Update',
            onAction: _canUpdate ? _submit : null,
          ),
        ],
      ),
    );
  }
}

class _ProfilePicturePickerHeader extends StatelessWidget {
  const _ProfilePicturePickerHeader({
    required this.profilePictureId,
    required this.title,
  });

  final String profilePictureId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppProfilePicture(
          profilePictureId: profilePictureId,
          size: AppProfilePictureSize.xxLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyLarge.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w600,
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
  static const _checkBadgeSize = 20.0;
  static const _checkIconSize = 16.0;
  static const _checkRight = -4.0;
  static const _checkBottom = -4.0;

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
                        shape: BoxShape.circle,
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
                        border: Border.all(
                          color: colors.background.base,
                          width: 2,
                        ),
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
