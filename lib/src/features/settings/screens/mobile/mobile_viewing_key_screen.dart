import '../../../../core/navigation/mobile_sidebar_exit.dart';
import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/clipboard/sensitive_clipboard.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/biometric_icon.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/wallet.dart' as rust_wallet;
import '../../../../services/biometric_unlock.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../../onboarding/mobile/adaptive_passcode_layout.dart';
import '../../widgets/viewing_key_content.dart';

enum _ViewingKeyStage { confirmAccess, reveal }

/// Settings → Viewing key (mobile) — Figma-less port of
/// [MobileSeedPhraseScreen]'s confirm-access gate to a lower-stakes reveal:
/// a Unified Full Viewing Key only grants view access (balance, transaction
/// history), never spend, so unlike the secret passphrase it is available
/// for hardware (Keystone) accounts too and skips the screenshot warning.
class MobileViewingKeyScreen extends ConsumerStatefulWidget {
  const MobileViewingKeyScreen({
    this.accountUuid,
    this.privacyOverlayController,
    this.viewingKeysLoader,
    super.key,
  });

  final String? accountUuid;

  @visibleForTesting
  final SensitivePrivacyOverlayController? privacyOverlayController;

  /// Test seam — production calls `rust_wallet.getAccountViewingKeys` directly.
  @visibleForTesting
  final Future<rust_wallet.AccountViewingKeys> Function(String accountUuid)?
  viewingKeysLoader;

  @override
  ConsumerState<MobileViewingKeyScreen> createState() =>
      _MobileViewingKeyScreenState();
}

/// Deterministic reveal-state fixture used by Widgetbook and visual comparison.
///
/// Keeping this separate from [MobileViewingKeyScreen] ensures production
/// navigation cannot bypass the passcode or biometric confirmation gate.
class MobileViewingKeyRevealPreview extends StatefulWidget {
  const MobileViewingKeyRevealPreview({
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
  State<MobileViewingKeyRevealPreview> createState() =>
      _MobileViewingKeyRevealPreviewState();
}

class _MobileViewingKeyRevealPreviewState
    extends State<MobileViewingKeyRevealPreview> {
  late ViewingKeyType? _selectedType = widget.initialType;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            _ViewingKeyMobileHeader(
              title: _selectedType?.title ?? 'Viewing key',
              onBack: () => setState(() => _selectedType = null),
            ),
            Expanded(
              child: _MobileViewingKeyRevealView(
                viewingKeys: widget.viewingKeys,
                initialType: _selectedType,
                onSelectType: (type) => setState(() => _selectedType = type),
                initialFormat: widget.initialFormat,
                account: widget.account,
                onRetry: () {},
                onCopy: _noopPreviewCopy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _noopPreviewCopy(String value) async {}

class _MobileViewingKeyScreenState
    extends ConsumerState<MobileViewingKeyScreen> {
  var _stage = _ViewingKeyStage.confirmAccess;
  var _entry = '';
  var _checking = false;
  String? _gateError;
  int _accessCheckGeneration = 0;

  rust_wallet.AccountViewingKeys? _viewingKeys;
  String? _revealError;
  ViewingKeyType? _selectedType;

  late final bool _ownsPrivacyController;
  late final SensitivePrivacyOverlayController _privacyController;

  @override
  void initState() {
    super.initState();
    _ownsPrivacyController = widget.privacyOverlayController == null;
    _privacyController =
        widget.privacyOverlayController ??
        SensitivePrivacyEnvironmentController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryBiometricGate());
    });
  }

  @override
  void dispose() {
    if (_ownsPrivacyController) _privacyController.dispose();
    _viewingKeys = null;
    super.dispose();
  }

  // ── Confirm access gate ────────────────────────────────────────────

  Future<void> _tryBiometricGate() async {
    if (_checking || _stage != _ViewingKeyStage.confirmAccess) return;
    final expectedAccountUuid = _targetAccount(
      ref.read(accountProvider).value,
    )?.uuid;
    final accessCheckGeneration = ++_accessCheckGeneration;
    final biometric = await ref.read(biometricUnlockProvider.future);
    if (!mounted) return;
    if (accessCheckGeneration != _accessCheckGeneration ||
        _targetAccountChanged(expectedAccountUuid)) {
      _showTargetAccountChangedError();
      return;
    }
    if (!biometric.usable) return;
    final wasEnabled = biometric.enabled;
    setState(() => _checking = true);
    _privacyController.beginAuthPrompt();
    String? readResult;
    try {
      readResult = await ref
          .read(biometricUnlockProvider.notifier)
          .readPasscode(reason: 'Confirm access to your viewing key');
    } finally {
      _privacyController.endAuthPrompt();
    }
    if (!mounted) return;
    if (accessCheckGeneration != _accessCheckGeneration ||
        _targetAccountChanged(expectedAccountUuid)) {
      _showTargetAccountChangedError();
      return;
    }
    final passcode = readResult;
    if (passcode == null) {
      final now = ref.read(biometricUnlockProvider).value;
      setState(() {
        _entry = '';
        _checking = false;
        if (wasEnabled && now != null && !now.enabled) {
          _gateError = biometric.availability.kind.changedMessage;
        }
      });
      return;
    }
    setState(() {
      _entry = passcode;
      _gateError = null;
    });
    await _confirmPasscode();
  }

  void _onDigit(int digit) {
    if (_checking || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _gateError = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      unawaited(_confirmPasscode());
    }
  }

  void _onBackspace() {
    if (_checking || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _confirmPasscode() async {
    final expectedAccountUuid = _targetAccount(
      ref.read(accountProvider).value,
    )?.uuid;
    final accessCheckGeneration = ++_accessCheckGeneration;
    setState(() => _checking = true);
    try {
      final valid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
      if (!mounted) return;
      if (!valid) {
        unawaited(AppHaptics.error());
        setState(() {
          _entry = '';
          _checking = false;
          _gateError = 'Incorrect passcode';
        });
        return;
      }
      if (accessCheckGeneration != _accessCheckGeneration ||
          _targetAccountChanged(expectedAccountUuid)) {
        _handleTargetAccountChanged();
        return;
      }
      await _reveal(expectedAccountUuid);
    } catch (e, st) {
      log('MobileViewingKey: passcode confirm failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _entry = '';
        _checking = false;
        _gateError = "Couldn't verify the passcode. Try again.";
      });
    }
  }

  // ── Reveal ─────────────────────────────────────────────────────────

  AccountInfo? _targetAccount(AccountState? accountState) {
    if (accountState == null) return null;
    final requestedUuid = widget.accountUuid;
    if (requestedUuid == null) return accountState.activeAccount;
    for (final account in accountState.accounts) {
      if (account.uuid == requestedUuid) return account;
    }
    return null;
  }

  bool _targetAccountChanged(String? expectedAccountUuid) {
    final accountState = ref.read(accountProvider).value;
    return _targetAccount(accountState)?.uuid != expectedAccountUuid;
  }

  void _handleTargetAccountChanged() {
    _accessCheckGeneration += 1;
    if (_stage == _ViewingKeyStage.confirmAccess &&
        !_checking &&
        _viewingKeys == null) {
      return;
    }
    _showTargetAccountChangedError();
  }

  void _showTargetAccountChangedError() {
    setState(() {
      _stage = _ViewingKeyStage.confirmAccess;
      _selectedType = null;
      _entry = '';
      _checking = false;
      _gateError = 'Selected account changed. Enter your passcode again.';
      _viewingKeys = null;
      _revealError = null;
    });
  }

  Future<void> _reveal(String? expectedAccountUuid) async {
    final accountState = ref.read(accountProvider).value;
    final account = _targetAccount(accountState);
    if (account?.uuid != expectedAccountUuid) {
      _handleTargetAccountChanged();
      return;
    }
    String? revealError;
    rust_wallet.AccountViewingKeys? viewingKeys;
    if (account == null) {
      revealError = widget.accountUuid == null
          ? 'No active account is selected.'
          : 'The selected account is no longer available.';
    } else {
      try {
        final loader = widget.viewingKeysLoader;
        if (loader != null) {
          viewingKeys = await loader(account.uuid);
        } else {
          final dbPath = await getWalletDbPath();
          final endpoint = ref.read(rpcEndpointProvider);
          viewingKeys = await rust_wallet.getAccountViewingKeys(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
        }
      } catch (e, st) {
        log('MobileViewingKey: getAccountViewingKeys failed: $e\n$st');
        revealError = 'Confirm access again to try loading this key.';
      }
    }
    if (!mounted) return;
    if (_targetAccountChanged(expectedAccountUuid)) {
      _handleTargetAccountChanged();
      return;
    }
    if (viewingKeys != null && revealError == null) {
      unawaited(AppHaptics.accessGranted());
    }
    setState(() {
      _viewingKeys = viewingKeys;
      _revealError = revealError;
      _stage = _ViewingKeyStage.reveal;
      _checking = false;
    });
  }

  void _retryReveal() {
    setState(() {
      _accessCheckGeneration += 1;
      _stage = _ViewingKeyStage.confirmAccess;
      _selectedType = null;
      _entry = '';
      _checking = false;
      _gateError = null;
      _viewingKeys = null;
      _revealError = null;
    });
  }

  Future<void> _copyViewingKey(String value) async {
    if (_stage != _ViewingKeyStage.reveal || _viewingKeys == null) return;
    await SensitiveClipboard.copyText(value);
    unawaited(AppHaptics.copy());
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
    final colors = context.colors;
    final accounts = ref.watch(accountProvider).value;
    final targetAccount = _targetAccount(accounts);
    return MobileSidebarExitScope(
      canNavigate: !_checking,
      child: PopScope(
        canPop: _selectedType == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selectedType != null) {
            setState(() => _selectedType = null);
          }
        },
        child: Scaffold(
          backgroundColor: colors.background.window,
          body: AppToastHost(
            child: SensitivePrivacyOverlay(
              sensitiveContentVisible:
                  _stage == _ViewingKeyStage.reveal && _viewingKeys != null,
              controller: _privacyController,
              child: SafeArea(
                child: Column(
                  children: [
                    _ViewingKeyMobileHeader(
                      title: _stage == _ViewingKeyStage.confirmAccess
                          ? ''
                          : _selectedType?.title ?? 'Viewing key',
                      onBack: () {
                        if (_selectedType != null) {
                          setState(() => _selectedType = null);
                        } else {
                          context.pop();
                        }
                      },
                    ),
                    Expanded(
                      child: switch (_stage) {
                        _ViewingKeyStage.confirmAccess => _buildGate(colors),
                        _ViewingKeyStage.reveal => _MobileViewingKeyRevealView(
                          viewingKeys: _viewingKeys,
                          initialType: _selectedType,
                          onSelectType: (type) =>
                              setState(() => _selectedType = type),
                          account: targetAccount,
                          showAccountName:
                              targetAccount != null &&
                              targetAccount.uuid != accounts?.activeAccountUuid,
                          onRetry: targetAccount == null
                              ? () => context.go('/accounts')
                              : _retryReveal,
                          errorText: _revealError,
                          onCopy: _copyViewingKey,
                        ),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGate(AppColors colors) {
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final showBiometric = !_checking && biometric.usable;
    return AdaptivePasscodeLayout(
      title: 'Enter Passcode',
      subtitle: 'Confirm your access',
      prompt: PasscodePromptField(
        length: kMobilePasscodeLength,
        filled: _entry.length,
        error: _gateError,
        minGap: 0,
      ),
      keypad: PasscodeNumpad(
        onDigit: _onDigit,
        onBackspace: _onBackspace,
        canDelete: _entry.isNotEmpty,
        enabled: !_checking,
      ),
      footer: showBiometric
          ? SizedBox(
              key: const ValueKey('mobile_viewing_key_biometric_footer'),
              height: 36,
              child: Center(
                child: PasscodeBiometricButton(
                  label: biometric.availability.kind.signInLabel,
                  icon: Center(
                    child: BiometricIcon(
                      kind: biometric.availability.kind,
                      size: 13.5,
                      fingerprintSize: 16,
                    ),
                  ),
                  onPressed: () => unawaited(_tryBiometricGate()),
                ),
              ),
            )
          : null,
      footerHeight: showBiometric ? 36 : 0,
      legacy: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter Passcode',
                    textAlign: TextAlign.center,
                    style: AppTypography.displayLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Confirm your access',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: kPasscodePromptDigitsHeight,
                    child: PasscodePromptField(
                      length: kMobilePasscodeLength,
                      filled: _entry.length,
                      error: _gateError,
                      minGap: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PasscodeNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            canDelete: _entry.isNotEmpty,
            enabled: !_checking,
          ),
          if (showBiometric) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              key: const ValueKey('mobile_viewing_key_biometric_footer'),
              height: 36,
              child: Center(
                child: PasscodeBiometricButton(
                  label: biometric.availability.kind.signInLabel,
                  icon: Center(
                    child: BiometricIcon(
                      kind: biometric.availability.kind,
                      size: 13.5,
                      fingerprintSize: 16,
                    ),
                  ),
                  onPressed: () => unawaited(_tryBiometricGate()),
                ),
              ),
            ),
          ],
          if (!showBiometric) const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

class _MobileViewingKeyRevealView extends StatelessWidget {
  const _MobileViewingKeyRevealView({
    required this.account,
    required this.viewingKeys,
    required this.onCopy,
    required this.onRetry,
    this.showAccountName = false,
    this.initialType,
    required this.onSelectType,
    this.initialFormat = ViewingKeyFormat.qr,
    this.errorText,
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
    return ViewingKeyContent(
      account: account,
      showAccountName: showAccountName,
      viewingKeys: viewingKeys,
      type: initialType,
      onSelectType: onSelectType,
      initialFormat: initialFormat,
      errorText: errorText,
      onCopy: onCopy,
      onRetry: onRetry,
      copyButtonKey: const ValueKey('mobile_viewing_key_copy'),
      keyValueKey: const ValueKey('mobile_viewing_key_value'),
      layoutBuilder: (context, content, footer) {
        if (footer == null) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.lg,
            ),
            children: [content],
          );
        }
        return CustomScrollView(
          key: const ValueKey('mobile_viewing_key_reveal_scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              sliver: SliverToBoxAdapter(child: content),
            ),
            // Match mobile review pages: spare space belongs above the
            // bottom actions. When content grows, the whole page scrolls.
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.s,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('mobile_viewing_key_footer'),
                      child: footer,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewingKeyMobileHeader extends StatelessWidget {
  const _ViewingKeyMobileHeader({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMobileTopNavHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.s,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Semantics(
                container: true,
                button: true,
                label: 'Back',
                child: AppButton(
                  onPressed: onBack,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.medium,
                  height: 44,
                  contentPadding: EdgeInsets.zero,
                  child: ExcludeSemantics(
                    child: AppIcon(
                      AppIcons.chevronBackward,
                      size: 24,
                      color: context.colors.icon.accent,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: ViewingKeyTransition(
                  value: title,
                  child: Text(
                    title,
                    key: const ValueKey('viewing_key_mobile_title'),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }
}
