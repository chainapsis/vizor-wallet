import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../create/onboarding_split_view.dart';
import '../import/import_draft_provider.dart';
import '../import/import_split_view.dart';

enum SetPasswordFlow { create, importWallet }

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs._({
    required this.flow,
    required this.mnemonic,
    this.birthdayHeight,
  });

  const SetPasswordScreenArgs.create({required String mnemonic})
    : this._(flow: SetPasswordFlow.create, mnemonic: mnemonic);

  const SetPasswordScreenArgs.importWallet({
    required String mnemonic,
    required int birthdayHeight,
  }) : this._(
         flow: SetPasswordFlow.importWallet,
         mnemonic: mnemonic,
         birthdayHeight: birthdayHeight,
       );

  final SetPasswordFlow flow;
  final String mnemonic;
  final int? birthdayHeight;

  bool get isImport => flow == SetPasswordFlow.importWallet;

  String get backRoutePath => switch (flow) {
    SetPasswordFlow.create => OnboardingStep.secretPassphrase.routePath,
    SetPasswordFlow.importWallet => '/import/birthday',
  };
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key, required this.args});

  final SetPasswordScreenArgs? args;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (widget.args == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(OnboardingStep.secretPassphrase.routePath);
      });
    }
  }

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
      !_isSubmitting &&
      widget.args != null &&
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
    if (_isSubmitting ||
        args == null ||
        passwordPolicyError != null ||
        !_matches) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final router = GoRouter.of(context);
    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final importDraftNotifier = ref.read(importDraftProvider.notifier);

    try {
      await securityNotifier.configurePassword(password);
      if (args.isImport) {
        await accountNotifier.importAccount(
          mnemonic: args.mnemonic,
          birthdayHeight: args.birthdayHeight,
        );
        importDraftNotifier.clear();
      } else {
        await accountNotifier.createAccountFromMnemonic(
          mnemonic: args.mnemonic,
        );
      }
    } catch (e, st) {
      log('SetPasswordScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
      return;
    }

    router.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final content = _SetPasswordContent(
      passwordController: _passwordController,
      confirmController: _confirmController,
      isSubmitting: _isSubmitting,
      canSubmit: _canSubmit,
      passwordMessage: _passwordMessage,
      confirmMessage: _confirmMessage,
      submitError: _submitError,
      backRoutePath:
          args?.backRoutePath ?? OnboardingStep.secretPassphrase.routePath,
      onChanged: () => setState(() {
        _submitError = null;
      }),
      onSubmit: _submit,
    );

    if (args?.isImport ?? false) {
      return ImportOnboardingShell(
        activeStep: ImportOnboardingStep.setPassword,
        showPasswordStep: true,
        child: ImportOnboardingTrailingPane(child: content),
      );
    }

    return OnboardingTrailingPane(child: content);
  }
}

class _SetPasswordContent extends StatelessWidget {
  const _SetPasswordContent({
    required this.passwordController,
    required this.confirmController,
    required this.isSubmitting,
    required this.canSubmit,
    required this.passwordMessage,
    required this.confirmMessage,
    required this.submitError,
    required this.backRoutePath,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool isSubmitting;
  final bool canSubmit;
  final String? passwordMessage;
  final String? confirmMessage;
  final String? submitError;
  final String backRoutePath;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  static const _contentWidth = 256.0;
  static const _contentGap = 16.0;
  static const _fieldGroupGap = 12.0;
  static const _fieldReservedMessageHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        _BackRow(routePath: backRoutePath),
        const SizedBox(height: AppSpacing.s),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                    child: SizedBox(
                      width: _contentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Set Password',
                                style: AppTypography.displaySmall.copyWith(
                                  color: colors.text.accent,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: AppSpacing.s),
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
                          const SizedBox(height: _contentGap),
                          const AppDecorativeDivider(width: _contentWidth),
                          const SizedBox(height: _contentGap),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PasswordFieldBlock(
                                reserveMessageSpace:
                                    _fieldReservedMessageHeight,
                                child: PasswordTextField(
                                  label: 'Password',
                                  controller: passwordController,
                                  messageText: passwordMessage,
                                  tone: passwordMessage == null
                                      ? AppTextFieldTone.neutral
                                      : AppTextFieldTone.destructive,
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
                                  label: 'Confirm Password',
                                  controller: confirmController,
                                  messageText: confirmMessage,
                                  tone: confirmMessage == null
                                      ? AppTextFieldTone.neutral
                                      : AppTextFieldTone.destructive,
                                  onChanged: (_) => onChanged(),
                                  onSubmitted: (_) => onSubmit(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _contentWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (submitError != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(
                          submitError!,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.warning,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    AppButton(
                      onPressed: canSubmit ? onSubmit : null,
                      variant: AppButtonVariant.primary,
                      minWidth: _contentWidth,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: Text(
                        isSubmitting ? 'Setting password...' : 'Set Password',
                      ),
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
  const _BackRow({required this.routePath});

  final String routePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.go(routePath),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
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
