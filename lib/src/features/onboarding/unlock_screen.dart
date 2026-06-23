import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../core/security/password_policy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/payment_uri_prefill_provider.dart';
import '../../providers/router_refresh_provider.dart';
import '../../providers/sync_provider.dart';
import 'shared/onboarding_auth_shell.dart';

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
        // Claim a payment-URI prefill parked while the wallet was locked,
        // before the post-unlock work runs, so we route to /send (the payment
        // the user intended) instead of the default /home.
        final pendingPrefill =
            ref.read(paymentUriPrefillProvider.notifier).take();
        await accountNotifier.restoreAfterUnlock();
        await syncNotifier.refreshAfterUnlock();
        await syncNotifier.startSyncAnyway();
        if (!mounted) return;
        if (pendingPrefill != null) {
          context.go('/send', extra: pendingPrefill);
        } else {
          context.go('/home');
        }
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
        _errorText = 'Incorrect password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: OnboardingAuthShell(
          card: OnboardingAuthCard(
            width: _UnlockContent.cardWidth,
            height: _UnlockContent.cardHeight,
            borderRadius: AppSpacing.base,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.lg,
            ),
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

  static const double cardWidth = 396;
  static const double cardHeight = 509;
  static const double _fieldWidth = 256;
  static const double _buttonWidth = 196;
  static const double _titleWidth = 364;
  static const double _fieldGroupHeight = 66;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/illustrations/welcome_badge.png',
          width: 50,
          height: 50,
        ),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          width: _titleWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome back',
                style: AppTypography.displayMedium.copyWith(
                  color: colors.text.accent,
                  height: 48 / 45,
                ),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enter your password to open Vizor.',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _fieldWidth,
              height: _fieldGroupHeight,
              child: PasswordTextField(
                label: 'Password',
                hintText: 'Enter password',
                showLabel: false,
                // Figma Field Type=Secondary on the auth card.
                surface: AppTextFieldSurface.secondary,
                leadingSlotWidth: 32,
                inputHorizontalPadding: AppSpacing.s,
                controller: passwordController,
                autofocus: false,
                showVisibilityToggle: false,
                messageText: messageText,
                tone: messageText == null
                    ? AppTextFieldTone.neutral
                    : AppTextFieldTone.destructive,
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppButton(
                  onPressed: canSubmit ? onSubmit : null,
                  variant: AppButtonVariant.primary,
                  minWidth: _buttonWidth,
                  child: const Text('Unlock Vizor'),
                ),
                const SizedBox(height: AppSpacing.s),
                AppButton(
                  onPressed: onForgotPassword,
                  variant: AppButtonVariant.ghost,
                  minWidth: _buttonWidth,
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
