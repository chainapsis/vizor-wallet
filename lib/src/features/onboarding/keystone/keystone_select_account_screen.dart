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
    final state = ref.watch(keystoneOnboardingProvider);
    final accounts = state.accounts;
    final selected = state.selectedAccount;

    return KeystoneOnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: KeystoneOnboardingStep.scanQrCode.label,
        routePath: KeystoneOnboardingStep.scanQrCode.routePath,
      ),
      bodyPadding: EdgeInsets.zero,
      child: _SelectAccountLayout(
        accounts: accounts,
        selectedAccount: selected,
        onSelect: (account) {
          ref.read(keystoneOnboardingProvider.notifier).selectAccount(account);
        },
        onContinue: _continue,
      ),
    );
  }
}

class _SelectAccountLayout extends StatelessWidget {
  const _SelectAccountLayout({
    required this.accounts,
    required this.selectedAccount,
    required this.onSelect,
    required this.onContinue,
  });

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  final List<KeystoneAccountInfo> accounts;
  final KeystoneAccountInfo? selectedAccount;
  final ValueChanged<KeystoneAccountInfo> onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: _OnPageContent(
                        accounts: accounts,
                        selectedAccount: selectedAccount,
                        onSelect: onSelect,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -9,
                      child: _FloatingConfirmButton(
                        enabled: selectedAccount != null,
                        onPressed: onContinue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent({
    required this.accounts,
    required this.selectedAccount,
    required this.onSelect,
  });

  static const double _sectionGap = 32;

  final List<KeystoneAccountInfo> accounts;
  final KeystoneAccountInfo? selectedAccount;
  final ValueChanged<KeystoneAccountInfo> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _TitleBlock(),
        const SizedBox(height: _sectionGap),
        _AccountPicker(
          accounts: accounts,
          selectedAccount: selectedAccount,
          onSelect: onSelect,
        ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Select account',
            style: AppTypography.displayLarge.copyWith(
              fontFamily: 'Young Serif',
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 226,
          child: Text(
            'Prepare your Keystone wallet',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _FloatingConfirmButton extends StatelessWidget {
  const _FloatingConfirmButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final background = context.colors.background.window;
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background.withValues(alpha: 0), background],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AppButton(
          onPressed: enabled ? onPressed : null,
          variant: AppButtonVariant.primary,
          minWidth: 196,
          child: const Text('Confirm selection'),
        ),
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
        '${accounts.length} ${accounts.length == 1 ? 'account' : 'accounts'} found';

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              countLabel,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
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
    final borderColor = selected
        ? colors.border.strong
        : const Color(0x00000000);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
            top: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: colors.surface.input,
            border: Border.all(color: borderColor, width: selected ? 2 : 0),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            boxShadow: _accountCardShadow(colors, selected: selected),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Opacity(
                    opacity: selected ? 1 : 0.5,
                    child: AppIcon(
                      AppIcons.user,
                      size: 18,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _accountName(account),
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _shortUfvk(account.ufvk),
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: selected
                              ? colors.text.accent
                              : colors.text.secondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

List<BoxShadow> _accountCardShadow(AppColors colors, {required bool selected}) {
  if (selected) {
    return [
      BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
      BoxShadow(
        color: colors.shadows.subtle,
        offset: const Offset(0, 2),
        blurRadius: 4,
      ),
      BoxShadow(
        color: colors.shadows.subtle,
        offset: const Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    ];
  }
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 0.5),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 2,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 1,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 0.5),
  ];
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
