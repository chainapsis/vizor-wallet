import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/security/password_policy.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';

class SettingsSeedPhraseScreen extends ConsumerStatefulWidget {
  const SettingsSeedPhraseScreen({super.key});

  @override
  ConsumerState<SettingsSeedPhraseScreen> createState() =>
      _SettingsSeedPhraseScreenState();
}

enum _SettingsSeedPhraseStage { password, reveal }

class _SeedPhraseUnavailableException implements Exception {
  const _SeedPhraseUnavailableException(this.message);

  final String message;
}

class _SettingsSeedPhraseScreenState
    extends ConsumerState<SettingsSeedPhraseScreen> {
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  _SettingsSeedPhraseStage _stage = _SettingsSeedPhraseStage.password;
  String? _passwordError;
  String? _mnemonic;
  String? _revealError;
  bool _copied = false;
  Timer? _copyResetTimer;

  bool get _canSubmit =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleBack() {
    _clearSensitiveState();
    context.go('/settings');
  }

  void _clearSensitiveState({String? passwordError}) {
    _copyResetTimer?.cancel();
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _SettingsSeedPhraseStage.password;
    _passwordError = passwordError;
    _mnemonic = null;
    _revealError = null;
    _copied = false;
  }

  void _handleActiveAccountChanged() {
    if (_stage == _SettingsSeedPhraseStage.password &&
        !_isSubmitting &&
        _mnemonic == null) {
      return;
    }

    setState(() {
      _clearSensitiveState(
        passwordError: 'Active account changed. Enter your password again.',
      );
    });
  }

  bool _activeAccountChanged(String expectedAccountUuid) {
    final currentAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    return currentAccountUuid != expectedAccountUuid;
  }

  void _handlePasswordChanged() {
    if (_passwordError == null) {
      setState(() {});
      return;
    }
    setState(() {
      _passwordError = null;
    });
  }

  Future<void> _submitPassword() async {
    if (_isSubmitting) return;
    if (!isWalletPasswordValid(_passwordController.text)) {
      final policyError = validateWalletPassword(_passwordController.text);
      if (policyError != null) {
        setState(() {
          _passwordError = policyError;
        });
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
      _passwordError = null;
      _revealError = null;
    });

    try {
      final accountState = ref.read(accountProvider).value;
      final activeAccount = accountState?.activeAccount;
      if (activeAccount == null) {
        throw const _SeedPhraseUnavailableException(
          'No active account is selected.',
        );
      }
      final activeAccountUuid = activeAccount.uuid;

      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_passwordController.text);
      if (!isValid) {
        if (!mounted) return;
        setState(() {
          _passwordError = 'Wrong password';
          _isSubmitting = false;
        });
        return;
      }

      if (_activeAccountChanged(activeAccountUuid)) {
        if (!mounted) return;
        setState(() {
          _clearSensitiveState(
            passwordError: 'Active account changed. Enter your password again.',
          );
        });
        return;
      }

      if (activeAccount.isHardware) {
        throw const _SeedPhraseUnavailableException(
          'Secret passphrase is not available for hardware accounts.',
        );
      }

      final mnemonic = await ref
          .read(accountProvider.notifier)
          .getMnemonicForAccount(activeAccountUuid);
      if (mnemonic == null || mnemonic.isEmpty) {
        throw const _SeedPhraseUnavailableException(
          'Secret passphrase is not available for this account.',
        );
      }

      if (!mounted) return;
      if (_activeAccountChanged(activeAccountUuid)) {
        setState(() {
          _clearSensitiveState(
            passwordError: 'Active account changed. Enter your password again.',
          );
        });
        return;
      }

      setState(() {
        _mnemonic = mnemonic;
        _stage = _SettingsSeedPhraseStage.reveal;
        _isSubmitting = false;
        _copied = false;
      });
    } on _SeedPhraseUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _revealError = e.message;
        _stage = _SettingsSeedPhraseStage.reveal;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsSeedPhraseScreen._submitPassword: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _revealError =
            "Couldn't load your secret passphrase. Please try again.";
        _stage = _SettingsSeedPhraseStage.reveal;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || mnemonic.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: mnemonic));
    if (!mounted) return;
    _copyResetTimer?.cancel();
    setState(() {
      _copied = true;
    });
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copied = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((state) => state.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        _handleActiveAccountChanged();
      },
    );

    return AppDesktopShell(
      sidebarWidth: 240,
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _SettingsSeedPhrasePane(
          onBack: _handleBack,
          child: switch (_stage) {
            _SettingsSeedPhraseStage.password => _PasswordGateView(
              passwordController: _passwordController,
              messageText: _passwordError,
              isSubmitting: _isSubmitting,
              canSubmit: _canSubmit,
              onChanged: _handlePasswordChanged,
              onSubmit: _submitPassword,
            ),
            _SettingsSeedPhraseStage.reveal => _SeedPhraseRevealView(
              mnemonic: _mnemonic,
              errorText: _revealError,
              copied: _copied,
              onCopyPressed: _copyMnemonic,
            ),
          },
        ),
      ),
    );
  }
}

class _SettingsSeedPhrasePane extends StatelessWidget {
  const _SettingsSeedPhrasePane({required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onTap: onBack),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
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

class _PasswordGateView extends StatelessWidget {
  const _PasswordGateView({
    required this.passwordController,
    required this.messageText,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController passwordController;
  final String? messageText;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmit;

  static const _contentWidth = 304.0;
  static const _buttonWidth = 256.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter Password',
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                SizedBox(
                  width: 270,
                  child: Text(
                    'Enter your password to continue.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppDecorativeDivider(width: 256),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: _contentWidth,
                  height: 86,
                  child: PasswordTextField(
                    label: 'Password',
                    hintText: 'Enter Your Password',
                    leadingSlotWidth: 32,
                    trailingSlotWidth: 40,
                    inputHorizontalPadding: AppSpacing.s,
                    controller: passwordController,
                    autofocus: true,
                    enabled: !isSubmitting,
                    messageText: messageText,
                    tone: messageText == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) {
                      onSubmit();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed: canSubmit
              ? () {
                  onSubmit();
                }
              : null,
          variant: AppButtonVariant.primary,
          minWidth: _buttonWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(
            isSubmitting ? 'Checking password...' : 'View Secret Passphrase',
          ),
        ),
      ],
    );
  }
}

class _SeedPhraseRevealView extends StatelessWidget {
  const _SeedPhraseRevealView({
    required this.mnemonic,
    required this.errorText,
    required this.copied,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final String? errorText;
  final bool copied;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Secret Passphrase',
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: 197,
            child: Text(
              "The Master Key to your wallet.\nDon't share it with anyone.",
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const AppDecorativeDivider(width: 256),
          const SizedBox(height: AppSpacing.sm),
          if (errorText == null && mnemonic != null)
            _SeedPhraseCard(
              mnemonic: mnemonic!,
              copied: copied,
              onCopyPressed: onCopyPressed,
            )
          else
            _SeedPhraseErrorCard(
              message:
                  errorText ??
                  'Secret passphrase is not available for this account.',
            ),
        ],
      ),
    );
  }
}

class _SeedPhraseCard extends StatelessWidget {
  const _SeedPhraseCard({
    required this.mnemonic,
    required this.copied,
    required this.onCopyPressed,
  });

  final String mnemonic;
  final bool copied;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = mnemonic.split(' ');

    return SizedBox(
      width: 529,
      height: 348,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secret Passphrase',
                        style: AppTypography.bodyLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (var i = 0; i < words.length; i++)
                            AppChip(
                              width: 90,
                              leadingText: '${i + 1}'.padLeft(2, '0'),
                              label: words[i],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.s,
                right: AppSpacing.s,
                child: AppButton(
                  onPressed: () {
                    onCopyPressed();
                  },
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.small,
                  minWidth: copied ? 72 : 61,
                  trailing: AppIcon(copied ? AppIcons.check : AppIcons.copy),
                  child: Text(copied ? 'Copied' : 'Copy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeedPhraseErrorCard extends StatelessWidget {
  const _SeedPhraseErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: 529,
      height: 348,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: Center(
            child: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: 24,
                    color: colors.icon.destructive,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
