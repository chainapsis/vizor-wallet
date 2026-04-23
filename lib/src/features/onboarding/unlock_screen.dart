import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show
        AlertDialog,
        Colors,
        Scaffold,
        TextButton,
        TextStyle,
        showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../core/layout/app_desktop_shell.dart';
import '../../core/security/password_policy.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_decorative_divider.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;

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

    final isValid = await ref
        .read(appSecurityProvider.notifier)
        .unlock(_passwordController.text);
    if (!mounted) return;
    if (!isValid) {
      log('UnlockScreen._submit: invalid password');
      setState(() {
        _isSubmitting = false;
        _errorText = 'Incorrect password. Please try again.';
      });
      return;
    }

    await ref.read(accountProvider.notifier).restoreAfterUnlock();
    await ref.read(syncProvider.notifier).refreshAfterUnlock();
    ref.read(syncProvider.notifier).startSync();
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _resetWallet(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Wallet'),
        content: const Text(
          'Delete all wallet data (DB + keychain)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    ref.read(syncProvider.notifier).stopSync();
    var waited = 0;
    while (rust_sync.isSyncRunning() && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    await ref.read(accountProvider.notifier).resetWallet();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(
            child: Center(
              child: SizedBox(
                width: 432,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.background.overlay.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                      child: const Center(
                        child: AppIcon(AppIcons.unlock, size: 24),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Unlock Wallet',
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Enter your password to access your wallet.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    const AppDecorativeDivider(),
                    const SizedBox(height: AppSpacing.s),
                    PasswordTextField(
                      label: 'Password',
                      controller: _passwordController,
                      autofocus: true,
                      messageText: _errorText ?? _passwordPolicyMessage,
                      tone: (_errorText ?? _passwordPolicyMessage) == null
                          ? AppTextFieldTone.neutral
                          : AppTextFieldTone.destructive,
                      onChanged: (_) {
                        setState(() {
                          _errorText = null;
                        });
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    AppButton(
                      onPressed: _canSubmit ? _submit : null,
                      variant: AppButtonVariant.primary,
                      minWidth: 256,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: Text(_isSubmitting ? 'Unlocking...' : 'Unlock'),
                    ),
                    if (kDebugMode && Platform.isMacOS) ...[
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _resetWallet(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxs,
                          ),
                          child: Text(
                            'Reset State',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.warning,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
