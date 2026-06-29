import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';

const kMultisigSetupPasswordFieldKey = ValueKey(
  'multisig_setup_password_field',
);
const kMultisigSetupConfirmPasswordFieldKey = ValueKey(
  'multisig_setup_confirm_password_field',
);

class MultisigSetupSecurityException implements Exception {
  const MultisigSetupSecurityException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MultisigSetupSecurityGateController {
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
  }

  bool requiresInput(AppSecurityState security) {
    return !security.isPasswordConfigured || !security.isUnlocked;
  }

  bool requiresPasswordSetup(AppSecurityState security) {
    return !security.isPasswordConfigured;
  }

  bool isValid(AppSecurityState security) {
    if (!requiresInput(security)) return true;
    if (validateRequiredWalletPassword(passwordController.text) != null) {
      return false;
    }
    if (requiresPasswordSetup(security) &&
        confirmPasswordController.text != passwordController.text) {
      return false;
    }
    return true;
  }

  String? passwordMessage(AppSecurityState security, bool showValidation) {
    if (!requiresInput(security)) return null;
    return showValidation
        ? validateRequiredWalletPassword(passwordController.text)
        : validateWalletPassword(passwordController.text);
  }

  String? confirmPasswordMessage(
    AppSecurityState security,
    bool showValidation,
  ) {
    if (!requiresPasswordSetup(security)) return null;
    if (passwordMessage(security, showValidation) != null) return null;
    final value = confirmPasswordController.text;
    if ((!showValidation && value.isEmpty) ||
        value == passwordController.text) {
      return null;
    }
    return 'Passwords do not match.';
  }

  Future<T> runWithOpenSession<T>({
    required WidgetRef ref,
    required AppSecurityState security,
    required Future<T> Function() action,
  }) async {
    if (!requiresInput(security)) {
      return action();
    }

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    if (requiresPasswordSetup(security)) {
      final routerRefresh = ref.read(routerRefreshProvider);
      var passwordPrepared = false;
      var passwordCommitted = false;
      try {
        return await routerRefresh.pauseWhile(() async {
          await securityNotifier.preparePasswordSetup(passwordController.text);
          passwordPrepared = true;
          final result = await action();
          securityNotifier.commitPasswordSetup();
          passwordCommitted = true;
          return result;
        });
      } catch (e, st) {
        if (passwordPrepared && !passwordCommitted) {
          try {
            await securityNotifier.rollbackPasswordSetup();
          } catch (_) {
            // Keep the original setup/create/join error visible to the caller.
          }
        }
        Error.throwWithStackTrace(e, st);
      }
    }

    final isValidPassword = await securityNotifier.unlock(
      passwordController.text,
    );
    if (!isValidPassword) {
      throw const MultisigSetupSecurityException(
        'Incorrect password. Try again.',
      );
    }
    return action();
  }
}

class MultisigSetupSecurityGate extends StatelessWidget {
  const MultisigSetupSecurityGate({
    super.key,
    required this.controller,
    required this.security,
    required this.showValidation,
    required this.enabled,
    required this.onChanged,
    this.onSubmitted,
  });

  final MultisigSetupSecurityGateController controller;
  final AppSecurityState security;
  final bool showValidation;
  final bool enabled;
  final VoidCallback onChanged;
  final Future<void> Function()? onSubmitted;

  @override
  Widget build(BuildContext context) {
    if (!controller.requiresInput(security)) {
      return const SizedBox.shrink();
    }

    final passwordField = PasswordTextField(
      key: kMultisigSetupPasswordFieldKey,
      label: 'Password',
      controller: controller.passwordController,
      hintText: 'Enter password',
      messageText: controller.passwordMessage(security, showValidation),
      tone: controller.passwordMessage(security, showValidation) == null
          ? AppTextFieldTone.neutral
          : AppTextFieldTone.destructive,
      enabled: enabled,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted?.call(),
    );

    if (!controller.requiresPasswordSetup(security)) {
      return passwordField;
    }

    final confirmMessage = controller.confirmPasswordMessage(
      security,
      showValidation,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        passwordField,
        const SizedBox(height: AppSpacing.sm),
        PasswordTextField(
          key: kMultisigSetupConfirmPasswordFieldKey,
          label: 'Confirm password',
          controller: controller.confirmPasswordController,
          hintText: 'Confirm password',
          messageText: confirmMessage,
          tone: confirmMessage == null
              ? AppTextFieldTone.neutral
              : AppTextFieldTone.destructive,
          enabled: enabled,
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmitted?.call(),
        ),
      ],
    );
  }
}
