// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart';

import '../src/core/theme/app_theme.dart';

/// One row in the typography sheet — pairs the canonical Figma name and
/// the rendered sample so a visual change at the call site (or in
/// `app_typography.dart`) can be eyeballed against the source of truth.
class _TypographyRow {
  const _TypographyRow({
    required this.name,
    required this.style,
    required this.sample,
  });

  final String name;
  final TextStyle style;
  final String sample;
}

const _displayRows = <_TypographyRow>[
  _TypographyRow(
    name: 'displayLarge',
    style: AppTypography.displayLarge,
    sample: 'Welcome Back',
  ),
  _TypographyRow(
    name: 'displayMedium',
    style: AppTypography.displayMedium,
    sample: 'Welcome to Zeplr',
  ),
  _TypographyRow(
    name: 'displaySmall',
    style: AppTypography.displaySmall,
    sample: 'Welcome to\nthe Shielded World',
  ),
  _TypographyRow(
    name: 'headlineLarge',
    style: AppTypography.headlineLarge,
    sample: 'Recent transactions',
  ),
  _TypographyRow(
    name: 'headlineMedium',
    style: AppTypography.headlineMedium,
    sample: 'Wallet balance',
  ),
  _TypographyRow(
    name: 'headlineSmall',
    style: AppTypography.headlineSmall,
    sample: 'Active account',
  ),
];

const _bodyRows = <_TypographyRow>[
  _TypographyRow(
    name: 'bodyLarge',
    style: AppTypography.bodyLarge,
    sample:
        'Zcash transactions hide the sender, recipient, and amount — '
        'verified by cryptography, not trust.',
  ),
  _TypographyRow(
    name: 'bodyMedium',
    style: AppTypography.bodyMedium,
    sample:
        'Default paragraph copy. The same metric used across most '
        'descriptive UI text.',
  ),
  _TypographyRow(
    name: 'bodyMediumStrong',
    style: AppTypography.bodyMediumStrong,
    sample:
        'Same metrics as bodyMedium, medium weight — for inline emphasis '
        'where italic / bold would over-shout.',
  ),
  _TypographyRow(
    name: 'bodySmall',
    style: AppTypography.bodySmall,
    sample: 'Fine print, legal footers, metadata captions.',
  ),
  _TypographyRow(
    name: 'bodyExtraSmall',
    style: AppTypography.bodyExtraSmall,
    sample: 'Smallest readable copy — chip text, dense table cells.',
  ),
];

const _labelRows = <_TypographyRow>[
  _TypographyRow(
    name: 'labelLarge',
    style: AppTypography.labelLarge,
    sample: 'Intro to Zcash',
  ),
  _TypographyRow(
    name: 'labelMedium',
    style: AppTypography.labelMedium,
    sample: 'Create new wallet',
  ),
  _TypographyRow(
    name: 'labelSmall',
    style: AppTypography.labelSmall,
    sample: 'PENDING',
  ),
];

const _codeRows = <_TypographyRow>[
  _TypographyRow(
    name: 'codeMedium',
    style: AppTypography.codeMedium,
    sample: 'u1l8…7q4w  •  zs1g7p…2nfm',
  ),
  _TypographyRow(
    name: 'codeSmall',
    style: AppTypography.codeSmall,
    sample: '6f5d9b8a3c…0e1f  •  height 2 938 174',
  ),
];

Widget _section(BuildContext context, String title, Widget body) {
  final colors = context.colors;
  return Column(
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
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}

Widget _typographyRow(BuildContext context, _TypographyRow row) {
  final colors = context.colors;
  // Metric summary mirrors the way the Figma inspector reads:
  // family / weight / size / line-height / letter-spacing.
  final ls = row.style.letterSpacing ?? 0;
  final lhPx = (row.style.height ?? 1.0) * (row.style.fontSize ?? 0);
  final metric =
      '${row.style.fontFamily}'
      ' • w${row.style.fontWeight?.value ?? 400}'
      ' • ${row.style.fontSize?.toInt()}/${lhPx.round()}'
      ' • ls ${ls == 0 ? '0' : ls.toStringAsFixed(2)}';

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                style: TextStyle(
                  color: colors.text.accent,
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                metric,
                style: TextStyle(
                  color: colors.text.muted,
                  fontFamily: 'Geist',
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            row.sample,
            style: row.style.copyWith(color: colors.text.primary),
          ),
        ),
      ],
    ),
  );
}

Widget _buildTypographyPage(BuildContext context, String headline) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline.toUpperCase(),
            style: TextStyle(
              color: colors.text.secondary,
              fontSize: 11,
              letterSpacing: 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _section(
            context,
            'Display',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _displayRows) _typographyRow(context, r),
              ],
            ),
          ),
          _section(
            context,
            'Body',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final r in _bodyRows) _typographyRow(context, r)],
            ),
          ),
          _section(
            context,
            'Label',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in _labelRows) _typographyRow(context, r),
              ],
            ),
          ),
          _section(
            context,
            'Code',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final r in _codeRows) _typographyRow(context, r)],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildTypographyAllUseCase(BuildContext context) =>
    _buildTypographyPage(context, 'Typography');
