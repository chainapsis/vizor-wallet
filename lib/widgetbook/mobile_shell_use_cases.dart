// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

import '../src/core/layout/mobile/app_mobile_shell.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/layout/mobile/app_mobile_tab_bar.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_profile_picture.dart';
import '../src/core/widgets/mobile/mobile_list_row.dart';
import '../src/core/widgets/mobile/mobile_surface_card.dart';

// Preview these with the mobile token lane for true metrics:
// fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile

const _mobileTabItems = [
  AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
  AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
  AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
  AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
];

Widget _phoneFrame(BuildContext context, Widget child) {
  return Center(
    child: SizedBox(
      width: 393,
      child: ColoredBox(color: context.colors.background.window, child: child),
    ),
  );
}

Widget buildMobileTopNavVariantsUseCase(BuildContext context) {
  return _phoneFrame(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MobileTopNav.account(
          accountName: 'Account1',
          syncLabel: 'Vizor is synced',
          onAccountTap: () {},
        ),
        MobileTopNav.account(
          accountName: 'Account1',
          balanceLabel: '140.12 ZEC',
          syncLabel: 'Vizor is synced',
          onAccountTap: () {},
        ),
        MobileTopNav.account(
          accountName: 'Account1',
          syncLabel: '20% Syncing...',
          syncLabelColor: context.colors.sync.textSyncing,
          syncIndicatorColor: context.colors.sync.textSyncing,
          syncHighlightColor: context.colors.sync.text,
          syncAnimated: true,
          onAccountTap: () {},
        ),
        MobileTopNav.steps(progress: 0.3, onBack: () {}),
        MobileTopNav.back(title: 'Activity', onBack: () {}),
      ],
    ),
  );
}

Widget buildMobileTabBarUseCase(BuildContext context) {
  return _phoneFrame(context, const _InteractiveTabBar());
}

class _InteractiveTabBar extends StatefulWidget {
  const _InteractiveTabBar();

  @override
  State<_InteractiveTabBar> createState() => _InteractiveTabBarState();
}

class _InteractiveTabBarState extends State<_InteractiveTabBar> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: AppMobileTabBar(
        items: _mobileTabItems,
        currentIndex: _index,
        onSelect: (index) => setState(() => _index = index),
      ),
    );
  }
}

Widget buildMobileShellUseCase(BuildContext context) {
  return Center(
    child: SizedBox(width: 393, height: 700, child: const _ShellPreview()),
  );
}

class _ShellPreview extends StatefulWidget {
  const _ShellPreview();

  @override
  State<_ShellPreview> createState() => _ShellPreviewState();
}

class _ShellPreviewState extends State<_ShellPreview> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final labels = ['Home', 'Swap', 'Activity', 'Settings'];
    return AppMobileShell(
      body: Column(
        children: [
          MobileTopNav.account(
            accountName: 'Account1',
            syncLabel: 'Vizor is synced',
          ),
          Expanded(
            child: Center(
              child: Text(
                labels[_index],
                style: AppTypography.headlineMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ),
          ),
        ],
      ),
      tabBar: AppMobileTabBar(
        items: _mobileTabItems,
        currentIndex: _index,
        onSelect: (index) => setState(() => _index = index),
      ),
    );
  }
}

Widget buildMobileSurfaceCardUseCase(BuildContext context) {
  return _phoneFrame(
    context,
    Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: MobileSurfaceCard(
        child: Column(
          children: [
            MobileListRow(
              leading: const AppProfilePicture(
                profilePictureId: 'pfp-01',
                size: AppProfilePictureSize.large,
              ),
              label: 'Account 1',
              trailing: AppIcon(
                AppIcons.copy,
                size: AppIconSize.medium,
                color: context.colors.icon.muted,
              ),
              onTap: () {},
            ),
            MobileListRow(
              leading: AppIcon(
                AppIcons.theme,
                size: 20,
                color: context.colors.icon.accent,
              ),
              label: 'Theme',
              value: 'Dark',
              showChevron: true,
              onTap: () {},
            ),
            const MobileListRow(
              label: 'Password',
              value: 'Change',
              showChevron: true,
              enabled: false,
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildMobileSheetUseCase(BuildContext context) {
  return _phoneFrame(
    context,
    Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Builder(
        builder: (context) => AppButton(
          child: const Text('Open sheet'),
          onPressed: () => showAppMobileSheet<void>(
            context: context,
            builder: (context) => SizedBox(
              height: 400,
              width: double.infinity,
              child: Center(
                child: Text(
                  'Sheet content',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
