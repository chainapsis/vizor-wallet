import 'dart:async';

import 'package:flutter/material.dart' show Icon, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/clipboard/sensitive_clipboard.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/device_owner_auth_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../rust/api/wallet.dart' as rust_wallet;
import '../../../../services/biometric_unlock.dart';
import '../../../../services/device_owner_auth.dart';
import '../../../onboarding/mobile/forgot_passcode_sheet.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';
import '../../viewing_key_copy.dart';

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
    this.ufvkLoader,
    super.key,
  });

  final String? accountUuid;

  @visibleForTesting
  final SensitivePrivacyOverlayController? privacyOverlayController;

  /// Test seam — production calls `rust_wallet.getAccountUfvk` directly.
  @visibleForTesting
  final Future<String> Function(String accountUuid)? ufvkLoader;

  @override
  ConsumerState<MobileViewingKeyScreen> createState() =>
      _MobileViewingKeyScreenState();
}

/// Deterministic reveal-state fixture used by Widgetbook and visual comparison.
///
/// Keeping this separate from [MobileViewingKeyScreen] ensures production
/// navigation cannot bypass the passcode or biometric confirmation gate.
class MobileViewingKeyRevealPreview extends StatelessWidget {
  const MobileViewingKeyRevealPreview({required this.ufvk, super.key});

  final String ufvk;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: 'Viewing Key', onBack: () {}),
            Expanded(
              child: _MobileViewingKeyRevealView(
                ufvk: ufvk,
                onCopyUfvk: _noopPreviewCopy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _noopPreviewCopy() async {}

class _MobileViewingKeyScreenState
    extends ConsumerState<MobileViewingKeyScreen> {
  var _stage = _ViewingKeyStage.confirmAccess;
  var _entry = '';
  var _checking = false;
  String? _gateError;
  int _accessCheckGeneration = 0;

  String? _ufvk;
  String? _revealError;

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
    _ufvk = null;
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

  Future<void> _showForgotPasscodeSheet() async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeSheet(),
    );
    if (confirmed != true || !mounted) return;
    final lastWarningConfirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeLastWarningSheet(),
    );
    if (lastWarningConfirmed != true || !mounted) return;
    await _resetWallet();
  }

  Future<void> _resetWallet() async {
    setState(() => _checking = true);
    final router = GoRouter.of(context);
    try {
      final didReset = await resetWalletForForgottenPasscode(ref);
      if (!mounted) return;
      if (!didReset) {
        setState(() {
          _checking = false;
          _entry = '';
          _gateError = null;
        });
        return;
      }
    } on DeviceOwnerAuthException catch (e, st) {
      log('MobileViewingKey._resetWallet auth failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _entry = '';
        _gateError = e.kind == DeviceOwnerAuthErrorKind.unavailable
            ? kWalletResetDeviceAuthRequiredMessage
            : kWalletResetDeviceAuthFailedMessage;
      });
      return;
    } catch (e, st) {
      log('MobileViewingKey._resetWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _entry = '';
        _gateError = "Couldn't reset the app. Please try again.";
      });
      return;
    }
    router.go('/welcome');
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
        _ufvk == null) {
      return;
    }
    _showTargetAccountChangedError();
  }

  void _showTargetAccountChangedError() {
    setState(() {
      _stage = _ViewingKeyStage.confirmAccess;
      _entry = '';
      _checking = false;
      _gateError = 'Selected account changed. Enter your passcode again.';
      _ufvk = null;
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
    String? ufvk;
    if (account == null) {
      revealError = widget.accountUuid == null
          ? 'No active account is selected.'
          : 'The selected account is no longer available.';
    } else {
      try {
        final loader = widget.ufvkLoader;
        if (loader != null) {
          ufvk = await loader(account.uuid);
        } else {
          final dbPath = await getWalletDbPath();
          final endpoint = ref.read(rpcEndpointProvider);
          ufvk = await rust_wallet.getAccountUfvk(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
        }
      } catch (e, st) {
        log('MobileViewingKey: getAccountUfvk failed: $e\n$st');
        revealError = 'Viewing key is not available for this account.';
      }
    }
    if (!mounted) return;
    if (_targetAccountChanged(expectedAccountUuid)) {
      _handleTargetAccountChanged();
      return;
    }
    setState(() {
      _ufvk = ufvk;
      _revealError = revealError;
      _stage = _ViewingKeyStage.reveal;
      _checking = false;
    });
  }

  Future<void> _copyUfvk() async {
    final ufvk = _ufvk;
    if (ufvk == null || ufvk.isEmpty) return;
    await SensitiveClipboard.copyText(ufvk);
    unawaited(AppHaptics.copy());
    if (mounted) showAppToast(context, 'Viewing key copied');
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
    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible:
              _stage == _ViewingKeyStage.reveal && _ufvk != null,
          controller: _privacyController,
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: _stage == _ViewingKeyStage.confirmAccess
                      ? ''
                      : 'Viewing Key',
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: switch (_stage) {
                    _ViewingKeyStage.confirmAccess => _buildGate(colors),
                    _ViewingKeyStage.reveal => _MobileViewingKeyRevealView(
                      ufvk: _ufvk,
                      errorText: _revealError,
                      onCopyUfvk: _copyUfvk,
                    ),
                  },
                ),
              ],
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
    return Column(
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
          onHelp: _checking ? null : _showForgotPasscodeSheet,
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
                icon: biometric.availability.kind == BiometricKind.face
                    ? const Center(child: AppIcon(AppIcons.faceId, size: 13.5))
                    : const Icon(Icons.fingerprint, size: 16),
                onPressed: () => unawaited(_tryBiometricGate()),
              ),
            ),
          ),
        ],
        if (!showBiometric) const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _MobileViewingKeyRevealView extends StatelessWidget {
  const _MobileViewingKeyRevealView({
    required this.ufvk,
    required this.onCopyUfvk,
    this.errorText,
  });

  final String? ufvk;
  final String? errorText;
  final VoidCallback onCopyUfvk;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: viewingKeyAccessSummary,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const TextSpan(text: ' $viewingKeyAccessDetails'),
            ],
          ),
          key: const ValueKey('viewing_key_explanation'),
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          viewingKeyPrivacyNotice,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (errorText != null || ufvk == null)
          MobileSurfaceCard(
            child: Text(
              errorText ?? 'Viewing key is not available for this account.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
              ),
            ),
          )
        else
          MobileSurfaceCard(
            cornerRadius: AppRadii.xLarge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Full Viewing Key',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    _CopyChip(
                      key: const ValueKey('mobile_viewing_key_copy'),
                      label: 'Copy',
                      onTap: onCopyUfvk,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  key: const ValueKey('mobile_viewing_key_value'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.background.ground,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Text(
                    ufvk!,
                    style: AppTypography.codeSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dark "Copy ⧉" chip in the card header — matches the secret passphrase
/// screen's reveal-card treatment.
class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Copy viewing key',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96, minHeight: 36),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xs,
            ),
            decoration: ShapeDecoration(
              color: colors.background.inverse,
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.inverse,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(
                  AppIcons.copy,
                  size: AppIconSize.medium,
                  color: colors.text.inverse,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
