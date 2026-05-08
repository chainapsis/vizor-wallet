import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState =
        ref.watch(accountProvider).value ?? const AccountState();
    final accounts = [...accountState.accounts]
      ..sort((a, b) => a.order.compareTo(b.order));
    final activeAccount = _activeAccountFor(
      accounts,
      accountState.activeAccountUuid,
    );
    final otherAccounts = [
      for (final account in accounts)
        if (account.uuid != activeAccount?.uuid) account,
    ];

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        child: _AccountsPane(
          activeAccount: activeAccount,
          otherAccounts: otherAccounts,
          onSelectAccount: (uuid) => _handleAccountSelected(ref, uuid),
        ),
      ),
    );
  }

  static Future<void> _handleAccountSelected(WidgetRef ref, String uuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (uuid == activeAccountUuid) return;
    await ref.read(accountProvider.notifier).switchAccount(uuid);
    await ref.read(syncProvider.notifier).refreshAfterSend();
  }

  static AccountInfo? _activeAccountFor(
    List<AccountInfo> accounts,
    String? activeAccountUuid,
  ) {
    if (accounts.isEmpty) return null;
    for (final account in accounts) {
      if (account.uuid == activeAccountUuid) return account;
    }
    return accounts.first;
  }
}

class _AccountsPane extends StatelessWidget {
  const _AccountsPane({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
  });

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Accounts',
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySmall.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        const AppDecorativeDivider(width: 256),
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          child: _AccountsList(
                            activeAccount: activeAccount,
                            otherAccounts: otherAccounts,
                            onSelectAccount: onSelectAccount,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    onPressed: () => context.go('/add-account'),
                    minWidth: 256,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: const Text('Add Account'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsList extends StatelessWidget {
  const _AccountsList({
    required this.activeAccount,
    required this.otherAccounts,
    required this.onSelectAccount,
  });

  static const _width = 352.0;

  final AccountInfo? activeAccount;
  final List<AccountInfo> otherAccounts;
  final Future<void> Function(String uuid) onSelectAccount;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (activeAccount != null)
              _AccountRow(
                key: ValueKey('accounts_active_row_${activeAccount!.uuid}'),
                account: activeAccount!,
                onTap: null,
              ),
            const _AccountsSectionLabel(label: 'Other'),
            if (otherAccounts.isNotEmpty)
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: otherAccounts.length,
                  itemBuilder: (context, index) {
                    final account = otherAccounts[index];
                    return _AccountRow(
                      key: ValueKey('accounts_other_row_${account.uuid}'),
                      account: account,
                      onTap: () {
                        onSelectAccount(account.uuid);
                      },
                    );
                  },
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountsSectionLabel extends StatelessWidget {
  const _AccountsSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

class _AccountRow extends StatefulWidget {
  const _AccountRow({required this.account, required this.onTap, super.key});

  final AccountInfo account;
  final VoidCallback? onTap;

  @override
  State<_AccountRow> createState() => _AccountRowState();
}

class _AccountRowState extends State<_AccountRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: _isHovered ? colors.state.hover : null,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Row(
                  children: [
                    AppProfilePicture(
                      profilePictureId: widget.account.profilePictureId,
                      size: AppProfilePictureSize.large,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        widget.account.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _AccountRowMenuButton(),
          ],
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() {
      _isHovered = value;
    });
  }
}

class _AccountRowMenuButton extends StatelessWidget {
  const _AccountRowMenuButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Center(
        child: Text(
          '...',
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.accent,
            height: 1,
          ),
        ),
      ),
    );
  }
}
