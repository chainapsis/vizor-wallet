// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/activity/models/activity_row_data.dart';
import '../src/features/activity/widgets/activity_feed.dart';

Widget buildActivityPageUseCase(BuildContext context) {
  return SizedBox(
    width: 1080,
    height: 720,
    child: AppDesktopShell(
      sidebar: const _ActivityUseCaseSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: ColoredBox(
          key: const ValueKey('activity_page_pane_background'),
          color: context.colors.macosUtility.window,
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: 48,
                child: AppPaneToolbar(
                  leading: AppBackLink(
                    key: ValueKey('activity_page_back_button'),
                    label: 'Home',
                    minWidth: 60,
                    onTap: _noop,
                  ),
                  padding: EdgeInsets.only(
                    left: AppSpacing.sm,
                    top: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 48,
                right: 0,
                bottom: 0,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    key: const ValueKey('activity_page_scroll_view'),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 420,
                        child: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: ActivityFeed(
                            sections: _activitySections(context),
                            rowKeyPrefix: 'activity_page',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _noop() {}

List<ActivityFeedSectionData> _activitySections(BuildContext context) {
  return [
    ActivityFeedSectionData(
      title: 'This week',
      rows: [
        _activityRow(
          context,
          title: 'Swapping...',
          iconName: AppIcons.swapArrows,
          subtitle: 'USDC on Optimism',
          amountText: '-26.60 USDC',
          progress: 0.75,
          childRows: [
            _activityRow(
              context,
              title: 'Receiving ZEC...',
              amountText: '+12.13 ZEC',
              amountColor: context.colors.text.primary,
              statusText: 'In progress',
            ),
          ],
        ),
        _activityRow(
          context,
          title: 'Received ZEC',
          iconName: AppIcons.arrowDownCircle,
          subtitle: 'Shielded',
          subtitleIconName: AppIcons.shieldKeyholeOutline,
          amountText: '+31.10 ZEC',
          amountColor: context.colors.text.positiveStrong,
        ),
        _activityRow(
          context,
          title: 'Sent ZEC',
          iconName: AppIcons.plane,
          subtitle: 'Shielded',
          subtitleIconName: AppIcons.shieldKeyholeOutline,
          amountText: '-4.12 ZEC',
        ),
      ],
    ),
    ActivityFeedSectionData(
      title: 'April 2026',
      rows: [
        _activityRow(
          context,
          title: 'Send failed',
          iconName: AppIcons.plane,
          subtitle: 'Transparent',
          amountText: '1.11 ZEC',
          amountIconName: AppIcons.arrowBack,
          amountSubtitle: 'Refunded',
          statusText: 'Failed',
          statusIconName: AppIcons.skull,
          statusColor: context.colors.text.destructive,
        ),
        _activityRow(
          context,
          title: 'Shielded',
          iconName: AppIcons.shieldKeyholeOutline,
          amountText: '0.30 ZEC',
        ),
      ],
    ),
  ];
}

ActivityRowData _activityRow(
  BuildContext context, {
  required String title,
  required String amountText,
  String iconName = AppIcons.sync,
  String? subtitle,
  String? subtitleIconName,
  String? amountIconName,
  String? amountSubtitle,
  String statusText = 'Completed',
  String? statusIconName,
  Color? statusColor,
  Color? amountColor,
  double? progress,
  List<ActivityRowData> childRows = const [],
}) {
  final colors = context.colors;
  return ActivityRowData(
    title: title,
    leadingIconName: iconName,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    leadingProgressValue: progress,
    subtitle: subtitle,
    subtitleIconName: subtitleIconName,
    amountText: amountText,
    amountIconName: amountIconName,
    amountIconColor: amountIconName == null ? null : colors.icon.regular,
    amountColor: amountColor ?? colors.text.primary,
    amountSubtitle: amountSubtitle,
    statusText: statusText,
    statusIconName: statusIconName,
    statusColor: statusColor ?? colors.text.secondary,
    timestampText: 'Today, 13:11',
    childRows: childRows,
  );
}

class _ActivityUseCaseSidebar extends StatelessWidget {
  const _ActivityUseCaseSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            const AppSidebarItem(
              label: 'Username',
              iconName: AppIcons.user,
              leadingGap: AppSpacing.xs,
            ),
            const SizedBox(height: AppSpacing.md),
            AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              active: true,
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -AppSpacing.sm,
                    top: 1,
                    bottom: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.sync.lightSuccess,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(AppRadii.full),
                        ),
                      ),
                      child: const SizedBox(width: 5),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '34% Syncing...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.sync.textSyncing,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
