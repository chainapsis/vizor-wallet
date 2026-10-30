import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../widgets/viewing_key_content.dart';
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';

/// Settings → Viewing key — password-gated choice and export of the account's
/// full or incoming viewing key. Available for both software and hardware
/// (Keystone) accounts, unlike the secret-passphrase screen: a UFVK only
/// grants view access (balance, transaction history), never spend, so
/// hardware accounts — which never hold spend authority on the phone — can
/// still export the same key their device already shares with Vizor.
class SettingsViewingKeyScreen extends ConsumerStatefulWidget {
  const SettingsViewingKeyScreen({
    this.accountUuid,
    this.privacyOverlayController,
    this.viewingKeysLoader,
    super.key,
  });

  final String? accountUuid;
  final SensitivePrivacyOverlayController? privacyOverlayController;

  /// Test seam — production calls `rust_wallet.getAccountViewingKeys` directly.
  @visibleForTesting
  final Future<rust_wallet.AccountViewingKeys> Function(String accountUuid)?
  viewingKeysLoader;

  @override
  ConsumerState<SettingsViewingKeyScreen> createState() =>
      _SettingsViewingKeyScreenState();
}

/// Deterministic reveal-state fixture used by Widgetbook and Figma comparison.
///
/// This is intentionally a separate widget rather than an initial state on
/// [SettingsViewingKeyScreen], so production navigation cannot bypass the
/// password confirmation gate.
class SettingsViewingKeyRevealPreview extends StatefulWidget {
  const SettingsViewingKeyRevealPreview({
    required this.viewingKeys,
    required this.account,
    this.initialType = ViewingKeyType.full,
    this.initialFormat = ViewingKeyFormat.qr,
    super.key,
  });

  final rust_wallet.AccountViewingKeys viewingKeys;
  final AccountInfo account;
  final ViewingKeyType? initialType;
  final ViewingKeyFormat initialFormat;

  @override
  State<SettingsViewingKeyRevealPreview> createState() =>
      _SettingsViewingKeyRevealPreviewState();
}

class _SettingsViewingKeyRevealPreviewState
    extends State<SettingsViewingKeyRevealPreview> {
  late ViewingKeyType? _selectedType = widget.initialType;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: ColoredBox(color: context.colors.background.window),
      sidebar: const AppMainSidebar(),
      pane: _SettingsViewingKeyPane(
        onBeforeNavigateBack: () {},
        onBackToChoice: _selectedType == null
            ? null
            : () => setState(() => _selectedType = null),
        centerContent: false,
        child: _ViewingKeyRevealView(
          viewingKeys: widget.viewingKeys,
          initialType: _selectedType,
          onSelectType: (type) => setState(() => _selectedType = type),
          initialFormat: widget.initialFormat,
          account: widget.account,
          onRetry: () {},
          errorText: null,
          onCopy: _noopPreviewCopy,
        ),
      ),
    );
  }
}

Future<void> _noopPreviewCopy(String value) async {}

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
  rust_wallet.AccountViewingKeys? _viewingKeys;
  String? _revealError;
  ViewingKeyType? _selectedType;

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
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _SettingsViewingKeyStage.password;
    _passwordError = passwordError;
    _viewingKeys = null;
    _revealError = null;
    _selectedType = null;
  }

  void _handleTargetAccountChanged() {
    if (_stage == _SettingsViewingKeyStage.password &&
        !_isSubmitting &&
        _viewingKeys == null) {
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

      final viewingKeys = await _loadViewingKeys(targetAccountUuid);

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
        _viewingKeys = viewingKeys;
        _stage = _SettingsViewingKeyStage.reveal;
        _isSubmitting = false;
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
        _revealError = 'Confirm access again to try loading this key.';
        _stage = _SettingsViewingKeyStage.reveal;
        _isSubmitting = false;
      });
    }
  }

  Future<rust_wallet.AccountViewingKeys> _loadViewingKeys(
    String targetAccountUuid,
  ) async {
    try {
      final loader = widget.viewingKeysLoader;
      if (loader != null) return await loader(targetAccountUuid);

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      return await rust_wallet.getAccountViewingKeys(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: targetAccountUuid,
      );
    } catch (e, st) {
      log('SettingsViewingKeyScreen._loadViewingKeys: ERROR: $e\n$st');
      throw _ViewingKeyUnavailableException(
        'Confirm access again to try loading this key.',
      );
    }
  }

  Future<void> _copyViewingKey(String value) async {
    if (_stage != _SettingsViewingKeyStage.reveal || _viewingKeys == null) {
      return;
    }
    await SensitiveClipboard.copyText(value);
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

    final accounts = ref.watch(accountProvider).value;
    final targetAccount = _targetAccount(accounts);
    return PopScope(
      canPop: _selectedType == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedType != null) {
          setState(() => _selectedType = null);
        }
      },
      child: AppDesktopBackdropShell(
        background: _stage == _SettingsViewingKeyStage.reveal
            ? ColoredBox(color: context.colors.background.window)
            : const SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
        sidebar: const AppMainSidebar(),
        pane: SensitivePrivacyOverlay(
          sensitiveContentVisible:
              _stage == _SettingsViewingKeyStage.reveal && _viewingKeys != null,
          controller: widget.privacyOverlayController,
          child: _SettingsViewingKeyPane(
            onBeforeNavigateBack: () => _clearSensitiveState(),
            onBackToChoice: _selectedType == null
                ? null
                : () => setState(() => _selectedType = null),
            centerContent: _stage != _SettingsViewingKeyStage.reveal,
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
                viewingKeys: _viewingKeys,
                initialType: _selectedType,
                onSelectType: (type) => setState(() => _selectedType = type),
                account: targetAccount,
                showAccountName:
                    targetAccount != null &&
                    targetAccount.uuid != accounts?.activeAccountUuid,
                onRetry: targetAccount == null
                    ? () => context.go('/accounts')
                    : () => setState(_clearSensitiveState),
                errorText: _revealError,
                onCopy: _copyViewingKey,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsViewingKeyPane extends StatelessWidget {
  const _SettingsViewingKeyPane({
    required this.onBeforeNavigateBack,
    required this.child,
    this.centerContent = true,
    this.onBackToChoice,
  });

  final VoidCallback onBeforeNavigateBack;
  final Widget child;
  final bool centerContent;
  final VoidCallback? onBackToChoice;

  @override
  Widget build(BuildContext context) {
    return AppPaneScrollScaffold(
      toolbar: AppPaneToolbar(
        backLinkMinWidth: 60,
        leading: onBackToChoice == null
            ? null
            : AppBackLink(label: 'Viewing key', onTap: onBackToChoice!),
        onBeforeNavigate: onBeforeNavigateBack,
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        centerContent ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Align(
        alignment: centerContent ? Alignment.center : Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _ViewingKeyRevealView extends StatelessWidget {
  const _ViewingKeyRevealView({
    required this.viewingKeys,
    required this.account,
    required this.errorText,
    required this.onCopy,
    required this.onRetry,
    this.showAccountName = false,
    this.initialType,
    required this.onSelectType,
    this.initialFormat = ViewingKeyFormat.qr,
  });

  final AccountInfo? account;
  final rust_wallet.AccountViewingKeys? viewingKeys;
  final String? errorText;
  final Future<void> Function(String) onCopy;
  final VoidCallback onRetry;
  final bool showAccountName;
  final ViewingKeyType? initialType;
  final ValueChanged<ViewingKeyType> onSelectType;
  final ViewingKeyFormat initialFormat;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 440,
      child: ViewingKeyContent(
        account: account,
        viewingKeys: viewingKeys,
        type: initialType,
        onSelectType: onSelectType,
        initialFormat: initialFormat,
        errorText: errorText,
        showTitle: true,
        showAccountName: showAccountName,
        onCopy: onCopy,
        onRetry: onRetry,
        copyButtonKey: const ValueKey('settings_viewing_key_copy_button'),
        keyValueKey: const ValueKey('settings_viewing_key_value'),
      ),
    );
  }
}
