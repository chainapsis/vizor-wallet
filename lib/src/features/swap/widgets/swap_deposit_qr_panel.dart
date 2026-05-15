import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

class SwapDepositQrPanel extends StatelessWidget {
  const SwapDepositQrPanel({
    required this.title,
    required this.qrData,
    required this.addressLabel,
    required this.address,
    required this.railLabel,
    required this.reuseWarning,
    this.expiresInLabel,
    this.memo,
    this.dense = false,
    super.key,
  });

  final String title;
  final String qrData;
  final String addressLabel;
  final String address;
  final String railLabel;
  final String reuseWarning;
  final String? expiresInLabel;
  final String? memo;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(dense ? AppSpacing.xxs : AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final qrSize =
              (dense ? (compact ? 112.0 : 132.0) : (compact ? 156.0 : 184.0))
                  .clamp(dense ? 96.0 : 128.0, constraints.maxWidth);
          final qr = _DepositQrCode(data: qrData, size: qrSize);
          final details = _DepositQrDetails(
            title: title,
            addressLabel: addressLabel,
            address: address,
            railLabel: railLabel,
            reuseWarning: reuseWarning,
            expiresInLabel: expiresInLabel,
            memo: memo,
            dense: dense,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.center, child: qr),
                SizedBox(height: dense ? AppSpacing.xxs : AppSpacing.xs),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              qr,
              SizedBox(width: dense ? AppSpacing.xs : AppSpacing.sm),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _DepositQrCode extends StatelessWidget {
  const _DepositQrCode({required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_deposit_qr_code'),
      width: size,
      height: size,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: PrettyQrView.data(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
        decoration: PrettyQrDecoration(
          quietZone: PrettyQrQuietZone.zero,
          shape: PrettyQrSmoothSymbol(
            roundFactor: 0.75,
            color: colors.text.accent,
          ),
        ),
      ),
    );
  }
}

class _DepositQrDetails extends StatelessWidget {
  const _DepositQrDetails({
    required this.title,
    required this.addressLabel,
    required this.address,
    required this.railLabel,
    required this.reuseWarning,
    required this.expiresInLabel,
    required this.memo,
    required this.dense,
  });

  final String title;
  final String addressLabel;
  final String address;
  final String railLabel;
  final String reuseWarning;
  final String? expiresInLabel;
  final String? memo;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
        SizedBox(height: dense ? 2 : AppSpacing.xxs),
        Text(
          railLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        SizedBox(height: dense ? AppSpacing.xxs : AppSpacing.xs),
        _DepositValueBlock(
          label: addressLabel,
          value: address,
          copyKey: const ValueKey('swap_deposit_qr_copy_address'),
          dense: dense,
        ),
        if (memo != null) ...[
          SizedBox(height: dense ? AppSpacing.xxs : AppSpacing.xs),
          _DepositValueBlock(
            label: 'Memo',
            value: memo!,
            copyKey: const ValueKey('swap_deposit_qr_copy_memo'),
            dense: dense,
          ),
        ],
        SizedBox(height: dense ? AppSpacing.xxs : AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            _DepositInfoPill(label: reuseWarning),
            if (expiresInLabel != null && expiresInLabel!.isNotEmpty)
              _DepositInfoPill(label: expiresInLabel!),
          ],
        ),
      ],
    );
  }
}

class _DepositValueBlock extends StatelessWidget {
  const _DepositValueBlock({
    required this.label,
    required this.value,
    required this.copyKey,
    required this.dense,
  });

  final String label;
  final String value;
  final Key copyKey;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(dense ? AppSpacing.xxs : AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
              AppButton(
                key: copyKey,
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: value)));
                },
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                leading: const AppIcon(AppIcons.copy),
                child: const Text('Copy'),
              ),
            ],
          ),
          SizedBox(height: dense ? 2 : AppSpacing.xxs),
          Text(
            value,
            maxLines: dense ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.codeSmall.copyWith(color: colors.text.primary),
          ),
        ],
      ),
    );
  }
}

class _DepositInfoPill extends StatelessWidget {
  const _DepositInfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(color: colors.text.secondary),
      ),
    );
  }
}
