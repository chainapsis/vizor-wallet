import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/wallet/keystone.dart' show KeystoneAccountInfo;

enum KeystoneOnboardingStep {
  howToConnect,
  scanQrCode,
  selectAccount,
  walletBirthdayHeight,
  setPassword,
}

extension KeystoneOnboardingStepX on KeystoneOnboardingStep {
  String get label => switch (this) {
    KeystoneOnboardingStep.howToConnect => 'How to Connect',
    KeystoneOnboardingStep.scanQrCode => 'Scan QR Code',
    KeystoneOnboardingStep.selectAccount => 'Select Account',
    KeystoneOnboardingStep.walletBirthdayHeight => 'Wallet Birthday Height',
    KeystoneOnboardingStep.setPassword => 'Set Password',
  };

  String get iconName => switch (this) {
    KeystoneOnboardingStep.howToConnect => AppIcons.book,
    KeystoneOnboardingStep.scanQrCode => AppIcons.qr,
    KeystoneOnboardingStep.selectAccount => AppIcons.user,
    KeystoneOnboardingStep.walletBirthdayHeight => AppIcons.block,
    KeystoneOnboardingStep.setPassword => AppIcons.lock,
  };

  String get routePath => switch (this) {
    KeystoneOnboardingStep.howToConnect => '/onboarding/keystone',
    KeystoneOnboardingStep.scanQrCode => '/onboarding/keystone/scan',
    KeystoneOnboardingStep.selectAccount =>
      '/onboarding/keystone/select-account',
    KeystoneOnboardingStep.walletBirthdayHeight =>
      '/onboarding/keystone/birthday',
    KeystoneOnboardingStep.setPassword => '/onboarding/keystone/set-password',
  };
}

KeystoneOnboardingStep keystoneOnboardingStepFromLocation(String location) {
  if (location.startsWith(KeystoneOnboardingStep.setPassword.routePath)) {
    return KeystoneOnboardingStep.setPassword;
  }
  if (location.startsWith(
    KeystoneOnboardingStep.walletBirthdayHeight.routePath,
  )) {
    return KeystoneOnboardingStep.walletBirthdayHeight;
  }
  if (location.startsWith(KeystoneOnboardingStep.selectAccount.routePath)) {
    return KeystoneOnboardingStep.selectAccount;
  }
  if (location.startsWith(KeystoneOnboardingStep.scanQrCode.routePath)) {
    return KeystoneOnboardingStep.scanQrCode;
  }
  return KeystoneOnboardingStep.howToConnect;
}

class KeystoneOnboardingState {
  const KeystoneOnboardingState({
    this.accounts = const <KeystoneAccountInfo>[],
    this.selectedAccount,
  });

  final List<KeystoneAccountInfo> accounts;
  final KeystoneAccountInfo? selectedAccount;

  KeystoneOnboardingState copyWith({
    List<KeystoneAccountInfo>? accounts,
    KeystoneAccountInfo? selectedAccount,
    bool clearSelectedAccount = false,
  }) {
    return KeystoneOnboardingState(
      accounts: accounts ?? this.accounts,
      selectedAccount: clearSelectedAccount
          ? null
          : selectedAccount ?? this.selectedAccount,
    );
  }
}

class KeystoneOnboardingNotifier extends Notifier<KeystoneOnboardingState> {
  @override
  KeystoneOnboardingState build() => const KeystoneOnboardingState();

  void resetScan() {
    state = const KeystoneOnboardingState();
  }

  void setAccounts(List<KeystoneAccountInfo> accounts) {
    state = KeystoneOnboardingState(
      accounts: List.unmodifiable(accounts),
      selectedAccount: accounts.isEmpty ? null : accounts.first,
    );
  }

  void selectAccount(KeystoneAccountInfo account) {
    state = state.copyWith(selectedAccount: account);
  }
}

final keystoneOnboardingProvider =
    NotifierProvider<KeystoneOnboardingNotifier, KeystoneOnboardingState>(
      KeystoneOnboardingNotifier.new,
    );

class KeystoneOnboardingShell extends StatelessWidget {
  const KeystoneOnboardingShell({
    required this.activeStep,
    required this.showPasswordStep,
    required this.child,
    super.key,
  });

  final KeystoneOnboardingStep activeStep;
  final bool showPasswordStep;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: kOnboardingForwardCurve,
      reverseCurve: kOnboardingReverseCurve,
    );

    return AppDesktopShell(
      sidebarWidth: 256,
      sidebar: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(entrance),
        child: _Sidebar(
          activeStep: activeStep,
          showPasswordStep: showPasswordStep,
        ),
      ),
      pane: FadeTransition(opacity: entrance, child: child),
    );
  }
}

class KeystoneOnboardingTrailingPane extends StatelessWidget {
  const KeystoneOnboardingTrailingPane({
    required this.child,
    this.overlay,
    super.key,
  });

  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final overlay = this.overlay;
    if (overlay == null) {
      return AppDesktopPane(child: child);
    }

    return AppDesktopPane(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
          overlay,
        ],
      ),
    );
  }
}

class KeystoneBackRow extends StatelessWidget {
  const KeystoneBackRow({required this.routePath, this.routeExtra, super.key});

  final String routePath;
  final Object? routeExtra;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.go(routePath, extra: routeExtra),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.chevronBackward,
                  size: AppIconSize.medium,
                  color: colors.text.accent,
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
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activeStep, required this.showPasswordStep});

  final KeystoneOnboardingStep activeStep;
  final bool showPasswordStep;

  List<KeystoneOnboardingStep> get _steps => [
    KeystoneOnboardingStep.howToConnect,
    KeystoneOnboardingStep.scanQrCode,
    KeystoneOnboardingStep.selectAccount,
    KeystoneOnboardingStep.walletBirthdayHeight,
    if (showPasswordStep) KeystoneOnboardingStep.setPassword,
  ];

  @override
  Widget build(BuildContext context) {
    return AppDesktopSidebarSurface(
      child: Stack(
        children: [
          const Positioned.fill(child: _SidebarIllustration()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _steps.length; i++) ...[
                      _KeystoneSidebarItem(
                        label: _steps[i].label,
                        iconName: _steps[i].iconName,
                        active: _steps[i] == activeStep,
                      ),
                      if (i != _steps.length - 1)
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeystoneSidebarItem extends StatelessWidget {
  const _KeystoneSidebarItem({
    required this.label,
    required this.iconName,
    required this.active,
  });

  final String label;
  final String iconName;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: active ? colors.state.selectedOpacity : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          AppIcon(iconName, size: 20, color: colors.icon.accent),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  static const _frameWidth = 256.0;
  static const _frameHeight = 405.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
        : 'assets/illustrations/onboarding_intro_sidebar_light.png';
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
