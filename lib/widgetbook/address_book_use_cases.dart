// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../src/core/widgets/app_text_field.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/address_book/widgets/address_book_contact_picker_modal.dart';

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

Widget buildAddressBookContactPickerModalUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      addressBookRepositoryProvider.overrideWithValue(
        _WidgetbookAddressBookRepository(_pickerContacts),
      ),
    ],
    child: Center(
      child: AddressBookContactPickerModal(
        title: 'USDC recipients',
        networks: const [AddressBookNetwork.ethereum],
        emptyTitle: 'No saved USDC recipients',
        onSelected: (_) {},
        onCancel: () {},
      ),
    ),
  );
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
    return LayoutBuilder(
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
                                minHeight: _kFloatingAddContactMinOverlayHeight,
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
              Text(
                'Contacts',
                textAlign: TextAlign.center,
                style: AppTypography.headlineLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
                  size: 16,
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
            actionLabel: 'Remove contact',
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
    if (network == _AddressBookNetwork.zcash) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.colors.background.brandCrimsonStrong,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AppIcon(
            AppIcons.zcashCurrency,
            size: size * 0.62,
            color: context.colors.icon.onPrimary,
          ),
        ),
      );
    }

    final padding = size <= 16 ? 0.0 : 3.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Image.asset(network.assetPath, fit: BoxFit.cover),
      ),
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
