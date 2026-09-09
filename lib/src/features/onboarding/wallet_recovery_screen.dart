import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_bootstrap.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/security/password_policy.dart';
import '../../core/security/software_wallet_secret.dart';
import '../../core/storage/wallet_recovery.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/password_text_field.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/api/wallet.dart' as rust_wallet;
import '../../services/qr_scanner.dart';
import '../keystone/widgets/keystone_qr_scanner_card.dart';
import 'mobile/passcode_widgets.dart';

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
  String? _editingAccount;
  String? _scanningAccount;
  String? _error;
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
      _authenticated = !_recovery.isPasswordConfigured;
      _error = null;
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
      setState(() => _error = validateRequiredWalletPassword(password));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final valid = await _session!.unlockExistingSecrets(password);
      if (!mounted) return;
      setState(() {
        _authenticated = valid;
        if (!valid) {
          _error = _mobile
              ? 'Incorrect passcode. Try again.'
              : 'Incorrect password. Try again.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
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
      _error = null;
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
          _error =
              'This recovery phrase and passphrase do not match the selected account.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
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
      _error = null;
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
          _error =
              'This Keystone QR does not match the selected wallet account.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Scan the Zcash account QR from your Keystone again.',
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
        setState(() => _error = policy);
        return;
      }
      if (!_mobile && newPassword != _confirmation.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
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
          () => _error =
              'The wallet could not be reconnected. Your original file is still in place. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterDigit(String digit) {
    if (_busy || _passcode.length >= 6) return;
    setState(() => _passcode += digit);
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
        _error = 'Passcodes do not match. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(appBootstrapProvider).walletRecovery;
    if (recovery == null) return const SizedBox.shrink();
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.ground,
      body: SafeArea(
        child: ColoredBox(
          color: colors.background.ground,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Recover your wallet',
                          style: AppTypography.headlineLarge.copyWith(
                            color: colors.text.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Vizor found signs of an existing wallet. Verify your recovery material to reconnect it.',
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_session == null)
                          ..._candidateList(recovery)
                        else
                          ..._selectedWallet(),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          variant: AppButtonVariant.ghost,
                          onPressed: _busy
                              ? null
                              : () async {
                                  _session?.dispose();
                                  _session = null;
                                  await ref.read(appBootstrapRetryProvider)();
                                },
                          child: const Text('Search again'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _candidateList(WalletRecoveryState recovery) => [
    if (recovery.candidates.isEmpty)
      Text(
        'No wallet file was found in this app’s data folder. Restore a preserved copy of your wallet file to that folder, then search again.',
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    for (final candidate in recovery.candidates) ...[
      Text(
        candidate.fileName,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.primary,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      if (candidate.error != null)
        Text(
          candidate.error!,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        )
      else
        AppButton(
          onPressed: _busy ? null : () => _select(candidate),
          variant: AppButtonVariant.secondary,
          child: const Text('Recover this wallet'),
        ),
      const SizedBox(height: AppSpacing.md),
    ],
  ];

  List<Widget> _selectedWallet() {
    final session = _session!;
    if (!_authenticated) {
      return [
        Text(
          _mobile
              ? 'Enter your existing passcode.'
              : 'Enter your existing password.',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_mobile)
          ..._passcodeEntry()
        else ...[
          PasswordTextField(
            label: 'Password',
            controller: _password,
            enabled: !_busy,
            onSubmitted: (_) => _unlock(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            onPressed: _busy ? null : _unlock,
            child: Text(_busy ? 'Checking' : 'Continue'),
          ),
        ],
      ];
    }
    return [
      for (final entry in session.candidate.accounts.indexed) ...[
        Text(
          'Account ${entry.$1 + 1}',
          style: AppTypography.headlineSmall.copyWith(
            color: context.colors.text.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          session.isVerified(entry.$2.uuid)
              ? 'Recovery material verified'
              : entry.$2.isHardware
              ? 'Reconnect your hardware wallet to verify this account.'
              : 'Recovery phrase needed',
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if (!session.isVerified(entry.$2.uuid)) ..._accountRecovery(entry.$2),
        const SizedBox(height: AppSpacing.md),
      ],
      if (session.canReconnect) ...[
        if (!_recovery.isPasswordConfigured &&
            !session.hasEstablishedPassword) ...[
          Text(
            _mobile
                ? (_newPasscode == null
                      ? 'Set a new passcode'
                      : 'Confirm your passcode')
                : 'Set a new password',
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_mobile)
            ..._passcodeEntry()
          else ...[
            PasswordTextField(
              label: 'New password',
              controller: _password,
              enabled: !_busy,
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordTextField(
              label: 'Confirm password',
              controller: _confirmation,
              enabled: !_busy,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
        if (!_mobile ||
            _recovery.isPasswordConfigured ||
            session.hasEstablishedPassword)
          AppButton(
            onPressed: _busy ? null : _reconnect,
            child: Text(_busy ? 'Reconnecting' : 'Reconnect wallet'),
          ),
      ],
    ];
  }

  List<Widget> _accountRecovery(rust_wallet.AccountInfo account) => [
    const SizedBox(height: AppSpacing.sm),
    if (account.isHardware && _scanningAccount != account.uuid)
      AppButton(
        variant: AppButtonVariant.secondary,
        onPressed: _busy
            ? null
            : () => setState(() => _scanningAccount = account.uuid),
        child: const Text('Scan Keystone QR'),
      )
    else if (account.isHardware)
      KeystoneQrScannerCard(
        expectedUrType: 'zcash-accounts',
        decoding: _busy,
        error: _error,
        onProgress: (_) {},
        onDecodeError: (_) => setState(
          () => _error = 'Scan the Zcash account QR from your Keystone.',
        ),
        onComplete: _verifyKeystone,
        unavailableMessage:
            'Connect a camera to scan your Keystone account QR.',
      )
    else if (_editingAccount != account.uuid)
      AppButton(
        variant: AppButtonVariant.secondary,
        onPressed: _busy
            ? null
            : () {
                _mnemonic.clear();
                _passphrase.clear();
                setState(() => _editingAccount = account.uuid);
              },
        child: const Text('Enter recovery phrase'),
      )
    else ...[
      AppTextField(
        label: 'Recovery phrase',
        controller: _mnemonic,
        minLines: 3,
        maxLines: 6,
        enabled: !_busy,
        autocorrect: false,
        enableSuggestions: false,
      ),
      const SizedBox(height: AppSpacing.sm),
      PasswordTextField(
        label: 'BIP39 passphrase (optional)',
        controller: _passphrase,
        enabled: !_busy,
      ),
      const SizedBox(height: AppSpacing.sm),
      AppButton(
        onPressed: _busy ? null : () => _verifyPhrase(account.uuid),
        child: Text(_busy ? 'Verifying' : 'Verify recovery phrase'),
      ),
    ],
  ];

  List<Widget> _passcodeEntry() => [
    PasscodeDots(length: 6, filled: _passcode.length),
    const SizedBox(height: AppSpacing.sm),
    PasscodeNumpad(
      onDigit: (digit) => _enterDigit('$digit'),
      enabled: !_busy,
      canDelete: _passcode.isNotEmpty && !_busy,
      onBackspace: () {
        if (!_busy && _passcode.isNotEmpty) {
          setState(
            () => _passcode = _passcode.substring(0, _passcode.length - 1),
          );
        }
      },
    ),
  ];
}
