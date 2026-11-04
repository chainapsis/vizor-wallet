import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField;
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/comma_to_dot_input_formatter.dart';
import '../../../../core/widgets/decimal_amount_input_formatter.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/review_info_row.dart';
import '../../../swap/models/swap_models.dart';
import '../../../swap/widgets/swap_asset_icon.dart';
import '../donation_views.dart';

class MobileDonationComposeView extends StatelessWidget {
  const MobileDonationComposeView({
    required this.controller,
    required this.mode,
    required this.conversionText,
    required this.balanceText,
    required this.selectedPreset,
    required this.onAmountChanged,
    required this.onToggleMode,
    required this.onPresetSelected,
    required this.onContinue,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final DonationAmountMode mode;
  final String conversionText;
  final String balanceText;
  final String? selectedPreset;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onToggleMode;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback? onContinue;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isUsd = mode == DonationAmountMode.usd;
    final presets = isUsd
        ? DonationComposeView.usdPresets
        : DonationComposeView.zecPresets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileSurfaceCard(
                  cornerRadius: 28,
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Enter your amount',
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            const SwapAssetIcon(
                              asset: SwapAsset.zec,
                              size: 32,
                              showChainBadge: false,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ZEC',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.accent,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'Zcash',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Column(
                          children: [
                            _MobileDonationAmountEditor(
                              controller: controller,
                              isUsd: isUsd,
                              hasError: errorText != null,
                              onChanged: onAmountChanged,
                            ),
                            const SizedBox(height: AppSpacing.s),
                            Semantics(
                              button: onToggleMode != null,
                              label: 'Switch between ZEC and USD',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onToggleMode,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AppIcon(
                                        AppIcons.doubleArrowVertical,
                                        size: 16,
                                        color: colors.icon.muted,
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Flexible(
                                        child: Text(
                                          conversionText,
                                          style: AppTypography.labelLarge
                                              .copyWith(
                                                color: colors.text.secondary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      for (var col = 0; col < 2; col++) ...[
                        if (col > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _MobileDonationPreset(
                            value: presets[row * 2 + col],
                            isUsd: isUsd,
                            selected: selectedPreset == presets[row * 2 + col],
                            onSelected: onPresetSelected,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    AppIcon(
                      AppIcons.shieldKeyhole,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                    Text(
                      'Shielded balance',
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                    Text(
                      balanceText,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
                if (errorText != null) ...[
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    errorText!,
                    key: const ValueKey('mobile_donation_amount_error'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.s,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: AppButton(
            key: const ValueKey('donation_continue_button'),
            expand: true,
            constrainContent: true,
            onPressed: onContinue,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}

class _MobileDonationAmountEditor extends StatelessWidget {
  const _MobileDonationAmountEditor({
    required this.controller,
    required this.isUsd,
    required this.hasError,
    required this.onChanged,
  });
  final TextEditingController controller;
  final bool isUsd;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.displayLarge.copyWith(
      color: hasError
          ? context.colors.text.destructive
          : context.colors.text.accent,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = isUsd ? 'USD' : 'ZEC';
        final unitStyle = style.copyWith(
          fontSize: 38,
          height: 40 / 38,
          color: context.colors.text.secondary,
        );
        final scaler = MediaQuery.textScalerOf(context);
        final text = TextPainter(
          text: TextSpan(
            text: controller.text.isEmpty ? '0' : controller.text,
            style: style,
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: SizedBox(
                  width: text.width + 12,
                  child: TextField(
                    key: const ValueKey('donation_amount_field'),
                    controller: controller,
                    onChanged: onChanged,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      const CommaToDotInputFormatter(),
                      DecimalAmountInputFormatter(
                        maxFractionDigits: isUsd ? 2 : 8,
                      ),
                    ],
                    style: style,
                    textAlign: TextAlign.right,
                    cursorColor: context.colors.text.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: '0',
                      hintStyle: style.copyWith(
                        color: context.colors.text.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(unit, style: unitStyle),
            ],
          ),
        );
      },
    );
  }
}

class _MobileDonationPreset extends StatelessWidget {
  const _MobileDonationPreset({
    required this.value,
    required this.isUsd,
    required this.selected,
    required this.onSelected,
  });
  final String value;
  final bool isUsd;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelected(value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.s,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.full),
          border: selected
              ? Border.all(color: context.colors.border.strong, width: 1.5)
              : null,
        ),
        child: Text(
          isUsd ? '\$$value' : '$value ZEC',
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.accent,
          ),
        ),
      ),
    ),
  );
}

class MobileDonationReviewContent extends StatelessWidget {
  const MobileDonationReviewContent({
    required this.amountText,
    required this.fiatText,
    required this.feeText,
    required this.totalText,
    required this.onFullAddress,
    required this.onFeeInfo,
    super.key,
  });
  final String amountText;
  final String? fiatText;
  final String feeText;
  final String totalText;
  final VoidCallback onFullAddress;
  final VoidCallback onFeeInfo;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MobileSurfaceCard(
        cornerRadius: 28,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: [
            ReviewInfoRow(
              label: 'Amount',
              value: amountText,
              leading: const SwapAssetIcon(
                asset: SwapAsset.zec,
                size: 40,
                showChainBadge: false,
              ),
              bottomLeftText: fiatText,
              valueFit: BoxFit.scaleDown,
            ),
            const SizedBox(height: AppSpacing.md),
            ReviewInfoRow(
              label: 'Donating to',
              value: 'Vizor Wallet',
              leading: const DonationVizorBadge(size: 40),
              valueFit: BoxFit.scaleDown,
              bottomLeftText: 'u15kdl…8tg3y',
              trailingActionLabel: 'Full address',
              onTrailingAction: onFullAddress,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      MobileSurfaceCard(
        cornerRadius: 28,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: [
            _DonationDetailRow(
              label: 'Sending from',
              value: 'Shielded balance',
            ),
            const SizedBox(height: AppSpacing.sm),
            _DonationDetailRow(
              label: 'Tx fee',
              value: feeText,
              trailingIconName: AppIcons.help,
              onTap: onFeeInfo,
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(height: 1, color: context.colors.border.subtle),
            const SizedBox(height: AppSpacing.sm),
            _DonationDetailRow(label: 'Total', value: totalText),
          ],
        ),
      ),
    ],
  );
}

class _DonationDetailRow extends StatelessWidget {
  const _DonationDetailRow({
    required this.label,
    required this.value,
    this.trailingIconName,
    this.onTap,
  });
  final String label;
  final String value;
  final String? trailingIconName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.labelLarge.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ),
            if (trailingIconName != null) ...[
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                trailingIconName!,
                size: 20,
                color: context.colors.icon.muted,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
