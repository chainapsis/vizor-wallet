import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_chrome.dart';

export '../shared/onboarding_chrome.dart' show OnboardingBackTarget;

class OnboardingSecretPassphraseRevealedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setRevealed(bool value) {
    state = value;
  }
}

final onboardingSecretPassphraseRevealedProvider =
    NotifierProvider<OnboardingSecretPassphraseRevealedNotifier, bool>(
      OnboardingSecretPassphraseRevealedNotifier.new,
    );

class CreateOnboardingMnemonicNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setMnemonic(String mnemonic) {
    state = mnemonic;
  }

  void clear() {
    state = null;
  }
}

final createOnboardingMnemonicProvider =
    NotifierProvider<CreateOnboardingMnemonicNotifier, String?>(
      CreateOnboardingMnemonicNotifier.new,
    );

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

void clearCreateOnboardingSecretState(ProviderReader read) {
  read(createOnboardingMnemonicProvider.notifier).clear();
  read(onboardingSecretPassphraseRevealedProvider.notifier).setRevealed(false);
}

enum OnboardingStep {
  intro,
  addressTypes,
  thingsToKnow,
  secretPassphrase,
  setPassword,
  customiseAccount,
}

extension OnboardingStepX on OnboardingStep {
  // Sidebar step labels follow the Figma sidebar verbatim (mixed casing as
  // drawn) — see the sentence-case exception in AGENTS.md.
  String get label => switch (this) {
    OnboardingStep.intro => 'Intro to Zcash',
    OnboardingStep.addressTypes => 'Address types',
    OnboardingStep.thingsToKnow => 'Things to know',
    OnboardingStep.secretPassphrase => 'Secret Passphrase',
    OnboardingStep.setPassword => 'Set Password',
    OnboardingStep.customiseAccount => 'Customise wallet',
  };

  String get iconName => switch (this) {
    OnboardingStep.intro => AppIcons.zcash,
    OnboardingStep.addressTypes => AppIcons.shieldKeyholeOutline,
    OnboardingStep.thingsToKnow => AppIcons.crystalBall,
    OnboardingStep.secretPassphrase => AppIcons.key,
    OnboardingStep.setPassword => AppIcons.lock,
    OnboardingStep.customiseAccount => AppIcons.user,
  };

  String get routePath => switch (this) {
    OnboardingStep.intro => '/onboarding/intro',
    OnboardingStep.addressTypes => '/onboarding/address-types',
    OnboardingStep.thingsToKnow => '/onboarding/things-to-know',
    OnboardingStep.secretPassphrase => '/onboarding/secret-passphrase',
    OnboardingStep.setPassword => '/onboarding/set-password',
    OnboardingStep.customiseAccount => '/onboarding/customise-account',
  };
}

OnboardingStep onboardingStepFromLocation(String location) {
  if (location.startsWith(OnboardingStep.customiseAccount.routePath)) {
    return OnboardingStep.customiseAccount;
  }
  if (location.startsWith(OnboardingStep.setPassword.routePath)) {
    return OnboardingStep.setPassword;
  }
  if (location.startsWith(OnboardingStep.secretPassphrase.routePath)) {
    return OnboardingStep.secretPassphrase;
  }
  if (location.startsWith(OnboardingStep.thingsToKnow.routePath)) {
    return OnboardingStep.thingsToKnow;
  }
  if (location.startsWith(OnboardingStep.addressTypes.routePath)) {
    return OnboardingStep.addressTypes;
  }
  if (location.startsWith(OnboardingStep.intro.routePath)) {
    return OnboardingStep.intro;
  }
  return OnboardingStep.intro;
}

class OnboardingSplitViewShell extends ConsumerWidget {
  const OnboardingSplitViewShell({
    required this.activeStep,
    required this.showPasswordStep,
    required this.child,
    super.key,
  });

  final OnboardingStep activeStep;
  final bool showPasswordStep;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secretPassphraseRevealed = ref.watch(
      onboardingSecretPassphraseRevealedProvider,
    );
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: kOnboardingForwardCurve,
      reverseCurve: kOnboardingReverseCurve,
    );
    final sidebarOffset = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(entrance);

    return AppDesktopShell(
      sidebarWidth: 256,
      background: _OnboardingWindowBackground(activeStep: activeStep),
      sidebar: SlideTransition(
        position: sidebarOffset,
        child: _Sidebar(
          activeStep: activeStep,
          showPasswordStep: showPasswordStep,
          secretPassphraseRevealed: secretPassphraseRevealed,
        ),
      ),
      pane: FadeTransition(opacity: entrance, child: child),
    );
  }
}

class _OnboardingWindowBackground extends StatelessWidget {
  const _OnboardingWindowBackground({required this.activeStep});

  final OnboardingStep activeStep;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (activeStep) {
      OnboardingStep.secretPassphrase =>
        isDark
            ? 'assets/illustrations/onboarding_secret_passphrase_background_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_background_light.png',
      // Figma uses the same castle line-art for both themes (alpha-only
      // strokes composite against the window color), so one asset serves
      // light and dark.
      OnboardingStep.setPassword =>
        'assets/illustrations/onboarding_set_password_background_light.png',
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

class OnboardingTrailingPane extends StatelessWidget {
  const OnboardingTrailingPane({
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
  const _Sidebar({
    required this.activeStep,
    required this.showPasswordStep,
    required this.secretPassphraseRevealed,
  });

  final OnboardingStep activeStep;
  final bool showPasswordStep;
  final bool secretPassphraseRevealed;

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
      illustration: AnimatedSwitcher(
        duration: kOnboardingForwardDuration,
        reverseDuration: kOnboardingReverseDuration,
        switchInCurve: kOnboardingForwardCurve,
        switchOutCurve: kOnboardingReverseCurve,
        transitionBuilder: _fadeTransition,
        child: KeyedSubtree(
          key: ValueKey('${activeStep.name}:$secretPassphraseRevealed'),
          child: _SidebarIllustration(
            step: activeStep,
            secretPassphraseRevealed: secretPassphraseRevealed,
          ),
        ),
      ),
    );
  }

  List<OnboardingStep> get _steps => [
    OnboardingStep.intro,
    OnboardingStep.addressTypes,
    OnboardingStep.thingsToKnow,
    OnboardingStep.secretPassphrase,
    if (showPasswordStep) OnboardingStep.setPassword,
    OnboardingStep.customiseAccount,
  ];

  Widget _fadeTransition(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration({
    required this.step,
    required this.secretPassphraseRevealed,
  });

  final OnboardingStep step;
  final bool secretPassphraseRevealed;

  static const _frameWidth = 256.0;
  static const _frameHeight = 430.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (step) {
      OnboardingStep.secretPassphrase =>
        secretPassphraseRevealed
            ? isDark
                  ? 'assets/illustrations/onboarding_secret_passphrase_sidebar_open_dark.png'
                  : 'assets/illustrations/onboarding_secret_passphrase_sidebar_open_light.png'
            : isDark
            ? 'assets/illustrations/onboarding_secret_passphrase_sidebar_closed_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_sidebar_closed_light.png',
      OnboardingStep.setPassword =>
        isDark
            ? 'assets/illustrations/onboarding_set_password_sidebar_dark.png'
            : 'assets/illustrations/onboarding_set_password_sidebar_light.png',
      OnboardingStep.customiseAccount =>
        'assets/illustrations/onboarding_customise_account_sidebar.png',
      OnboardingStep.thingsToKnow =>
        isDark
            ? 'assets/illustrations/onboarding_things_to_know_sidebar_dark.png'
            : 'assets/illustrations/onboarding_things_to_know_sidebar_light.png',
      OnboardingStep.addressTypes =>
        isDark
            ? 'assets/illustrations/onboarding_address_types_sidebar_dark.png'
            : 'assets/illustrations/onboarding_address_types_sidebar_light.png',
      _ =>
        isDark
            ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
            : 'assets/illustrations/onboarding_intro_sidebar_light.png',
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
