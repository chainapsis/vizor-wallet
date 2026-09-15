// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';

/// Matrix view — every (variant × size × state) combination on one canvas,
/// matching the Figma component sheet at node 54:81.
///
/// The interactive states (hover / pressed / focus) cannot be forced on a
/// real widget, so this matrix renders the *default* visual for each cell.
/// Use the Interactive use case to exercise hover/press/focus on a live
/// instance.
Widget buildButtonMatrixUseCase(BuildContext context) {
  const variants = AppButtonVariant.values;
  const sizes = AppButtonSize.values;

  final leading = const Icon(Icons.add);
  final trailing = const Icon(Icons.arrow_forward);

  Widget cell(AppButtonVariant variant, AppButtonSize size) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: AppButton(
        onPressed: () {},
        variant: variant,
        size: size,
        leading: leading,
        trailing: trailing,
        child: Text(buttonFixtureLabelForSize(size)),
      ),
    );
  }

  return ColoredBox(
    color: context.colors.background.ground,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUTTON MATRIX',
            style: TextStyle(
              color: context.colors.text.secondary,
              fontSize: 11,
              letterSpacing: 0.88,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final size in sizes)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        size.name.toUpperCase(),
                        style: TextStyle(
                          color: context.colors.text.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              for (final variant in variants)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        variant.name,
                        style: TextStyle(
                          color: context.colors.text.muted,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    for (final size in sizes) cell(variant, size),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One button on the plain component ground, behind the gallery playground.
/// The defaults are the Figma component sheet's render, so adding a knob
/// never moves them.
Widget buttonSingleFixture(
  BuildContext context, {
  required AppButtonVariant variant,
  required AppButtonSize size,
  bool enabled = true,
  bool leadingIcon = true,
  bool trailingIcon = true,
  String? label,
}) {
  return ColoredBox(
    color: context.colors.background.ground,
    child: Center(
      child: AppButton(
        onPressed: enabled ? () {} : null,
        variant: variant,
        size: size,
        leading: leadingIcon ? const Icon(Icons.add) : null,
        trailing: trailingIcon ? const Icon(Icons.arrow_forward) : null,
        child: Text(label ?? buttonFixtureLabelForSize(size)),
      ),
    ),
  );
}

String buttonFixtureLabelForSize(AppButtonSize size) {
  return switch (size) {
    AppButtonSize.large => 'Create New Wallet',
    AppButtonSize.mediumLarge => 'Add to contacts',
    AppButtonSize.medium => 'Review',
    AppButtonSize.small => 'Copy',
  };
}

Widget buildButtonPrimaryLargeUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.primary,
      size: AppButtonSize.large,
    );
Widget buildButtonPrimaryMediumUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.primary,
      size: AppButtonSize.medium,
    );
Widget buildButtonPrimarySmallUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.primary,
      size: AppButtonSize.small,
    );
Widget buildButtonSecondaryLargeUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.large,
    );
Widget buildButtonSecondaryMediumUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.medium,
    );
Widget buildButtonSecondarySmallUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.small,
    );
Widget buildButtonGhostLargeUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.large,
    );
Widget buildButtonGhostMediumUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.medium,
    );
Widget buildButtonGhostSmallUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.small,
    );
Widget buildButtonDestructiveLargeUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.destructive,
      size: AppButtonSize.large,
    );
Widget buildButtonDestructiveMediumUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.destructive,
      size: AppButtonSize.medium,
    );
Widget buildButtonDestructiveSmallUseCase(BuildContext context) =>
    buttonSingleFixture(
      context,
      variant: AppButtonVariant.destructive,
      size: AppButtonSize.small,
    );

Widget buildButtonInteractiveUseCase(BuildContext context) {
  final variant = context.knobs.object.dropdown<AppButtonVariant>(
    label: 'Variant',
    options: AppButtonVariant.values,
    initialOption: AppButtonVariant.primary,
    labelBuilder: (v) => v.name,
  );
  final size = context.knobs.object.segmented<AppButtonSize>(
    label: 'Size',
    options: AppButtonSize.values,
    initialOption: AppButtonSize.large,
    labelBuilder: (s) => s.name,
  );
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);
  final showLeading = context.knobs.boolean(
    label: 'Leading icon',
    initialValue: true,
  );
  final showTrailing = context.knobs.boolean(
    label: 'Trailing icon',
    initialValue: true,
  );
  final label = context.knobs.string(
    label: 'Label',
    initialValue: 'Create New Wallet',
  );

  return buttonSingleFixture(
    context,
    variant: variant,
    size: size,
    enabled: enabled,
    leadingIcon: showLeading,
    trailingIcon: showTrailing,
    label: label,
  );
}
