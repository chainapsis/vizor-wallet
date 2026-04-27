import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../core/security/password_policy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/router_refresh_provider.dart';
import '../../providers/sync_provider.dart';
import 'shared/onboarding_welcome_art.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  String? get _passwordPolicyMessage =>
      validateWalletPassword(_passwordController.text);

  bool get _canSubmit =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final policyError = _passwordPolicyMessage;
    if (_isSubmitting) return;
    if (!isWalletPasswordValid(_passwordController.text)) {
      if (policyError == null) return;
      setState(() {
        _errorText = policyError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var unlocked = false;

    try {
      await routerRefresh.pauseWhile(() async {
        final isValid = await securityNotifier.unlock(_passwordController.text);
        if (!isValid) return;

        unlocked = true;
        await accountNotifier.restoreAfterUnlock();
        await syncNotifier.refreshAfterUnlock();
        await syncNotifier.startSyncAnyway();
        if (!mounted) return;
        context.go('/home');
      });
    } catch (e, st) {
      log('UnlockScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = "Couldn't open your wallet. Please try again.";
      });
      return;
    }

    if (!unlocked) {
      if (!mounted) return;
      log('UnlockScreen._submit: invalid password');
      setState(() {
        _isSubmitting = false;
        _errorText = 'Incorrect password. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _UnlockPane(
            child: _UnlockContent(
              passwordController: _passwordController,
              canSubmit: _canSubmit,
              messageText: _errorText ?? _passwordPolicyMessage,
              onChanged: () {
                setState(() {
                  _errorText = null;
                });
              },
              onSubmit: _submit,
              onForgotPassword: () => context.go('/lost-password'),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockPane extends StatelessWidget {
  const _UnlockPane({required this.child});

  final Widget child;

  static const double _canvasWidth = 1064;
  static const double _canvasHeight = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: OnboardingWelcomeBackdrop(
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final alignment = constraints.maxHeight < _canvasHeight
                    ? Alignment.bottomCenter
                    : Alignment.center;
                return OverflowBox(
                  alignment: alignment,
                  minWidth: _canvasWidth,
                  maxWidth: _canvasWidth,
                  minHeight: _canvasHeight,
                  maxHeight: _canvasHeight,
                  child: SizedBox(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [child],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockContent extends StatelessWidget {
  const _UnlockContent({
    required this.passwordController,
    required this.canSubmit,
    required this.messageText,
    required this.onChanged,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final TextEditingController passwordController;
  final bool canSubmit;
  final String? messageText;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;
  final VoidCallback onForgotPassword;

  static const double _contentWidth = 256;
  static const double _titleWidth = 347;
  static const double _fieldGroupHeight = 66;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.base),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _titleWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const VizorWordmark(),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Welcome Back',
                    style: AppTypography.displayLarge.copyWith(
                      color: colors.text.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Enter your password to open Vizor.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: _contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _fieldGroupHeight,
                    child: PasswordTextField(
                      label: 'Password',
                      hintText: 'Enter Your Password',
                      showLabel: false,
                      leadingSlotWidth: 32,
                      trailingSlotWidth: 40,
                      inputHorizontalPadding: AppSpacing.s,
                      controller: passwordController,
                      autofocus: false,
                      messageText: messageText,
                      tone: messageText == null
                          ? AppTextFieldTone.neutral
                          : AppTextFieldTone.destructive,
                      onChanged: (_) => onChanged(),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  AppButton(
                    onPressed: canSubmit ? onSubmit : null,
                    variant: AppButtonVariant.primary,
                    minWidth: _contentWidth,
                    trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            AppButton(
              onPressed: onForgotPassword,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              child: const Text('Forgot Password?'),
            ),
          ],
        ),
      ),
    );
  }
}
