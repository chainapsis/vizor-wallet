import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_bootstrap.dart';
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/theme_mode_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider).value;
    final activeAccountName = accountState?.activeAccount?.name ?? 'Wallet 1';
    final activeAccountIsHardware =
        accountState?.activeAccount?.isHardware ?? false;
    final themeMode = ref.watch(themeModeProvider);
    final endpointLabel = _endpointLabel(
      ref.watch(appBootstrapProvider).network,
    );

    return AppDesktopShell(
      sidebarWidth: 240,
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _SettingsPane(
          accountName: activeAccountName,
          activeAccountIsHardware: activeAccountIsHardware,
          endpointLabel: endpointLabel,
          themeLabel: _themeLabel(themeMode),
          onBack: () => _handleBack(context),
          onSeedPhrase: () => context.go('/settings/secret-passphrase'),
          onChangePassword: () => context.go('/settings/change-password'),
        ),
      ),
    );
  }

  static void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  static String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
  }

  static String _endpointLabel(String networkName) {
    final network = networkName == ZcashNetwork.testnet.name
        ? ZcashNetwork.testnet
        : ZcashNetwork.mainnet;
    return network.lightwalletdHost;
  }
}

class _SettingsPane extends StatelessWidget {
  const _SettingsPane({
    required this.accountName,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.onBack,
    required this.onSeedPhrase,
    required this.onChangePassword,
  });

  final String accountName;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final VoidCallback onBack;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _SettingsBackButton(onTap: onBack),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 752),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Settings',
                        textAlign: TextAlign.center,
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const AppDecorativeDivider(width: 256),
                      const SizedBox(height: AppSpacing.sm),
                      _SettingsList(
                        accountName: accountName,
                        activeAccountIsHardware: activeAccountIsHardware,
                        endpointLabel: endpointLabel,
                        themeLabel: themeLabel,
                        onSeedPhrase: onSeedPhrase,
                        onChangePassword: onChangePassword,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsBackButton extends StatelessWidget {
  const _SettingsBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.accountName,
    required this.activeAccountIsHardware,
    required this.endpointLabel,
    required this.themeLabel,
    required this.onSeedPhrase,
    required this.onChangePassword,
  });

  final String accountName;
  final bool activeAccountIsHardware;
  final String endpointLabel;
  final String themeLabel;
  final VoidCallback onSeedPhrase;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsBlock(
          title: 'Account',
          rows: [
            _SettingsRow(
              iconName: AppIcons.key,
              label: 'Secret Passphrase',
              value: activeAccountIsHardware ? 'Unavailable' : 'View',
              onTap: activeAccountIsHardware ? null : onSeedPhrase,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.lock,
              label: 'Password',
              value: 'Change',
              onTap: onChangePassword,
            ),
            const _SettingsRowDivider(),
            const _SettingsRow(
              iconName: AppIcons.users,
              label: 'Profile Picture',
              value: 'Knight',
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.scroll,
              label: 'Account Name',
              value: accountName,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _SettingsBlock(
          title: 'System',
          rows: [
            _SettingsRow(
              iconName: AppIcons.endpoint,
              label: 'Endpoint',
              value: endpointLabel,
            ),
            const _SettingsRowDivider(),
            _SettingsRow(
              iconName: AppIcons.theme,
              label: 'Theme',
              value: themeLabel,
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsBlock extends StatelessWidget {
  const _SettingsBlock({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ],
    );
  }
}

class _SettingsRowDivider extends StatelessWidget {
  const _SettingsRowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.border.subtle),
        child: const SizedBox(height: 1),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.iconName,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String iconName;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          _SettingsRowIcon(iconName: iconName),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.chevronForward, size: 16, color: colors.icon.accent),
        ],
      ),
    );

    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class _SettingsRowIcon extends StatelessWidget {
  const _SettingsRowIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AppIcon(iconName, size: 16, color: colors.icon.regular),
    );
  }
}
