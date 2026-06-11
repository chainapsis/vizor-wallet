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

    return SafeArea(
      top: false,
      child: Padding(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receiveAddressInfoTitle(type),
                        style: AppTypography.bodyLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        receiveAddressInfoSubtitle(type),
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
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
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 32,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: AppIcon(
                        items[i].iconName,
                        size: 16,
                        color: colors.icon.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      items[i].text,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('receive_address_info_close'),
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
