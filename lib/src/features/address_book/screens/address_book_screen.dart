import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_context_menu.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../send/models/send_prefill_args.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../models/address_book_contact.dart';
import '../models/address_format_validator.dart';
import '../providers/address_book_provider.dart';
import '../widgets/address_book_network_icon.dart';

class AddressBookScreen extends ConsumerStatefulWidget {
  const AddressBookScreen({super.key});

  @override
  ConsumerState<AddressBookScreen> createState() => _AddressBookScreenState();
}

enum _AddressBookModalKind {
  addContact,
  editContact,
  avatarPicker,
  networkSelector,
  addressScanner,
  removeContact,
}

class _AddressBookScreenState extends ConsumerState<AddressBookScreen> {
  _AddressBookModalKind? _modal;
  _ContactDraft? _draft;
  AddressBookContact? _editingContact;
  AddressBookContact? _removingContact;
  String? _submitError;

  void _openAddContact() {
    setState(() {
      _modal = _AddressBookModalKind.addContact;
      _draft = _ContactDraft.empty();
      _editingContact = null;
      _removingContact = null;
      _submitError = null;
    });
  }

  void _openEditContact(AddressBookContact contact) {
    setState(() {
      _modal = _AddressBookModalKind.editContact;
      _draft = _ContactDraft.fromContact(contact);
      _editingContact = contact;
      _removingContact = null;
      _submitError = null;
    });
  }

  void _openAvatarPicker() {
    setState(() => _modal = _AddressBookModalKind.avatarPicker);
  }

  void _openNetworkSelector() {
    setState(() => _modal = _AddressBookModalKind.networkSelector);
  }

  void _openRemoveContact(AddressBookContact contact) {
    setState(() {
      _modal = _AddressBookModalKind.removeContact;
      _draft = null;
      _editingContact = null;
      _removingContact = contact;
      _submitError = null;
    });
  }

  void _returnToDraftForm() {
    final draft = _draft;
    if (draft == null) {
      _closeModal();
      return;
    }
    setState(() {
      _modal = _editingContact == null
          ? _AddressBookModalKind.addContact
          : _AddressBookModalKind.editContact;
      _removingContact = null;
      _submitError = null;
    });
  }

  void _closeModal() {
    setState(() {
      _modal = null;
      _draft = null;
      _editingContact = null;
      _removingContact = null;
      _submitError = null;
    });
  }

  void _updateDraft(_ContactDraft draft) {
    setState(() => _draft = draft);
  }

  void _selectAvatar(String profilePictureId) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(profilePictureId: profilePictureId);
      _modal = _editingContact == null
          ? _AddressBookModalKind.addContact
          : _AddressBookModalKind.editContact;
    });
  }

  void _selectNetwork(AddressBookNetwork network) {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _draft = draft.copyWith(network: network);
      _modal = _editingContact == null
          ? _AddressBookModalKind.addContact
          : _AddressBookModalKind.editContact;
    });
  }

  void _scanAddress() {
    if (_draft == null) return;
    setState(() => _modal = _AddressBookModalKind.addressScanner);
  }

  void _selectScannedAddress(String address) {
    final draft = _draft;
    final scanned = address.trim();
    if (draft == null || scanned.isEmpty) {
      _returnToDraftForm();
      return;
    }
    setState(() {
      _draft = draft.copyWith(address: scanned);
      _modal = _editingContact == null
          ? _AddressBookModalKind.addContact
          : _AddressBookModalKind.editContact;
      _submitError = null;
    });
  }

  Future<void> _submitDraft() async {
    final draft = _draft;
    if (draft == null || !draft.isValid) return;
    setState(() => _submitError = null);

    try {
      final notifier = ref.read(addressBookProvider.notifier);
      final editing = _editingContact;
      if (editing == null) {
        await notifier.addContact(
          label: draft.label,
          network: draft.network,
          address: draft.address,
          profilePictureId: draft.profilePictureId,
        );
      } else {
        await notifier.updateContact(
          editing.id,
          label: draft.label,
          network: draft.network,
          address: draft.address,
          profilePictureId: draft.profilePictureId,
        );
      }
      if (!mounted) return;
      _closeModal();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitError = "Couldn't save contact. Try again.");
    }
  }

  Future<void> _removeContact() async {
    final contact = _removingContact;
    if (contact == null) return;
    try {
      await ref.read(addressBookProvider.notifier).removeContact(contact.id);
      if (!mounted) return;
      _closeModal();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitError = "Couldn't remove contact. Try again.");
    }
  }

  Future<void> _copyAddress(AddressBookContact contact) async {
    await Clipboard.setData(ClipboardData(text: contact.address));
    if (!mounted) return;
    showAppToast(context, 'Address copied');
  }

  void _sendToContact(AddressBookContact contact) {
    context.go(
      '/send',
      extra: SendPrefillArgs(
        id: 'address-book-${contact.id}',
        source: 'address-book',
        address: contact.address,
        label: contact.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(addressBookProvider);
    Widget buildPane(AddressBookState state) {
      return _AddressBookPane(
        state: state,
        onQueryChanged: (query) =>
            ref.read(addressBookProvider.notifier).setQuery(query),
        onAddContact: _openAddContact,
        onEditContact: _openEditContact,
        onCopyAddress: _copyAddress,
        onSendContact: _sendToContact,
        onRemoveContact: _openRemoveContact,
      );
    }

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: contactsAsync.when(
                loading: () => buildPane(
                  contactsAsync.asData?.value ?? const AddressBookState(),
                ),
                error: (_, _) => const _AddressBookError(),
                data: buildPane,
              ),
            ),
            if (_modal != null)
              AppPaneModalOverlay(onDismiss: _closeModal, child: _buildModal()),
          ],
        ),
      ),
    );
  }

  Widget _buildModal() {
    final modal = _modal;
    final draft = _draft;
    switch (modal) {
      case _AddressBookModalKind.addContact:
      case _AddressBookModalKind.editContact:
        return _ContactFormModal(
          draft: draft ?? _ContactDraft.empty(),
          editing: _editingContact != null,
          submitError: _submitError,
          onChanged: _updateDraft,
          onAvatarPressed: _openAvatarPicker,
          onNetworkPressed: _openNetworkSelector,
          onScanAddress: _scanAddress,
          onCancel: _closeModal,
          onSubmit: _submitDraft,
        );
      case _AddressBookModalKind.avatarPicker:
        return _ContactAvatarPickerModal(
          selectedProfilePictureId:
              draft?.profilePictureId ?? kDefaultProfilePictureId,
          onSelected: _selectAvatar,
          onCancel: _returnToDraftForm,
        );
      case _AddressBookModalKind.networkSelector:
        return _NetworkSelectorModal(
          selectedNetwork: draft?.network ?? AddressBookNetwork.zcash,
          onSelected: _selectNetwork,
          onCancel: _returnToDraftForm,
        );
      case _AddressBookModalKind.addressScanner:
        return AddressQrScanModal(
          onAddressScanned: _selectScannedAddress,
          onCancel: _returnToDraftForm,
        );
      case _AddressBookModalKind.removeContact:
        return _RemoveContactModal(
          contact: _removingContact,
          submitError: _submitError,
          onCancel: _closeModal,
          onRemove: _removeContact,
        );
      case null:
        return const SizedBox.shrink();
    }
  }
}

class _ContactDraft {
  const _ContactDraft({
    required this.label,
    required this.network,
    required this.address,
    required this.profilePictureId,
  });

  factory _ContactDraft.empty() {
    return const _ContactDraft(
      label: '',
      network: AddressBookNetwork.zcash,
      address: '',
      profilePictureId: kDefaultProfilePictureId,
    );
  }

  factory _ContactDraft.fromContact(AddressBookContact contact) {
    return _ContactDraft(
      label: contact.label,
      network: contact.network,
      address: contact.address,
      profilePictureId: contact.profilePictureId,
    );
  }

  final String label;
  final AddressBookNetwork network;
  final String address;
  final String profilePictureId;

  bool get isValid =>
      validateAddressBookLabel(label) == null &&
      validateAddressBookAddress(address) == null;

  _ContactDraft copyWith({
    String? label,
    AddressBookNetwork? network,
    String? address,
    String? profilePictureId,
  }) {
    return _ContactDraft(
      label: label ?? this.label,
      network: network ?? this.network,
      address: address ?? this.address,
      profilePictureId: profilePictureId ?? this.profilePictureId,
    );
  }
}

class _AddressBookPane extends StatelessWidget {
  const _AddressBookPane({
    required this.state,
    required this.onQueryChanged,
    required this.onAddContact,
    required this.onEditContact,
    required this.onCopyAddress,
    required this.onSendContact,
    required this.onRemoveContact,
  });

  final AddressBookState state;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAddContact;
  final ValueChanged<AddressBookContact> onEditContact;
  final ValueChanged<AddressBookContact> onCopyAddress;
  final ValueChanged<AddressBookContact> onSendContact;
  final ValueChanged<AddressBookContact> onRemoveContact;

  bool get _showBottomAction => state.hasContacts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: AppRouteBackLink(minWidth: 60),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  Text(
                    'Address book',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const AppDecorativeDivider(width: 256),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: _AddressBookContent(
                      state: state,
                      onQueryChanged: onQueryChanged,
                      onAddContact: onAddContact,
                      onEditContact: onEditContact,
                      onCopyAddress: onCopyAddress,
                      onSendContact: onSendContact,
                      onRemoveContact: onRemoveContact,
                    ),
                  ),
                  if (_showBottomAction) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _AddressBookAddButton(onPressed: onAddContact),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBookContent extends StatelessWidget {
  const _AddressBookContent({
    required this.state,
    required this.onQueryChanged,
    required this.onAddContact,
    required this.onEditContact,
    required this.onCopyAddress,
    required this.onSendContact,
    required this.onRemoveContact,
  });

  final AddressBookState state;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAddContact;
  final ValueChanged<AddressBookContact> onEditContact;
  final ValueChanged<AddressBookContact> onCopyAddress;
  final ValueChanged<AddressBookContact> onSendContact;
  final ValueChanged<AddressBookContact> onRemoveContact;

  @override
  Widget build(BuildContext context) {
    if (!state.hasContacts) {
      return _AddressBookNoContacts(onAddContact: onAddContact);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 352,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AddressBookSearchField(
              query: state.query,
              onChanged: onQueryChanged,
            ),
            const SizedBox(height: AppSpacing.base),
            Expanded(
              child: state.filteredContacts.isEmpty
                  ? const _EmptySearchResult()
                  : _AddressBookContactsList(
                      contacts: state.filteredContacts,
                      onEditContact: onEditContact,
                      onCopyAddress: onCopyAddress,
                      onSendContact: onSendContact,
                      onRemoveContact: onRemoveContact,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressBookSearchField extends StatefulWidget {
  const _AddressBookSearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<_AddressBookSearchField> createState() =>
      _AddressBookSearchFieldState();
}

class _AddressBookSearchFieldState extends State<_AddressBookSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _AddressBookSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      key: const ValueKey('address_book_search_field'),
      label: 'Search',
      showLabel: false,
      controller: _controller,
      focusNode: _focusNode,
      hintText: 'Search name or address',
      leading: const AppIcon(AppIcons.search),
      leadingSlotWidth: 40,
      trailingSlotWidth: 40,
      inputHorizontalPadding: AppSpacing.xs,
      showClearButton: true,
      clearButtonRequiresText: false,
      onChanged: widget.onChanged,
      onClear: () => widget.onChanged(''),
    );
  }
}

class _AddressBookContactsList extends StatelessWidget {
  const _AddressBookContactsList({
    required this.contacts,
    required this.onEditContact,
    required this.onCopyAddress,
    required this.onSendContact,
    required this.onRemoveContact,
  });

  final List<AddressBookContact> contacts;
  final ValueChanged<AddressBookContact> onEditContact;
  final ValueChanged<AddressBookContact> onCopyAddress;
  final ValueChanged<AddressBookContact> onSendContact;
  final ValueChanged<AddressBookContact> onRemoveContact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final network in AddressBookNetwork.values) {
      final group = [
        for (final contact in contacts)
          if (contact.network == network) contact,
      ];
      if (group.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(
        _ContactGroup(
          network: network,
          contacts: group,
          onEditContact: onEditContact,
          onCopyAddress: onCopyAddress,
          onSendContact: onSendContact,
          onRemoveContact: onRemoveContact,
        ),
      );
    }

    return ListView(padding: EdgeInsets.zero, children: children);
  }
}

class _ContactGroup extends StatelessWidget {
  const _ContactGroup({
    required this.network,
    required this.contacts,
    required this.onEditContact,
    required this.onCopyAddress,
    required this.onSendContact,
    required this.onRemoveContact,
  });

  final AddressBookNetwork network;
  final List<AddressBookContact> contacts;
  final ValueChanged<AddressBookContact> onEditContact;
  final ValueChanged<AddressBookContact> onCopyAddress;
  final ValueChanged<AddressBookContact> onSendContact;
  final ValueChanged<AddressBookContact> onRemoveContact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContactGroupLabel(network: network),
        const SizedBox(height: AppSpacing.xs),
        for (final contact in contacts)
          _ContactRow(
            key: ValueKey('address_book_contact_row_${contact.id}'),
            contact: contact,
            onEdit: () => onEditContact(contact),
            onCopy: () => onCopyAddress(contact),
            onSend: contact.network.canSendFromWallet
                ? () => onSendContact(contact)
                : null,
            onRemove: () => onRemoveContact(contact),
          ),
      ],
    );
  }
}

class _ContactGroupLabel extends StatelessWidget {
  const _ContactGroupLabel({required this.network});

  final AddressBookNetwork network;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          children: [
            _NetworkAssetIcon(network: network, size: 16),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              network.label,
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onEdit,
    required this.onCopy,
    required this.onSend,
    required this.onRemove,
    super.key,
  });

  final AddressBookContact contact;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback? onSend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            AppProfilePicture(
              profilePictureId: contact.profilePictureId,
              size: AppProfilePictureSize.large,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.addressPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _ContactRowMenuButton(
              contact: contact,
              onEdit: onEdit,
              onCopy: onCopy,
              onSend: onSend,
              onRemove: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRowMenuButton extends StatefulWidget {
  const _ContactRowMenuButton({
    required this.contact,
    required this.onEdit,
    required this.onCopy,
    required this.onSend,
    required this.onRemove,
  });

  final AddressBookContact contact;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback? onSend;
  final VoidCallback onRemove;

  @override
  State<_ContactRowMenuButton> createState() => _ContactRowMenuButtonState();
}

class _ContactRowMenuButtonState extends State<_ContactRowMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _isHovered = false;

  @override
  void dispose() {
    _hideMenu(rebuild: false);
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuEntry == null) {
      _showMenu();
    } else {
      _hideMenu();
    }
  }

  void _showMenu() {
    final overlay = Overlay.of(context);
    final appTheme = AppTheme.of(context);
    _menuEntry = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _hideMenu(),
              ),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 22),
              child: AppTheme(
                data: appTheme,
                child: _ContactContextMenu(
                  canSend: widget.onSend != null,
                  onEdit: _handleEdit,
                  onCopy: _handleCopy,
                  onSend: _handleSend,
                  onRemove: _handleRemove,
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_menuEntry!);
    setState(() {});
  }

  void _hideMenu({bool rebuild = true}) {
    final entry = _menuEntry;
    if (entry == null) return;
    _menuEntry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  void _handleEdit() {
    _hideMenu();
    widget.onEdit();
  }

  void _handleCopy() {
    _hideMenu();
    widget.onCopy();
  }

  void _handleSend() {
    _hideMenu();
    widget.onSend?.call();
  }

  void _handleRemove() {
    _hideMenu();
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || _menuEntry != null;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleMenu,
          child: Semantics(
            button: true,
            label: '${widget.contact.label} actions',
            child: Container(
              key: ValueKey('address_book_contact_menu_${widget.contact.id}'),
              width: 20,
              height: 20,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: active ? context.colors.background.base : null,
                borderRadius: BorderRadius.circular(AppRadii.xSmall),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -math.pi / 2,
                  child: AppIcon(
                    AppIcons.options,
                    size: AppIconSize.medium,
                    color: context.colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (!mounted) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }
}

class _ContactContextMenu extends StatelessWidget {
  const _ContactContextMenu({
    required this.canSend,
    required this.onEdit,
    required this.onCopy,
    required this.onSend,
    required this.onRemove,
  });

  final bool canSend;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onSend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppContextMenu(
      children: [
        AppContextMenuItem(
          iconName: AppIcons.scroll,
          label: 'Edit contact',
          onTap: onEdit,
        ),
        if (canSend) ...[
          const SizedBox(height: AppSpacing.xxs),
          AppContextMenuItem(
            iconName: AppIcons.plane,
            label: 'Send ZEC',
            onTap: onSend,
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.copy,
          label: 'Copy address',
          onTap: onCopy,
        ),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          iconName: AppIcons.trash,
          label: 'Remove contact',
          destructive: true,
          onTap: onRemove,
        ),
      ],
    );
  }
}

class _AddressBookNoContacts extends StatelessWidget {
  const _AddressBookNoContacts({required this.onAddContact});

  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 352,
        height: 460,
        child: Center(
          child: SizedBox(
            height: 286,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 76,
                  top: -21,
                  child: Image.asset(
                    _addressBookEmptyContactsAsset(context),
                    width: 200,
                    height: 175,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  left: 48,
                  top: 186,
                  child: SizedBox(
                    width: 256,
                    child: Column(
                      children: [
                        Text(
                          'No contacts yet',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineSmall.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Add your first contact to get started.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: context.colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 48,
                  top: 263,
                  child: _AddressBookAddButton(onPressed: onAddContact),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 286,
      child: Stack(
        children: [
          Positioned(
            left: 106,
            top: 42.5,
            child: Image.asset(
              _addressBookEmptySearchAsset(context),
              width: 140,
              height: 140,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: 48,
            top: 198.5,
            child: SizedBox(
              width: 256,
              child: Column(
                children: [
                  Text(
                    'No contacts found',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Try a different search',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBookAddButton extends StatelessWidget {
  const _AddressBookAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('address_book_add_contact_button'),
      onPressed: onPressed,
      variant: AppButtonVariant.secondary,
      minWidth: 256,
      leading: const AppIcon(AppIcons.users),
      child: const Text('Add contact'),
    );
  }
}

class _ContactFormModal extends StatefulWidget {
  const _ContactFormModal({
    required this.draft,
    required this.editing,
    required this.submitError,
    required this.onChanged,
    required this.onAvatarPressed,
    required this.onNetworkPressed,
    required this.onScanAddress,
    required this.onCancel,
    required this.onSubmit,
  });

  final _ContactDraft draft;
  final bool editing;
  final String? submitError;
  final ValueChanged<_ContactDraft> onChanged;
  final VoidCallback onAvatarPressed;
  final VoidCallback onNetworkPressed;
  final VoidCallback onScanAddress;
  final VoidCallback onCancel;
  final Future<void> Function() onSubmit;

  @override
  State<_ContactFormModal> createState() => _ContactFormModalState();
}

class _ContactFormModalState extends State<_ContactFormModal> {
  late final TextEditingController _labelController;
  late final TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.draft.label);
    _addressController = TextEditingController(text: widget.draft.address);
  }

  @override
  void didUpdateWidget(covariant _ContactFormModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_labelController, widget.draft.label);
    _syncController(_addressController, widget.draft.address);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  void _emitLabel(String label) {
    widget.onChanged(widget.draft.copyWith(label: label));
  }

  void _clearLabel() {
    _labelController.clear();
    _emitLabel('');
  }

  void _emitAddress(String address) {
    widget.onChanged(widget.draft.copyWith(address: address));
  }

  @override
  Widget build(BuildContext context) {
    final labelError = validateAddressBookLabel(widget.draft.label);
    final addressError = validateAddressBookAddress(widget.draft.address);
    final showLabelError =
        widget.draft.label.trim().length > 20 || widget.submitError != null;
    final showAddressError =
        widget.draft.address.trim().isEmpty &&
        _addressController.text.trim().isNotEmpty;
    // Soft warning: surface a chain format mismatch without blocking save.
    final addressFormatWarning = addressFormatIssue(
      widget.draft.network,
      widget.draft.address,
    );
    final addressMessage = showAddressError ? addressError : addressFormatWarning;
    final addressHasIssue = showAddressError || addressFormatWarning != null;

    return _AddressBookModalCard(
      header: _EditableContactAvatar(
        profilePictureId: widget.draft.profilePictureId,
        onPressed: widget.onAvatarPressed,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.editing ? 66 : 86,
            child: AppTextField(
              key: const ValueKey('address_book_contact_label_field'),
              label: 'Label',
              showLabel: !widget.editing,
              controller: _labelController,
              hintText: 'Add a label (1-20 characters)',
              trailing: widget.editing
                  ? _IconButtonLike(
                      semanticLabel: 'Clear contact label',
                      onTap: _clearLabel,
                      child: const AppIcon(AppIcons.cross),
                    )
                  : null,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              messageText:
                  widget.submitError ?? (showLabelError ? labelError : null),
              tone: (widget.submitError != null || showLabelError)
                  ? AppTextFieldTone.destructive
                  : AppTextFieldTone.neutral,
              onChanged: _emitLabel,
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _ChainAddressSelector(
            network: widget.draft.network,
            onPressed: widget.onNetworkPressed,
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: 66,
            child: AppTextField(
              key: const ValueKey('address_book_contact_address_field'),
              label: 'Address',
              showLabel: false,
              controller: _addressController,
              hintText: 'Add address',
              trailing: _IconButtonLike(
                semanticLabel: 'Scan address QR',
                onTap: widget.onScanAddress,
                child: const AppIcon(AppIcons.qr),
              ),
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
              messageText: addressMessage,
              tone: addressHasIssue
                  ? AppTextFieldTone.destructive
                  : AppTextFieldTone.neutral,
              onChanged: _emitAddress,
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('address_book_contact_submit_button'),
            onPressed: widget.draft.isValid
                ? () => unawaited(widget.onSubmit())
                : null,
            variant: AppButtonVariant.primary,
            minWidth: 280,
            child: Text(widget.editing ? 'Save changes' : 'Add contact'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: widget.onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: 280,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _EditableContactAvatar extends StatelessWidget {
  const _EditableContactAvatar({
    required this.profilePictureId,
    required this.onPressed,
  });

  final String profilePictureId;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _IconButtonLike(
      semanticLabel: 'Change contact picture',
      onTap: onPressed,
      child: SizedBox(
        width: 62,
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AppProfilePicture(
              profilePictureId: profilePictureId,
              size: AppProfilePictureSize.xLarge,
            ),
            Positioned(
              right: 0,
              bottom: -3,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: context.colors.background.inverse,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.edit,
                    size: AppIconSize.medium,
                    color: context.colors.icon.inverse,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainAddressSelector extends StatelessWidget {
  const _ChainAddressSelector({required this.network, required this.onPressed});

  final AddressBookNetwork network;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs),
              child: Text(
                'Chain & address',
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
          _IconButtonLike(
            key: const ValueKey('address_book_network_selector_button'),
            semanticLabel: 'Select network',
            onTap: onPressed,
            child: Container(
              height: 26,
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xxs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NetworkAssetIcon(network: network, size: 16),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    network.label,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  AppIcon(
                    AppIcons.chevronForward,
                    size: AppIconSize.medium,
                    color: colors.icon.regular,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactAvatarPickerModal extends StatefulWidget {
  const _ContactAvatarPickerModal({
    required this.selectedProfilePictureId,
    required this.onSelected,
    required this.onCancel,
  });

  final String selectedProfilePictureId;
  final ValueChanged<String> onSelected;
  final VoidCallback onCancel;

  @override
  State<_ContactAvatarPickerModal> createState() =>
      _ContactAvatarPickerModalState();
}

class _ContactAvatarPickerModalState extends State<_ContactAvatarPickerModal> {
  late String _selectedProfilePictureId;

  @override
  void initState() {
    super.initState();
    _selectedProfilePictureId = widget.selectedProfilePictureId;
  }

  @override
  void didUpdateWidget(covariant _ContactAvatarPickerModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProfilePictureId != widget.selectedProfilePictureId) {
      _selectedProfilePictureId = widget.selectedProfilePictureId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = resolveProfilePictureOption(_selectedProfilePictureId);
    final original = resolveProfilePictureOption(
      widget.selectedProfilePictureId,
    );
    final hasChanged = selected.id != original.id;

    return _AddressBookModalCard(
      gap: AppSpacing.sm,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppProfilePicture(
            profilePictureId: selected.id,
            size: AppProfilePictureSize.xLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'New contact',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 184,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final option in kProfilePictureOptions)
                    _ProfilePictureChoice(
                      key: ValueKey('address_book_avatar_${option.id}'),
                      option: option,
                      selected: option.id == selected.id,
                      onSelected: (id) {
                        setState(() => _selectedProfilePictureId = id);
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: hasChanged ? () => widget.onSelected(selected.id) : null,
            variant: AppButtonVariant.primary,
            minWidth: 280,
            child: const Text('Use this picture'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: widget.onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: 280,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _ProfilePictureChoice extends StatelessWidget {
  const _ProfilePictureChoice({
    required this.option,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ProfilePictureOption option;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _IconButtonLike(
      semanticLabel: option.label,
      onTap: () => onSelected(option.id),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AppProfilePicture(
              profilePictureId: option.id,
              size: AppProfilePictureSize.large,
            ),
            if (selected)
              Positioned(
                right: -3,
                bottom: -1,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.check,
                          size: 12,
                          color: colors.background.ground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NetworkSelectorModal extends StatefulWidget {
  const _NetworkSelectorModal({
    required this.selectedNetwork,
    required this.onSelected,
    required this.onCancel,
  });

  final AddressBookNetwork selectedNetwork;
  final ValueChanged<AddressBookNetwork> onSelected;
  final VoidCallback onCancel;

  @override
  State<_NetworkSelectorModal> createState() => _NetworkSelectorModalState();
}

class _NetworkSelectorModalState extends State<_NetworkSelectorModal> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final options = [
      for (final network in AddressBookNetwork.values)
        if (query.isEmpty ||
            network.id.toLowerCase().contains(query) ||
            network.label.toLowerCase().contains(query))
          network,
    ];

    return _AddressBookModalCard(
      gap: AppSpacing.xs,
      header: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.colors.background.base,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: AppIcon(
                AppIcons.link,
                size: AppIconSize.medium,
                color: context.colors.icon.regular,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Select network',
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              key: const ValueKey('address_book_network_search_field'),
              label: 'Search',
              showLabel: false,
              controller: _queryController,
              autofocus: true,
              hintText: 'Search network',
              leading: const AppIcon(AppIcons.search),
              leadingSlotWidth: 40,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.xs,
              showClearButton: true,
              clearButtonRequiresText: false,
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 230,
              child: options.isEmpty
                  ? const _NetworkSelectorEmptyResult()
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final network in options)
                          _NetworkSelectorRow(
                            network: network,
                            selected: network == widget.selectedNetwork,
                            onSelected: widget.onSelected,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              onPressed: widget.onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 280,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkSelectorEmptyResult extends StatelessWidget {
  const _NetworkSelectorEmptyResult();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 112,
        child: Text(
          'No networks found',
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class _NetworkSelectorRow extends StatelessWidget {
  const _NetworkSelectorRow({
    required this.network,
    required this.selected,
    required this.onSelected,
  });

  final AddressBookNetwork network;
  final bool selected;
  final ValueChanged<AddressBookNetwork> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _IconButtonLike(
      semanticLabel: network.label,
      onTap: () => onSelected(network),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? colors.background.base : null,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Row(
          children: [
            _NetworkAssetIcon(network: network, size: 32),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                network.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveContactModal extends StatelessWidget {
  const _RemoveContactModal({
    required this.contact,
    required this.submitError,
    required this.onCancel,
    required this.onRemove,
  });

  final AddressBookContact? contact;
  final String? submitError;
  final VoidCallback onCancel;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final contact = this.contact;
    return _AddressBookModalCard(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppProfilePicture(
            profilePictureId: contact?.profilePictureId ?? 'chest',
            size: AppProfilePictureSize.xLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Remove contact',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            contact == null
                ? 'This contact will be removed.'
                : '${contact.label} will be removed from your address book.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          if (submitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: () => unawaited(onRemove()),
            variant: AppButtonVariant.destructive,
            minWidth: 280,
            child: const Text('Remove contact'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: 280,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _AddressBookModalCard extends StatelessWidget {
  const _AddressBookModalCard({
    required this.header,
    required this.child,
    this.gap = AppSpacing.md,
  });

  final Widget header;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

class _NetworkAssetIcon extends StatelessWidget {
  const _NetworkAssetIcon({required this.network, required this.size});

  final AddressBookNetwork network;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AddressBookNetworkIcon(network: network, size: size);
  }
}

class _IconButtonLike extends StatelessWidget {
  const _IconButtonLike({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _AddressBookError extends StatelessWidget {
  const _AddressBookError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        "Couldn't load your address book. "
        'Try again, or contact support if this keeps happening.',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.destructive,
        ),
      ),
    );
  }
}

String _addressBookEmptyContactsAsset(BuildContext context) {
  return AppTheme.of(context) == AppThemeData.dark
      ? 'assets/illustrations/address_book_empty_contacts_dark.png'
      : 'assets/illustrations/address_book_empty_contacts_light.png';
}

String _addressBookEmptySearchAsset(BuildContext context) {
  return AppTheme.of(context) == AppThemeData.dark
      ? 'assets/illustrations/address_book_empty_search_dark.png'
      : 'assets/illustrations/address_book_empty_search_light.png';
}
