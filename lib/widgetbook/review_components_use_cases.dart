// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/formatting/address_display.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/theme/primitives.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/core/widgets/review_buttons_stack.dart';
import '../src/core/widgets/review_info_row.dart';
import '../src/core/widgets/review_list_row.dart';
import '../src/core/widgets/review_wrap_card.dart';

const _sampleAddress =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

const _sampleMemo = 'Zcash is a privacy-focused ...';

/// Review Info rows — amount, unknown shielded address, resolved contact,
/// and the failed strikethrough variant. (Toggle the Widgetbook theme for
/// dark mode.)
Widget buildReviewInfoRowGalleryUseCase(BuildContext context) {
  return _ReviewComponentsFrame(
    children: [
      ReviewInfoRow(
        label: 'Amount',
        value: '123.12 ZEC',
        leading: ClipOval(
          child: Image.asset(
            'assets/icons/network_zec.png',
            width: AppAssetSize.size,
            height: AppAssetSize.size,
            fit: BoxFit.cover,
          ),
        ),
        bottomLeftText: r'$250.12',
      ),
      const _ReviewArrowSeparator(),
      ReviewInfoRow(
        label: 'To',
        value: truncatedAddress(_sampleAddress),
        leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
        bottomLeftIconName: AppIcons.shieldKeyhole,
        bottomLeftText: 'Shielded',
        trailingActionLabel: 'Show full address',
        onTrailingAction: () {},
      ),
      const SizedBox(height: AppSpacing.md),
      ReviewInfoRow(
        label: 'To',
        value: 'Mike',
        leading: const AppProfilePicture(
          profilePictureId: 'pfp-02',
          size: AppProfilePictureSize.large,
        ),
        bottomLeftText: truncatedAddress(_sampleAddress),
        trailingActionLabel: 'Show full address',
        onTrailingAction: () {},
      ),
      const SizedBox(height: AppSpacing.md),
      ReviewInfoRow(
        label: 'To',
        value: truncatedAddress(_sampleAddress),
        leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
        struckThrough: true,
        bottomLeftIconName: AppIcons.shieldKeyhole,
        bottomLeftText: 'Shielded',
        trailingActionLabel: 'Show full address',
        onTrailingAction: () {},
      ),
    ],
  );
}

/// Completed-status Review Wrap card with the full detail row set.
Widget buildReviewWrapCardCompletedUseCase(BuildContext context) {
  final colors = context.colors;
  return _ReviewComponentsFrame(
    children: [
      ReviewWrapCard(
        children: [
          ReviewListRow(
            label: 'Status',
            value: 'Completed',
            valueColor: colors.text.positiveStrong,
            leadingIconName: AppIcons.checkCircle,
          ),
          // Detail rows stack with no gap (one group); the card's 16px gap
          // applies between groups only, matching the status/receipt views.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewListRow(
                label: 'Message',
                value: _sampleMemo,
                trailingIconName: AppIcons.expand,
                onPressed: () {},
              ),
              const ReviewListRow(label: 'Timestamp', value: '25 May, 13:30'),
              ReviewListRow(
                label: 'Tx ID',
                value: '0123123124512512',
                trailingIconName: AppIcons.arrowTopRight,
                onPressed: () {},
              ),
            ],
          ),
          const ReviewWrapDivider(),
          ReviewListRow(
            label: 'Tx fee',
            value: '0.012 ZEC',
            trailingIconName: AppIcons.help,
            trailingIconColor: colors.text.secondary,
            onPressed: () {},
          ),
        ],
      ),
    ],
  );
}

/// Failed-status Review Wrap card. The surface is pinned to the dark
/// `Primitives.p50Dark` (#1b1f1f) in BOTH themes per the Figma spec, so the
/// row colors are passed as dark-theme tokens explicitly instead of reading
/// the ambient (possibly light) theme.
Widget buildReviewWrapCardFailedUseCase(BuildContext context) {
  const darkColors = AppThemeData.dark;
  final destructive = darkColors.colors.text.destructive;
  final secondary = darkColors.colors.text.secondary;
  final accent = darkColors.colors.text.accent;
  return _ReviewComponentsFrame(
    children: [
      ReviewWrapCard(
        surfaceColor: Primitives.p50Dark,
        children: [
          ReviewListRow(
            label: 'Status',
            value: 'Failed, refunded minus tx fee',
            labelColor: destructive,
            valueColor: destructive,
            leadingIconName: AppIcons.cancel,
          ),
          ReviewListRow(
            label: 'Message',
            value: _sampleMemo,
            labelColor: secondary,
            valueColor: accent,
            trailingIconName: AppIcons.expand,
            onPressed: () {},
          ),
          ReviewListRow(
            label: 'Timestamp',
            value: '25 May, 13:30',
            labelColor: secondary,
            valueColor: accent,
          ),
          const ReviewWrapDivider(),
          ReviewListRow(
            label: 'Tx fee',
            value: '0.012 ZEC',
            labelColor: secondary,
            valueColor: accent,
            trailingIconName: AppIcons.help,
            trailingIconColor: secondary,
            onPressed: () {},
          ),
        ],
      ),
    ],
  );
}

/// List row variants in isolation — status colors, loader, and trailing
/// affordances.
Widget buildReviewListRowGalleryUseCase(BuildContext context) {
  final colors = context.colors;
  return _ReviewComponentsFrame(
    children: [
      ReviewListRow(
        label: 'Status',
        value: 'Completed',
        valueColor: colors.text.positiveStrong,
        leadingIconName: AppIcons.checkCircle,
      ),
      ReviewListRow(
        label: 'Status',
        value: 'In progress',
        valueColor: colors.text.secondary,
        leadingIconName: AppIcons.loader,
      ),
      ReviewListRow(
        label: 'Status',
        value: 'Failed, refunded minus tx fee',
        labelColor: colors.text.destructive,
        valueColor: colors.text.destructive,
        leadingIconName: AppIcons.cancel,
      ),
      ReviewListRow(
        label: 'Message',
        value: _sampleMemo,
        trailingIconName: AppIcons.expand,
        onPressed: () {},
      ),
      ReviewListRow(
        label: 'Tx fee',
        value: '0.012 ZEC',
        trailingIconName: AppIcons.help,
        trailingIconColor: colors.text.secondary,
        onPressed: () {},
      ),
    ],
  );
}

/// Primary + ghost CTA stack from the review screens.
Widget buildReviewButtonsStackUseCase(BuildContext context) {
  return _ReviewComponentsFrame(
    children: [
      ReviewButtonsStack(
        primaryLabel: 'Confirm & send',
        primaryLeadingIconName: AppIcons.plane,
        onPrimaryPressed: () {},
        secondaryLabel: 'Cancel',
        onSecondaryPressed: () {},
      ),
    ],
  );
}

/// 420px content-column frame on the window background, mirroring the
/// trailing-pane Content Area the review screens render in.
class _ReviewComponentsFrame extends StatelessWidget {
  const _ReviewComponentsFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.background.window,
      child: Center(
        child: SizedBox(
          width: AppWindowSizing.contentAreaMaxWidth,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 24px arrow-down connector between Review Info rows, centered in the
/// 32px leading-column width.
class _ReviewArrowSeparator extends StatelessWidget {
  const _ReviewArrowSeparator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: AppAssetSize.size,
        child: Center(
          child: AppIcon(
            AppIcons.arrowDown,
            size: AppIconSize.large,
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
