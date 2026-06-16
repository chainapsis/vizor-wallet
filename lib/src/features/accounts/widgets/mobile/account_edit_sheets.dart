import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../main.dart' show log;
import '../../../../core/account_name_policy.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/account_provider.dart';

/// Pending edits popped by [showAccountEditSheet]; null fields mean
/// "unchanged".
class AccountEdits {
  const AccountEdits({this.name, this.profilePictureId});

  final String? name;
  final String? profilePictureId;
}

/// Opens the account edit sheet — Figma `Accounts Edits` / `Update
/// Account` (4514:84873 / 4503:73086): avatar with the pencil overlay
/// opening the picture picker, the name field, and Save edits. Shared
/// by the accounts manager and the settings account rows.
Future<AccountEdits?> showAccountEditSheet(
  BuildContext context, {
  required AccountInfo account,
}) {
  return showAppMobileSheet<AccountEdits>(
    context: context,
    builder: (_) => _EditAccountSheet(account: account),
  );
}

/// Opens the picture picker — Figma `PFP Modal` (4514:85279 /
/// 4503:72528). Pops the chosen picture id.
Future<String?> showProfilePictureSheet(
  BuildContext context, {
  required String selectedId,
}) {
  return showAppMobileSheet<String>(
    context: context,
    builder: (_) => _ProfilePictureSheet(selectedId: selectedId),
  );
}

/// Persists [edits] for [account]; returns false when a write failed
/// (callers surface their own toast).
Future<bool> applyAccountEdits(
  WidgetRef ref,
  AccountInfo account,
  AccountEdits edits,
) async {
  final accountNotifier = ref.read(accountProvider.notifier);
  try {
    if (edits.name != null) {
      await accountNotifier.renameAccount(account.uuid, edits.name!);
    }
    if (edits.profilePictureId != null) {
      await accountNotifier.updateProfilePicture(
        account.uuid,
        edits.profilePictureId!,
      );
    }
    return true;
  } catch (e, st) {
    log('applyAccountEdits: failed: $e\n$st');
    return false;
  }
}

class _EditAccountSheet extends StatefulWidget {
  const _EditAccountSheet({required this.account});

  final AccountInfo account;

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.account.name,
  );
  final _nameFocusNode = FocusNode();
  late String _profilePictureId = widget.account.profilePictureId;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPicture() async {
    final picked = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (picked != null && mounted) {
      setState(() => _profilePictureId = picked);
    }
  }

  void _save() {
    final name = normalizeAccountName(_nameController.text);
    try {
      validateAccountName(name);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    Navigator.of(context).pop(
      AccountEdits(
        name: name == widget.account.name ? null : name,
        profilePictureId: _profilePictureId == widget.account.profilePictureId
            ? null
            : _profilePictureId,
      ),
    );
  }

  void _clearName() {
    setState(() {
      _nameController.clear();
      _error = null;
    });
    _nameFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Semantics(
                  button: true,
                  label: 'Change profile picture',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('mobile_account_edit_avatar'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _pickPicture,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppProfilePicture(
                          key: const ValueKey(
                            'mobile_account_edit_avatar_image',
                          ),
                          profilePictureId: _profilePictureId,
                          size: AppProfilePictureSize.xxLarge,
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: _AvatarEditBadge(
                            ringColor: colors.background.base,
                            fillColor: colors.background.inverse,
                            iconColor: colors.text.inverse,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Account label',
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              MobileTextField(
                fieldKey: const ValueKey('mobile_account_edit_name'),
                controller: _nameController,
                focusNode: _nameFocusNode,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Semantics(
                    label: 'Clear account name',
                    button: true,
                    child: GestureDetector(
                      key: const ValueKey('mobile_account_edit_name_clear'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _clearName,
                      child: SizedBox(
                        width: 32,
                        height: AppInputSizing.height,
                        child: Center(
                          child: AppIcon(
                            AppIcons.cross,
                            size: 20,
                            color: colors.icon.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 16,
                child: _error == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('mobile_account_edit_save'),
                expand: true,
                onPressed: _save,
                child: const Text('Save edits'),
              ),
              const SizedBox(height: AppSpacing.s),
              MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: MobileSheetClose(onTap: () => Navigator.of(context).pop()),
        ),
      ],
    );
  }
}

class _ProfilePictureSheet extends StatefulWidget {
  const _ProfilePictureSheet({required this.selectedId});

  final String selectedId;

  @override
  State<_ProfilePictureSheet> createState() => _ProfilePictureSheetState();
}

class _ProfilePictureSheetState extends State<_ProfilePictureSheet> {
  late String _selected = widget.selectedId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppProfilePicture(
                    key: const ValueKey('mobile_account_pfp_current_image'),
                    profilePictureId: _selected,
                    size: AppProfilePictureSize.xxLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Select profile picture',
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: _ProfilePictureGrid(
                  selected: _selected,
                  onSelected: (id) => setState(() => _selected = id),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('mobile_account_pfp_update'),
                expand: true,
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text('Update picture'),
              ),
              const SizedBox(height: AppSpacing.s),
              MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: MobileSheetClose(onTap: () => Navigator.of(context).pop()),
        ),
      ],
    );
  }
}

class _ProfilePictureGrid extends StatelessWidget {
  const _ProfilePictureGrid({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const itemSize = AppProfilePictureSize.xLarge;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth;
        final rows = <Widget>[];
        for (var start = 0; start < kProfilePictureOptions.length; start += 5) {
          final options = kProfilePictureOptions.skip(start).take(5).toList();
          rows.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final option in options)
                  SizedBox(
                    width: itemSize.dimension,
                    height: itemSize.dimension,
                    child: Semantics(
                      button: true,
                      label: option.label,
                      selected: option.id == selected,
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: ValueKey('mobile_account_pfp_option_${option.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(option.id),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AppProfilePicture(
                              profilePictureId: option.id,
                              size: itemSize,
                            ),
                            if (option.id == selected)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: Container(
                                  key: ValueKey(
                                    'mobile_account_pfp_selected_badge_${option.id}',
                                  ),
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: colors.background.inverse,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.background.base,
                                      width: 3,
                                    ),
                                  ),
                                  child: Center(
                                    child: AppIcon(
                                      AppIcons.check,
                                      size: AppIconSize.medium,
                                      color: colors.text.inverse,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          if (start + 5 < kProfilePictureOptions.length) {
            rows.add(const SizedBox(height: AppSpacing.sm));
          }
        }
        return Center(
          child: SizedBox(
            width: gridWidth,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        );
      },
    );
  }
}

class _AvatarEditBadge extends StatelessWidget {
  const _AvatarEditBadge({
    required this.ringColor,
    required this.fillColor,
    required this.iconColor,
  });

  final Color ringColor;
  final Color fillColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    // Figma node 4514:50561: the badge layout frame is 24x24, but its
    // 4px stroke renders outside the frame, so the visual ring is 32x32.
    return SizedBox(
      key: const ValueKey('mobile_account_edit_avatar_badge_frame'),
      width: 24,
      height: 24,
      child: OverflowBox(
        maxWidth: 32,
        maxHeight: 32,
        child: Container(
          key: const ValueKey('mobile_account_edit_avatar_badge_outer'),
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
          child: Center(
            child: Container(
              key: const ValueKey('mobile_account_edit_avatar_badge_fill'),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: fillColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: _AvatarEditGlyph(color: iconColor)),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarEditGlyph extends StatelessWidget {
  const _AvatarEditGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Figma Edit component 2865:121738 is scaled to a 16px frame here.
    // Its vector sits at x=2.4287, y=2 inside that frame and is 11.572px.
    return SizedBox(
      width: AppIconSize.medium,
      height: AppIconSize.medium,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2.4287, 2, 2, 2.4276),
        child: AppIcon(AppIcons.editFilled, size: 11.572, color: color),
      ),
    );
  }
}

/// Circled X dismiss control in a sheet's top-right corner.
class MobileSheetClose extends StatelessWidget {
  const MobileSheetClose({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Close',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.background.raised,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(AppIcons.cross, size: 20, color: colors.icon.accent),
          ),
        ),
      ),
    );
  }
}

/// Centered "Cancel" text action below a sheet's primary button.
class MobileSheetCancel extends StatelessWidget {
  const MobileSheetCancel({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Text(
              'Cancel',
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
