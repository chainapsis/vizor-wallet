import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/profile_pictures.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_context_menu.dart';
import '../../../../core/widgets/app_copy_feedback.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_icon_hover_button.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../accounts/widgets/mobile/account_edit_sheets.dart'
    show MobileSheetCancel, showProfilePictureSheet;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import '../../models/address_book_contact.dart';
import '../../models/address_format_validator.dart';
import '../../providers/address_book_provider.dart';
import '../../widgets/address_book_network_icon.dart';

/// Mobile Contacts screen — Figma `CONTACTS` mobile frames (node 5032:83888).
///
/// Mirrors the desktop address book behavior (network-grouped contacts,
/// per-row Copy/Send/Edit/Remove menu, search, illustration empty states)
/// in the mobile idiom: a back-nav header with a `+` add affordance, a
/// full-width search field, ground surface cards per network, and bottom
/// sheets for add/edit/remove/network-pick.
///
/// Presented as a full-screen push over the tab shell (the bottom tab bar
/// is hidden), consistent with the other Settings detail screens. The
/// Figma frames render the tab bar for context; that is an intentional
/// deviation kept for routing/structural consistency.
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

  void _copyAddress(BuildContext context, AddressBookContact contact) {
    copyTextWithToast(
      context,
      text: contact.address,
      toastMessage: 'Address copied',
    );
  }

  void _sendToContact(BuildContext context, AddressBookContact contact) {
    // Mobile send takes the recipient address as a plain string via `extra`
    // (see mobile_routes.dart). Push so back returns to Contacts.
    context.push('/send', extra: contact.address);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final state =
        ref.watch(addressBookProvider).value ?? const AddressBookState();
    final hasContacts = state.hasContacts;
    final filtered = state.filteredContacts;

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        // bottom: false so the contact list scrolls to the physical bottom
        // edge; the list itself absorbs the bottom inset as scroll padding so
        // the last card clears the home indicator instead of ending above a
        // hard safe-area gap.
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.back(
                title: 'Contacts',
                onBack: () => context.pop(),
                // The Figma no-contacts frame has no top-nav add button (the
                // centered "Add contact" CTA covers it); the + appears only
                // once there are contacts (list + empty-search states).
                trailing: hasContacts
                    ? _TopNavAddButton(
                        onPressed: () => unawaited(_openEditor(context, ref)),
                      )
                    : null,
              ),
              Expanded(
                child: !hasContacts
                    ? _NoContactsState(
                        onAdd: () => unawaited(_openEditor(context, ref)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.sm,
                              AppSpacing.s,
                              AppSpacing.sm,
                              0,
                            ),
                            child: _ContactsSearchField(
                              query: state.query,
                              onChanged: (query) => ref
                                  .read(addressBookProvider.notifier)
                                  .setQuery(query),
                            ),
                          ),
                          Expanded(
                            child: filtered.isEmpty
                                ? const _EmptySearchState()
                                : _ContactsGroupedList(
                                    contacts: filtered,
                                    onCopy: (c) => _copyAddress(context, c),
                                    onSend: (c) => _sendToContact(context, c),
                                    onEdit: (c) => unawaited(
                                      _openEditor(context, ref, contact: c),
                                    ),
                                    onRemove: (c) => unawaited(
                                      _confirmRemove(context, ref, c),
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top-nav trailing `+` — a 44×44 secondary circle that opens the add
/// contact sheet (Figma `Mobile Top Nav` plus button).
class _TopNavAddButton extends StatelessWidget {
  const _TopNavAddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Add contact',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          key: const ValueKey('mobile_contacts_add'),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.button.secondary.bg,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              AppIcons.plus,
              size: 20,
              color: colors.button.secondary.label,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactsSearchField extends StatefulWidget {
  const _ContactsSearchField({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<_ContactsSearchField> createState() => _ContactsSearchFieldState();
}

class _ContactsSearchFieldState extends State<_ContactsSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.query,
  );
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _ContactsSearchField oldWidget) {
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

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    widget.onChanged('');
    setState(() {});
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The shared mobile input — same shell the swap modals and the contact
    // picker use (surface.input box, search glyph, inline clear button).
    return MobileTextField(
      fieldKey: const ValueKey('mobile_contacts_search_field'),
      controller: _controller,
      focusNode: _focusNode,
      hintText: 'Search for label or network',
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        widget.onChanged(value);
        setState(() {});
      },
      leading: SizedBox(
        width: AppInputSizing.iconWrapWidth,
        child: Align(
          alignment: Alignment.centerRight,
          child: AppIcon(
            AppIcons.search,
            size: AppInputSizing.iconSize,
            color: colors.icon.accent,
          ),
        ),
      ),
      trailing: _controller.text.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: AppIconHoverButton(
                semanticLabel: 'Clear search',
                icon: AppIcons.cross,
                onTap: _clear,
                size: 32,
                borderRadius: BorderRadius.circular(AppRadii.small),
                hoverColor: colors.background.ground,
                iconColor: colors.icon.regular,
              ),
            ),
    );
  }
}

/// Network-grouped surface cards (Figma `Surface Group`): one ground card
/// per network, each headed by the network label and listing its contacts.
class _ContactsGroupedList extends StatelessWidget {
  const _ContactsGroupedList({
    required this.contacts,
    required this.onCopy,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
  });

  final List<AddressBookContact> contacts;
  final ValueChanged<AddressBookContact> onCopy;
  final ValueChanged<AddressBookContact> onSend;
  final ValueChanged<AddressBookContact> onEdit;
  final ValueChanged<AddressBookContact> onRemove;

  @override
  Widget build(BuildContext context) {
    final groups = <Widget>[];
    for (final network in AddressBookNetwork.values) {
      final group = [
        for (final contact in contacts)
          if (contact.network == network) contact,
      ];
      if (group.isEmpty) continue;
      if (groups.isNotEmpty) {
        groups.add(const SizedBox(height: AppSpacing.md));
      }
      groups.add(
        _ContactGroupCard(
          network: network,
          contacts: group,
          onCopy: onCopy,
          onSend: onSend,
          onEdit: onEdit,
          onRemove: onRemove,
        ),
      );
    }

    // Absorb the bottom safe-area inset here (the screen uses SafeArea(bottom:
    // false)) so the list scrolls to the physical bottom edge while the last
    // card still clears the home indicator.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: groups,
      ),
    );
  }
}

class _ContactGroupCard extends StatelessWidget {
  const _ContactGroupCard({
    required this.network,
    required this.contacts,
    required this.onCopy,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
  });

  final AddressBookNetwork network;
  final List<AddressBookContact> contacts;
  final ValueChanged<AddressBookContact> onCopy;
  final ValueChanged<AddressBookContact> onSend;
  final ValueChanged<AddressBookContact> onEdit;
  final ValueChanged<AddressBookContact> onRemove;

  @override
  Widget build(BuildContext context) {
    // `for (final ...)` gives each row a fresh `contact` binding so the
    // action closures capture the right contact (a C-style index loop would
    // share one variable and every closure would see the last contact).
    final rows = <Widget>[];
    for (final contact in contacts) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppSpacing.s));
      }
      rows.add(
        _ContactRow(
          key: ValueKey('mobile_contact_row_${contact.id}'),
          contact: contact,
          onCopy: () => onCopy(contact),
          onSend: contact.network.canSendFromWallet
              ? () => onSend(contact)
              : null,
          onEdit: () => onEdit(contact),
          onRemove: () => onRemove(contact),
        ),
      );
    }

    // Figma `Surface`: ground card, radii/m (24), px16 py32, gap16 between
    // the network label and the contact rows.
    return MobileSurfaceCard(
      cornerRadius: AppRadii.large,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContactGroupLabel(network: network),
          const SizedBox(height: AppSpacing.sm),
          ...rows,
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        children: [
          AddressBookNetworkIcon(network: network, size: 16),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              network.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Figma `List Title`: Label M Medium (16) — mobile `labelLarge`.
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onCopy,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
    super.key,
  });

  final AddressBookContact contact;
  final VoidCallback onCopy;
  final VoidCallback? onSend;
  final VoidCallback onEdit;
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
          const SizedBox(width: AppSpacing.s),
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
                const SizedBox(height: AppSpacing.xxs / 2),
                Text(
                  contact.addressPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Figma `Asset Sub Text`: Label M Regular (16) — mobile
                  // `labelLarge` weighted down to regular.
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _ContactRowMenuButton(
            contact: contact,
            onCopy: onCopy,
            onSend: onSend,
            onEdit: onEdit,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}

/// The per-row `…` overflow button (Figma `Context Menu`): opens the dark
/// action popover anchored to the button's top-right, with the same
/// containment/auto-flip behavior as the desktop rows.
class _ContactRowMenuButton extends StatefulWidget {
  const _ContactRowMenuButton({
    required this.contact,
    required this.onCopy,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
  });

  final AddressBookContact contact;
  final VoidCallback onCopy;
  final VoidCallback? onSend;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  State<_ContactRowMenuButton> createState() => _ContactRowMenuButtonState();
}

class _ContactRowMenuButtonState extends State<_ContactRowMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;

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
              // Anchor the menu's top-right to the button's top-right so it
              // opens down-left under the dots (Figma `right-0`, `top-22`).
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 22),
              child: AppTheme(
                data: appTheme,
                child: _ContactContextMenu(
                  canSend: widget.onSend != null,
                  onCopy: _handleCopy,
                  onSend: _handleSend,
                  onEdit: _handleEdit,
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

  void _handleCopy() {
    _hideMenu();
    widget.onCopy();
  }

  void _handleSend() {
    _hideMenu();
    widget.onSend?.call();
  }

  void _handleEdit() {
    _hideMenu();
    widget.onEdit();
  }

  void _handleRemove() {
    _hideMenu();
    widget.onRemove();
  }

  @override
  Widget build(BuildContext context) {
    final active = _menuEntry != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleMenu,
      child: Semantics(
        button: true,
        label: '${widget.contact.label} actions',
        child: SizedBox(
          key: ValueKey('mobile_contact_menu_${widget.contact.id}'),
          width: 44,
          height: 44,
          child: Center(
            child: CompositedTransformTarget(
              link: _layerLink,
              child: Container(
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
      ),
    );
  }
}

class _ContactContextMenu extends StatelessWidget {
  const _ContactContextMenu({
    required this.canSend,
    required this.onCopy,
    required this.onSend,
    required this.onEdit,
    required this.onRemove,
  });

  final bool canSend;
  final VoidCallback onCopy;
  final VoidCallback onSend;
  final VoidCallback onEdit;
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

/// No-contacts empty state (Figma `Contacts Empty`): illustration, serif
/// headline, subtitle, and a centered add-contact button.
class _NoContactsState extends StatelessWidget {
  const _NoContactsState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // Center the illustration + text + CTA in the full available height (the
    // Figma `Contacts Empty` frame centers the block vertically), scrolling
    // only if it can't fit.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                _emptyContactsAsset(context),
                width: 280,
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
              AppButton(
                key: const ValueKey('mobile_contacts_add_empty'),
                onPressed: onAdd,
                variant: AppButtonVariant.secondary,
                minWidth: 163,
                leading: const AppIcon(AppIcons.users),
                child: const Text('Add contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty search-results state (Figma `Contacts Search Empty`).
class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    // Center in the full area below the search field (Figma `Contacts Search
    // Empty` centers the no-results block there).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                _emptySearchAsset(context),
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
          ),
        ),
      ),
    );
  }
}

String _emptyContactsAsset(BuildContext context) {
  return AppTheme.of(context) == AppThemeData.dark
      ? 'assets/illustrations/address_book_empty_contacts_dark.png'
      : 'assets/illustrations/address_book_empty_contacts_light.png';
}

String _emptySearchAsset(BuildContext context) {
  return AppTheme.of(context) == AppThemeData.dark
      ? 'assets/illustrations/address_book_empty_search_dark.png'
      : 'assets/illustrations/address_book_empty_search_light.png';
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

  @override
  void initState() {
    super.initState();
    // The clear (×) affordances and the Add-contact button enablement react to
    // focus and text, so rebuild whenever either changes.
    _labelFocus.addListener(_onFieldStateChanged);
    _addressFocus.addListener(_onFieldStateChanged);
    _labelController.addListener(_onFieldStateChanged);
    _addressController.addListener(_onFieldStateChanged);
  }

  void _onFieldStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _labelFocus.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  /// Minimal validation: a label plus a non-empty address whose format is
  /// plausible for the selected network (per [addressFormatIssue]).
  bool get _canSave {
    if (_labelController.text.trim().isEmpty) return false;
    final address = _addressController.text.trim();
    if (address.isEmpty) return false;
    return addressFormatIssue(_network, address) == null;
  }

  /// Live format error for the address field (null when empty or valid).
  String? get _addressError {
    final address = _addressController.text.trim();
    if (address.isEmpty) return null;
    return addressFormatIssue(_network, address);
  }

  Future<void> _pickNetwork() async {
    final picked = await showAppMobileSheet<AddressBookNetwork>(
      context: context,
      builder: (_) => _NetworkPickerSheet(selected: _network),
    );
    if (picked == null || !mounted) return;
    setState(() => _network = picked);
  }

  Future<void> _pickAvatar() async {
    final picked = await showProfilePictureSheet(
      context,
      selectedId: _profilePictureId,
    );
    if (picked == null || !mounted) return;
    setState(() => _profilePictureId = picked);
  }

  Future<void> _scanAddress() async {
    final scanned = await showAppMobileSheet<String>(
      context: context,
      builder: (sheetContext) => MobileAddressScanCard(
        resolve: (raw) async {
          final address = normalizeAddressScanPayload(raw);
          if (address == null || address.isEmpty) {
            return const MobileScanOutcome.rejected(
              'QR code did not include an address.',
            );
          }
          return MobileScanOutcome.accepted(address);
        },
        onScanned: (value) => Navigator.of(sheetContext).pop(value),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    );
    if (scanned == null || !mounted) return;
    _addressController.text = scanned;
    _addressController.selection = TextSelection.collapsed(
      offset: scanned.length,
    );
  }

  void _clearLabel() {
    _labelController.clear();
    _labelFocus.requestFocus();
  }

  void _clearAddress() {
    _addressController.clear();
    _addressFocus.requestFocus();
  }

  void _save() {
    if (!_canSave) return;
    Navigator.of(context).pop(
      _ContactDraft(
        label: _labelController.text.trim(),
        network: _network,
        address: _addressController.text.trim(),
        profilePictureId: _profilePictureId,
      ),
    );
  }

  Widget _fieldIcon(
    String icon,
    String label,
    VoidCallback onTap, {
    required Color iconColor,
  }) {
    return AppIconHoverButton(
      semanticLabel: label,
      icon: icon,
      onTap: onTap,
      size: 32,
      borderRadius: BorderRadius.circular(AppRadii.small),
      hoverColor: context.colors.background.ground,
      iconColor: iconColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEdit = widget.contact != null;
    final media = MediaQuery.of(context);
    // MobileModalScaffold lays its body out unbounded, so cap the scroll
    // area here: when a tall keyboard (e.g. Korean with its candidate bar)
    // is up, the form scrolls instead of overflowing the card. The card
    // already floats above the keyboard via MobileModalCard.
    final maxBodyHeight =
        (media.size.height - media.viewInsets.bottom - media.padding.top - 120)
            .clamp(240.0, 620.0)
            .toDouble();
    final addressError = _addressError;

    final nameClear = (_labelFocus.hasFocus && _labelController.text.isNotEmpty)
        ? _fieldIcon(
            AppIcons.cross,
            'Clear name',
            _clearLabel,
            iconColor: colors.icon.muted,
          )
        : null;
    final addressClear =
        (_addressFocus.hasFocus && _addressController.text.isNotEmpty)
        ? _fieldIcon(
            AppIcons.cross,
            'Clear address',
            _clearAddress,
            iconColor: colors.icon.muted,
          )
        : null;

    return MobileModalScaffold(
      // The title sits below the avatar (like the account edit sheet), so the
      // scaffold renders only the pinned close; the heading lives in the body.
      title: isEdit ? 'Edit contact' : 'Add contact',
      showTitle: false,
      onClose: () => Navigator.of(context).pop(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxBodyHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(
                isEdit ? 'Edit contact' : 'Add contact',
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
                            style: AppTypography.labelMedium.copyWith(
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
              MobileTextField(
                fieldKey: const ValueKey('mobile_address_book_label'),
                controller: _labelController,
                focusNode: _labelFocus,
                hintText: 'Add a name',
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _addressFocus.requestFocus(),
                trailing: nameClear == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: nameClear,
                      ),
              ),
              const SizedBox(height: AppSpacing.s),
              _FieldLabel('Address'),
              const SizedBox(height: AppSpacing.xxs),
              MobileTextField(
                fieldKey: const ValueKey('mobile_address_book_address'),
                controller: _addressController,
                focusNode: _addressFocus,
                hintText: 'Add an address',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (addressClear != null) ...[
                        addressClear,
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                      _fieldIcon(
                        AppIcons.qr,
                        'Scan address QR',
                        () => unawaited(_scanAddress()),
                        iconColor: colors.icon.accent,
                      ),
                    ],
                  ),
                ),
              ),
              if (addressError != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  addressError,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.destructive,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: const ValueKey('mobile_address_book_save'),
                expand: true,
                onPressed: _canSave ? _save : null,
                child: Text(isEdit ? 'Save contact' : 'Add contact'),
              ),
              const SizedBox(height: AppSpacing.s),
              MobileSheetCancel(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
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
    // Mirror the resting MobileTextField surface (surface.input fill, radius
    // 16, 60px tall, the layered subtle shadow) so the network selector
    // matches the Name / Address fields in the same form.
    return Container(
      height: AppInputSizing.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppInputSizing.radius),
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
    return MobileModalScaffold(
      title: 'Select network',
      onClose: () => Navigator.of(context).pop(),
      child: ConstrainedBox(
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
    );
  }
}

class _RemoveContactSheet extends StatelessWidget {
  const _RemoveContactSheet({required this.contact});

  final AddressBookContact contact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: 'Remove contact?',
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '"${contact.label}" will be removed from your contacts. '
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
