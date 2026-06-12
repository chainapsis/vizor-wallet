import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../main.dart' show log;
import '../../../../core/account_name_policy.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileBottomSafeArea(
      bottomPadding: AppSpacing.md,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: MobileSheetClose(
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
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
                        profilePictureId: _profilePictureId,
                        size: AppProfilePictureSize.xLarge,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.background.homeCard,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: AppIcon(
                              AppIcons.edit,
                              size: AppIconSize.medium,
                              color: colors.text.homeCard,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Account name',
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(color: colors.border.subtle),
              ),
              // A real TextField (bare, no decoration) rather than raw
              // EditableText so long-press selection and the paste menu
              // work; the container owns all visible chrome.
              child: TextField(
                key: const ValueKey('mobile_account_edit_name'),
                controller: _nameController,
                focusNode: _nameFocusNode,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
                cursorColor: colors.text.accent,
                decoration: null,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            // 48 from the field to Save edits per the Accounts Edits
            // frame (field bottom 627 → button top 677).
            const SizedBox(height: AppSpacing.lg),
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
    return MobileBottomSafeArea(
      bottomPadding: AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: MobileSheetClose(
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Center(
              child: AppProfilePicture(
                profilePictureId: _selected,
                size: AppProfilePictureSize.xLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Select profile picture',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // 5-up grid of 56 px portraits per the Figma PFP modal.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final option in kProfilePictureOptions)
                  Semantics(
                    button: true,
                    label: option.label,
                    selected: option.id == _selected,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = option.id),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AppProfilePicture(
                            profilePictureId: option.id,
                            size: AppProfilePictureSize.xLarge,
                          ),
                          if (option.id == _selected)
                            Positioned(
                              left: -2,
                              bottom: -2,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: colors.background.homeCard,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: AppIcon(
                                    AppIcons.check,
                                    size: 14,
                                    color: colors.text.homeCard,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
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
            child: AppIcon(
              AppIcons.cross,
              size: AppIconSize.medium,
              color: colors.icon.accent,
            ),
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
