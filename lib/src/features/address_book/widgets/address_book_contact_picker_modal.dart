import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show TextInputAction;

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/mobile_text_field.dart';
import '../models/address_book_contact.dart';
import '../providers/address_book_provider.dart';
import 'address_book_network_icon.dart';

const double _contactPickerRowHeight = 44;
const double _contactPickerRowGap = AppSpacing.xs;
const int _contactPickerMobileVisibleRows = 6;
const double _contactPickerMobileMinListHeight =
    _contactPickerRowHeight * 5 + _contactPickerRowGap * 4; // 252
const double _contactPickerMobileMaxListHeight =
    _contactPickerRowHeight * _contactPickerMobileVisibleRows +
    _contactPickerRowGap * 5; // 304

class AddressBookContactPickerModal extends ConsumerStatefulWidget {
  const AddressBookContactPickerModal({
    required this.title,
    required this.networks,
    required this.onSelected,
    required this.onCancel,
    this.emptyTitle = 'No contacts found',
    this.searchHint = 'Search contacts',
    this.showCloseButton = true,
    super.key,
  });

  final String title;
  final List<AddressBookNetwork> networks;
  final ValueChanged<AddressBookContact> onSelected;
  final VoidCallback onCancel;
  final String emptyTitle;
  final String searchHint;
  final bool showCloseButton;

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

  double _mobileListHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    // Reserve the title, search field, inter-element gaps, and modal margins.
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.top - 260;
    return available
        .clamp(
          _contactPickerMobileMinListHeight,
          _contactPickerMobileMaxListHeight,
        )
        .toDouble();
  }

  void _clearQuery() {
    if (_queryController.text.isEmpty) return;
    setState(() => _queryController.clear());
    _queryFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contactsAsync = ref.watch(addressBookProvider);

    // On mobile the swap modal route wraps this in the shared
    // MobileModalCard (base surface, radius 32, bottom-anchored), so the
    // surface is full-width, draws no card, and the list scrolls within a
    // bounded height that the card hugs. Desktop keeps the fixed card.
    final isMobile = kAppFormFactor == AppFormFactor.mobile;
    final listHeight = isMobile ? _mobileListHeight(context) : null;
    final body = _pickerBody(
      isMobile: isMobile,
      listHeight: listHeight,
      contactsAsync: contactsAsync,
      searchTopInset: !isMobile,
    );

    if (isMobile) {
      return MobileModalScaffold(
        key: const ValueKey('address_book_contact_picker_modal'),
        title: widget.title,
        onClose: widget.onCancel,
        child: body,
      );
    }

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
        mainAxisSize: MainAxisSize.max,
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
              if (widget.showCloseButton) ...[
                const SizedBox(width: AppSpacing.xs),
                Builder(
                  builder: (context) => AppIconHoverButton(
                    semanticLabel: 'Close contacts',
                    icon: AppIcons.cross,
                    onTap: widget.onCancel,
                    size: 24,
                    borderRadius: BorderRadius.circular(AppRadii.xSmall),
                    hoverColor: context.colors.background.ground,
                    iconColor: context.colors.icon.regular,
                  ),
                ),
              ],
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickerBody({
    required bool isMobile,
    required double? listHeight,
    required AsyncValue<AddressBookState> contactsAsync,
    required bool searchTopInset,
  }) {
    final colors = context.colors;
    final searchField = isMobile
        ? MobileTextField(
            fieldKey: const ValueKey('address_book_contact_picker_search'),
            controller: _queryController,
            focusNode: _queryFocusNode,
            hintText: widget.searchHint,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
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
            trailing: _queryController.text.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: AppIconHoverButton(
                      semanticLabel: 'Clear search',
                      icon: AppIcons.cross,
                      onTap: _clearQuery,
                      size: 24,
                      borderRadius: BorderRadius.circular(AppRadii.xSmall),
                      hoverColor: colors.background.ground,
                      iconColor: colors.icon.regular,
                    ),
                  ),
          )
        : AppTextField(
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
          );

    return Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchTopInset
            ? Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: searchField,
              )
            : searchField,
        const SizedBox(height: AppSpacing.md),
        _pickerExpandOrBound(
          isMobile,
          child: contactsAsync.when(
            loading: () => _pickerListViewport(
              height: listHeight,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: AppIcon(AppIcons.loader, size: 18),
                ),
              ),
            ),
            error: (_, _) => _pickerListViewport(
              height: listHeight,
              child: const _ContactPickerEmptyResult(
                title: "Couldn't load contacts. Try again.",
              ),
            ),
            data: (state) {
              final contacts = _filteredContacts(state);
              if (contacts.isEmpty) {
                return _pickerListViewport(
                  height: listHeight,
                  child: _ContactPickerEmptyResult(title: widget.emptyTitle),
                );
              }
              final list = _ContactPickerList(
                contacts: contacts,
                showNetwork: widget.networks.length > 1,
                thumbVisibilityThreshold: isMobile
                    ? _contactPickerMobileVisibleRows
                    : 5,
                onSelected: widget.onSelected,
              );
              return _pickerListViewport(height: listHeight, child: list);
            },
          ),
        ),
      ],
    );
  }
}

/// Desktop fills the fixed-height card ([Expanded]); mobile lets the
/// search/list area flow so the card hugs its content (the populated list
/// bounds its own height separately).
Widget _pickerExpandOrBound(bool mobile, {required Widget child}) =>
    mobile ? child : Expanded(child: child);

Widget _pickerListViewport({required double? height, required Widget child}) {
  if (height == null) return child;
  return SizedBox(
    key: const ValueKey('address_book_contact_picker_list_viewport'),
    height: height,
    child: child,
  );
}

class _ContactPickerList extends StatefulWidget {
  const _ContactPickerList({
    required this.contacts,
    required this.showNetwork,
    required this.thumbVisibilityThreshold,
    required this.onSelected,
  });

  final List<AddressBookContact> contacts;
  final bool showNetwork;
  final int thumbVisibilityThreshold;
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
      thumbVisibility: widget.contacts.length > widget.thumbVisibilityThreshold,
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
            separatorBuilder: (_, _) =>
                const SizedBox(height: _contactPickerRowGap),
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
