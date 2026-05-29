import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.background.base,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.users,
                    size: AppIconSize.medium,
                    color: colors.icon.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _ContactPickerIconButton(
                semanticLabel: 'Close contacts',
                iconName: AppIcons.cross,
                onTap: widget.onCancel,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const ValueKey('address_book_contact_picker_search'),
            label: 'Search',
            showLabel: false,
            controller: _queryController,
            focusNode: _queryFocusNode,
            hintText: widget.searchHint,
            leading: const AppIcon(AppIcons.search),
            leadingSlotWidth: 40,
            trailingSlotWidth: 40,
            inputHorizontalPadding: AppSpacing.xs,
            showClearButton: true,
            clearButtonRequiresText: false,
            onChanged: (_) => setState(() {}),
            onClear: () => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: AppIcon(AppIcons.loader, size: 18),
                ),
              ),
              error: (_, _) => const _ContactPickerEmptyResult(
                title: "Couldn't load contacts. Try again.",
              ),
              data: (state) {
                final contacts = _filteredContacts(state);
                if (contacts.isEmpty) {
                  return _ContactPickerEmptyResult(title: widget.emptyTitle);
                }
                return _ContactPickerList(
                  contacts: contacts,
                  showNetwork: widget.networks.length > 1,
                  onSelected: widget.onSelected,
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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

class _ContactPickerList extends StatelessWidget {
  const _ContactPickerList({
    required this.contacts,
    required this.showNetwork,
    required this.onSelected,
  });

  final List<AddressBookContact> contacts;
  final bool showNetwork;
  final ValueChanged<AddressBookContact> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final contact in contacts)
          _ContactPickerRow(
            key: ValueKey('address_book_contact_picker_contact_${contact.id}'),
            contact: contact,
            showNetwork: showNetwork,
            onTap: () => onSelected(contact),
          ),
      ],
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
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: _hovered ? colors.background.base : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
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
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.contact.addressPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
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
              color: _hovered ? context.colors.background.base : null,
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Center(
              child: AppIcon(
                widget.iconName,
                size: AppIconSize.medium,
                color: context.colors.icon.regular,
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
