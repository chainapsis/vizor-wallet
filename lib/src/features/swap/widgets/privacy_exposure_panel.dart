import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';

class PrivacyExposurePanel extends StatelessWidget {
  const PrivacyExposurePanel({required this.rows, super.key});

  final List<SwapPrototypeField> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
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
              AppIcon(AppIcons.shieldKeyhole, size: 18),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Privacy check',
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) ...[
            _ExposureRow(row: row),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _ExposureRow extends StatelessWidget {
  const _ExposureRow({required this.row});

  final SwapPrototypeField row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = _ExposureScope.from(row);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row.label,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _ExposureScopeBadge(scope: scope),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          row.value,
          style: AppTypography.bodySmall.copyWith(color: colors.text.primary),
        ),
      ],
    );
  }
}

enum _ExposureScope {
  provider(keySuffix: 'provider', label: 'Provider', iconName: AppIcons.link),
  wallet(keySuffix: 'wallet', label: 'Wallet', iconName: AppIcons.wallet),
  network(keySuffix: 'network', label: 'Network', iconName: AppIcons.endpoint);

  const _ExposureScope({
    required this.keySuffix,
    required this.label,
    required this.iconName,
  });

  final String keySuffix;
  final String label;
  final String iconName;

  static _ExposureScope from(SwapPrototypeField row) {
    final haystack = '${row.label} ${row.value}'.toLowerCase();
    if (haystack.contains('third-party') ||
        haystack.contains('solver') ||
        haystack.contains('provider') ||
        haystack.contains('1click')) {
      return _ExposureScope.provider;
    }
    if (haystack.contains('network') ||
        haystack.contains('transparent') ||
        haystack.contains('deposit') ||
        haystack.contains('source-chain') ||
        haystack.contains('public') ||
        haystack.contains('tx')) {
      return _ExposureScope.network;
    }
    return _ExposureScope.wallet;
  }
}

class _ExposureScopeBadge extends StatelessWidget {
  const _ExposureScopeBadge({required this.scope});

  final _ExposureScope scope;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: ValueKey('swap_privacy_scope_${scope.keySuffix}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(scope.iconName, size: 12, color: colors.icon.regular),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            scope.label,
            style: AppTypography.labelSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
