import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_bootstrap.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/security/password_policy.dart';
import '../../core/security/software_wallet_secret.dart';
import '../../core/storage/wallet_recovery.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/api/wallet.dart' as rust_wallet;
import '../../services/qr_scanner.dart';
import '../keystone/widgets/keystone_qr_scanner_card.dart';
import 'mobile/mobile_passcode_screen.dart' show kMobilePasscodeLength;
import 'mobile/passcode_widgets.dart';
import 'shared/onboarding_auth_shell.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;

class WalletRecoveryScreen extends ConsumerStatefulWidget {
  const WalletRecoveryScreen({super.key});

  @override
  ConsumerState<WalletRecoveryScreen> createState() =>
      _WalletRecoveryScreenState();
}

class _WalletRecoveryScreenState extends ConsumerState<WalletRecoveryScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _mnemonic = TextEditingController();
  final _passphrase = TextEditingController();
  WalletRecoverySession? _session;
  String? _selectedCandidatePath;
  String? _editingAccount;
  String? _scanningAccount;
  String? _passwordError;
  String? _phraseError;
  String? _newPasswordError;
  String? _confirmationError;
  String? _stageError;
  bool _busy = false;
  bool _authenticated = false;
  String _passcode = '';
  String? _newPasscode;

  WalletRecoveryState get _recovery =>
      ref.read(appBootstrapProvider).walletRecovery!;

  @override
  void dispose() {
    _session?.dispose();
    _password.dispose();
    _confirmation.dispose();
    _mnemonic.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  void _select(WalletRecoveryCandidate candidate) {
    _session?.dispose();
    setState(() {
      _session = WalletRecoverySession(candidate: candidate);
      _selectedCandidatePath = candidate.path;
      _authenticated = !_recovery.isPasswordConfigured;
      _clearErrors();
      _editingAccount = null;
      _scanningAccount = null;
      _passcode = '';
      _newPasscode = null;
    });
  }

  Future<void> _unlock() async {
    if (_busy || _session == null) return;
    final password = _mobile ? _passcode : _password.text;
    if (!isWalletPasswordValid(password)) {
      setState(() => _passwordError = validateRequiredWalletPassword(password));
      return;
    }
    setState(() {
      _busy = true;
      _passwordError = null;
      _stageError = null;
    });
    try {
      final valid = await _session!.unlockExistingSecrets(password);
      if (!mounted) return;
      setState(() {
        _authenticated = valid;
        if (!valid) {
          _passwordError = _mobile
              ? 'Incorrect passcode. Try again.'
              : 'Incorrect password. Try again.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _passwordError =
              'Your saved recovery material could not be read. Try again.',
        );
      }
    } finally {
      _password.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _passcode = '';
        });
      }
    }
  }

  Future<void> _verifyPhrase(String uuid) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _phraseError = null;
      _stageError = null;
    });
    try {
      final verified = await _session!.verifySoftwareSecret(
        uuid,
        SoftwareWalletSecret(
          mnemonic: _mnemonic.text.trim().split(RegExp(r'\s+')).join(' '),
          bip39Passphrase: _passphrase.text,
        ),
      );
      if (!mounted) return;
      setState(() {
        if (verified) {
          _editingAccount = null;
          _mnemonic.clear();
          _passphrase.clear();
        } else {
          final accountName = _accountName(uuid);
          _phraseError =
              "This phrase doesn't match $accountName. Check the words and passphrase.";
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _phraseError =
              'Check your recovery phrase and passphrase, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyKeystone(ScanResult result) async {
    final uuid = _scanningAccount;
    if (_busy || uuid == null) return;
    setState(() {
      _busy = true;
      _stageError = null;
    });
    try {
      final accounts = await rust_keystone.decodeAccountsFromCbor(
        cbor: result.data,
      );
      var matched = false;
      for (final account in accounts) {
        if (await _session!.verifyHardwareKey(uuid, account.ufvk)) {
          matched = true;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        if (matched) {
          _scanningAccount = null;
        } else {
          _stageError =
              'This Keystone QR does not match the selected wallet account.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _stageError =
              'Scan the Zcash account QR from your Keystone again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnect() async {
    if (_busy || _session?.canReconnect != true) return;
    String? newPassword;
    if (!_recovery.isPasswordConfigured && !_session!.hasEstablishedPassword) {
      newPassword = _mobile ? _newPasscode : _password.text;
      final policy = validateRequiredWalletPassword(newPassword ?? '');
      if (policy != null) {
        setState(() => _newPasswordError = policy);
        return;
      }
      if (!_mobile && newPassword != _confirmation.text) {
        setState(() => _confirmationError = 'Passwords do not match.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _newPasswordError = null;
      _confirmationError = null;
      _stageError = null;
    });
    try {
      await _session!.reconnect(newPassword: newPassword);
      _password.clear();
      _confirmation.clear();
      _newPasscode = null;
      await ref.read(appBootstrapRetryProvider)();
    } catch (_) {
      if (mounted) {
        setState(
          () => _stageError =
              "Couldn't reconnect. Your original wallet file is unchanged. Try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterDigit(String digit) {
    if (_busy || _passcode.length >= 6) return;
    setState(() {
      _passcode += digit;
      _passwordError = null;
      _newPasswordError = null;
    });
    if (_passcode.length != 6) return;
    if (!_authenticated) {
      _unlock();
    } else if (_newPasscode == null) {
      setState(() {
        _newPasscode = _passcode;
        _passcode = '';
      });
    } else if (_newPasscode == _passcode) {
      _reconnect();
    } else {
      setState(() {
        _newPasscode = null;
        _passcode = '';
        _newPasswordError = 'Passcodes do not match. Try again.';
      });
    }
  }

  void _clearErrors() {
    _passwordError = null;
    _phraseError = null;
    _newPasswordError = null;
    _confirmationError = null;
    _stageError = null;
  }

  String _accountName(String uuid) => _session!.candidate.accounts
      .firstWhere((account) => account.uuid == uuid)
      .name;

  bool get _needsNewCredential =>
      _session?.canReconnect == true &&
      !_recovery.isPasswordConfigured &&
      !_session!.hasEstablishedPassword;

  bool get _isMobilePasscodeStage =>
      _mobile && _session != null && (!_authenticated || _needsNewCredential);

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(appBootstrapProvider).walletRecovery;
    if (recovery == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: _mobile
          ? context.colors.background.ground
          : Colors.transparent,
      body: SafeArea(
        child: _mobile
            ? (_isMobilePasscodeStage
                  ? _mobilePasscodeContent()
                  : _mobileRegularContent(recovery))
            : OnboardingAuthShell(card: _desktopCard(recovery)),
      ),
    );
  }

  Widget _desktopCard(WalletRecoveryState recovery) {
    return OnboardingAuthCard(
      width: 396,
      height: 600,
      borderRadius: AppSpacing.md,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        children: [
          _RecoveryHeader(title: _title(recovery), body: _subtitle(recovery)),
          const SizedBox(height: AppSpacing.base),
          Expanded(child: SingleChildScrollView(child: _regularBody(recovery))),
        ],
      ),
    );
  }

  Widget _mobileRegularContent(WalletRecoveryState recovery) {
    return ColoredBox(
      color: context.colors.background.ground,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RecoveryHeader(
                  title: _title(recovery),
                  body: _subtitle(recovery),
                ),
                const SizedBox(height: AppSpacing.base),
                _regularBody(recovery),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobilePasscodeContent() {
    final colors = context.colors;
    final enteringExistingPasscode = !_authenticated;
    final confirming = !enteringExistingPasscode && _newPasscode != null;
    final title = enteringExistingPasscode
        ? 'Enter your passcode'
        : confirming
        ? 'Confirm passcode'
        : 'Create passcode';
    final subtitle = enteringExistingPasscode
        ? 'Use the passcode you set for this wallet.'
        : confirming
        ? 'Re-enter your passcode.'
        : '6 digits';
    final error = enteringExistingPasscode ? _passwordError : _newPasswordError;

    return ColoredBox(
      color: colors.background.ground,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppTypography.displayLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: kPasscodePromptDigitsHeight,
                      child: PasscodePromptField(
                        length: kMobilePasscodeLength,
                        filled: _passcode.length,
                        error: error,
                        minGap: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PasscodeNumpad(
              onDigit: (digit) => _enterDigit('$digit'),
              enabled: !_busy,
              canDelete: _passcode.isNotEmpty && !_busy,
              onBackspace: () {
                if (_busy || _passcode.isEmpty) return;
                setState(() {
                  _passcode = _passcode.substring(0, _passcode.length - 1);
                  _passwordError = null;
                  _newPasswordError = null;
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _regularBody(WalletRecoveryState recovery) {
    if (_session == null) return _candidateContent(recovery);
    if (!_authenticated) return _desktopPasswordContent();
    if (!_session!.canReconnect) return _accountVerificationContent();
    if (_needsNewCredential) return _desktopNewPasswordContent();
    return _readyContent();
  }

  Widget _candidateContent(WalletRecoveryState recovery) {
    if (recovery.candidates.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _primaryAction(
            label: _busy ? 'Searching...' : 'Search again',
            onPressed: _busy ? null : _restart,
          ),
        ],
      );
    }

    final selectable = recovery.candidates
        .where((candidate) => candidate.canInspect)
        .toList();
    final selected = _selectedCandidate(recovery);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in recovery.candidates.indexed) ...[
          _CandidateRow(
            candidate: entry.$2,
            networkLabel: _networkLabel(entry.$2.network),
            accountCount: _accountCount(entry.$2.accounts.length),
            selected: selected?.path == entry.$2.path,
            showSelection: selectable.length > 1,
            onSelect: entry.$2.canInspect
                ? () => setState(() => _selectedCandidatePath = entry.$2.path)
                : null,
          ),
          if (entry.$1 != recovery.candidates.length - 1) _rowDivider(),
        ],
        if (_stageError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StageError(message: _stageError!),
        ],
        const SizedBox(height: AppSpacing.base),
        if (selected != null)
          _primaryAction(
            label: 'Recover this wallet',
            onPressed: _busy ? null : () => _select(selected),
          )
        else
          _primaryAction(
            label: _busy ? 'Searching...' : 'Search again',
            onPressed: _busy ? null : _restart,
          ),
        if (selected != null) ...[
          const SizedBox(height: AppSpacing.s),
          _secondaryAction(label: 'Search again', onPressed: _restart),
        ],
      ],
    );
  }

  Widget _desktopPasswordContent() {
    final candidate = _session!.candidate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WalletMeta(
          text:
              '${_networkLabel(candidate.network)} · ${_accountCount(candidate.accounts.length)}',
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: SizedBox(
            width: 256,
            child: _RecoveryFieldBlock(
              child: PasswordTextField(
                label: 'Password',
                hintText: 'Password',
                showLabel: false,
                surface: AppTextFieldSurface.secondary,
                leadingSlotWidth: 32,
                inputHorizontalPadding: AppSpacing.s,
                controller: _password,
                enabled: !_busy,
                showVisibilityToggle: false,
                messageText: _passwordError,
                tone: _passwordError == null
                    ? AppTextFieldTone.neutral
                    : AppTextFieldTone.destructive,
                onChanged: (_) => setState(() => _passwordError = null),
                onSubmitted: (_) => _unlock(),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        _primaryAction(
          label: _busy ? 'Checking...' : 'Continue',
          onPressed: _busy ? null : _unlock,
        ),
        const SizedBox(height: AppSpacing.s),
        _secondaryAction(label: 'Start over', onPressed: _restart),
      ],
    );
  }

  Widget _accountVerificationContent() {
    final session = _session!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in session.candidate.accounts.indexed) ...[
          _AccountRow(
            account: entry.$2,
            verified: session.isVerified(entry.$2.uuid),
            child: session.isVerified(entry.$2.uuid)
                ? null
                : _accountRecovery(entry.$2),
          ),
          if (entry.$1 != session.candidate.accounts.length - 1) _rowDivider(),
        ],
        if (_stageError != null && _scanningAccount == null) ...[
          const SizedBox(height: AppSpacing.md),
          _StageError(message: _stageError!),
        ],
        const SizedBox(height: AppSpacing.base),
        _secondaryAction(label: 'Start over', onPressed: _restart),
      ],
    );
  }

  Widget _desktopNewPasswordContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 256,
            child: Column(
              children: [
                _RecoveryFieldBlock(
                  child: PasswordTextField(
                    label: 'New password',
                    hintText: 'Min. 8 characters and symbols',
                    controller: _password,
                    enabled: !_busy,
                    showVisibilityToggle: false,
                    messageText: _newPasswordError,
                    tone: _newPasswordError == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    onChanged: (_) => setState(() {
                      _newPasswordError = null;
                      _confirmationError = null;
                    }),
                    onSubmitted: (_) => _reconnect(),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                _RecoveryFieldBlock(
                  child: PasswordTextField(
                    label: 'Confirm password',
                    hintText: 'Confirm password',
                    controller: _confirmation,
                    enabled: !_busy,
                    showVisibilityToggle: false,
                    messageText: _confirmationError,
                    tone: _confirmationError == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    onChanged: (_) => setState(() => _confirmationError = null),
                    onSubmitted: (_) => _reconnect(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_stageError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StageError(message: _stageError!),
        ],
        const SizedBox(height: AppSpacing.base),
        _primaryAction(
          label: _busy ? 'Reconnecting...' : 'Reconnect wallet',
          onPressed: _busy ? null : _reconnect,
        ),
        const SizedBox(height: AppSpacing.s),
        _secondaryAction(label: 'Start over', onPressed: _restart),
      ],
    );
  }

  Widget _readyContent() {
    final session = _session!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in session.candidate.accounts.indexed) ...[
          _AccountRow(account: entry.$2, verified: true),
          if (entry.$1 != session.candidate.accounts.length - 1) _rowDivider(),
        ],
        if (_stageError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _StageError(message: _stageError!),
        ],
        const SizedBox(height: AppSpacing.base),
        _primaryAction(
          label: _busy ? 'Reconnecting...' : 'Reconnect wallet',
          onPressed: _busy ? null : _reconnect,
        ),
        const SizedBox(height: AppSpacing.s),
        _secondaryAction(label: 'Start over', onPressed: _restart),
      ],
    );
  }

  Widget _accountRecovery(rust_wallet.AccountInfo account) {
    if (account.isHardware && _scanningAccount != account.uuid) {
      return _inlineAction(
        label: 'Scan Keystone QR',
        onPressed: _busy
            ? null
            : () => setState(() {
                _scanningAccount = account.uuid;
                _stageError = null;
              }),
      );
    }
    if (account.isHardware) {
      return KeystoneQrScannerCard(
        expectedUrType: 'zcash-accounts',
        decoding: _busy,
        error: _stageError,
        onProgress: (_) {},
        onDecodeError: (_) => setState(
          () => _stageError = 'Scan the Zcash account QR from your Keystone.',
        ),
        onComplete: _verifyKeystone,
        unavailableMessage:
            'Connect a camera to scan your Keystone account QR.',
      );
    }
    if (_editingAccount != account.uuid) {
      return _inlineAction(
        label: 'Enter recovery phrase',
        onPressed: _busy
            ? null
            : () {
                _mnemonic.clear();
                _passphrase.clear();
                setState(() {
                  _editingAccount = account.uuid;
                  _phraseError = null;
                });
              },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecoveryFieldBlock(
          child: AppTextField(
            label: 'Recovery phrase',
            controller: _mnemonic,
            minLines: 3,
            maxLines: 6,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            messageText: _phraseError,
            tone: _phraseError == null
                ? AppTextFieldTone.neutral
                : AppTextFieldTone.destructive,
            onChanged: (_) => setState(() => _phraseError = null),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        PasswordTextField(
          label: 'BIP39 passphrase (optional)',
          controller: _passphrase,
          enabled: !_busy,
          onChanged: (_) => setState(() => _phraseError = null),
        ),
        const SizedBox(height: AppSpacing.s),
        _primaryAction(
          label: _busy ? 'Verifying...' : 'Verify recovery phrase',
          onPressed: _busy ? null : () => _verifyPhrase(account.uuid),
        ),
      ],
    );
  }

  Widget _primaryAction({
    required String label,
    required VoidCallback? onPressed,
  }) => Center(
    child: AppButton(
      onPressed: onPressed,
      minWidth: _mobile ? null : 196,
      expand: _mobile,
      child: Text(label),
    ),
  );

  Widget _secondaryAction({
    required String label,
    required VoidCallback? onPressed,
  }) => Center(
    child: AppButton(
      variant: AppButtonVariant.ghost,
      size: AppButtonSize.large,
      onPressed: _busy ? null : onPressed,
      minWidth: _mobile ? null : 196,
      expand: _mobile,
      child: Text(label),
    ),
  );

  Widget _inlineAction({
    required String label,
    required VoidCallback? onPressed,
  }) => Center(
    child: AppButton(
      variant: AppButtonVariant.secondary,
      size: _mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
      onPressed: onPressed,
      minWidth: _mobile ? null : 196,
      expand: _mobile,
      child: Text(label),
    ),
  );

  Widget _rowDivider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: context.colors.border.subtle),
    ),
  );

  WalletRecoveryCandidate? _selectedCandidate(WalletRecoveryState recovery) {
    final selectable = recovery.candidates.where(
      (candidate) => candidate.canInspect,
    );
    if (selectable.isEmpty) return null;
    return selectable.firstWhere(
      (candidate) => candidate.path == _selectedCandidatePath,
      orElse: () => selectable.first,
    );
  }

  Future<void> _restart() async {
    if (_busy) return;
    _session?.dispose();
    setState(() {
      _session = null;
      _selectedCandidatePath = null;
      _authenticated = false;
      _editingAccount = null;
      _scanningAccount = null;
      _passcode = '';
      _newPasscode = null;
      _password.clear();
      _confirmation.clear();
      _mnemonic.clear();
      _passphrase.clear();
      _clearErrors();
    });
    await ref.read(appBootstrapRetryProvider)();
  }

  String _title(WalletRecoveryState recovery) {
    if (_session == null) {
      return recovery.candidates.isEmpty ? 'No wallet found' : 'Wallet found';
    }
    if (!_authenticated) {
      return _mobile ? 'Enter your passcode' : 'Enter your password';
    }
    if (!_session!.canReconnect) return 'Verify accounts';
    if (_needsNewCredential) {
      return _mobile ? 'Create passcode' : 'New password';
    }
    return 'Reconnect wallet';
  }

  String _subtitle(WalletRecoveryState recovery) {
    if (_session == null) {
      return recovery.candidates.isEmpty
          ? "Restore your backup copy to Vizor's data folder, then search again."
          : 'Vizor found a wallet from a previous setup. Verify it to keep using it.';
    }
    if (!_authenticated) {
      return _mobile
          ? 'Use the passcode you set for this wallet.'
          : 'Use the password you set for this wallet.';
    }
    if (!_session!.canReconnect) {
      return 'Add the missing recovery details for each account.';
    }
    if (_needsNewCredential) {
      return _mobile
          ? '6 digits'
          : 'Choose a password to protect this wallet on this device.';
    }
    return 'All accounts are verified. Your original wallet file stays unchanged.';
  }

  String _accountCount(int count) =>
      '$count ${count == 1 ? 'account' : 'accounts'}';

  String _networkLabel(String network) => switch (network.toLowerCase()) {
    'main' || 'mainnet' => 'Zcash mainnet',
    'test' || 'testnet' => 'Zcash testnet',
    'regtest' => 'Local regtest',
    _ => network,
  };
}

class _RecoveryHeader extends StatelessWidget {
  const _RecoveryHeader({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        ExcludeSemantics(
          child: Image.asset(
            'assets/illustrations/welcome_badge.png',
            width: 50,
            height: 50,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        Semantics(
          header: true,
          child: SizedBox(
            width: _mobile ? 320 : 348,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: AppTypography.displayMedium.copyWith(
                  color: colors.text.accent,
                  height: _mobile ? null : 48 / 45,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 348),
          child: Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.networkLabel,
    required this.accountCount,
    required this.selected,
    required this.showSelection,
    required this.onSelect,
  });

  final WalletRecoveryCandidate candidate;
  final String networkLabel;
  final String accountCount;
  final bool selected;
  final bool showSelection;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$networkLabel · $accountCount',
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Semantics(
                    label: 'Wallet file ${candidate.fileName}',
                    child: ExcludeSemantics(
                      child: Text(
                        candidate.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.codeSmall.copyWith(
                          color: colors.text.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (candidate.error != null)
              AppIcon(
                AppIcons.warningCircle,
                size: AppIconSize.medium,
                color: colors.icon.destructive,
              )
            else if (selected && showSelection)
              _RecoveryStatus(icon: AppIcons.checkCircle, label: 'Selected')
            else if (showSelection)
              AppButton(
                variant: AppButtonVariant.secondary,
                size: _mobile ? AppButtonSize.large : AppButtonSize.mediumLarge,
                onPressed: onSelect,
                child: const Text('Select'),
              ),
          ],
        ),
        if (candidate.error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _StageError(message: candidate.error!),
        ],
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.verified,
    this.child,
  });

  final rust_wallet.AccountInfo account;
  final bool verified;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              if (account.isHardware) ...[
                AppIcon(AppIcons.keystone, size: 20, color: colors.icon.accent),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      account.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    Text(
                      account.isHardware
                          ? 'Keystone account'
                          : 'Software account',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _RecoveryStatus(
                icon: verified
                    ? AppIcons.checkCircle
                    : account.isHardware
                    ? AppIcons.keystone
                    : AppIcons.key,
                label: verified
                    ? 'Verified'
                    : account.isHardware
                    ? 'Keystone needed'
                    : 'Phrase needed',
                positive: verified,
              ),
            ],
          ),
        ),
        if (child != null) ...[const SizedBox(height: AppSpacing.s), child!],
      ],
    );
  }
}

class _RecoveryStatus extends StatelessWidget {
  const _RecoveryStatus({
    required this.icon,
    required this.label,
    this.positive = false,
  });

  final String icon;
  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = positive ? colors.text.positiveStrong : colors.text.secondary;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: AppIconSize.medium, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletMeta extends StatelessWidget {
  const _WalletMeta({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

class _RecoveryFieldBlock extends StatelessWidget {
  const _RecoveryFieldBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 20), child: child);
  }
}

class _StageError extends StatelessWidget {
  const _StageError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMediumStrong.copyWith(
          color: context.colors.text.destructive,
        ),
      ),
    );
  }
}
