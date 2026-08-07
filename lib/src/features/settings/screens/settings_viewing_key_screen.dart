import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';

/// Settings → Viewing key — password-gated export of the account's Unified
/// Full Viewing Key (UFVK). Available for both software and hardware
/// (Keystone) accounts, unlike the secret-passphrase screen: a UFVK only
/// grants view access (balance, transaction history), never spend, so
/// hardware accounts — which never hold spend authority on the phone — can
/// still export the same key their device already shares with Vizor.
class SettingsViewingKeyScreen extends ConsumerStatefulWidget {
  const SettingsViewingKeyScreen({
    this.accountUuid,
    this.privacyOverlayController,
    this.ufvkLoader,
    super.key,
  });

  final String? accountUuid;
  final SensitivePrivacyOverlayController? privacyOverlayController;

  /// Test seam — production calls `rust_wallet.getAccountUfvk` directly.
  @visibleForTesting
  final Future<String> Function(String accountUuid)? ufvkLoader;

  @override
  ConsumerState<SettingsViewingKeyScreen> createState() =>
      _SettingsViewingKeyScreenState();
}

/// Deterministic reveal-state fixture used by Widgetbook and Figma comparison.
///
/// This is intentionally a separate widget rather than an initial state on
/// [SettingsViewingKeyScreen], so production navigation cannot bypass the
/// password confirmation gate.
class SettingsViewingKeyRevealPreview extends StatelessWidget {
  const SettingsViewingKeyRevealPreview({required this.ufvk, super.key});

  final String ufvk;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: const AppMainSidebar(),
      pane: _SettingsViewingKeyPane(
        onBeforeNavigateBack: () {},
        child: _ViewingKeyRevealView(
          ufvk: ufvk,
          errorText: null,
          copied: false,
          onCopyPressed: _noopPreviewCopy,
        ),
      ),
    );
  }
}

Future<void> _noopPreviewCopy() async {}

enum _SettingsViewingKeyStage { password, reveal }

class _ViewingKeyUnavailableException implements Exception {
  const _ViewingKeyUnavailableException(this.message);

  final String message;
}

class _SettingsViewingKeyScreenState
    extends ConsumerState<SettingsViewingKeyScreen> {
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  _SettingsViewingKeyStage _stage = _SettingsViewingKeyStage.password;
  String? _passwordError;
  String? _ufvk;
  String? _revealError;
  bool _copied = false;
  Timer? _copyResetTimer;

  String? get _passwordPolicyMessage =>
      validateWalletPassword(_passwordController.text);

  bool get _canSubmit =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  @override
  void dispose() {
    _clearSensitiveState();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearSensitiveState({String? passwordError}) {
    _copyResetTimer?.cancel();
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _SettingsViewingKeyStage.password;
    _passwordError = passwordError;
    _ufvk = null;
    _revealError = null;
    _copied = false;
  }

  void _handleTargetAccountChanged() {
    if (_stage == _SettingsViewingKeyStage.password &&
        !_isSubmitting &&
        _ufvk == null) {
      return;
    }

    setState(() {
      _clearSensitiveState(
        passwordError: 'Selected account changed. Enter your password again.',
      );
    });
  }

  AccountInfo? _targetAccount(AccountState? accountState) {
    if (accountState == null) return null;
    final requestedUuid = widget.accountUuid;
    if (requestedUuid == null) return accountState.activeAccount;
    for (final account in accountState.accounts) {
      if (account.uuid == requestedUuid) return account;
    }
    return null;
  }

  bool _targetAccountChanged(String expectedAccountUuid) {
    final accountState = ref.read(accountProvider).value;
    final targetAccount = _targetAccount(accountState);
    return targetAccount?.uuid != expectedAccountUuid;
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
    final policyError = _passwordPolicyMessage;
    if (_isSubmitting) return;
    if (!isWalletPasswordValid(_passwordController.text)) {
      if (policyError == null) return;
      setState(() {
        _passwordError = policyError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _passwordError = null;
      _revealError = null;
    });

    try {
      final accountState = ref.read(accountProvider).value;
      final targetAccount = _targetAccount(accountState);
      if (targetAccount == null) {
        throw const _ViewingKeyUnavailableException(
          'The selected account is no longer available.',
        );
      }
      final targetAccountUuid = targetAccount.uuid;

      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_passwordController.text);
      if (!isValid) {
        if (!mounted) return;
        setState(() {
          _passwordError = 'Incorrect password. Please try again.';
          _isSubmitting = false;
        });
        return;
      }

      if (_targetAccountChanged(targetAccountUuid)) {
        if (!mounted) return;
        setState(() {
          _clearSensitiveState(
            passwordError:
                'Selected account changed. Enter your password again.',
          );
        });
        return;
      }

      final ufvk = await _loadUfvk(targetAccountUuid);

      if (!mounted) return;
      if (_targetAccountChanged(targetAccountUuid)) {
        setState(() {
          _clearSensitiveState(
            passwordError:
                'Selected account changed. Enter your password again.',
          );
        });
        return;
      }

      setState(() {
        _ufvk = ufvk;
        _stage = _SettingsViewingKeyStage.reveal;
        _isSubmitting = false;
        _copied = false;
      });
    } on _ViewingKeyUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _revealError = e.message;
        _stage = _SettingsViewingKeyStage.reveal;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsViewingKeyScreen._submitPassword: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _revealError = "Couldn't load the viewing key. Please try again.";
        _stage = _SettingsViewingKeyStage.reveal;
        _isSubmitting = false;
      });
    }
  }

  Future<String> _loadUfvk(String targetAccountUuid) async {
    try {
      final loader = widget.ufvkLoader;
      if (loader != null) return await loader(targetAccountUuid);

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      return await rust_wallet.getAccountUfvk(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: targetAccountUuid,
      );
    } catch (e) {
      throw _ViewingKeyUnavailableException(
        'Viewing key is not available for this account: $e',
      );
    }
  }

  Future<void> _copyUfvk() async {
    final ufvk = _ufvk;
    if (ufvk == null || ufvk.isEmpty) return;
    await SensitiveClipboard.copyText(ufvk);
    _markCopied();
  }

  void _markCopied() {
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
    ref.listen<AccountInfo?>(
      accountProvider.select((state) => _targetAccount(state.value)),
      (previous, next) {
        if (previous?.uuid == next?.uuid) return;
        _handleTargetAccountChanged();
      },
    );

    return AppDesktopBackdropShell(
      background: _stage == _SettingsViewingKeyStage.reveal
          ? ColoredBox(color: context.colors.background.window)
          : const SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
      sidebar: const AppMainSidebar(),
      pane: SensitivePrivacyOverlay(
        sensitiveContentVisible:
            _stage == _SettingsViewingKeyStage.reveal && _ufvk != null,
        controller: widget.privacyOverlayController,
        child: _SettingsViewingKeyPane(
          onBeforeNavigateBack: () => _clearSensitiveState(),
          child: switch (_stage) {
            _SettingsViewingKeyStage.password => Center(
              child: ConfirmAccessCard(
                subtitle: 'To view the viewing key.',
                controller: _passwordController,
                errorText: _passwordError ?? _passwordPolicyMessage,
                isSubmitting: _isSubmitting,
                canSubmit: _canSubmit,
                onChanged: _handlePasswordChanged,
                onSubmit: _submitPassword,
              ),
            ),
            _SettingsViewingKeyStage.reveal => _ViewingKeyRevealView(
              ufvk: _ufvk,
              errorText: _revealError,
              copied: _copied,
              onCopyPressed: _copyUfvk,
            ),
          },
        ),
      ),
    );
  }
}

class _SettingsViewingKeyPane extends StatelessWidget {
  const _SettingsViewingKeyPane({
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

const _viewingKeyCardWidth = 396.0;

List<BoxShadow> _viewingKeyCardShadows(Color color) => [
  BoxShadow(color: color, blurRadius: 0.5),
  BoxShadow(color: color, offset: const Offset(0, 2), blurRadius: 2),
  BoxShadow(color: color, offset: const Offset(0, 1), blurRadius: 1),
  BoxShadow(color: color, blurRadius: 0.5),
];

class _ViewingKeyRevealView extends StatelessWidget {
  const _ViewingKeyRevealView({
    required this.ufvk,
    required this.errorText,
    required this.copied,
    required this.onCopyPressed,
  });

  final String? ufvk;
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
            'Viewing Key',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Anyone with this key can see this account’s balance and\n'
            'transaction history — but they can never spend from it.',
            textAlign: TextAlign.center,
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
              height: 18 / 14,
              letterSpacing: -0.14,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (errorText == null && ufvk != null)
            _ViewingKeyCard(
              ufvk: ufvk!,
              copied: copied,
              onCopyPressed: onCopyPressed,
            )
          else
            _ViewingKeyErrorCard(
              message:
                  errorText ?? 'Viewing key is not available for this account.',
            ),
        ],
      ),
    );
  }
}

class _ViewingKeyCard extends StatelessWidget {
  const _ViewingKeyCard({
    required this.ufvk,
    required this.copied,
    required this.onCopyPressed,
  });

  final String ufvk;
  final bool copied;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;

    return Container(
      width: _viewingKeyCardWidth,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _viewingKeyCardShadows(colors.shadows.subtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                AppIcon(
                  AppIcons.eye,
                  size: AppIconSize.medium,
                  color: cardTextColor,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Full Viewing Key',
                    style: AppTypography.bodyLarge.copyWith(
                      color: cardTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppButton(
                  key: const ValueKey('settings_viewing_key_copy_button'),
                  onPressed: () {
                    onCopyPressed();
                  },
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.mediumLarge,
                  height: 24,
                  minWidth: 52,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  child: Text(copied ? 'Copied' : 'Copy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Container(
            key: const ValueKey('settings_viewing_key_value'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Text(
              ufvk,
              style: AppTypography.codeSmall.copyWith(color: cardTextColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewingKeyErrorCard extends StatelessWidget {
  const _ViewingKeyErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: _viewingKeyCardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _viewingKeyCardShadows(colors.shadows.subtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            AppIcons.warning,
            size: AppIconSize.large,
            color: colors.icon.destructive,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ],
      ),
    );
  }
}
