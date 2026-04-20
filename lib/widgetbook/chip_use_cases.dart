// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_chip.dart';
import '../src/core/widgets/app_icon.dart';

Widget buildChipUseCase(BuildContext context) {
  return ColoredBox(
    color: context.colors.background.ground,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CHIP',
            style: TextStyle(
              color: context.colors.text.secondary,
              fontSize: 11,
              letterSpacing: 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              AppChip(
                type: AppChipType.defaultText,
                leadingText: '01',
                label: 'Shield',
              ),
              AppChip(
                type: AppChipType.icons,
                leading: AppIcon(AppIcons.block),
                label: 'Shield',
                trailing: AppIcon(AppIcons.block),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
