// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/config/swap_feature_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_context_menu.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_modal_card.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/core/widgets/app_profile_picture_picker_modal.dart';
import '../src/core/widgets/app_tappable.dart';
import '../src/core/widgets/app_text_field.dart';
import '../src/core/widgets/mobile_text_field.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/address_book/screens/address_book_screen.dart';
import '../src/features/address_book/screens/mobile/mobile_address_book_screen.dart';
import '../src/features/address_book/widgets/address_book_contact_picker_modal.dart';
import '../src/features/address_book/widgets/address_book_network_icon.dart';
import '../src/features/address_book/widgets/contact_name_inline.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/sync_provider.dart';
import 'support/wb_layout.dart';

Widget buildAddressBookContactsListUseCase(BuildContext context) {
  return const _AddressBookFrame(contentState: _AddressBookContentState.list);
}

Widget buildAddressBookSolanaMenuUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.listSolanaMenu,
  );
}

Widget buildAddressBookNoContactsUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.noContacts,
  );
}

Widget buildAddressBookEmptySearchUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.emptySearch,
  );
}

Widget buildAddressBookAddContactModalUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.addContact,
  );
}

Widget buildAddressBookAvatarModalUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.avatarPicker,
  );
}

Widget buildAddressBookNetworkModalUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.networkSelector,
  );
}

Widget buildAddressBookNetworkModalEmptyUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.networkSelectorEmpty,
  );
}

Widget buildAddressBookEditContactModalUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.editContact,
  );
}

Widget buildAddressBookRemoveContactModalUseCase(BuildContext context) {
  return const _AddressBookFrame(
    contentState: _AddressBookContentState.list,
    modalState: _AddressBookModalState.removeContact,
  );
}

Widget buildMobileContactsListUseCase(BuildContext context) {
  return _mobileContactsPreview(
    const AddressBookState(contacts: _mobileContacts),
  );
}

Widget buildMobileContactsNoContactsUseCase(BuildContext context) {
  return _mobileContactsPreview(const AddressBookState());
}

Widget buildMobileContactsEmptySearchUseCase(BuildContext context) {
  return _mobileContactsPreview(
    const AddressBookState(contacts: _mobileContacts, query: 'zzzz'),
  );
}

Widget buildAddressBookContactPickerModalUseCase(BuildContext context) {
  return addressBookContactPickerFixture();
}

enum _AddressBookContentState { list, listSolanaMenu, noContacts, emptySearch }

enum _AddressBookModalState {
  addContact,
  avatarPicker,
  networkSelector,
  networkSelectorEmpty,
  editContact,
  removeContact,
}

const _addressBookContacts = <_AddressBookContact>[
  _AddressBookContact(
    name: 'Mike',
    addressPreview: 'u12345 ... 12345',
    profilePictureId: 'pfp-01',
    network: _AddressBookNetwork.zcash,
  ),
  _AddressBookContact(
    name: 'John',
    addressPreview: 'u12345 ... 12345',
    profilePictureId: 'pfp-02',
    network: _AddressBookNetwork.zcash,
  ),
  _AddressBookContact(
    name: 'Bob',
    addressPreview: 'u12345 ... 12345',
    profilePictureId: 'pfp-03',
    network: _AddressBookNetwork.zcash,
  ),
  _AddressBookContact(
    name: 'Mike SOL',
    addressPreview: '43123 ... 43123',
    profilePictureId: 'pfp-06',
    network: _AddressBookNetwork.solana,
  ),
  _AddressBookContact(
    name: 'Solana Binance',
    addressPreview: '43123 ... 43123',
    profilePictureId: 'pfp-08',
    network: _AddressBookNetwork.solana,
  ),
];

const _pickerContacts = <AddressBookContact>[
  AddressBookContact(
    id: 'widgetbook_picker_mike',
    label: 'Mike',
    network: AddressBookNetwork.ethereum,
    address: '0x1234567890abcdef1234567890abcdef12345678',
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'widgetbook_picker_john',
    label: 'John',
    network: AddressBookNetwork.ethereum,
    address: '0xabcdef1234567890abcdef1234567890abcdef12',
    profilePictureId: 'pfp-02',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
  AddressBookContact(
    id: 'widgetbook_picker_zcash',
    label: 'Zcash Contact',
    network: AddressBookNetwork.zcash,
    address: 'u1234567890abcdef1234567890abcdef1234567890abcdef',
    profilePictureId: 'pfp-03',
    createdAtMs: 3,
    updatedAtMs: 3,
  ),
];

class _AddressBookContact {
  const _AddressBookContact({
    required this.name,
    required this.addressPreview,
    required this.profilePictureId,
    required this.network,
  });

  final String name;
  final String addressPreview;
  final String profilePictureId;
  final _AddressBookNetwork network;
}

enum _AddressBookNetwork {
  zcash('Zcash', 'assets/swap/chains/zec.png'),
  solana('Solana', 'assets/swap/chains/sol.png'),
  ethereum('Ethereum', 'assets/swap/chains/eth.png'),
  base('Base', 'assets/swap/chains/base.png');

  const _AddressBookNetwork(this.label, this.assetPath);

  final String label;
  final String assetPath;
}

class _AddressBookFrame extends StatelessWidget {
  const _AddressBookFrame({required this.contentState, this.modalState});

  final _AddressBookContentState contentState;
  final _AddressBookModalState? modalState;

  bool get _showBottomAction =>
      contentState != _AddressBookContentState.noContacts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WbDesktopWindowBox(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1080.0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 720.0;

          return SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: colors.background.base,
              child: AppDesktopShell(
                sidebar: const _AddressBookSidebar(),
                pane: AppDesktopPane(
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: [
                      AppPaneScrollScaffold(
                        toolbar: const AppPaneToolbar(
                          leading: AppBackLink(
                            label: 'Settings',
                            minWidth: 60,
                            onTap: _noop,
                          ),
                        ),
                        padding: EdgeInsets.only(
                          top: AppSpacing.md,
                          bottom: _showBottomAction
                              ? _kFloatingAddContactMinOverlayHeight
                              : 0,
                        ),
                        child: _AddressBookPane(contentState: contentState),
                      ),
                      if (_showBottomAction)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          context
                                              .colors
                                              .macosUtility
                                              .windowTransparent,
                                          context.colors.macosUtility.window,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                constraints: const BoxConstraints(
                                  minHeight:
                                      _kFloatingAddContactMinOverlayHeight,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                alignment: Alignment.bottomCenter,
                                // Flat per the updated design — no shadow
                                // wrapper.
                                child: _AddressBookAddButton(onPressed: () {}),
                              ),
                            ],
                          ),
                        ),
                      if (modalState != null)
                        AppPaneModalOverlay(
                          onDismiss: () {},
                          child: _AddressBookModalPreview(state: modalState!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Minimum height of the floating add-contact overlay (gradient band + 36px
/// button with 16px vertical padding). Mirrors the real screen's
/// `_kFloatingAddContactMinOverlayHeight`.
const double _kFloatingAddContactMinOverlayHeight = 96;

class _AddressBookPane extends StatelessWidget {
  const _AddressBookPane({required this.contentState});

  final _AddressBookContentState contentState;

  bool get _hasContacts => contentState != _AddressBookContentState.noContacts;

  bool get _showEmptySearch =>
      contentState == _AddressBookContentState.emptySearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final wantsCenteredState = !_hasContacts || _showEmptySearch;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.minHeight;
        final centerStates = wantsCenteredState && viewportHeight > 0;

        Widget centeredState(Widget child) =>
            centerStates ? Expanded(child: Center(child: child)) : child;

        return SizedBox(
          height: centerStates ? viewportHeight : null,
          child: Column(
            children: [
              // Mirrors the real screen: the no-contacts state drops the page
              // title — its serif "No contacts yet" headline takes that role.
              if (_hasContacts) ...[
                Text(
                  'Contacts',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!_hasContacts)
                centeredState(const _AddressBookNoContacts())
              else ...[
                SizedBox(
                  width: 256,
                  child: _AddressBookSearchField(
                    value: _showEmptySearch ? 'Value' : null,
                    autofocus: _showEmptySearch,
                  ),
                ),
                if (_showEmptySearch)
                  centeredState(const _EmptySearchResult())
                else
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.base),
                    child: SizedBox(
                      width: 352,
                      child: _AddressBookContactsList(
                        initialOpenContactName:
                            contentState ==
                                _AddressBookContentState.listSolanaMenu
                            ? 'Mike SOL'
                            : null,
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

class _AddressBookContactsList extends StatelessWidget {
  const _AddressBookContactsList({this.initialOpenContactName});

  final String? initialOpenContactName;

  @override
  Widget build(BuildContext context) {
    // Non-scrolling: AppPaneScrollScaffold owns the single scroll surface.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContactGroup(
          network: _AddressBookNetwork.zcash,
          initialOpenContactName: initialOpenContactName,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ContactGroup(
          network: _AddressBookNetwork.solana,
          initialOpenContactName: initialOpenContactName,
        ),
      ],
    );
  }
}

class _WidgetbookContactMenuButton extends StatefulWidget {
  const _WidgetbookContactMenuButton({
    required this.contact,
    required this.initialOpen,
  });

  final _AddressBookContact contact;
  final bool initialOpen;

  @override
  State<_WidgetbookContactMenuButton> createState() =>
      _WidgetbookContactMenuButtonState();
}

class _WidgetbookContactMenuButtonState
    extends State<_WidgetbookContactMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menuEntry == null) _showMenu();
      });
    }
  }

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
                  network: widget.contact.network,
                  onAction: _hideMenu,
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
            label: '${widget.contact.name} actions',
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
    );
  }

  void _setHovered(bool value) {
    if (!mounted) return;
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }
}

class _AddressBookNoContacts extends StatelessWidget {
  const _AddressBookNoContacts();

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
        _AddressBookAddButton(onPressed: () {}, iconName: AppIcons.users),
      ],
    );
  }
}

class _AddressBookSearchField extends StatelessWidget {
  const _AddressBookSearchField({this.value, this.autofocus = false});

  final String? value;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: 'Search',
      showLabel: false,
      initialValue: value,
      hintText: 'Search for label or network',
      autofocus: autofocus,
      leading: const AppIcon(AppIcons.search),
      // Mirrors the real screen: 32px icon slot, 12px text inset, no idle
      // trailing slot so the placeholder fits without ellipsizing.
      leadingSlotWidth: 32,
      inputHorizontalPadding: AppSpacing.s,
      showClearButton: value != null,
      clearButtonRequiresText: false,
    );
  }
}

class _ContactGroup extends StatelessWidget {
  const _ContactGroup({
    required this.network,
    required this.initialOpenContactName,
  });

  final _AddressBookNetwork network;
  final String? initialOpenContactName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contacts = [
      for (final contact in _addressBookContacts)
        if (contact.network == network) contact,
    ];

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
              contact: contact,
              initialMenuOpen: initialOpenContactName == contact.name,
            ),
        ],
      ),
    );
  }
}

class _ContactGroupLabel extends StatelessWidget {
  const _ContactGroupLabel({required this.network});

  final _AddressBookNetwork network;

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
  const _ContactRow({required this.contact, required this.initialMenuOpen});

  final _AddressBookContact contact;
  final bool initialMenuOpen;

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
                  contact.name,
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
          _WidgetbookContactMenuButton(
            contact: contact,
            initialOpen: initialMenuOpen,
          ),
        ],
      ),
    );
  }
}

class _ContactContextMenu extends StatelessWidget {
  const _ContactContextMenu({required this.network, this.onAction = _noop});

  final _AddressBookNetwork network;
  final VoidCallback onAction;

  bool get _canSend => network == _AddressBookNetwork.zcash;

  @override
  Widget build(BuildContext context) {
    return AppContextMenu(
      children: [
        AppContextMenuItem(
          iconName: AppIcons.copy,
          label: 'Copy address',
          onTap: onAction,
        ),
        if (_canSend) ...[
          const SizedBox(height: AppSpacing.xxs),
          AppContextMenuItem(
            iconName: AppIcons.plane,
            label: 'Send ZEC',
            onTap: onAction,
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        AppContextMenuItem(
          iconName: AppIcons.scroll,
          label: 'Edit contact',
          onTap: onAction,
        ),
        const AppContextMenuDivider(),
        AppContextMenuItem(
          iconName: AppIcons.trash,
          label: 'Remove contact',
          destructive: true,
          onTap: onAction,
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

class _AddressBookModalPreview extends StatelessWidget {
  const _AddressBookModalPreview({required this.state});

  final _AddressBookModalState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      _AddressBookModalState.addContact => const _ContactFormModal(
        mode: _ContactFormMode.add,
      ),
      _AddressBookModalState.avatarPicker => const _ContactAvatarPickerModal(),
      _AddressBookModalState.networkSelector => const _NetworkSelectorModal(),
      _AddressBookModalState.networkSelectorEmpty =>
        const _NetworkSelectorModal(initialQuery: 'Value'),
      _AddressBookModalState.editContact => const _ContactFormModal(
        mode: _ContactFormMode.edit,
      ),
      _AddressBookModalState.removeContact => const _RemoveContactModal(),
    };
  }
}

enum _ContactFormMode { add, edit }

class _ContactFormModal extends StatelessWidget {
  const _ContactFormModal({required this.mode});

  final _ContactFormMode mode;

  bool get _isEdit => mode == _ContactFormMode.edit;

  @override
  Widget build(BuildContext context) {
    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EditableContactAvatar(
            profilePictureId: _isEdit ? 'pfp-08' : kDefaultProfilePictureId,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 86,
            child: AppTextField(
              label: 'Address label',
              initialValue: _isEdit ? 'Mike' : null,
              hintText: 'Add label 1-20 characters',
              trailing: _isEdit ? const AppIcon(AppIcons.cross) : null,
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const _ChainAddressSelector(),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: 66,
            child: AppTextField(
              label: 'Address',
              showLabel: false,
              initialValue: _isEdit ? 'u1x12adas3l512...31235129812' : null,
              hintText: 'Add address',
              trailing: const AppIcon(AppIcons.qr),
              trailingSlotWidth: 40,
              inputHorizontalPadding: AppSpacing.s,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppModalActions(
            cancelKey: const ValueKey('address_book_modal_cancel_button'),
            actionKey: const ValueKey('address_book_contact_submit_button'),
            onCancel: () {},
            actionLabel: _isEdit ? 'Update' : 'Add contact',
            onAction: _isEdit ? () {} : null,
          ),
        ],
      ),
    );
  }
}

class _EditableContactAvatar extends StatelessWidget {
  const _EditableContactAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

class _ChainAddressSelector extends StatelessWidget {
  const _ChainAddressSelector();

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
          Container(
            height: 26,
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              right: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _NetworkAssetIcon(
                  network: _AddressBookNetwork.zcash,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Zcash',
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
        ],
      ),
    );
  }
}

/// Legacy stand-in kept only for the existing builder contract; the real
/// picker is now reachable through `addressBookScreenFixture`.
class _ContactAvatarPickerModal extends StatelessWidget {
  const _ContactAvatarPickerModal();

  @override
  Widget build(BuildContext context) {
    // Mirrors the real screen's _ContactAvatarPickerModal which delegates to
    // AppProfilePicturePickerModal. Keys preserved for widgetbook fixture
    // consistency.
    return AppProfilePicturePickerModal(
      title: 'Select contact picture',
      currentProfilePictureId: kDefaultProfilePictureId,
      onCancel: () {},
      onUpdate: (_) async {},
      optionKeyPrefix: 'address_book_avatar_',
      cancelKey: const ValueKey('address_book_avatar_cancel_button'),
      actionKey: const ValueKey('address_book_avatar_update_button'),
    );
  }
}

class _NetworkSelectorModal extends StatefulWidget {
  const _NetworkSelectorModal({this.initialQuery = 'Eth'});

  final String initialQuery;

  @override
  State<_NetworkSelectorModal> createState() => _NetworkSelectorModalState();
}

class _NetworkSelectorModalState extends State<_NetworkSelectorModal> {
  /// List viewport height from the 312×440 modal spec: 440 − 24 top pad −
  /// 24 title − 16 title/field gap − 46 field − 24 field/list gap − 8 gap −
  /// 44 cancel − 16 bottom pad.
  static const double _listViewportHeight = 238;

  static const _options = <_NetworkSelectorOption>[
    _NetworkSelectorOption(
      label: 'Ethereum',
      network: _AddressBookNetwork.ethereum,
    ),
    _NetworkSelectorOption(
      label: 'Ethereum',
      network: _AddressBookNetwork.ethereum,
    ),
    _NetworkSelectorOption(label: 'Base', network: _AddressBookNetwork.base),
    _NetworkSelectorOption(
      label: 'Solana',
      network: _AddressBookNetwork.solana,
    ),
    _NetworkSelectorOption(label: 'Zcash', network: _AddressBookNetwork.zcash),
  ];

  final _listScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.initialQuery.trim().toLowerCase();
    final options = [
      for (final option in _options)
        if (query.isEmpty || option.label.toLowerCase().contains(query)) option,
    ];
    final listIsScrollable = options.length * 44.0 > _listViewportHeight;

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
            initialValue: widget.initialQuery,
            autofocus: true,
            leading: const AppIcon(AppIcons.search),
            leadingSlotWidth: 40,
            trailingSlotWidth: 40,
            inputHorizontalPadding: AppSpacing.xs,
            showClearButton: true,
            clearButtonRequiresText: false,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _listViewportHeight,
            child: options.isEmpty
                ? const _NetworkSelectorEmptyResult()
                : RawScrollbar(
                    key: const ValueKey('address_book_network_scrollbar'),
                    controller: _listScrollController,
                    thumbVisibility: listIsScrollable,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 6,
                    crossAxisMargin: 6,
                    thumbColor: context.colors.background.overlay,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 22),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView(
                          controller: _listScrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            for (
                              var index = 0;
                              index < options.length;
                              index += 1
                            )
                              _NetworkSelectorRow(
                                option: options[index],
                                selected: index == 0,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            onPressed: () {},
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

class _NetworkSelectorOption {
  const _NetworkSelectorOption({required this.label, required this.network});

  final String label;
  final _AddressBookNetwork network;
}

class _NetworkSelectorRow extends StatelessWidget {
  const _NetworkSelectorRow({required this.option, required this.selected});

  final _NetworkSelectorOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: selected ? colors.background.base : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          _NetworkAssetIcon(network: option.network, size: 32),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _RemoveContactModal extends StatelessWidget {
  const _RemoveContactModal();

  @override
  Widget build(BuildContext context) {
    return AppModalCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppProfilePicture(
            profilePictureId: 'pfp-01',
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
            'Mike will be removed from your contacts.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppModalActions(
            onCancel: () {},
            actionLabel: 'Remove',
            actionVariant: AppButtonVariant.destructive,
            onAction: () {},
          ),
        ],
      ),
    );
  }
}

class _NetworkAssetIcon extends StatelessWidget {
  const _NetworkAssetIcon({required this.network, required this.size});

  final _AddressBookNetwork network;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipOval(child: Image.asset(network.assetPath, fit: BoxFit.cover)),
    );
  }
}

class _AddressBookSidebar extends StatelessWidget {
  const _AddressBookSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Home',
                    iconName: AppIcons.home,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Pay',
                    iconName: AppIcons.paid,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Vote',
                    iconName: AppIcons.vote,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Contacts',
                    iconName: AppIcons.users,
                    active: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSuccess,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetbookAddressBookRepository implements AddressBookRepository {
  const _WidgetbookAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

void _noop() {}

// --- Mobile Contacts previews (Figma CONTACTS mobile frames) ---

const _mobileContacts = <AddressBookContact>[
  AddressBookContact(
    id: 'mobile_mike',
    label: 'Mike',
    network: AddressBookNetwork.zcash,
    address: 'u1234512345abcdef67890zyxwv',
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'mobile_john',
    label: 'John',
    network: AddressBookNetwork.zcash,
    address: 'u9876543210fedcba09876lkjhg',
    profilePictureId: 'pfp-02',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
  AddressBookContact(
    id: 'mobile_sol',
    label: 'Solana Binance',
    network: AddressBookNetwork.solana,
    address: '43123abc987def43123xyz0pqrs',
    profilePictureId: 'pfp-06',
    createdAtMs: 3,
    updatedAtMs: 3,
  ),
];

Widget _mobileContactsPreview(AddressBookState state) {
  return ProviderScope(
    overrides: [
      addressBookProvider.overrideWith(
        () => _PreviewAddressBookNotifier(state),
      ),
    ],
    // IgnorePointer keeps it a static gallery snapshot — the real screen's
    // back/send/add taps route through GoRouter, which the widgetbook host
    // doesn't provide.
    child: const _MobileContactsFrame(
      child: IgnorePointer(child: MobileAddressBookScreen()),
    ),
  );
}

class _PreviewAddressBookNotifier extends AddressBookNotifier {
  _PreviewAddressBookNotifier(this._state);

  final AddressBookState _state;

  @override
  Future<AddressBookState> build() async => _state;
}

class _MobileContactsFrame extends StatelessWidget {
  const _MobileContactsFrame({required this.child});

  final Widget child;

  static const _size = Size(393, 852);
  static const _safeArea = EdgeInsets.only(top: 55, bottom: 24);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Center(
      child: WbScaleDownBox(
        size: _size,
        child: SizedBox.fromSize(
          size: _size,
          child: ClipRect(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                size: _size,
                padding: _safeArea,
                viewPadding: _safeArea,
              ),
              child: child,
            ),
          ),
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

// --- Real AddressBookScreen (desktop) --------------------------------------
//
// The fixtures above are hand-built mirrors kept for their figma_compare
// scenarios; everything below renders the production `AddressBookScreen`
// (shell + sidebar + pane + private modals) driven only through provider
// overrides and production callbacks.

/// Contacts the preview provider is seeded with.
enum AddressBookScreenContacts { zcashOnly, mixedNetworks, allNetworks }

/// How the contacts provider resolves.
enum AddressBookScreenLoad {
  contacts,
  noContacts,
  noSearchResults,
  loading,
  failed,
}

/// Which production modal the fixture drives open.
enum AddressBookScreenModal {
  none,
  addContact,
  editContact,
  avatarPicker,
  networkSelector,
  removeContact,
}

/// Contact draft the form modal is seeded with, through the production
/// `onChanged` / network-selector callbacks (never by typing).
enum AddressBookScreenDraft {
  unchanged,
  labelTooLong,
  invalidAddress,
  addressAdvisory,
}

/// Profile picture the draft carries, chosen through the production picker.
enum AddressBookScreenAvatar { defaultPicture, pfp08, lastOption }

const String addressBookScreenZcashContactId = 'wb-contact-zec-mike';
const String addressBookScreenOtherNetworkContactId = 'wb-contact-sol-binance';
const double kWbAddressBookWindowWidth = 1080;

/// The production address book screen in a 1080×[windowHeight] desktop window.
///
/// Every state is reached the way the app reaches it: the provider decides the
/// pane, and the modals / row menu are opened by replaying the production
/// callbacks one per frame.
Widget addressBookScreenFixture({
  AddressBookScreenLoad load = AddressBookScreenLoad.contacts,
  AddressBookScreenContacts contacts = AddressBookScreenContacts.zcashOnly,
  AddressBookScreenModal modal = AddressBookScreenModal.none,
  AddressBookScreenDraft draft = AddressBookScreenDraft.unchanged,
  AddressBookScreenAvatar avatar = AddressBookScreenAvatar.defaultPicture,
  bool submitFails = false,
  String? openMenuForContactId,
  double windowHeight = 720,
}) {
  final seeded = _addressBookScreenContacts(contacts);
  final state = switch (load) {
    AddressBookScreenLoad.noContacts => const AddressBookState(),
    AddressBookScreenLoad.noSearchResults => AddressBookState(
      contacts: seeded,
      query: 'qqqq',
    ),
    _ => AddressBookState(contacts: seeded),
  };

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_addressBookScreenBootstrap),
      accountProvider.overrideWith(
        () => _WbAddressBookAccountNotifier(_addressBookScreenAccountState),
      ),
      syncProvider.overrideWith(
        () => _WbAddressBookSyncNotifier(
          SyncState(
            accountUuid: _addressBookScreenAccountState.activeAccountUuid,
            hasAccountScopedData: true,
            totalBalance: BigInt.from(1422300000),
          ),
        ),
      ),
      networkPrivacyProvider.overrideWith(
        _WbAddressBookNetworkPrivacyNotifier.new,
      ),
      // The screen mounts the real AppMainSidebar; without these four its
      // migration chain reaches SharedPreferences and lightwalletd.
      swapFeatureEnabledProvider.overrideWithValue(true),
      ironwoodPostMigrationStateProvider.overrideWith(
        (ref) => const IronwoodPostMigrationState.inactive(),
      ),
      ironwoodHomeMigrationPresentationProvider.overrideWithValue(
        const IronwoodHomeMigrationCtaState.hidden(),
      ),
      ironwoodMigrationCoordinatorProvider.overrideWith(
        _WbAddressBookMigrationCoordinator.new,
      ),
      addressBookProvider.overrideWith(
        () => _WbAddressBookNotifier(
          seed: state,
          loading: load == AddressBookScreenLoad.loading,
          failed: load == AddressBookScreenLoad.failed,
          failSubmit: submitFails,
        ),
      ),
    ],
    child: _WbAddressBookScreenFrame(
      windowHeight: windowHeight,
      steps: _addressBookScreenSteps(
        modal: modal,
        draft: draft,
        avatar: avatar,
        submitFails: submitFails,
        openMenuForContactId: openMenuForContactId,
      ),
    ),
  );
}

/// No migration for the address book preview — keeps the sidebar off the
/// coordinator's Rust refresh.
class _WbAddressBookMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

List<AddressBookContact> _addressBookScreenContacts(
  AddressBookScreenContacts contacts,
) {
  return switch (contacts) {
    AddressBookScreenContacts.zcashOnly => _wbZcashOnlyContacts,
    AddressBookScreenContacts.mixedNetworks => _wbMixedNetworkContacts,
    AddressBookScreenContacts.allNetworks => _wbAllNetworkContacts,
  };
}

const _wbZcashOnlyContacts = <AddressBookContact>[
  AddressBookContact(
    id: addressBookScreenZcashContactId,
    label: 'Mike',
    network: AddressBookNetwork.zcash,
    address: 'u1mike512345abcdef67890zyxwvutsrq',
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'wb-contact-zec-john',
    label: 'John',
    network: AddressBookNetwork.zcash,
    address: 'u1john43210fedcba09876lkjhgfedcb',
    profilePictureId: 'pfp-02',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
  AddressBookContact(
    id: 'wb-contact-zec-sarah',
    label: 'Sarah',
    network: AddressBookNetwork.zcash,
    address: 'u1sarah90210qwertyuiopasdfghjkl',
    profilePictureId: 'pfp-06',
    createdAtMs: 3,
    updatedAtMs: 3,
  ),
];

const _wbMixedNetworkContacts = <AddressBookContact>[
  ..._wbZcashOnlyContacts,
  AddressBookContact(
    id: 'wb-contact-eth-vault',
    label: 'Ethereum vault',
    network: AddressBookNetwork.ethereum,
    address: '0x52908400098527886E0F7030069857D2E4169EE7',
    profilePictureId: 'pfp-04',
    createdAtMs: 4,
    updatedAtMs: 4,
  ),
  AddressBookContact(
    id: addressBookScreenOtherNetworkContactId,
    label: 'Solana Binance',
    network: AddressBookNetwork.solana,
    address: '43123abc987def43123xyz0pqrsTUVWXyz12345678',
    profilePictureId: 'pfp-08',
    createdAtMs: 5,
    updatedAtMs: 5,
  ),
  AddressBookContact(
    id: 'wb-contact-near-payroll',
    label: 'NEAR payroll',
    network: AddressBookNetwork.near,
    address: 'payroll.near',
    profilePictureId: 'pfp-11',
    createdAtMs: 6,
    updatedAtMs: 6,
  ),
];

/// One contact per network, so the grouped list shows every group header.
final _wbAllNetworkContacts = <AddressBookContact>[
  for (final (index, network) in AddressBookNetwork.values.indexed)
    AddressBookContact(
      id: switch (network) {
        AddressBookNetwork.zcash => addressBookScreenZcashContactId,
        AddressBookNetwork.solana => addressBookScreenOtherNetworkContactId,
        _ => 'wb-contact-${network.id}',
      },
      label: '${network.label} wallet',
      network: network,
      address: '${network.id}1address0987654321abcdefghijklmn',
      profilePictureId:
          kProfilePictureOptions[index % kProfilePictureOptions.length].id,
      createdAtMs: index + 1,
      updatedAtMs: index + 1,
    ),
];

const _addressBookScreenAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'wb-address-book-account',
      name: 'Account Name',
      order: 0,
      isSeedAnchor: true,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'wb-address-book-account',
  activeAddress: 'u1widgetbookaddressbookaddress',
);

final _addressBookScreenBootstrap = AppBootstrapState(
  initialLocation: '/address-book',
  initialAccountState: _addressBookScreenAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

/// The screen sits under its own router: the sidebar reads `GoRouterState`,
/// the toolbar back link reads the route stack, and `Send ZEC` goes to
/// `/send` — none of which a bare `InheritedGoRouter` can answer.
class _WbAddressBookScreenFrame extends StatefulWidget {
  const _WbAddressBookScreenFrame({
    required this.windowHeight,
    required this.steps,
  });

  final double windowHeight;
  final List<_WbStep> steps;

  @override
  State<_WbAddressBookScreenFrame> createState() =>
      _WbAddressBookScreenFrameState();
}

class _WbAddressBookScreenFrameState extends State<_WbAddressBookScreenFrame> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/address-book',
      routes: [
        GoRoute(
          path: '/address-book',
          builder: (BuildContext context, GoRouterState state) =>
              _WbAddressBookDriver(
                steps: widget.steps,
                child: const AddressBookScreen(),
              ),
        ),
        for (final path in const [
          '/home',
          '/send',
          '/receive',
          '/activity',
          '/accounts',
          '/settings',
          '/swap',
          '/pay',
          '/voting',
        ])
          GoRoute(
            path: path,
            builder: (BuildContext context, GoRouterState state) =>
                const SizedBox.shrink(),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: WbDesktopWindowBox(
        size: Size(kWbAddressBookWindowWidth, widget.windowHeight),
        child: ColoredBox(
          color: context.colors.macosUtility.window,
          child: Router.withConfig(config: _router),
        ),
      ),
    );
  }
}

/// One replayed production callback. Returns false while its target is not in
/// the tree yet — the contacts provider resolves a frame or two after mount.
typedef _WbStep = bool Function();

/// Replays production callbacks, one per frame, to reach a state the screen
/// only enters through user input.
class _WbAddressBookDriver extends StatefulWidget {
  const _WbAddressBookDriver({required this.steps, required this.child});

  final List<_WbStep> steps;
  final Widget child;

  @override
  State<_WbAddressBookDriver> createState() => _WbAddressBookDriverState();
}

class _WbAddressBookDriverState extends State<_WbAddressBookDriver> {
  /// Frames one step may wait for its target; enough for the provider and the
  /// modal transitions, small enough to end a preview that cannot proceed.
  static const int _maxAttempts = 30;

  int _index = 0;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_index >= widget.steps.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.steps[_index]()) {
        _index += 1;
        _attempts = 0;
        _scheduleNext();
        return;
      }
      _attempts += 1;
      if (_attempts >= _maxAttempts) return;
      // The failed step changed nothing, so ask for the next frame explicitly.
      setState(() {});
      _scheduleNext();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

List<_WbStep> _addressBookScreenSteps({
  required AddressBookScreenModal modal,
  required AddressBookScreenDraft draft,
  required AddressBookScreenAvatar avatar,
  required bool submitFails,
  required String? openMenuForContactId,
}) {
  final steps = <_WbStep>[];

  if (openMenuForContactId != null) {
    steps.add(() => _wbTapKeyed(_wbContactMenuKey(openMenuForContactId)));
    return steps;
  }
  if (modal == AddressBookScreenModal.none) return steps;

  if (modal == AddressBookScreenModal.removeContact) {
    steps.add(
      () => _wbTapKeyed(_wbContactMenuKey(addressBookScreenZcashContactId)),
    );
    steps.add(() => _wbTapContextMenuItem('Remove contact'));
    if (submitFails) {
      steps.add(
        () =>
            _wbTapButton(const ValueKey('address_book_remove_confirm_button')),
      );
    }
    return steps;
  }

  if (modal == AddressBookScreenModal.editContact) {
    steps.add(
      () => _wbTapKeyed(_wbContactMenuKey(addressBookScreenZcashContactId)),
    );
    steps.add(() => _wbTapContextMenuItem('Edit contact'));
  } else {
    steps.add(
      () => _wbTapButton(const ValueKey('address_book_add_contact_button')),
    );
  }

  // The advisory tier only exists on NEAR, so the draft's network is switched
  // through the production selector before the address is seeded.
  if (draft == AddressBookScreenDraft.addressAdvisory) {
    steps.add(_wbOpenNetworkSelector);
    steps.add(() => _wbTapTappableLabelled(AddressBookNetwork.near.label));
  }
  final seeded = _wbDraftSeed(draft);
  if (seeded != null) {
    steps.add(
      () => _wbEmitText(
        const ValueKey('address_book_contact_label_field'),
        seeded.$1,
      ),
    );
    steps.add(
      () => _wbEmitText(
        const ValueKey('address_book_contact_address_field'),
        seeded.$2,
      ),
    );
  }

  final avatarId = _wbAvatarId(avatar);
  if (avatarId != null) {
    steps.add(_wbOpenAvatarPicker);
    steps.add(() => _wbTapKeyed(ValueKey('address_book_avatar_$avatarId')));
    steps.add(
      () => _wbTapButton(const ValueKey('address_book_avatar_update_button')),
    );
  }

  switch (modal) {
    case AddressBookScreenModal.avatarPicker:
      steps.add(_wbOpenAvatarPicker);
    case AddressBookScreenModal.networkSelector:
      steps.add(_wbOpenNetworkSelector);
    case _:
      break;
  }

  if (submitFails) {
    steps.add(
      () => _wbTapButton(const ValueKey('address_book_contact_submit_button')),
    );
  }
  return steps;
}

ValueKey<String> _wbContactMenuKey(String contactId) =>
    ValueKey('address_book_contact_menu_$contactId');

/// `(label, address)` the draft is seeded with, or null to leave it as opened.
(String, String)? _wbDraftSeed(AddressBookScreenDraft draft) {
  return switch (draft) {
    AddressBookScreenDraft.unchanged => null,
    AddressBookScreenDraft.labelTooLong => (
      'Twenty five characters!!!',
      'u1mike512345abcdef67890zyxwvutsrq',
    ),
    AddressBookScreenDraft.invalidAddress => ('Mike', '0xnothexatall'),
    AddressBookScreenDraft.addressAdvisory => ('Mike', 'alice'),
  };
}

String? _wbAvatarId(AddressBookScreenAvatar avatar) {
  return switch (avatar) {
    AddressBookScreenAvatar.defaultPicture => null,
    AddressBookScreenAvatar.pfp08 => 'pfp-08',
    AddressBookScreenAvatar.lastOption => kProfilePictureOptions.last.id,
  };
}

bool _wbOpenAvatarPicker() => _wbTapTappableLabelled('Change contact picture');

bool _wbOpenNetworkSelector() =>
    _wbTapKeyed(const ValueKey('address_book_network_selector_button'));

// --- Element-tree driver helpers -------------------------------------------
// The row menu lives in an OverlayEntry outside the fixture subtree, so the
// walk starts at the root element.

Element? _wbFindElement(bool Function(Widget widget) test) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (test(element.widget)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

T? _wbFindWidget<T extends Widget>(bool Function(T widget) test) {
  final element = _wbFindElement((widget) => widget is T && test(widget));
  return element?.widget as T?;
}

bool _wbTapButton(Key key) {
  final onPressed = _wbFindWidget<AppButton>(
    (widget) => widget.key == key,
  )?.onPressed;
  onPressed?.call();
  return onPressed != null;
}

bool _wbTapTappableLabelled(String semanticsLabel) {
  final onTap = _wbFindWidget<AppTappable>(
    (widget) => widget.semanticsLabel == semanticsLabel,
  )?.onTap;
  onTap?.call();
  return onTap != null;
}

bool _wbTapContextMenuItem(String label) {
  final item = _wbFindWidget<AppContextMenuItem>(
    (widget) => widget.label == label,
  );
  item?.onTap();
  return item != null;
}

bool _wbEmitText(Key key, String value) {
  final onChanged = _wbFindWidget<AppTextField>(
    (widget) => widget.key == key,
  )?.onChanged;
  onChanged?.call(value);
  return onChanged != null;
}

/// Invokes the tap handler nearest the widget keyed [key] — a descendant
/// detector for wrapper widgets, an ancestor one for keyed leaf containers.
bool _wbTapKeyed(Key key) {
  final element = _wbFindElement((widget) => widget.key == key);
  if (element == null) return false;

  GestureDetector? detector;
  void visitDown(Element child) {
    if (detector != null) return;
    final widget = child.widget;
    if (widget is GestureDetector && widget.onTap != null) {
      detector = widget;
      return;
    }
    child.visitChildren(visitDown);
  }

  element.visitChildren(visitDown);
  if (detector == null) {
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is GestureDetector && widget.onTap != null) {
        detector = widget;
        return false;
      }
      return true;
    });
  }
  detector?.onTap?.call();
  return detector != null;
}

// --- Preview notifiers -----------------------------------------------------

class _WbAddressBookNotifier extends AddressBookNotifier {
  _WbAddressBookNotifier({
    required this.seed,
    this.loading = false,
    this.failed = false,
    this.failSubmit = false,
  });

  final AddressBookState seed;
  final bool loading;
  final bool failed;
  final bool failSubmit;

  @override
  Future<AddressBookState> build() {
    if (loading) return Completer<AddressBookState>().future;
    if (failed) {
      return Future<AddressBookState>.error(
        StateError('Widgetbook preview: contacts could not be loaded'),
      );
    }
    return Future<AddressBookState>.value(seed);
  }

  // Writes never touch storage: they either fail (so the modal shows its
  // submit error) or succeed without changing the seeded list.
  @override
  Future<AddressBookContact> addContact({
    required String label,
    required AddressBookNetwork network,
    required String address,
    required String profilePictureId,
  }) async {
    if (failSubmit) throw StateError('Widgetbook preview: save failed');
    return AddressBookContact(
      id: 'wb-contact-new',
      label: label,
      network: network,
      address: address,
      profilePictureId: profilePictureId,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
  }

  @override
  Future<void> updateContact(
    String id, {
    required String label,
    required AddressBookNetwork network,
    required String address,
    required String profilePictureId,
  }) async {
    if (failSubmit) throw StateError('Widgetbook preview: save failed');
  }

  @override
  Future<void> removeContact(String id) async {
    if (failSubmit) throw StateError('Widgetbook preview: remove failed');
  }
}

class _WbAddressBookAccountNotifier extends AccountNotifier {
  _WbAddressBookAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _WbAddressBookSyncNotifier extends SyncNotifier {
  _WbAddressBookSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

class _WbAddressBookNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();

  @override
  Future<void> setTorEnabled(bool enabled) async {}
}

// --- Contact picker (parameterized) ----------------------------------------
//
// `buildAddressBookContactPickerModalUseCase` delegates to this helper with
// its defaults, so its render (and the figma_compare scenario bound to it) is
// unchanged.

/// Whether the seeded repository holds contacts on the picker's networks.
enum AddressBookPickerContacts { results, noResults }

/// How the contacts provider resolves under the picker.
enum AddressBookPickerAsync { loaded, loading, failed }

/// One network hides the per-row badge; more than one shows it.
enum AddressBookPickerNetworks { single, multiple }

/// Whether the picker's own search field carries a query.
enum AddressBookPickerQuery { empty, typed }

/// Query seeded into the picker's search field; matches one contact.
const String addressBookPickerTypedQuery = 'mike';

const Key _kAddressBookPickerSearchKey = ValueKey(
  'address_book_contact_picker_search',
);

const List<AddressBookNetwork> _addressBookPickerMultipleNetworks = [
  AddressBookNetwork.ethereum,
  AddressBookNetwork.zcash,
];

/// The production contact picker over a stub repository.
Widget addressBookContactPickerFixture({
  AddressBookPickerContacts contacts = AddressBookPickerContacts.results,
  AddressBookPickerAsync async = AddressBookPickerAsync.loaded,
  AddressBookPickerNetworks networks = AddressBookPickerNetworks.single,
  AddressBookPickerQuery query = AddressBookPickerQuery.empty,
}) {
  final seeded = contacts == AddressBookPickerContacts.results
      ? _pickerContacts
      : const <AddressBookContact>[];
  final picker = Center(
    child: AddressBookContactPickerModal(
      title: 'USDC recipients',
      networks: networks == AddressBookPickerNetworks.single
          ? const [AddressBookNetwork.ethereum]
          : _addressBookPickerMultipleNetworks,
      emptyTitle: 'No saved USDC recipients',
      onSelected: (_) {},
      onCancel: () {},
    ),
  );

  return ProviderScope(
    overrides: [
      addressBookRepositoryProvider.overrideWithValue(
        _WidgetbookAddressBookRepository(seeded),
      ),
      if (async != AddressBookPickerAsync.loaded)
        addressBookProvider.overrideWith(
          () => _WbAddressBookNotifier(
            seed: AddressBookState(contacts: seeded),
            loading: async == AddressBookPickerAsync.loading,
            failed: async == AddressBookPickerAsync.failed,
          ),
        ),
    ],
    child: query == AddressBookPickerQuery.empty
        ? picker
        : _WbAddressBookDriver(
            steps: [() => _wbSeedPickerQuery(addressBookPickerTypedQuery)],
            child: picker,
          ),
  );
}

/// Types into the picker's own search field through its controller, then
/// replays `onChanged` so the picker re-filters the way a keystroke does.
bool _wbSeedPickerQuery(String value) {
  final desktopField = _wbFindWidget<AppTextField>(
    (widget) => widget.key == _kAddressBookPickerSearchKey,
  );
  final desktopController = desktopField?.controller;
  if (desktopController != null) {
    desktopController.text = value;
    desktopField!.onChanged?.call(value);
    return true;
  }
  final mobileField = _wbFindWidget<MobileTextField>(
    (widget) => widget.fieldKey == _kAddressBookPickerSearchKey,
  );
  if (mobileField == null) return false;
  mobileField.controller.text = value;
  mobileField.onChanged?.call(value);
  return true;
}

// --- Real MobileAddressBookScreen ------------------------------------------

/// How the contacts provider resolves behind the mobile screen.
enum MobileAddressBookLoad {
  contacts,
  noContacts,
  noSearchResults,
  loading,
  failed,
}

/// Which production sheet the fixture drives open.
///
/// The row menu — and the edit / remove sheets behind it — are absent on
/// purpose: `_ContactRowMenuButton` inserts into `Overlay.of(rootOverlay:
/// true)`, and the widgetbook's root overlay sits above the theme addon's
/// `AppTheme`, so the menu's `AppContextMenuDivider` asserts. Only a change in
/// `lib/src` (or an `AppTheme` above the widgetbook navigator) can fix it.
enum MobileAddressBookOverlay { none, addContact, networkPicker }

/// The draft's network, chosen through the production picker sheet.
enum MobileAddressBookNetwork { zcash, solana }

/// Contact draft the add sheet is seeded with, through its own controllers
/// (never by typing).
enum MobileAddressBookDraft { asOpened, invalidAddress, typing }

const String mobileAddressBookZcashContactId = 'wb-mobile-contact-zec-mike';
const String mobileAddressBookOtherContactId = 'wb-mobile-contact-sol-binance';

/// The production mobile Contacts screen in a phone frame.
///
/// KNOWN APPROXIMATION: `showAppMobileSheet` presents with
/// `useRootNavigator: true`, so every sheet lands on the widgetbook's root
/// overlay and spans the whole canvas instead of the phone frame. Nothing can
/// scope that without changing `lib/src`. Root-overlay surfaces are outside
/// [WbScaleDownBox] too, so on a canvas short enough to scale the frame down
/// the sheet still paints at canvas scale.
Widget mobileAddressBookScreenFixture({
  MobileAddressBookLoad load = MobileAddressBookLoad.contacts,
  MobileAddressBookOverlay overlay = MobileAddressBookOverlay.none,
  MobileAddressBookNetwork network = MobileAddressBookNetwork.zcash,
  MobileAddressBookDraft draft = MobileAddressBookDraft.asOpened,
}) {
  final state = switch (load) {
    MobileAddressBookLoad.noContacts => const AddressBookState(),
    MobileAddressBookLoad.noSearchResults => const AddressBookState(
      contacts: _wbMobileContacts,
      query: 'qqqq',
    ),
    _ => const AddressBookState(contacts: _wbMobileContacts),
  };

  return ProviderScope(
    overrides: [
      addressBookProvider.overrideWith(
        () => _WbAddressBookNotifier(
          seed: state,
          loading: load == MobileAddressBookLoad.loading,
          failed: load == MobileAddressBookLoad.failed,
        ),
      ),
    ],
    child: _WbMobileAddressBookFrame(
      steps: _mobileAddressBookSteps(
        overlay: overlay,
        network: network,
        draft: draft,
      ),
    ),
  );
}

const _wbMobileContacts = <AddressBookContact>[
  AddressBookContact(
    id: mobileAddressBookZcashContactId,
    label: 'Mike',
    network: AddressBookNetwork.zcash,
    address: 'u1mike512345abcdef67890zyxwvutsrq',
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'wb-mobile-contact-zec-john',
    label: 'John',
    network: AddressBookNetwork.zcash,
    address: 'u1john43210fedcba09876lkjhgfedcb',
    profilePictureId: 'pfp-02',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
  AddressBookContact(
    id: mobileAddressBookOtherContactId,
    label: 'Solana Binance',
    network: AddressBookNetwork.solana,
    address: '43123abc987def43123xyz0pqrsTUVWXyz12345678',
    profilePictureId: 'pfp-08',
    createdAtMs: 3,
    updatedAtMs: 3,
  ),
];

/// The screen pops back to the previous route and pushes `/send`, so it is
/// mounted on a detached two-page router rather than a bare scope.
class _WbMobileAddressBookFrame extends StatefulWidget {
  const _WbMobileAddressBookFrame({required this.steps});

  final List<_WbStep> steps;

  @override
  State<_WbMobileAddressBookFrame> createState() =>
      _WbMobileAddressBookFrameState();
}

class _WbMobileAddressBookFrameState extends State<_WbMobileAddressBookFrame> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/home/contacts',
      routes: [
        GoRoute(
          path: '/home',
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: 'contacts',
              builder: (BuildContext context, GoRouterState state) =>
                  _WbAddressBookDriver(
                    steps: widget.steps,
                    child: const MobileAddressBookScreen(),
                  ),
            ),
          ],
        ),
        GoRoute(
          path: '/send',
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WbFrame(
      layout: WbLayout.mobile,
      child: Router.withConfig(config: _router),
    );
  }
}

List<_WbStep> _mobileAddressBookSteps({
  required MobileAddressBookOverlay overlay,
  required MobileAddressBookNetwork network,
  required MobileAddressBookDraft draft,
}) {
  if (overlay == MobileAddressBookOverlay.none) return const [];

  final steps = <_WbStep>[_wbTapMobileAddContact];
  // The network is changed the way the user changes it: open the picker and
  // pick, which pops the sheet back to the add sheet.
  if (network != MobileAddressBookNetwork.zcash) {
    steps.add(_wbOpenMobileNetworkPicker);
    steps.add(() => _wbTapSemanticsButton(AddressBookNetwork.solana.label));
  }
  steps.addAll(_mobileAddressBookDraftSteps(draft));
  if (overlay == MobileAddressBookOverlay.networkPicker) {
    steps.add(_wbOpenMobileNetworkPicker);
  }
  return steps;
}

List<_WbStep> _mobileAddressBookDraftSteps(MobileAddressBookDraft draft) {
  return switch (draft) {
    MobileAddressBookDraft.asOpened => const [],
    MobileAddressBookDraft.invalidAddress => [
      () => _wbSeedMobileField(
        const ValueKey('mobile_address_book_address'),
        'not-a-valid-address',
      ),
    ],
    // The clear (x) affordance needs both text and focus.
    MobileAddressBookDraft.typing => [
      () => _wbSeedMobileField(
        const ValueKey('mobile_address_book_label'),
        'Mik',
        focus: true,
      ),
    ],
  };
}

/// The top-nav `+` when there are contacts, the centered CTA when there are
/// none.
bool _wbTapMobileAddContact() {
  return _wbTapKeyed(const ValueKey('mobile_contacts_add')) ||
      _wbTapButton(const ValueKey('mobile_contacts_add_empty'));
}

bool _wbOpenMobileNetworkPicker() =>
    _wbTapGestureKeyed(const ValueKey('mobile_address_book_network'));

bool _wbSeedMobileField(Key fieldKey, String value, {bool focus = false}) {
  final field = _wbFindWidget<MobileTextField>(
    (widget) => widget.fieldKey == fieldKey,
  );
  if (field == null) return false;
  field.controller.text = value;
  field.controller.selection = TextSelection.collapsed(offset: value.length);
  if (focus) field.focusNode.requestFocus();
  return true;
}

/// Taps a keyed [GestureDetector] itself — the network field is its own
/// detector, so [_wbTapKeyed]'s child/ancestor walk would miss it.
bool _wbTapGestureKeyed(Key key) {
  final detector = _wbFindWidget<GestureDetector>(
    (widget) => widget.key == key,
  );
  detector?.onTap?.call();
  return detector?.onTap != null;
}

/// Taps the detector under the semantics button labelled [label] — the picker
/// sheet's rows carry no keys.
bool _wbTapSemanticsButton(String label) {
  final element = _wbFindElement(
    (widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == label,
  );
  if (element == null) return false;

  GestureDetector? detector;
  void visit(Element child) {
    if (detector != null) return;
    final widget = child.widget;
    if (widget is GestureDetector && widget.onTap != null) {
      detector = widget;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  detector?.onTap?.call();
  return detector != null;
}

// --- Network icon ----------------------------------------------------------

/// The three sizes [AddressBookNetworkIcon] is called at in the app.
enum AddressBookNetworkIconSize { row, groupLabel, badge }

double addressBookNetworkIconSizeValue(AddressBookNetworkIconSize size) {
  return switch (size) {
    AddressBookNetworkIconSize.row => 24,
    AddressBookNetworkIconSize.groupLabel => 16,
    AddressBookNetworkIconSize.badge => 12,
  };
}

/// One production network icon, centred on the plain frame.
Widget addressBookNetworkIconFixture({
  AddressBookNetwork network = AddressBookNetwork.zcash,
  AddressBookNetworkIconSize size = AddressBookNetworkIconSize.row,
}) {
  return Center(
    child: AddressBookNetworkIcon(
      network: network,
      size: addressBookNetworkIconSizeValue(size),
    ),
  );
}

/// Every network asset at row size, so a missing or mis-cropped one shows.
Widget buildAddressBookNetworkIconGridUseCase(BuildContext context) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.base,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          for (final network in AddressBookNetwork.values)
            SizedBox(
              width: 120,
              child: Column(
                children: [
                  AddressBookNetworkIcon(network: network, size: 24),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    network.label,
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

// --- Contact name inline ---------------------------------------------------

/// Whether the inline name carries a compact address in parentheses.
enum ContactNameInlineAddress { none, compactAddress }

/// A name that fits the row, and one that has to ellipsize.
enum ContactNameInlineName { short, overflowing }

const String kContactNameInlineShortName = 'Rowan';
const String kContactNameInlineLongName =
    'Rowan from the very long contact list';

/// The production inline contact name in a row-width box, so the overflowing
/// name actually ellipsizes.
Widget contactNameInlineFixture({
  ContactNameInlineAddress address = ContactNameInlineAddress.none,
  ContactNameInlineName name = ContactNameInlineName.short,
}) {
  return Center(
    child: SizedBox(
      width: 200,
      child: ContactNameInline(
        name: name == ContactNameInlineName.short
            ? kContactNameInlineShortName
            : kContactNameInlineLongName,
        address: address == ContactNameInlineAddress.none
            ? null
            : '0x0cd7…7181',
      ),
    ),
  );
}
