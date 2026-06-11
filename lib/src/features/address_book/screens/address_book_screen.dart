import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_context_menu.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_profile_picture_picker_modal.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../send/models/send_prefill_args.dart';
import '../../address_scan/widgets/address_qr_scan_modal.dart';
import '../models/address_book_contact.dart';
import '../models/address_format_validator.dart';
import '../providers/address_book_provider.dart';
import '../widgets/address_book_network_icon.dart';

/// Fixed content column width for the group cards (Figma contacts design).
const double _kContactsContentWidth = 352;

/// Width of the compact contacts search field (Figma updated design: 256×46,
/// narrower than the group cards).
const double _kContactsSearchFieldWidth = 256;

/// Minimum height of the floating add-contact overlay (Figma: the bottom
/// gradient band is min 96 tall with 16px vertical padding around the 36px
/// button), and the matching minimum scroll reserve. Mirrors the settings
/// endpoint floating-bar contract.
const double _kFloatingAddContactMinOverlayHeight = 96;

/// Breathing room between the last group card and the top of the floating
/// overlay once it grows past its minimum (matches the settings endpoint
/// floating-bar gap).
const double _kFloatingAddContactGap = 12;

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

  final _floatingButtonKey = GlobalKey();

  /// Latest measured height of the floating add-contact overlay (gradient
  /// band + button). Drives the scroll scaffold's reserved bottom padding so
  /// the last group card scrolls clear of the overlay.
  double _floatingButtonReserve = _kFloatingAddContactMinOverlayHeight;

  void _measureFloatingButton() {
    final box =
        _floatingButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final measured = box?.hasSize == true ? box!.size.height : null;
    if (measured == null) return;
    // Only rebuild when the value actually moves to avoid a layout feedback
    // loop.
    if ((measured - _floatingButtonReserve).abs() < 0.5) return;
    setState(() {
      _floatingButtonReserve = measured;
    });
  }

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
    // Loading keeps the previous pane (or the empty state) so the toolbar and
    // content stay stable; an error replaces the pane content only.
    final AddressBookState? paneState = contactsAsync.when(
      loading: () => contactsAsync.asData?.value ?? const AddressBookState(),
      error: (_, _) => null,
      data: (state) => state,
    );
    final showBottomAction = paneState?.hasContacts ?? false;

    if (showBottomAction) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _measureFloatingButton();
      });
    }

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            AppPaneScrollScaffold(
              toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
              padding: EdgeInsets.only(
                top: AppSpacing.md,
                // The minimum reserve matches the overlay's minimum height;
                // once the overlay grows past it the gap is added on top so
                // the last card never slides under the button.
                bottom: !showBottomAction
                    ? 0
                    : (_floatingButtonReserve <=
                              _kFloatingAddContactMinOverlayHeight
                          ? _kFloatingAddContactMinOverlayHeight
                          : _floatingButtonReserve + _kFloatingAddContactGap),
              ),
              child: paneState == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: _AddressBookError(),
                    )
                  : _AddressBookPane(
                      state: paneState,
                      onQueryChanged: (query) => ref
                          .read(addressBookProvider.notifier)
                          .setQuery(query),
                      onAddContact: _openAddContact,
                      onEditContact: _openEditContact,
                      onCopyAddress: _copyAddress,
                      onSendContact: _sendToContact,
                      onRemoveContact: _openRemoveContact,
                    ),
            ),
            if (showBottomAction)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Stack(
                  children: [
                    // Bottom fade so list content scrolling beneath the
                    // floating button dissolves into the window background
                    // (Figma: window-transparent -> window gradient band).
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                context.colors.macosUtility.windowTransparent,
                                context.colors.macosUtility.window,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      key: _floatingButtonKey,
                      constraints: const BoxConstraints(
                        minHeight: _kFloatingAddContactMinOverlayHeight,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      alignment: Alignment.bottomCenter,
                      // Flat per the updated design — no shadow wrapper.
                      child: _AddressBookAddButton(onPressed: _openAddContact),
                    ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showEmptySearch = state.hasContacts && state.filteredContacts.isEmpty;
    final wantsCenteredState = !state.hasContacts || showEmptySearch;

    return LayoutBuilder(
      builder: (context, constraints) {
        // AppPaneScrollScaffold lays the scroll child out with a minHeight
        // equal to the visible pane area below the toolbar band, so the empty
        // states can center in the real viewport instead of a fixed-height
        // box. minHeight is 0 when the pane height is unbounded (previews);
        // fall back to top flow there because Expanded needs a bounded height.
        final viewportHeight = constraints.minHeight;
        final centerStates = wantsCenteredState && viewportHeight > 0;

        Widget centeredState(Widget child) =>
            centerStates ? Expanded(child: Center(child: child)) : child;

        return SizedBox(
          height: centerStates ? viewportHeight : null,
          child: Column(
            children: [
              Text(
                'Contacts',
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!state.hasContacts)
                centeredState(
                  _AddressBookNoContacts(onAddContact: onAddContact),
                )
              else ...[
                SizedBox(
                  width: _kContactsSearchFieldWidth,
                  child: _AddressBookSearchField(
                    query: state.query,
                    onChanged: onQueryChanged,
                  ),
                ),
                if (state.filteredContacts.isEmpty)
                  centeredState(const _EmptySearchResult())
                else
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.base),
                    child: SizedBox(
                      width: _kContactsContentWidth,
                      child: _AddressBookContactsList(
                        contacts: state.filteredContacts,
                        onEditContact: onEditContact,
                        onCopyAddress: onCopyAddress,
                        onSendContact: onSendContact,
                        onRemoveContact: onRemoveContact,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
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
      hintText: 'Search for label or network',
      leading: const AppIcon(AppIcons.search),
      // Figma: 32px icon slot + 12px text inset, and no idle trailing slot —
      // the clear button claims its slot only when shown, so the full
      // placeholder fits the 256px field without ellipsizing.
      leadingSlotWidth: 32,
      inputHorizontalPadding: AppSpacing.s,
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

    // Non-scrolling: AppPaneScrollScaffold owns the pane's single scroll
    // surface, and the bottom scroll reserve comes from the scaffold padding.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
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
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Column(
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
      ),
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
          iconName: AppIcons.copy,
          label: 'Copy address',
          onTap: onCopy,
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
          iconName: AppIcons.scroll,
          label: 'Edit contact',
          onTap: onEdit,
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
    // Updated design: illustration (340×220) → 32 → serif headline + 4 →
    // subtitle (236 wide) → 32 → compact add button with the users icon.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          _addressBookEmptyContactsAsset(context),
          width: 340,
          height: 220,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'No contacts yet',
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          width: 236,
          child: Text(
            'Add your first contact to get started.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        _AddressBookAddButton(
          onPressed: onAddContact,
          iconName: AppIcons.users,
        ),
      ],
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult();

  @override
  Widget build(BuildContext context) {
    // Updated design: illustration (170×170) → 32 → sans-serif Headline S
    // title + 4 → subtitle (236 wide).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          _addressBookEmptySearchAsset(context),
          width: 170,
          height: 170,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: AppSpacing.base),
        Text(
          'No contacts were found',
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          width: 236,
          child: Text(
            'Try to modify your search',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact flat add-contact pill (updated design: h 36, min-w 96, no
/// shadow). The floating button and the empty-search flow use the default
/// plus-circle icon; the no-contacts empty state passes [AppIcons.users].
class _AddressBookAddButton extends StatelessWidget {
  const _AddressBookAddButton({
    required this.onPressed,
    this.iconName = AppIcons.addNew,
  });

  final VoidCallback onPressed;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('address_book_add_contact_button'),
      onPressed: onPressed,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.medium,
      height: 36,
      minWidth: 96,
      leading: AppIcon(iconName),
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
    // Soft check: surface a chain format finding without blocking save.
    // Error severity (cannot be valid) renders destructive; warning severity
    // (valid but unusual, e.g. a bare NEAR top-level name) renders neutral.
    final addressFormatFinding = addressFormatCheck(
      widget.draft.network,
      widget.draft.address,
    );
    final addressMessage = showAddressError
        ? addressError
        : addressFormatFinding?.message;
    final addressHasError =
        showAddressError ||
        addressFormatFinding?.severity == AddressFormatSeverity.error;

    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EditableContactAvatar(
            profilePictureId: widget.draft.profilePictureId,
            onPressed: widget.onAvatarPressed,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 86,
            child: AppTextField(
              key: const ValueKey('address_book_contact_label_field'),
              label: 'Address label',
              controller: _labelController,
              hintText: 'Add label 1-20 characters',
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
              tone: addressHasError
                  ? AppTextFieldTone.destructive
                  : AppTextFieldTone.neutral,
              onChanged: _emitAddress,
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppModalActions(
            cancelKey: const ValueKey('address_book_modal_cancel_button'),
            actionKey: const ValueKey('address_book_contact_submit_button'),
            onCancel: widget.onCancel,
            actionLabel: widget.editing ? 'Update' : 'Add contact',
            onAction: widget.draft.isValid
                ? () => unawaited(widget.onSubmit())
                : null,
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

/// Thin wrapper over the shared [AppProfilePicturePickerModal].
///
/// Selection is confirmed synchronously: `onUpdate` resolves immediately by
/// forwarding to [onSelected], which stores the id on the contact draft and
/// returns to the form. Keeps the established address-book keys
/// (`address_book_avatar_*`).
class _ContactAvatarPickerModal extends StatelessWidget {
  const _ContactAvatarPickerModal({
    required this.selectedProfilePictureId,
    required this.onSelected,
    required this.onCancel,
  });

  final String selectedProfilePictureId;
  final ValueChanged<String> onSelected;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicturePickerModal(
      title: 'Select contact picture',
      currentProfilePictureId: selectedProfilePictureId,
      onCancel: onCancel,
      onUpdate: (profilePictureId) async => onSelected(profilePictureId),
      optionKeyPrefix: 'address_book_avatar_',
      cancelKey: const ValueKey('address_book_avatar_cancel_button'),
      actionKey: const ValueKey('address_book_avatar_update_button'),
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
  /// List viewport height from the 312×440 modal spec: 440 − 24 top pad −
  /// 24 title − 16 title/field gap − 46 field − 24 field/list gap − 8 gap −
  /// 44 cancel − 16 bottom pad.
  static const double _listViewportHeight = 238;

  /// Fixed network row height; the scrollbar shows whenever the rows
  /// overflow the viewport.
  static const double _rowHeight = 44;

  final _queryController = TextEditingController();
  final _listScrollController = ScrollController();

  @override
  void dispose() {
    _queryController.dispose();
    _listScrollController.dispose();
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
    final listIsScrollable = options.length * _rowHeight > _listViewportHeight;

    return AppModalCard(
      bottomPadding: AppSpacing.sm,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Select network',
              style: AppTypography.bodyLarge.copyWith(
                color: context.colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
            height: _listViewportHeight,
            child: options.isEmpty
                ? const _NetworkSelectorEmptyResult()
                : RawScrollbar(
                    key: const ValueKey('address_book_network_scrollbar'),
                    controller: _listScrollController,
                    // Visible by default whenever the list overflows, so a
                    // cleanly-cut list still signals more content below.
                    thumbVisibility: listIsScrollable,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 6,
                    crossAxisMargin: 6,
                    thumbColor: context.colors.background.overlay,
                    child: Padding(
                      // List ends 4 + 18-wide scrollbar gutter short of the
                      // body's right edge.
                      padding: const EdgeInsets.only(right: 22),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView(
                          controller: _listScrollController,
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
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            onPressed: widget.onCancel,
            variant: AppButtonVariant.ghost,
            minWidth: 196,
            child: const Text('Cancel'),
          ),
        ],
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
    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppProfilePicture(
            profilePictureId: contact?.profilePictureId ?? 'pfp-08',
            size: AppProfilePictureSize.xLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Remove contact',
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            contact == null
                ? 'This contact will be removed.'
                : '${contact.label} will be removed from your contacts.',
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
          AppModalActions(
            cancelKey: const ValueKey('address_book_remove_cancel_button'),
            actionKey: const ValueKey('address_book_remove_confirm_button'),
            onCancel: onCancel,
            actionLabel: 'Remove contact',
            actionVariant: AppButtonVariant.destructive,
            onAction: () => unawaited(onRemove()),
          ),
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
        "Couldn't load your contacts. "
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
