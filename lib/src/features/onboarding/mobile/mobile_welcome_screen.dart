import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/external_action_guard_provider.dart';
import '../shared/create_account_submission.dart';
import '../shared/onboarding_error_messages.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/app_language_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../settings/widgets/language_picker.dart';
import '../shared/welcome_language_button.dart';
import '../providers/welcome_network_settings_provider.dart';
import 'mobile_network_settings_sheet.dart';

import 'mobile_onboarding_progress_scope.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../core/layout/mobile/mobile_window_policy.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_welcome_art.dart' show VizorWordmark;
import 'mobile_welcome_backdrop.dart';
import '../shared/welcome_accent_button.dart';
import '../shared/welcome_button_tokens.dart';
import '../shared/welcome_gift_card_button.dart';

/// Figma `Welcome` (8635:103040): native video with create and import entry paths.
class MobileWelcomeScreen extends ConsumerStatefulWidget {
  const MobileWelcomeScreen({
    this.showBackButton = false,
    this.animateBackground = true,
    super.key,
  });

  /// `/add-account` returns home and offers the same Gift Card setup choices.
  final bool showBackButton;
  final bool animateBackground;

  @override
  ConsumerState<MobileWelcomeScreen> createState() =>
      _MobileWelcomeScreenState();
}

class _MobileWelcomeScreenState extends ConsumerState<MobileWelcomeScreen> {
  bool _openingScheduled = false;
  final _creation = CreateAccountSubmission();
  bool _creating = false;
  OnboardingSubmitError? _createError;
  bool get _creationBlocksNavigation => _creating || _creation.requiresRecovery;

  Future<void> _createWallet() async {
    if (_creating) return;
    final lease = ref.read(externalActionGuardProvider.notifier).tryProtect();
    if (lease == null) return;
    setState(() {
      _creating = true;
      _createError = null;
    });
    try {
      await _creation.continueSetup(ref);
    } catch (error) {
      if (mounted) {
        _createError = OnboardingSubmitError.fromError(
          error,
          requiresRecovery: _creation.requiresRecovery,
        );
      }
    } finally {
      lease.release();
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.showBackButton &&
        !welcomeNetworkReady(ref.read(networkPrivacyProvider))) {
      _scheduleSettings();
    }
  }

  void _scheduleSettings() {
    if (_openingScheduled ||
        ref.read(welcomeNetworkSettingsPresentedProvider)) {
      return;
    }
    _openingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingScheduled = false;
      if (!mounted ||
          widget.showBackButton ||
          ModalRoute.of(context)?.isCurrent != true ||
          welcomeNetworkReady(ref.read(networkPrivacyProvider))) {
        return;
      }
      showMobileWelcomeNetworkSettings(context, ref);
    });
  }

  // Holds incoming Gift links like the network sheet does.
  Future<void> _openLanguageSheet() async {
    if (_creationBlocksNavigation ||
        ref.read(welcomeNetworkSettingsPresentedProvider)) {
      return;
    }
    final presentation = ref.read(
      welcomeNetworkSettingsPresentedProvider.notifier,
    );
    final current = ref.read(appLanguageProvider);
    presentation.setPresented(true);
    try {
      final choice = await showMobileLanguageSheet(
        context,
        current: current,
        available: ref.read(availableAppLanguagesProvider),
      );
      if (choice == null || choice == current) return;
      await ref.read(appLanguageProvider.notifier).set(choice);
    } catch (_) {
      if (mounted) {
        showAppToast(context, context.l10n.settingsLanguageUpdateFailed);
      }
    } finally {
      presentation.setPresented(false);
    }
  }

  void _enter(VoidCallback navigate) {
    if (_creationBlocksNavigation) return;
    if (!widget.showBackButton &&
        !welcomeNetworkReady(ref.read(networkPrivacyProvider))) {
      showMobileWelcomeNetworkSettings(context, ref);
      return;
    }
    if (!ref.read(welcomeNetworkSettingsPresentedProvider)) navigate();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(networkPrivacyProvider, (_, state) {
      if (!widget.showBackButton && !welcomeNetworkReady(state)) {
        _scheduleSettings();
      }
    });
    final windowPolicy = MobileWindowPolicyScope.of(context);
    final showLanguage =
        !widget.showBackButton &&
        ref.watch(availableAppLanguagesProvider).length > 1;
    final bottom = MediaQuery.paddingOf(context).bottom + kMobileFooterGap;
    return PopScope<void>(
      canPop: !_creationBlocksNavigation,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xff0f0f0f),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final insets = MediaQuery.paddingOf(context);
              final safeWidth = constraints.maxWidth - insets.horizontal;
              final landscape = windowPolicy.usesWideLayout;
              // Keep 240-point mobile buttons and 16-point side padding even in
              // a short, wide window below the former 740-point breakpoint.
              final paneWidth = (safeWidth * 0.4).clamp(272.0, 420.0);
              final artWidth = math.max(
                constraints.maxHeight * 16 / 9,
                safeWidth - paneWidth,
              );
              final paneRight = insets.left + paneWidth;
              final artCenter =
                  (paneRight + constraints.maxWidth - insets.right) / 2;
              final videoHeight = (constraints.maxWidth + 1) * 700 / 394;
              final fadeEnd = math.min(
                1.0,
                videoHeight / constraints.maxHeight,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 394×700 video slot at x=-1 in the 393×852 reference.
                  Positioned(
                    top: 0,
                    left: landscape ? artCenter - artWidth / 2 : -1,
                    width: landscape ? artWidth : constraints.maxWidth + 1,
                    height: landscape ? constraints.maxHeight : videoHeight,
                    child: MobileWelcomeBackdrop(
                      animate: widget.animateBackground,
                      landscape: landscape,
                    ),
                  ),
                  if (landscape)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      width: paneRight + 180,
                      child: const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xff0f0f0f),
                                Color(0xff0f0f0f),
                                Color(0x990f0f0f),
                                Color(0x000f0f0f),
                              ],
                              stops: [0, 0.35, 0.7, 1],
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: const [
                                Color(0x00000000),
                                Color(0x99000000),
                                Color(0xff000000),
                              ],
                              // Keep the artwork visible behind the copy, then
                              // blend its bottom edge into the page background.
                              stops: [
                                fadeEnd * 0.40857,
                                fadeEnd * 0.88,
                                fadeEnd,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (landscape)
                    Positioned(
                      left: insets.left,
                      top: insets.top,
                      bottom: insets.bottom,
                      width: paneWidth,
                      child: Center(
                        child: SingleChildScrollView(
                          // Leave room for Back even in short windows.
                          padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
                          child: _buildContent(context),
                        ),
                      ),
                    )
                  else
                    SafeArea(
                      bottom: false,
                      child: LayoutBuilder(
                        builder: (context, available) => SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            kMobilePageMargin,
                            24,
                            kMobilePageMargin,
                            bottom,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0,
                                available.maxHeight - bottom - 24,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [_buildContent(context)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!widget.showBackButton)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
                      right: (landscape ? insets.right : 0) + kMobilePageMargin,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showLanguage) ...[
                            WelcomeLanguageButton(
                              key: const ValueKey('mobile_welcome_language'),
                              height: 44,
                              background: const Color(0x66000000),
                              hoverBackground: const Color(0x66000000),
                              onTap: () => unawaited(_openLanguageSheet()),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          Semantics(
                            label: context.l10n.networkSettingsTitle,
                            button: true,
                            child: GestureDetector(
                              key: const ValueKey(
                                'mobile_welcome_network_settings',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onTap: _creationBlocksNavigation
                                  ? null
                                  : () => showMobileWelcomeNetworkSettings(
                                      context,
                                      ref,
                                    ),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Color(0x66000000),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: AppIcon(
                                    AppIcons.cog,
                                    size: 24,
                                    color: Color(0xffffffff),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.showBackButton)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
                      left: (landscape ? insets.left : 0) + AppSpacing.s,
                      child: Semantics(
                        label: context.l10n.commonBack,
                        button: true,
                        child: AppButton(
                          variant: AppButtonVariant.ghost,
                          focusRingColor: WelcomeButtonTokens.focusRing,
                          enabledLabelColor: const Color(0xffffffff),
                          // Back to whatever opened Add account (Accounts,
                          // or the tab under the accounts sheet); home when
                          // it was reached without history.
                          onPressed: _creationBlocksNavigation
                              ? null
                              : () => context.canPop()
                                    ? context.pop()
                                    : context.go('/home'),
                          child: const AppIcon(
                            AppIcons.chevronBackward,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 313),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const VizorWordmark(width: 106, height: 40, color: Color(0xffffffff)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Shielded\nby default', // l10n-ignore: brand tagline
          textAlign: TextAlign.center,
          style: AppTypography.displayLarge.copyWith(
            color: const Color(0xffffffff),
            fontSize: 56,
            height: 1.02,
            letterSpacing: -1.68,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_createError != null) ...[
                Text(
                  _createError!.resolve(context.l10n),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: const Color(0xffffffff),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              WelcomeAccentButton(
                semanticKey: const ValueKey('mobile_welcome_get_started'),
                onPressed: _creating
                    ? null
                    : () => _creation.requiresRecovery
                          ? unawaited(_createWallet())
                          : _enter(() => unawaited(_createWallet())),
                label: _creation.requiresRecovery
                    ? context.l10n.onboardingRetrySetup
                    : _creating
                    ? context.l10n.commonCreating
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                key: const ValueKey('mobile_welcome_import'),
                button: true,
                child: AppButton(
                  expand: true,
                  focusRingColor: WelcomeButtonTokens.focusRing,
                  enabledBackgroundColor:
                      WelcomeButtonTokens.secondaryBackground,
                  pressedBackgroundColor:
                      WelcomeButtonTokens.secondaryHighlightedBackground,
                  enabledBorderColor: WelcomeButtonTokens.border,
                  enabledLabelColor: WelcomeButtonTokens.secondaryLabel,
                  pressedLabelColor: WelcomeButtonTokens.secondaryLabel,
                  onPressed: _creationBlocksNavigation
                      ? null
                      : () => _enter(
                          () => context.startOnboarding('/onboarding/method'),
                        ),
                  leading: const AppIcon(AppIcons.importWallet),
                  growWithContent: true,
                  constrainContent: true,
                  child: Text(
                    context.l10n.onboardingWelcomeImportWallet,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  key: const ValueKey('mobile_welcome_redeem_card'),
                  button: true,
                  enabled: !_creationBlocksNavigation,
                  child: WelcomeGiftCardButton(
                    onPressed: _creationBlocksNavigation
                        ? null
                        : () => _enter(
                            () => context.push(
                              widget.showBackButton
                                  ? '/gift?addAccount=true'
                                  : '/gift',
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
