import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/wallet/keystone.dart' show KeystoneAccountInfo;
import 'keystone_onboarding_flow.dart';

class KeystoneSelectAccountScreen extends ConsumerStatefulWidget {
  const KeystoneSelectAccountScreen({super.key});

  @override
  ConsumerState<KeystoneSelectAccountScreen> createState() =>
      _KeystoneSelectAccountScreenState();
}

class _KeystoneSelectAccountScreenState
    extends ConsumerState<KeystoneSelectAccountScreen> {
  void _continue() {
    context.go(KeystoneOnboardingStep.walletBirthdayHeight.routePath);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(keystoneOnboardingProvider);
    final accounts = state.accounts;
    final selected = state.selectedAccount;

    return KeystoneOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: KeystoneOnboardingStep.scanQrCode.label,
        routePath: KeystoneOnboardingStep.scanQrCode.routePath,
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select account',
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: 360,
                      child: Text(
                        'Choose the Keystone account you want to import into Vizor.',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _AccountPicker(
                      accounts: accounts,
                      selectedAccount: selected,
                      onSelect: (account) {
                        ref
                            .read(keystoneOnboardingProvider.notifier)
                            .selectAccount(account);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 256,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  onPressed: selected == null ? null : _continue,
                  variant: AppButtonVariant.primary,
                  minWidth: 256,
                  trailing: const AppIcon(AppIcons.chevronForward),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPicker extends StatefulWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedAccount,
    required this.onSelect,
  });

  final List<KeystoneAccountInfo> accounts;
  final KeystoneAccountInfo? selectedAccount;
  final ValueChanged<KeystoneAccountInfo> onSelect;

  @override
  State<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<_AccountPicker> {
  final _scrollController = ScrollController();

  static const _width = 304.0;
  static const _maxListHeight = 280.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accounts = widget.accounts;
    final countLabel =
        '${accounts.length} ${accounts.length == 1 ? 'Account' : 'Accounts'} found';

    return SizedBox(
      width: _width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              countLabel,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.large),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxListHeight),
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: accounts.length > 4,
                child: ListView.separated(
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    return _AccountRadioCard(
                      account: account,
                      selected: identical(account, widget.selectedAccount),
                      onTap: () => widget.onSelect(account),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRadioCard extends StatelessWidget {
  const _AccountRadioCard({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final KeystoneAccountInfo account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = selected ? colors.border.strong : colors.border.regular;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
            top: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: Row(
            children: [
              Opacity(
                opacity: selected ? 1 : 0.5,
                child: AppIcon(
                  AppIcons.users,
                  size: 18,
                  color: colors.icon.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _accountName(account),
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _shortUfvk(account.ufvk),
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _RadioIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }

  String _accountName(KeystoneAccountInfo account) {
    final name = account.name.trim();
    return name.isEmpty ? 'Account ${account.index + 1}' : name;
  }

  String _shortUfvk(String ufvk) {
    if (ufvk.length <= 28) return ufvk;
    return '${ufvk.substring(0, 12)} ... ${ufvk.substring(ufvk.length - 12)}';
  }
}

class _RadioIndicator extends StatelessWidget {
  const _RadioIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: selected
          ? AppIcon(AppIcons.check, size: 12, color: colors.text.inverse)
          : null,
    );
  }
}
