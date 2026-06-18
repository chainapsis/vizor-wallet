import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/wallet/keystone.dart' show KeystoneAccountInfo;
import '../shared/onboarding_chrome.dart';

export '../shared/onboarding_chrome.dart' show OnboardingBackTarget;

enum KeystoneOnboardingStep {
  howToConnect,
  scanQrCode,
  selectAccount,
  walletBirthdayHeight,
  setPassword,
}

extension KeystoneOnboardingStepX on KeystoneOnboardingStep {
  // Sidebar step labels keep their original Title Case — see the
  // sentence-case exception in AGENTS.md (UI Copy Conventions).
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
    final normalizedAccounts = accounts
        .map(_withFallbackAccountName)
        .toList(growable: false);
    state = KeystoneOnboardingState(
      accounts: List.unmodifiable(normalizedAccounts),
      selectedAccount: normalizedAccounts.isEmpty
          ? null
          : normalizedAccounts.first,
    );
  }

  void selectAccount(KeystoneAccountInfo account) {
    state = state.copyWith(selectedAccount: _withFallbackAccountName(account));
  }

  KeystoneAccountInfo _withFallbackAccountName(KeystoneAccountInfo account) {
    if (account.name.trim().isNotEmpty) return account;
    return KeystoneAccountInfo(
      name: 'Account ${account.index + 1}',
      ufvk: account.ufvk,
      index: account.index,
      seedFingerprint: account.seedFingerprint,
    );
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
      background: _KeystoneOnboardingWindowBackground(activeStep: activeStep),
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

class _KeystoneOnboardingWindowBackground extends StatelessWidget {
  const _KeystoneOnboardingWindowBackground({required this.activeStep});

  final KeystoneOnboardingStep activeStep;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (activeStep) {
      KeystoneOnboardingStep.setPassword =>
        isDark
            ? 'assets/illustrations/onboarding_secret_passphrase_background_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_background_light.png',
      _ => null,
    };

    if (asset == null) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: context.colors.background.window),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }
}

class KeystoneOnboardingTrailingPane extends StatelessWidget {
  const KeystoneOnboardingTrailingPane({
    required this.child,
    this.backTarget,
    this.overlay,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 16, 12, 16),
    super.key,
  });

  final Widget child;
  final OnboardingBackTarget? backTarget;
  final Widget? overlay;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    return OnboardingPaneChrome(
      backTarget: backTarget,
      overlay: overlay,
      bodyPadding: bodyPadding,
      child: child,
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
    return OnboardingSidebarChrome(
      steps: [
        for (final step in _steps)
          OnboardingSidebarStepData(
            label: step.label,
            iconName: step.iconName,
            active: step == activeStep,
          ),
      ],
      illustration: _SidebarIllustration(activeStep: activeStep),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration({required this.activeStep});

  final KeystoneOnboardingStep activeStep;

  static const _frameWidth = 256.0;
  static const _frameHeight = 405.0;
  static const _lightAsset =
      'assets/illustrations/onboarding_keystone_sidebar_light.png';
  static const _darkAsset =
      'assets/illustrations/onboarding_keystone_sidebar_dark.png';

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (activeStep) {
      KeystoneOnboardingStep.walletBirthdayHeight =>
        isDark
            ? 'assets/illustrations/onboarding_wallet_birthday_sidebar_dark.png'
            : 'assets/illustrations/onboarding_wallet_birthday_sidebar_light.png',
      KeystoneOnboardingStep.setPassword =>
        isDark
            ? 'assets/illustrations/onboarding_set_password_sidebar_dark.png'
            : 'assets/illustrations/onboarding_set_password_sidebar_light.png',
      _ => isDark ? _darkAsset : _lightAsset,
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}
