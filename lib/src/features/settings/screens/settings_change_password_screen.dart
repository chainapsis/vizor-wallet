import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/app_security_provider.dart';
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';
import '../../../../l10n/app_localizations.dart';

class SettingsChangePasswordScreen extends ConsumerStatefulWidget {
  const SettingsChangePasswordScreen({super.key});

  @override
  ConsumerState<SettingsChangePasswordScreen> createState() =>
      _SettingsChangePasswordScreenState();
}

enum _ChangePasswordStage { currentPassword, newPassword }

class _SettingsChangePasswordScreenState
    extends ConsumerState<SettingsChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  _ChangePasswordStage _stage = _ChangePasswordStage.currentPassword;
  String? _verifiedCurrentPassword;
  String? _currentPasswordError;
  String? _submitError;
  bool _isSubmitting = false;

  String? get _currentPasswordPolicyMessage =>
      validateWalletPasswordLocalized(
        _currentPasswordController.text,
        AppLocalizations.of(context),
      );

  bool get _canContinue =>
      !_isSubmitting && isWalletPasswordValid(_currentPasswordController.text);

  String? get _passwordMessage {
    final policyError = validateWalletPasswordLocalized(
      _passwordController.text,
      AppLocalizations.of(context),
    );
    if (policyError != null) return policyError;
    if (_passwordController.text.isNotEmpty &&
        _verifiedCurrentPassword != null &&
        _passwordController.text == _verifiedCurrentPassword) {
      return AppLocalizations.of(context).passwordMustDiffer;
    }
    return null;
  }

  bool get _matches =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;

  bool get _canUpdate =>
      !_isSubmitting &&
      _verifiedCurrentPassword != null &&
      _passwordMessage == null &&
      _matches;

  String? get _confirmMessage {
    final value = _confirmController.text;
    if (value.isEmpty || _passwordMessage != null || _matches) return null;
    return AppLocalizations.of(context).onbPasswordsDoNotMatch;
  }

  @override
  void dispose() {
    _clearSensitiveState();
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearSensitiveState() {
    _currentPasswordController.clear();
    _passwordController.clear();
    _confirmController.clear();
    _verifiedCurrentPassword = null;
    _currentPasswordError = null;
    _submitError = null;
    _isSubmitting = false;
  }

  void _handleCurrentPasswordChanged() {
    if (_currentPasswordError == null) {
      setState(() {});
      return;
    }
    setState(() {
      _currentPasswordError = null;
    });
  }

  void _handleNewPasswordChanged() {
    setState(() {
      _submitError = null;
    });
  }

  Future<void> _submitCurrentPassword() async {
    final policyError = _currentPasswordPolicyMessage;
    if (_isSubmitting) return;
    if (!isWalletPasswordValid(_currentPasswordController.text)) {
      if (policyError == null) return;
      setState(() {
        _currentPasswordError = policyError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _currentPasswordError = null;
    });

    try {
      final currentPassword = _currentPasswordController.text;
      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(currentPassword);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _currentPasswordError = AppLocalizations.of(context).accountsIncorrectPassword;
          _isSubmitting = false;
        });
        return;
      }

      setState(() {
        _verifiedCurrentPassword = currentPassword;
        _currentPasswordController.clear();
        _stage = _ChangePasswordStage.newPassword;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log(
        'SettingsChangePasswordScreen._submitCurrentPassword: ERROR: $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _currentPasswordError =
            AppLocalizations.of(context).settingsPasswordCheckFailed;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _submitNewPassword() async {
    if (_isSubmitting) return;
    final currentPassword = _verifiedCurrentPassword;
    final passwordError = _passwordMessage;
    if (currentPassword == null) {
      setState(() {
        _stage = _ChangePasswordStage.currentPassword;
        _currentPasswordError =
            AppLocalizations.of(context).settingsEnterCurrentPasswordAgain;
      });
      return;
    }
    if (passwordError != null || !_matches) {
      setState(() {});
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final didChange = await ref
          .read(appSecurityProvider.notifier)
          .changePassword(
            currentPassword: currentPassword,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      if (!didChange) {
        setState(() {
          _verifiedCurrentPassword = null;
          _passwordController.clear();
          _confirmController.clear();
          _stage = _ChangePasswordStage.currentPassword;
          _currentPasswordError = AppLocalizations.of(context).accountsIncorrectPassword;
          _isSubmitting = false;
        });
        return;
      }

      _clearSensitiveState();
      context.go('/settings');
    } on PasswordRotationRecoveryFailedException {
      if (!mounted) return;
      setState(() {
        _submitError =
            AppLocalizations.of(context).settingsKeepPassphraseAvailable;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsChangePasswordScreen._submitNewPassword: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitError = e is ArgumentError && e.message != null
            ? e.message.toString()
            : AppLocalizations.of(context).settingsPasswordUpdateFailed;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: const SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
      sidebar: const AppMainSidebar(),
      pane: _SettingsChangePasswordPane(
        onBeforeNavigateBack: _clearSensitiveState,
        child: switch (_stage) {
          _ChangePasswordStage.currentPassword => Center(
            child: ConfirmAccessCard(
              subtitle: AppLocalizations.of(context).settingsEnterCurrentPasswordFirst,
              controller: _currentPasswordController,
              errorText: _currentPasswordError ?? _currentPasswordPolicyMessage,
              isSubmitting: _isSubmitting,
              canSubmit: _canContinue,
              onChanged: _handleCurrentPasswordChanged,
              onSubmit: _submitCurrentPassword,
            ),
          ),
          _ChangePasswordStage.newPassword => _NewPasswordView(
            passwordController: _passwordController,
            confirmController: _confirmController,
            isSubmitting: _isSubmitting,
            canSubmit: _canUpdate,
            passwordMessage: _passwordMessage,
            confirmMessage: _confirmMessage,
            submitError: _submitError,
            onChanged: _handleNewPasswordChanged,
            onSubmit: _submitNewPassword,
          ),
        },
      ),
    );
  }
}

class _SettingsChangePasswordPane extends StatelessWidget {
  const _SettingsChangePasswordPane({
    required this.onBeforeNavigateBack,
    required this.child,
  });

  final VoidCallback onBeforeNavigateBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPaneToolbar(
            backLinkMinWidth: 60,
            onBeforeNavigate: onBeforeNavigateBack,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewPasswordView extends StatelessWidget {
  const _NewPasswordView({
    required this.passwordController,
    required this.confirmController,
    required this.isSubmitting,
    required this.canSubmit,
    required this.passwordMessage,
    required this.confirmMessage,
    required this.submitError,
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
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  static const _formWidth = 304.0;
  static const _subtitleWidth = 270.0;
  static const _buttonMinWidth = 196.0;
  static const _fieldGroupGap = 12.0;
  static const _fieldReservedMessageHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).settingsUpdatePassword,
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: _subtitleWidth,
            child: Text(
              AppLocalizations.of(context).settingsPasswordHintLong,
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          SizedBox(
            width: _formWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PasswordFieldBlock(
                  reserveMessageSpace: _fieldReservedMessageHeight,
                  child: PasswordTextField(
                    label: AppLocalizations.of(context).settingsPassword,
                    controller: passwordController,
                    messageText: passwordMessage,
                    tone: passwordMessage == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    leadingSlotWidth: 32,
                    trailingSlotWidth: 40,
                    inputHorizontalPadding: AppSpacing.s,
                    autofocus: true,
                    enabled: !isSubmitting,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(height: _fieldGroupGap),
                _PasswordFieldBlock(
                  reserveMessageSpace: _fieldReservedMessageHeight,
                  child: PasswordTextField(
                    label: AppLocalizations.of(context).settingsConfirmPassword,
                    controller: confirmController,
                    messageText: confirmMessage,
                    tone: confirmMessage == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    leadingSlotWidth: 32,
                    inputHorizontalPadding: AppSpacing.s,
                    showVisibilityToggle: false,
                    enabled: !isSubmitting,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          if (submitError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s),
              child: SizedBox(
                width: _formWidth,
                child: Text(
                  submitError!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.destructive,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          AppButton(
            onPressed: canSubmit ? onSubmit : null,
            variant: AppButtonVariant.primary,
            minWidth: _buttonMinWidth,
            child: Text(
              isSubmitting
                  ? AppLocalizations.of(context).settingsUpdatingPassword
                  : AppLocalizations.of(context).settingsUpdatePassword,
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
