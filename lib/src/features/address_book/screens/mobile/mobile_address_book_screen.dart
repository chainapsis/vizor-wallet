import 'dart:async';

import 'package:flutter/material.dart' show Scaffold, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel, MobileSheetClose, showProfilePictureSheet;
import '../../models/address_book_contact.dart';
import '../../models/address_format_validator.dart';
import '../../providers/address_book_provider.dart';
import '../../widgets/address_book_network_icon.dart';

/// Mobile address book — the settings "Address Book" entry. There is no
/// mobile Figma frame for this screen yet, so it follows the desktop
/// address book's behavior (multi-network contacts, format validation)
/// in the mobile settings idiom: surface-card list, bottom sheets for
/// add/edit/remove, and a pinned add CTA.
class MobileAddressBookScreen extends ConsumerWidget {
  const MobileAddressBookScreen({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    AddressBookContact? contact,
  }) async {
    final result = await showAppMobileSheet<_ContactDraft>(
      context: context,
      builder: (_) => _ContactEditSheet(contact: contact),
    );
    if (result == null || !context.mounted) return;

    final notifier = ref.read(addressBookProvider.notifier);
    try {
      if (contact == null) {
        await notifier.addContact(
          label: result.label,
          network: result.network,
          address: result.address,
          profilePictureId: result.profilePictureId,
        );
      } else {
        await notifier.updateContact(
          contact.id,
          label: result.label,
          network: result.network,
          address: result.address,
          profilePictureId: result.profilePictureId,
        );
      }
    } catch (e, st) {
      log('MobileAddressBook: save error: $e\n$st');
      if (!context.mounted) return;
      showAppToast(context, "Couldn't save the contact. Please try again.");
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    AddressBookContact contact,
  ) async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (_) => _RemoveContactSheet(contact: contact),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(addressBookProvider.notifier).removeContact(contact.id);
    } catch (e, st) {
      log('MobileAddressBook: remove error: $e\n$st');
      if (!context.mounted) return;
      showAppToast(context, "Couldn't remove the contact. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final contacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.back(
                title: 'Address book',
                onBack: () => context.pop(),
              ),
              Expanded(
                child: contacts.isEmpty
                    ? _EmptyState(
                        onAdd: () => unawaited(_openEditor(context, ref)),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.s,
                          AppSpacing.sm,
                          AppSpacing.md,
                        ),
                        child: MobileSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final contact in contacts)
                                _ContactRow(
                                  contact: contact,
                                  onTap: () => unawaited(
                                    _openEditor(context, ref, contact: contact),
                                  ),
                                  onRemove: () => unawaited(
                                    _confirmRemove(context, ref, contact),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (contacts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: AppButton(
                    key: const ValueKey('mobile_address_book_add'),
                    expand: true,
                    onPressed: () => unawaited(_openEditor(context, ref)),
                    leading: const AppIcon(AppIcons.addNew),
                    child: const Text('Add contact'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.background.inverse,
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.users,
                size: 24,
                color: colors.icon.inverse,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No contacts yet',
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Save addresses you send to often.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_address_book_add_empty'),
            onPressed: onAdd,
            minWidth: 200,
            leading: const AppIcon(AppIcons.addNew),
            child: const Text('Add contact'),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onTap,
    required this.onRemove,
  });

  final AddressBookContact contact;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String get _truncatedAddress {
    final address = contact.address;
    if (address.length <= 20) return address;
    return '${address.substring(0, 10)} ... ${address.substring(address.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Edit ${contact.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Row(
            children: [
              AppProfilePicture(
                profilePictureId: contact.profilePictureId,
                size: AppProfilePictureSize.large,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            contact.label,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        AddressBookNetworkIcon(
                          network: contact.network,
                          size: 16,
                        ),
                      ],
                    ),
                    Text(
                      _truncatedAddress,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                button: true,
                label: 'Remove ${contact.label}',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AppIcon(
                        AppIcons.trash,
                        size: AppIconSize.medium,
                        color: colors.icon.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactDraft {
  const _ContactDraft({
    required this.label,
    required this.network,
    required this.address,
    required this.profilePictureId,
  });

  final String label;
  final AddressBookNetwork network;
  final String address;
  final String profilePictureId;
}

class _ContactEditSheet extends StatefulWidget {
  const _ContactEditSheet({this.contact});

  final AddressBookContact? contact;

  @override
  State<_ContactEditSheet> createState() => _ContactEditSheetState();
}

class _ContactEditSheetState extends State<_ContactEditSheet> {
  late final TextEditingController _labelController = TextEditingController(
    text: widget.contact?.label ?? '',
  );
  late final TextEditingController _addressController = TextEditingController(
    text: widget.contact?.address ?? '',
  );
  late AddressBookNetwork _network =
      widget.contact?.network ?? AddressBookNetwork.zcash;
  late String _profilePictureId =
      widget.contact?.profilePictureId ?? kDefaultProfilePictureId;
  final _labelFocus = FocusNode();
  final _addressFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _labelFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  Future<void> _pickNetwork() async {
    final picked = await showAppMobileSheet<AddressBookNetwork>(
      context: context,
      builder: (_) => _NetworkPickerSheet(selected: _network),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _network = picked;
      _error = null;
    });
  }

  Future<void> _pickAvatar() async {
    final picked = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (picked == null || !mounted) return;
    setState(() => _profilePictureId = picked);
  }

  void _save() {
    final label = _labelController.text.trim();
    final address = _addressController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Enter a name for this contact.');
      return;
    }
    if (address.isEmpty) {
      setState(() => _error = 'Enter an address.');
      return;
    }
    final issue = addressFormatIssue(_network, address);
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    Navigator.of(context).pop(
      _ContactDraft(
        label: label,
        network: _network,
        address: address,
        profilePictureId: _profilePictureId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEdit = widget.contact != null;
    // Scrollable so a tall keyboard (e.g. Korean with its candidate bar)
    // compresses the sheet instead of overflowing it and hiding the save
    // button. The sheet frame floats the whole card above the keyboard,
    // so no manual keyboard inset is needed here.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? 'Edit contact' : 'Add contact',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              MobileSheetClose(onTap: () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Semantics(
              button: true,
              label: 'Change contact picture',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickAvatar(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppProfilePicture(
                      profilePictureId: _profilePictureId,
                      size: AppProfilePictureSize.xLarge,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: colors.background.inverse,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.edit,
                            size: 12,
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
          const SizedBox(height: AppSpacing.sm),
          _FieldLabel('Network'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            button: true,
            label: 'Select network',
            child: GestureDetector(
              key: const ValueKey('mobile_address_book_network'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_pickNetwork()),
              child: _FieldShell(
                child: Row(
                  children: [
                    AddressBookNetworkIcon(network: _network, size: 20),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _network.label,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    AppIcon(
                      AppIcons.expand,
                      size: AppIconSize.medium,
                      color: colors.icon.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _FieldLabel('Name'),
          const SizedBox(height: AppSpacing.xxs),
          _FieldShell(
            // A real TextField (bare, no decoration) rather than raw
            // EditableText so long-press selection and the paste menu
            // work; the shell owns all visible chrome.
            child: TextField(
              key: const ValueKey('mobile_address_book_label'),
              controller: _labelController,
              focusNode: _labelFocus,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
              cursorColor: colors.text.accent,
              decoration: null,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _FieldLabel('Address'),
          const SizedBox(height: AppSpacing.xxs),
          _FieldShell(
            child: TextField(
              key: const ValueKey('mobile_address_book_address'),
              controller: _addressController,
              focusNode: _addressFocus,
              maxLines: 2,
              style: AppTypography.codeMedium.copyWith(
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
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_address_book_save'),
            expand: true,
            onPressed: _save,
            child: Text(isEdit ? 'Save contact' : 'Add contact'),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: child,
    );
  }
}

class _NetworkPickerSheet extends StatelessWidget {
  const _NetworkPickerSheet({required this.selected});

  final AddressBookNetwork selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select network',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              MobileSheetClose(onTap: () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final network in AddressBookNetwork.values)
                  Semantics(
                    button: true,
                    selected: network == selected,
                    label: network.label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(network),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Row(
                          children: [
                            AddressBookNetworkIcon(network: network, size: 24),
                            const SizedBox(width: AppSpacing.s),
                            Expanded(
                              child: Text(
                                network.label,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                            ),
                            if (network == selected)
                              AppIcon(
                                AppIcons.check,
                                size: AppIconSize.medium,
                                color: colors.icon.accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveContactSheet extends StatelessWidget {
  const _RemoveContactSheet({required this.contact});

  final AddressBookContact contact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Remove contact?',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              MobileSheetClose(onTap: () => Navigator.of(context).pop(false)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '"${contact.label}" will be removed from your address book. '
            'This does not affect any past transactions.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_address_book_remove_confirm'),
            expand: true,
            variant: AppButtonVariant.destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove contact'),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileSheetCancel(onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
