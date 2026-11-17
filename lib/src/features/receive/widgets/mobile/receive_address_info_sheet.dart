import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../receive_address_widgets.dart';

/// Opens the address-type explainer sheet — Figma `Shielded Address` /
/// `Transparent Address` modals (4562:97619 / 4562:100793).
Future<void> showReceiveAddressInfoSheet(
  BuildContext context,
  ReceiveAddressType type,
) {
  return showAppMobileSheet<void>(
    context: context,
    builder: (_) => ReceiveAddressInfoSheet(type: type),
  );
}

class ReceiveAddressInfoSheet extends StatelessWidget {
  const ReceiveAddressInfoSheet({required this.type, super.key});

  final ReceiveAddressType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = receiveAddressInfoItems(context.l10n, type, touchUi: true);
    final isShielded = type == ReceiveAddressType.shielded;
    final itemMaxLines = isShielded ? const [3, 3, 3] : const [2, 4, 5, 4];

    // The shared sheet template; the subtitle reads as part of the title.
    return MobileModalScaffold(
      title: receiveAddressInfoTitle(context.l10n, type),
      onClose: () => Navigator.of(context).pop(),
      bodyGap: AppSpacing.xxs,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            receiveAddressInfoSubtitle(context.l10n, type),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _ReceiveAddressInfoSheetItem(
                  key: ValueKey('receive_address_info_item_$i'),
                  iconName: items[i].iconName,
                  text: items[i].text,
                  maxLines: itemMaxLines[i],
                ),
                if (i != items.length - 1)
                  const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('receive_address_info_close'),
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }
}

class _ReceiveAddressInfoSheetItem extends StatelessWidget {
  const _ReceiveAddressInfoSheetItem({
    required this.iconName,
    required this.text,
    required this.maxLines,
    super.key,
  });

  final String iconName;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 25,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppIcon(iconName, size: 20, color: colors.icon.accent),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
      ],
    );
  }
}
