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
import 'onboarding_split_view.dart';

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs({required this.mnemonic});

  final String mnemonic;
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key, required this.args});

  final SetPasswordScreenArgs? args;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  static const _contentWidth = 256.0;
  static const _contentGap = 16.0;
  static const _fieldGroupGap = 12.0;
  static const _fieldReservedMessageHeight = 20.0;

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

    try {
      await ref
          .read(appSecurityProvider.notifier)
          .configurePassword(_passwordController.text);
      await ref
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(mnemonic: args.mnemonic);
    } catch (e, st) {
      log('SetPasswordScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
      return;
    }

    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OnboardingTrailingPane(
      child: Column(
        children: [
          const SizedBox(height: 32, child: _BackRow()),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s,
                      ),
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
                                    controller: _passwordController,
                                    messageText: _passwordMessage,
                                    tone: _passwordMessage == null
                                        ? AppTextFieldTone.neutral
                                        : AppTextFieldTone.destructive,
                                    autofocus: true,
                                    onChanged: (_) => setState(() {
                                      _submitError = null;
                                    }),
                                    onSubmitted: (_) => _submit(),
                                  ),
                                ),
                                const SizedBox(height: _fieldGroupGap),
                                _PasswordFieldBlock(
                                  reserveMessageSpace:
                                      _fieldReservedMessageHeight,
                                  child: PasswordTextField(
                                    label: 'Confirm Password',
                                    controller: _confirmController,
                                    messageText: _confirmMessage,
                                    tone: _confirmMessage == null
                                        ? AppTextFieldTone.neutral
                                        : AppTextFieldTone.destructive,
                                    onChanged: (_) => setState(() {
                                      _submitError = null;
                                    }),
                                    onSubmitted: (_) => _submit(),
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
                      if (_submitError != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            _submitError!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.warning,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      AppButton(
                        onPressed: _canSubmit ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: _contentWidth,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(
                          _isSubmitting
                              ? 'Setting password...'
                              : 'Set Password',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(OnboardingStep.secretPassphrase.routePath),
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
    );
  }
}
