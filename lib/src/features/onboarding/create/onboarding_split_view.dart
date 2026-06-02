import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

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
}

extension OnboardingStepX on OnboardingStep {
  String get label => switch (this) {
    OnboardingStep.intro => 'Intro to Zcash',
    OnboardingStep.addressTypes => 'Address types',
    OnboardingStep.thingsToKnow => 'Things to know',
    OnboardingStep.secretPassphrase => 'Secret Passphrase',
    OnboardingStep.setPassword => 'Set Password',
  };

  String get iconName => switch (this) {
    OnboardingStep.intro => AppIcons.zcash,
    OnboardingStep.addressTypes => AppIcons.shieldKeyholeOutline,
    OnboardingStep.thingsToKnow => AppIcons.crystalBall,
    OnboardingStep.secretPassphrase => AppIcons.key,
    OnboardingStep.setPassword => AppIcons.lock,
  };

  String get routePath => switch (this) {
    OnboardingStep.intro => '/onboarding/intro',
    OnboardingStep.addressTypes => '/onboarding/address-types',
    OnboardingStep.thingsToKnow => '/onboarding/things-to-know',
    OnboardingStep.secretPassphrase => '/onboarding/secret-passphrase',
    OnboardingStep.setPassword => '/onboarding/set-password',
  };
}

OnboardingStep onboardingStepFromLocation(String location) {
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
      showSidebar: isDesktopLayoutPlatform,
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

class OnboardingTrailingPane extends StatelessWidget {
  const OnboardingTrailingPane({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppDesktopPane(child: child);
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
    return AppDesktopSidebarSurface(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
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
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: AnimatedSwitcher(
                duration: kOnboardingForwardDuration,
                reverseDuration: kOnboardingReverseDuration,
                switchInCurve: kOnboardingForwardCurve,
                switchOutCurve: kOnboardingReverseCurve,
                transitionBuilder: _fadeTransition,
                child: KeyedSubtree(
                  key: ValueKey(activeStep),
                  child: _SidebarNav(
                    activeStep: activeStep,
                    showPasswordStep: showPasswordStep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadeTransition(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({required this.activeStep, required this.showPasswordStep});

  final OnboardingStep activeStep;
  final bool showPasswordStep;

  List<OnboardingStep> get _steps => [
    OnboardingStep.intro,
    OnboardingStep.addressTypes,
    OnboardingStep.thingsToKnow,
    OnboardingStep.secretPassphrase,
    if (showPasswordStep) OnboardingStep.setPassword,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _OnboardingSidebarItem(
              label: _steps[i].label,
              iconName: _steps[i].iconName,
              active: _steps[i] == activeStep,
            ),
            if (i != _steps.length - 1) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _OnboardingSidebarItem extends StatelessWidget {
  const _OnboardingSidebarItem({
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
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
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
  static const _frameHeight = 405.0;

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
            ? 'assets/illustrations/onboarding_secret_passphrase_sidebar_open_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_sidebar_open_light.png',
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
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
