import 'package:flutter/widgets.dart';

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
    final items = receiveAddressInfoItems(type, touchUi: true);
    final isShielded = type == ReceiveAddressType.shielded;
    final itemMaxLines = isShielded ? const [3, 3, 3] : const [2, 4, 4];

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.base,
            AppSpacing.sm,
            AppSpacing.base,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 184,
                  height: 51,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receiveAddressInfoTitle(type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        receiveAddressInfoSubtitle(type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
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
              SizedBox(
                height: AppButtonSizing.largeHeight,
                child: AppButton(
                  key: const ValueKey('receive_address_info_close'),
                  variant: AppButtonVariant.secondary,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: Semantics(
            button: true,
            label: 'Close',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.background.raised,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.cross,
                    size: AppIconSize.medium,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
