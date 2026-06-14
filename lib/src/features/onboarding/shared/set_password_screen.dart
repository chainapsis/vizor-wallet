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
import '../keystone/keystone_onboarding_flow.dart';
import 'onboarding_chrome.dart' as onboarding_chrome;
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
            switch (args.flow) {
              case SetPasswordFlow.create:
                await accountNotifier.createAccountFromMnemonic(
                  mnemonic: args.requiredMnemonic,
                );
              case SetPasswordFlow.importWallet:
                await accountNotifier.importAccount(
                  mnemonic: args.requiredMnemonic,
                  birthdayHeight: args.importBirthdayHeight,
                  additionalAccountIndices:
                      args.selectedAdditionalAccountIndices,
                );
              case SetPasswordFlow.importKeystone:
                await accountNotifier.importKeystoneAccount(
                  name: args.requiredKeystoneAccountName,
                  ufvk: args.requiredKeystoneUfvk,
                  seedFingerprint: args.requiredKeystoneSeedFingerprint,
                  zip32Index: args.requiredKeystoneZip32Index,
                  birthdayHeight: args.importBirthdayHeight,
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
        if (args.flow == SetPasswordFlow.importKeystone) {
          ref.read(keystoneOnboardingProvider.notifier).resetScan();
        }
        if (args.flow == SetPasswordFlow.create) {
          clearCreateOnboardingSecretState(ref.read);
        }
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
      onChanged: () => setState(() {
        _submitError = null;
      }),
      onSubmit: _submit,
    );
    final backTarget = onboarding_chrome.OnboardingBackTarget.route(
      label: _backLabel(args.flow),
      routePath: args.backRoutePath,
      routeExtra: args.backRouteExtra,
    );

    return switch (args.flow) {
      SetPasswordFlow.create => OnboardingTrailingPane(
        backTarget: backTarget,
        child: content,
      ),
      SetPasswordFlow.importWallet => ImportOnboardingTrailingPane(
        backTarget: backTarget,
        child: content,
      ),
      SetPasswordFlow.importKeystone => KeystoneOnboardingTrailingPane(
        backTarget: backTarget,
        child: content,
      ),
    };
  }

  String _backLabel(SetPasswordFlow flow) => switch (flow) {
    SetPasswordFlow.create => OnboardingStep.secretPassphrase.label,
    SetPasswordFlow.importWallet =>
      ImportOnboardingStep.walletBirthdayHeight.label,
    SetPasswordFlow.importKeystone =>
      KeystoneOnboardingStep.walletBirthdayHeight.label,
  };
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
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  static const _contentWidth = 396.0;
  static const _mainHeight = 248.0;
  static const _formWidth = 256.0;
  static const _buttonMinWidth = 196.0;
  static const _fieldGroupGap = 12.0;
  static const _fieldReservedMessageHeight = 20.0;
  static const _sectionGap = 32.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SizedBox(
            width: _contentWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Expanded(
                  child: _SetPasswordOnPageContent(
                    passwordController: passwordController,
                    confirmController: confirmController,
                    passwordMessage: passwordMessage,
                    confirmMessage: confirmMessage,
                    onChanged: onChanged,
                    onSubmit: onSubmit,
                  ),
                ),
                _SetPasswordBottomActions(
                  submitPhase: submitPhase,
                  canSubmit: canSubmit,
                  submitError: submitError,
                  onSubmit: onSubmit,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SetPasswordOnPageContent extends StatelessWidget {
  const _SetPasswordOnPageContent({
    required this.passwordController,
    required this.confirmController,
    required this.passwordMessage,
    required this.confirmMessage,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final String? passwordMessage;
  final String? confirmMessage;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final fieldLabelStyle = AppTypography.labelLarge.copyWith(
      color: context.colors.text.secondary,
      fontWeight: FontWeight.w400,
    );

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SetPasswordTitle(),
          const SizedBox(height: _SetPasswordContent._sectionGap),
          SizedBox(
            width: double.infinity,
            height: _SetPasswordContent._mainHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.base,
              ),
              child: Center(
                child: SizedBox(
                  width: _SetPasswordContent._formWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PasswordFieldBlock(
                        reserveMessageSpace:
                            _SetPasswordContent._fieldReservedMessageHeight,
                        child: PasswordTextField(
                          key: const ValueKey('set_password_password_field'),
                          label: 'Password',
                          labelStyle: fieldLabelStyle,
                          hintText: 'Min. 8 characters and symbols',
                          controller: passwordController,
                          messageText: passwordMessage,
                          tone: passwordMessage == null
                              ? AppTextFieldTone.neutral
                              : AppTextFieldTone.destructive,
                          leadingSlotWidth: 32,
                          inputHorizontalPadding: AppSpacing.s,
                          autofocus: true,
                          showVisibilityToggle: false,
                          onChanged: (_) => onChanged(),
                          onSubmitted: (_) => onSubmit(),
                        ),
                      ),
                      const SizedBox(
                        height: _SetPasswordContent._fieldGroupGap,
                      ),
                      _PasswordFieldBlock(
                        reserveMessageSpace:
                            _SetPasswordContent._fieldReservedMessageHeight,
                        child: PasswordTextField(
                          key: const ValueKey('set_password_confirm_field'),
                          label: 'Confirm password',
                          labelStyle: fieldLabelStyle,
                          hintText: 'Confirm password',
                          controller: confirmController,
                          messageText: confirmMessage,
                          tone: confirmMessage == null
                              ? AppTextFieldTone.neutral
                              : AppTextFieldTone.destructive,
                          leadingSlotWidth: 32,
                          inputHorizontalPadding: AppSpacing.s,
                          showVisibilityToggle: false,
                          onChanged: (_) => onChanged(),
                          onSubmitted: (_) => onSubmit(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetPasswordTitle extends StatelessWidget {
  const _SetPasswordTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Set Password',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Set password for signing in to Vizor wallet.',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SetPasswordBottomActions extends StatelessWidget {
  const _SetPasswordBottomActions({
    required this.submitPhase,
    required this.canSubmit,
    required this.submitError,
    required this.onSubmit,
  });

  final _SetPasswordSubmitPhase submitPhase;
  final bool canSubmit;
  final String? submitError;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
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
          minWidth: _SetPasswordContent._buttonMinWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(switch (submitPhase) {
            _SetPasswordSubmitPhase.stoppingSync => 'Stop syncing...',
            _SetPasswordSubmitPhase.settingPassword => 'Setting password...',
            _SetPasswordSubmitPhase.idle => 'Set password & finish',
          }),
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
