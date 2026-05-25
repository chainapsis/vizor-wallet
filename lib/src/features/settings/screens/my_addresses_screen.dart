import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/address_labels_provider.dart';
import '../../../providers/address_list_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../activity/address_display.dart';

class MyAddressesScreen extends ConsumerWidget {
  const MyAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountUuid =
        ref.watch(accountProvider).value?.activeAccountUuid ?? '';

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _MyAddressesPane(accountUuid: accountUuid),
        ),
      ),
    );
  }
}

class _MyAddressesPane extends StatelessWidget {
  const _MyAddressesPane({required this.accountUuid});

  final String accountUuid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 752),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'My Addresses',
                        textAlign: TextAlign.center,
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const AppDecorativeDivider(width: 256),
                      const SizedBox(height: AppSpacing.sm),
                      _AddressList(accountUuid: accountUuid),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressList extends ConsumerWidget {
  const _AddressList({required this.accountUuid});

  final String accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressListProvider(accountUuid));
    final colors = context.colors;

    return addressesAsync.when(
      loading: () => Center(
        child: Text(
          'Loading...',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
        ),
      ),
      error: (error, _) => Center(
        child: Text(
          'Error loading addresses: $error',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.destructive,
          ),
        ),
      ),
      data: (addresses) {
        if (addresses.isEmpty) {
          return Center(
            child: Text(
              'No addresses',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < addresses.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xs,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.border.subtle),
                    child: const SizedBox(height: 1),
                  ),
                ),
              _AddressRow(
                accountUuid: accountUuid,
                address: addresses[i],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AddressRow extends ConsumerStatefulWidget {
  const _AddressRow({
    required this.accountUuid,
    required this.address,
  });

  final String accountUuid;
  final rust_wallet.AccountAddress address;

  @override
  ConsumerState<_AddressRow> createState() => _AddressRowState();
}

class _AddressRowState extends ConsumerState<_AddressRow> {
  bool _editing = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEdit(String? currentLabel) {
    _controller.text = currentLabel ?? '';
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  Future<void> _saveLabel() async {
    final newLabel = _controller.text;
    await ref
        .read(addressLabelsProvider.notifier)
        .setLabel(
          accountUuid: widget.accountUuid,
          address: widget.address.address,
          label: newLabel,
        );
    if (mounted) setState(() => _editing = false);
  }

  void _cancelEdit() {
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = ref
        .watch(addressLabelsProvider)
        .labelFor(widget.accountUuid, widget.address.address);

    final truncatedAddress = truncateAddress(widget.address.address);

    if (_editing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AddressRowContent(
              label: label,
              truncatedAddress: truncatedAddress,
              isDefault: widget.address.isDefault,
              colors: colors,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _RenameField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmitted: (_) => _saveLabel(),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  onPressed: _saveLabel,
                  variant: AppButtonVariant.primary,
                  child: const Text('Save'),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  onPressed: _cancelEdit,
                  variant: AppButtonVariant.ghost,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: _AddressRowContent(
              label: label,
              truncatedAddress: truncatedAddress,
              isDefault: widget.address.isDefault,
              colors: colors,
            ),
          ),
          AppButton(
            onPressed: () => _startEdit(label),
            variant: AppButtonVariant.ghost,
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

class _AddressRowContent extends StatelessWidget {
  const _AddressRowContent({
    required this.label,
    required this.truncatedAddress,
    required this.isDefault,
    required this.colors,
  });

  final String? label;
  final String truncatedAddress;
  final bool isDefault;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(
            label!,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            'Unnamed',
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.secondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          truncatedAddress,
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RenameField extends StatelessWidget {
  const _RenameField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return EditableText(
      controller: controller,
      focusNode: focusNode,
      style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
      cursorColor: colors.text.accent,
      backgroundCursorColor: colors.background.base,
      maxLines: 1,
      onSubmitted: onSubmitted,
      // ignore long labels gracefully; normalizeAddressLabel trims on save
    );
  }
}

