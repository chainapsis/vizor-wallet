// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart';

import '../src/core/theme/app_theme.dart';

class _TokenRow {
  const _TokenRow(this.name, this.value);
  final String name;
  final double value;
}

const _spacingRows = <_TokenRow>[
  _TokenRow('xxs', AppSpacing.xxs),
  _TokenRow('xs', AppSpacing.xs),
  _TokenRow('s', AppSpacing.s),
  _TokenRow('sm', AppSpacing.sm),
  _TokenRow('md', AppSpacing.md),
  _TokenRow('base', AppSpacing.base),
  _TokenRow('lg', AppSpacing.lg),
  _TokenRow('xl', AppSpacing.xl),
  _TokenRow('xl2', AppSpacing.xl2),
  _TokenRow('xl3', AppSpacing.xl3),
];

const _iconSizeRows = <_TokenRow>[
  _TokenRow('medium', AppIconSize.medium),
  _TokenRow('large', AppIconSize.large),
];

const _radiiRows = <_TokenRow>[
  _TokenRow('medium', AppRadii.medium),
  _TokenRow('large', AppRadii.large),
  _TokenRow('full', AppRadii.full),
];

Widget _page({
  required BuildContext context,
  required String title,
  required Widget body,
}) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colors.text.secondary,
              fontSize: 11,
              letterSpacing: 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(height: 0.5, color: colors.border.subtle),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      ),
    ),
  );
}

Widget _rowLabel(BuildContext context, String name, double value) {
  final colors = context.colors;
  return SizedBox(
    width: 80,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: TextStyle(
            color: colors.text.accent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${value.toInt()} px',
          style: TextStyle(color: colors.text.muted, fontSize: 10),
        ),
      ],
    ),
  );
}

Widget buildSpacingUseCase(BuildContext context) {
  final colors = context.colors;
  return _page(
    context: context,
    title: 'Spacing',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _spacingRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _rowLabel(context, row.name, row.value),
                Container(
                  width: row.value,
                  height: 16,
                  color: colors.button.primary.bg,
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget buildIconSizeUseCase(BuildContext context) {
  final colors = context.colors;
  return _page(
    context: context,
    title: 'Icon Size',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _iconSizeRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: Row(
              children: [
                _rowLabel(context, row.name, row.value),
                Icon(Icons.add, size: row.value, color: colors.icon.accent),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget buildRadiiUseCase(BuildContext context) {
  final colors = context.colors;
  return _page(
    context: context,
    title: 'Radii',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _radiiRows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: Row(
              children: [
                _rowLabel(context, row.name, row.value),
                Container(
                  width: 80,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surface.card,
                    border: Border.all(color: colors.border.regular, width: 1),
                    // `full` would blow out the rect; cap at half the
                    // shorter side so the render matches intent.
                    borderRadius: BorderRadius.circular(
                      row.value == AppRadii.full ? 20 : row.value,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
