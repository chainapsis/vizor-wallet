import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import '../models/address_book_contact.dart';
import '../providers/address_book_provider.dart';
import 'address_book_network_icon.dart';

class AddressBookContactPickerModal extends ConsumerStatefulWidget {
  const AddressBookContactPickerModal({
    required this.title,
    required this.networks,
    required this.onSelected,
    required this.onCancel,
    this.emptyTitle = 'No contacts found',
    this.searchHint = 'Search contacts',
    super.key,
  });

  final String title;
  final List<AddressBookNetwork> networks;
  final ValueChanged<AddressBookContact> onSelected;
  final VoidCallback onCancel;
  final String emptyTitle;
  final String searchHint;

  @override
  ConsumerState<AddressBookContactPickerModal> createState() =>
      _AddressBookContactPickerModalState();
}

class _AddressBookContactPickerModalState
    extends ConsumerState<AddressBookContactPickerModal> {
  static const _modalSurfaceShadows = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 14), blurRadius: 28),
    BoxShadow(color: Color(0x08000000), offset: Offset(0, -6), blurRadius: 12),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocusNode = FocusNode(debugLabel: 'AddressBookContactPickerQuery');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queryFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  List<AddressBookContact> _filteredContacts(AddressBookState state) {
    final networks = widget.networks.toSet();
    if (networks.isEmpty) return const [];
    final query = _queryController.text.trim().toLowerCase();
    return [
      for (final contact in state.contacts)
        if (networks.contains(contact.network) &&
            (query.isEmpty ||
                contact.label.toLowerCase().contains(query) ||
                contact.address.toLowerCase().contains(query) ||
                contact.network.id.toLowerCase().contains(query) ||
                contact.network.label.toLowerCase().contains(query)))
          contact,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contactsAsync = ref.watch(addressBookProvider);

    return Container(
      key: const ValueKey('address_book_contact_picker_modal'),
      width: 312,
      height: 440,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        0,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _modalSurfaceShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ContactPickerIconButton(
                semanticLabel: 'Close contacts',
                iconName: AppIcons.cross,
                onTap: widget.onCancel,
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: AppTextField(
                      key: const ValueKey('address_book_contact_picker_search'),
                      label: 'Search',
                      showLabel: false,
                      controller: _queryController,
                      focusNode: _queryFocusNode,
                      hintText: widget.searchHint,
                      leading: const AppIcon(AppIcons.search),
                      leadingSlotWidth: AppInputSizing.iconWrapWidth,
                      trailingSlotWidth: 40,
                      inputHorizontalPadding: AppSpacing.s,
                      showClearButton: true,
                      onChanged: (_) => setState(() {}),
                      onClear: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: contactsAsync.when(
                      loading:
                          () => const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: AppIcon(AppIcons.loader, size: 18),
                            ),
                          ),
                      error:
                          (_, _) => const _ContactPickerEmptyResult(
                            title: "Couldn't load contacts. Try again.",
                          ),
                      data: (state) {
                        final contacts = _filteredContacts(state);
                        if (contacts.isEmpty) {
                          return _ContactPickerEmptyResult(
                            title: widget.emptyTitle,
                          );
                        }
                        return _ContactPickerList(
                          contacts: contacts,
                          showNetwork: widget.networks.length > 1,
                          onSelected: widget.onSelected,
                        );
                      },
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

class _ContactPickerList extends StatefulWidget {
  const _ContactPickerList({
    required this.contacts,
    required this.showNetwork,
    required this.onSelected,
  });

  final List<AddressBookContact> contacts;
  final bool showNetwork;
  final ValueChanged<AddressBookContact> onSelected;

  @override
  State<_ContactPickerList> createState() => _ContactPickerListState();
}

class _ContactPickerListState extends State<_ContactPickerList> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return RawScrollbar(
      key: const ValueKey('address_book_contact_picker_scrollbar'),
      controller: _scrollController,
      thumbVisibility: widget.contacts.length > 5,
      radius: const Radius.circular(AppRadii.full),
      thickness: 6,
      mainAxisMargin: 6,
      crossAxisMargin: 6,
      thumbColor: colors.background.overlay,
      child: Padding(
        key: const ValueKey('address_book_contact_picker_list_gutter'),
        padding: const EdgeInsets.only(right: 22),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.zero,
            itemCount: widget.contacts.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final contact = widget.contacts[index];
              return _ContactPickerRow(
                key: ValueKey(
                  'address_book_contact_picker_contact_${contact.id}',
                ),
                contact: contact,
                showNetwork: widget.showNetwork,
                onTap: () => widget.onSelected(contact),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ContactPickerIconButton extends StatefulWidget {
  const _ContactPickerIconButton({
    required this.semanticLabel,
    required this.iconName,
    required this.onTap,
  });

  final String semanticLabel;
  final String iconName;
  final VoidCallback onTap;

  @override
  State<_ContactPickerIconButton> createState() =>
      _ContactPickerIconButtonState();
}

class _ContactPickerIconButtonState extends State<_ContactPickerIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovered ? colors.background.ground : null,
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Center(
              child: AppIcon(
                widget.iconName,
                size: AppIconSize.medium,
                color: colors.icon.regular,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }
}

class _ContactPickerRow extends StatefulWidget {
  const _ContactPickerRow({
    required this.contact,
    required this.showNetwork,
    required this.onTap,
    super.key,
  });

  final AddressBookContact contact;
  final bool showNetwork;
  final VoidCallback onTap;

  @override
  State<_ContactPickerRow> createState() => _ContactPickerRowState();
}

class _ContactPickerRowState extends State<_ContactPickerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: _hovered ? colors.background.base : null,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            children: [
              AppProfilePicture(
                profilePictureId: widget.contact.profilePictureId,
                size: AppProfilePictureSize.large,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contact.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      widget.contact.addressPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showNetwork) ...[
                const SizedBox(width: AppSpacing.xs),
                AddressBookNetworkIcon(
                  network: widget.contact.network,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }
}

class _ContactPickerEmptyResult extends StatelessWidget {
  const _ContactPickerEmptyResult({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        key: const ValueKey('address_book_contact_picker_empty'),
        width: 160,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
