import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../create/onboarding_split_view.dart';
import '../import/import_split_view.dart';
import 'onboarding_flow_args.dart';
import 'onboarding_error_messages.dart';

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key, required this.args});

  final SetPasswordScreenArgs args;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

enum _SetPasswordSubmitPhase { idle, stoppingSync, settingPassword }

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  _SetPasswordSubmitPhase _submitPhase = _SetPasswordSubmitPhase.idle;
  String? _submitError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? get _passwordPolicyError =>
      validateWalletPassword(_passwordController.text);
  bool get _matches =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;

  bool get _canSubmit =>
      _submitPhase == _SetPasswordSubmitPhase.idle &&
      _passwordPolicyError == null &&
      _matches;

  String? get _passwordMessage => _passwordPolicyError;

  String? get _confirmMessage {
    final value = _confirmController.text;
    if (value.isEmpty || _passwordPolicyError != null || _matches) return null;
    return 'Passwords do not match.';
  }

  Future<void> _submit() async {
    final args = widget.args;
    final passwordPolicyError = _passwordPolicyError;
    final password = _passwordController.text;
    if (_submitPhase != _SetPasswordSubmitPhase.idle ||
        passwordPolicyError != null ||
        !_matches) {
      return;
    }

    setState(() {
      _submitPhase = _SetPasswordSubmitPhase.settingPassword;
      _submitError = null;
    });

    final router = GoRouter.of(context);
    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var passwordPrepared = false;
    var passwordCommitted = false;

    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(password);
        passwordPrepared = true;

        await runWithSyncPausedForAccountMutation(
          ref,
          () async {
            if (args.isImport) {
              await accountNotifier.importAccount(
                mnemonic: args.mnemonic,
                birthdayHeight: args.importBirthdayHeight,
              );
            } else {
              await accountNotifier.createAccountFromMnemonic(
                mnemonic: args.mnemonic,
              );
            }
          },
          onStoppingSync: () {
            if (!mounted) return;
            setState(() {
              _submitPhase = _SetPasswordSubmitPhase.stoppingSync;
            });
          },
          onSyncPaused: () {
            if (!mounted) return;
            setState(() {
              _submitPhase = _SetPasswordSubmitPhase.settingPassword;
            });
          },
        );

        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        router.go('/home');
      });
    } catch (e, st) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.rollbackPasswordSetup();
        } catch (rollbackError, rollbackStack) {
          log(
            'SetPasswordScreen._submit: password rollback failed: '
            '$rollbackError\n$rollbackStack',
          );
        }
      }
      log('SetPasswordScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _SetPasswordSubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final content = _SetPasswordContent(
      passwordController: _passwordController,
      confirmController: _confirmController,
      submitPhase: _submitPhase,
      canSubmit: _canSubmit,
      passwordMessage: _passwordMessage,
      confirmMessage: _confirmMessage,
      submitError: _submitError,
      backRoutePath: args.backRoutePath,
      backRouteExtra: args.backRouteExtra,
      onChanged: () => setState(() {
        _submitError = null;
      }),
      onSubmit: _submit,
    );

    return args.isImport
        ? ImportOnboardingTrailingPane(child: content)
        : OnboardingTrailingPane(child: content);
  }
}

class _SetPasswordContent extends StatelessWidget {
  const _SetPasswordContent({
    required this.passwordController,
    required this.confirmController,
    required this.submitPhase,
    required this.canSubmit,
    required this.passwordMessage,
    required this.confirmMessage,
    required this.submitError,
    required this.backRoutePath,
    required this.backRouteExtra,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final _SetPasswordSubmitPhase submitPhase;
  final bool canSubmit;
  final String? passwordMessage;
  final String? confirmMessage;
  final String? submitError;
  final String backRoutePath;
  final Object backRouteExtra;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  static const _formWidth = 304.0;
  static const _buttonWidth = 256.0;
  static const _fieldGroupGap = 12.0;
  static const _fieldReservedMessageHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _BackRow(routePath: backRoutePath, routeExtra: backRouteExtra),
        const SizedBox(height: AppSpacing.s),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Set Password',
                              style: AppTypography.displayLarge.copyWith(
                                color: colors.text.accent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              width: 270,
                              child: Text(
                                'Minimum 8 symbols including characters.',
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          width: _formWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PasswordFieldBlock(
                                reserveMessageSpace:
                                    _fieldReservedMessageHeight,
                                child: PasswordTextField(
                                  key: const ValueKey(
                                    'set_password_password_field',
                                  ),
                                  label: 'Password',
                                  controller: passwordController,
                                  messageText: passwordMessage,
                                  tone: passwordMessage == null
                                      ? AppTextFieldTone.neutral
                                      : AppTextFieldTone.destructive,
                                  leadingSlotWidth: 32,
                                  trailingSlotWidth: 40,
                                  inputHorizontalPadding: AppSpacing.s,
                                  autofocus: true,
                                  onChanged: (_) => onChanged(),
                                  onSubmitted: (_) => onSubmit(),
                                ),
                              ),
                              const SizedBox(height: _fieldGroupGap),
                              _PasswordFieldBlock(
                                reserveMessageSpace:
                                    _fieldReservedMessageHeight,
                                child: PasswordTextField(
                                  key: const ValueKey(
                                    'set_password_confirm_field',
                                  ),
                                  label: 'Confirm Password',
                                  controller: confirmController,
                                  messageText: confirmMessage,
                                  tone: confirmMessage == null
                                      ? AppTextFieldTone.neutral
                                      : AppTextFieldTone.destructive,
                                  leadingSlotWidth: 32,
                                  trailingSlotWidth: 40,
                                  inputHorizontalPadding: AppSpacing.s,
                                  showVisibilityToggle: false,
                                  onChanged: (_) => onChanged(),
                                  onSubmitted: (_) => onSubmit(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: _buttonWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (submitError != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(
                          submitError!,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.destructive,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    AppButton(
                      key: const ValueKey('set_password_submit_button'),
                      onPressed: canSubmit ? onSubmit : null,
                      variant: AppButtonVariant.primary,
                      minWidth: _buttonWidth,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: Text(switch (submitPhase) {
                        _SetPasswordSubmitPhase.stoppingSync =>
                          'Stop syncing...',
                        _SetPasswordSubmitPhase.settingPassword =>
                          'Setting password...',
                        _SetPasswordSubmitPhase.idle => 'Set Password',
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordFieldBlock extends StatelessWidget {
  const _PasswordFieldBlock({
    required this.child,
    required this.reserveMessageSpace,
  });

  final Widget child;
  final double reserveMessageSpace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: reserveMessageSpace),
      child: child,
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.routePath, required this.routeExtra});

  final String routePath;
  final Object routeExtra;

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
