import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

class SaplingParamsPrompt extends StatelessWidget {
  const SaplingParamsPrompt({
    required this.onDownload,
    required this.onCancel,
    super.key,
  });

  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCancel,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: ColoredBox(color: colors.background.neutralScrim),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 312,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colors.background.neutralSubtleOpacity,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: AppIcon(
                            AppIcons.importWallet,
                            size: AppIconSize.medium,
                            color: colors.icon.regular,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).saplingDownloadRequired,
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.text.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          AppLocalizations.of(context).saplingDownloadBody,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          AppLocalizations.of(context).saplingDownloadOnce,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    onPressed: onDownload,
                    minWidth: 280,
                    child: Text(AppLocalizations.of(context).saplingDownload),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    onPressed: onCancel,
                    variant: AppButtonVariant.ghost,
                    minWidth: 280,
                    child: Text(AppLocalizations.of(context).commonCancel),
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
