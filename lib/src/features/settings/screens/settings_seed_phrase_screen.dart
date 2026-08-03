import 'dart:async';

import 'package:flutter/services.dart';
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
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';

class SettingsSeedPhraseScreen extends ConsumerStatefulWidget {
  const SettingsSeedPhraseScreen({
    this.accountUuid,
    this.privacyOverlayController,
    super.key,
  });

  final String? accountUuid;
  final SensitivePrivacyOverlayController? privacyOverlayController;

  @override
  ConsumerState<SettingsSeedPhraseScreen> createState() =>
      _SettingsSeedPhraseScreenState();
}

/// Deterministic reveal-state fixture used by Widgetbook and Figma comparison.
///
/// This is intentionally a separate widget rather than an initial state on
/// [SettingsSeedPhraseScreen], so production navigation cannot bypass the
/// password confirmation gate.
class SettingsSeedPhraseRevealPreview extends StatelessWidget {
  const SettingsSeedPhraseRevealPreview({
    required this.mnemonic,
    this.bip39Passphrase,
    this.birthdayHeight = 3428019,
    this.birthdayBlockTime = 1785196800,
    super.key,
  });

  final String mnemonic;
  final String? bip39Passphrase;
  final int birthdayHeight;
  final int birthdayBlockTime;

  @override
  Widget build(BuildContext context) {
    return AppDesktopBackdropShell(
      background: const SettingsPaneBackdrop(art: SettingsBackdropArt.vault),
      sidebar: const AppMainSidebar(),
      pane: _SettingsSeedPhrasePane(
        onBeforeNavigateBack: () {},
        child: _SeedPhraseRevealView(
          mnemonic: mnemonic,
          bip39Passphrase: bip39Passphrase,
          birthdayHeight: birthdayHeight,
          birthdayBlockTime: birthdayBlockTime,
          birthdayHeightLoading: false,
          birthdayDateLoading: false,
          errorText: null,
          phraseCopied: false,
          bip39PassphraseCopied: false,
          birthdayDateCopied: false,
          birthdayHeightCopied: false,
          onCopyPressed: _noopPreviewCopy,
          onCopyBip39PassphrasePressed: _noopPreviewCopy,
          onCopyBirthdayDatePressed: _noopPreviewCopy,
          onCopyBirthdayHeightPressed: _noopPreviewCopy,
        ),
      ),
    );
  }
}

Future<void> _noopPreviewCopy() async {}

enum _SettingsSeedPhraseStage { password, reveal }

enum _SeedPhraseCopyTarget {
  phrase,
  bip39Passphrase,
  birthdayDate,
  birthdayHeight,
}

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
  String? _bip39Passphrase;
  int? _birthdayHeight;
  int? _birthdayBlockTime;
  bool _isBirthdayHeightLoading = false;
  bool _isBirthdayDateLoading = false;
  int _birthdayLoadGeneration = 0;
  String? _revealError;
  _SeedPhraseCopyTarget? _copiedTarget;
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
    _birthdayLoadGeneration++;
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _SettingsSeedPhraseStage.password;
    _passwordError = passwordError;
    _mnemonic = null;
    _bip39Passphrase = null;
    _birthdayHeight = null;
    _birthdayBlockTime = null;
    _isBirthdayHeightLoading = false;
    _isBirthdayDateLoading = false;
    _revealError = null;
    _copiedTarget = null;
  }

  void _handleTargetAccountChanged() {
    if (_stage == _SettingsSeedPhraseStage.password &&
        !_isSubmitting &&
        _mnemonic == null) {
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
        throw const _SeedPhraseUnavailableException(
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

      if (targetAccount.isHardware) {
        throw const _SeedPhraseUnavailableException(
          'Secret passphrase is not available for hardware accounts.',
        );
      }

      final secret = await ref
          .read(accountProvider.notifier)
          .getSoftwareWalletSecretForAccount(targetAccountUuid);
      final mnemonic = secret?.mnemonic;
      if (mnemonic == null || mnemonic.isEmpty) {
        throw const _SeedPhraseUnavailableException(
          'Secret passphrase is not available for this account.',
        );
      }

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

      final birthdayLoadGeneration = _birthdayLoadGeneration + 1;
      setState(() {
        _mnemonic = mnemonic;
        _bip39Passphrase = secret!.hasBip39Passphrase
            ? secret.bip39Passphrase
            : null;
        _birthdayHeight = null;
        _birthdayBlockTime = null;
        _isBirthdayHeightLoading = true;
        _isBirthdayDateLoading = true;
        _birthdayLoadGeneration = birthdayLoadGeneration;
        _stage = _SettingsSeedPhraseStage.reveal;
        _isSubmitting = false;
        _copiedTarget = null;
      });
      unawaited(
        _loadBirthdayHeightForReveal(targetAccountUuid, birthdayLoadGeneration),
      );
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

  bool _canApplyBirthdayLoad(String targetAccountUuid, int generation) {
    if (!mounted) return false;
    if (_birthdayLoadGeneration != generation) return false;
    if (_stage != _SettingsSeedPhraseStage.reveal || _mnemonic == null) {
      return false;
    }
    return !_targetAccountChanged(targetAccountUuid);
  }

  Future<void> _loadBirthdayHeightForReveal(
    String targetAccountUuid,
    int generation,
  ) async {
    try {
      final height = await _loadBirthdayHeight(targetAccountUuid);
      if (!_canApplyBirthdayLoad(targetAccountUuid, generation)) return;
      setState(() {
        _birthdayHeight = height;
        _isBirthdayHeightLoading = false;
        _isBirthdayDateLoading = true;
      });
      unawaited(
        _loadBirthdayDateForReveal(targetAccountUuid, generation, height),
      );
    } catch (e, st) {
      log('SettingsSeedPhraseScreen._loadBirthdayHeight: ERROR: $e\n$st');
      if (!_canApplyBirthdayLoad(targetAccountUuid, generation)) return;
      setState(() {
        _birthdayHeight = null;
        _birthdayBlockTime = null;
        _isBirthdayHeightLoading = false;
        _isBirthdayDateLoading = false;
      });
    }
  }

  Future<void> _loadBirthdayDateForReveal(
    String targetAccountUuid,
    int generation,
    int height,
  ) async {
    try {
      final blockTime = await _loadBirthdayBlockTime(
        height,
      ).timeout(const Duration(seconds: 10));
      if (!_canApplyBirthdayLoad(targetAccountUuid, generation)) return;
      setState(() {
        _birthdayBlockTime = blockTime > 0 ? blockTime : null;
        _isBirthdayDateLoading = false;
      });
    } catch (e, st) {
      log('SettingsSeedPhraseScreen._loadBirthdayDate: ERROR: $e\n$st');
      if (!_canApplyBirthdayLoad(targetAccountUuid, generation)) return;
      setState(() {
        _birthdayBlockTime = null;
        _isBirthdayDateLoading = false;
      });
    }
  }

  Future<int> _loadBirthdayHeight(String targetAccountUuid) async {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    final height = await rust_sync.getExportBirthdayHeight(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: targetAccountUuid,
    );
    return height.toInt();
  }

  Future<int> _loadBirthdayBlockTime(int height) async {
    final blockTime = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback(
          operation: 'birthday block time',
          action: (endpoint) => rust_sync.getBlockTime(
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            height: BigInt.from(height),
          ),
        );
    return blockTime.toInt();
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || mnemonic.isEmpty) return;
    await SensitiveClipboard.copyText(mnemonic);
    _markCopied(_SeedPhraseCopyTarget.phrase);
  }

  Future<void> _copyBip39Passphrase() async {
    final passphrase = _bip39Passphrase;
    if (passphrase == null || passphrase.isEmpty) return;
    await SensitiveClipboard.copyText(passphrase);
    _markCopied(_SeedPhraseCopyTarget.bip39Passphrase);
  }

  Future<void> _copyBirthdayDate() async {
    final blockTime = _birthdayBlockTime;
    if (blockTime == null || blockTime <= 0) return;
    await Clipboard.setData(
      ClipboardData(text: _formatBirthdayDate(blockTime)),
    );
    _markCopied(_SeedPhraseCopyTarget.birthdayDate);
  }

  Future<void> _copyBirthdayHeight() async {
    final height = _birthdayHeight;
    if (height == null || height <= 0) return;
    await Clipboard.setData(ClipboardData(text: height.toString()));
    _markCopied(_SeedPhraseCopyTarget.birthdayHeight);
  }

  void _markCopied(_SeedPhraseCopyTarget target) {
    if (!mounted) return;
    _copyResetTimer?.cancel();
    setState(() {
      _copiedTarget = target;
    });
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copiedTarget = null;
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
      background: SettingsPaneBackdrop(
        art: _stage == _SettingsSeedPhraseStage.reveal
            ? SettingsBackdropArt.vault
            : SettingsBackdropArt.castle,
      ),
      sidebar: const AppMainSidebar(),
      pane: SensitivePrivacyOverlay(
        sensitiveContentVisible:
            _stage == _SettingsSeedPhraseStage.reveal && _mnemonic != null,
        controller: widget.privacyOverlayController,
        child: _SettingsSeedPhrasePane(
          onBeforeNavigateBack: () => _clearSensitiveState(),
          child: switch (_stage) {
            _SettingsSeedPhraseStage.password => Center(
              child: ConfirmAccessCard(
                subtitle: 'To view the secret passphrase.',
                controller: _passwordController,
                errorText: _passwordError ?? _passwordPolicyMessage,
                isSubmitting: _isSubmitting,
                canSubmit: _canSubmit,
                onChanged: _handlePasswordChanged,
                onSubmit: _submitPassword,
              ),
            ),
            _SettingsSeedPhraseStage.reveal => _SeedPhraseRevealView(
              mnemonic: _mnemonic,
              bip39Passphrase: _bip39Passphrase,
              birthdayHeight: _birthdayHeight,
              birthdayBlockTime: _birthdayBlockTime,
              birthdayHeightLoading: _isBirthdayHeightLoading,
              birthdayDateLoading: _isBirthdayDateLoading,
              errorText: _revealError,
              phraseCopied: _copiedTarget == _SeedPhraseCopyTarget.phrase,
              bip39PassphraseCopied:
                  _copiedTarget == _SeedPhraseCopyTarget.bip39Passphrase,
              birthdayDateCopied:
                  _copiedTarget == _SeedPhraseCopyTarget.birthdayDate,
              birthdayHeightCopied:
                  _copiedTarget == _SeedPhraseCopyTarget.birthdayHeight,
              onCopyPressed: _copyMnemonic,
              onCopyBip39PassphrasePressed: _copyBip39Passphrase,
              onCopyBirthdayDatePressed: _copyBirthdayDate,
              onCopyBirthdayHeightPressed: _copyBirthdayHeight,
            ),
          },
        ),
      ),
    );
  }
}

class _SettingsSeedPhrasePane extends StatelessWidget {
  const _SettingsSeedPhrasePane({
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

const _seedPhraseCardWidth = 396.0;

List<BoxShadow> _seedCardShadows(Color color) => [
  BoxShadow(color: color, blurRadius: 0.5),
  BoxShadow(color: color, offset: const Offset(0, 2), blurRadius: 2),
  BoxShadow(color: color, offset: const Offset(0, 1), blurRadius: 1),
  BoxShadow(color: color, blurRadius: 0.5),
];

class _SeedPhraseRevealView extends StatelessWidget {
  const _SeedPhraseRevealView({
    required this.mnemonic,
    required this.bip39Passphrase,
    required this.birthdayHeight,
    required this.birthdayBlockTime,
    required this.birthdayHeightLoading,
    required this.birthdayDateLoading,
    required this.errorText,
    required this.phraseCopied,
    required this.bip39PassphraseCopied,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyPressed,
    required this.onCopyBip39PassphrasePressed,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final String? mnemonic;
  final String? bip39Passphrase;
  final int? birthdayHeight;
  final int? birthdayBlockTime;
  final bool birthdayHeightLoading;
  final bool birthdayDateLoading;
  final String? errorText;
  final bool phraseCopied;
  final bool bip39PassphraseCopied;
  final bool birthdayDateCopied;
  final bool birthdayHeightCopied;
  final Future<void> Function() onCopyPressed;
  final Future<void> Function() onCopyBip39PassphrasePressed;
  final Future<void> Function() onCopyBirthdayDatePressed;
  final Future<void> Function() onCopyBirthdayHeightPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Secret passphrase',
            textAlign: TextAlign.center,
            style: AppTypography.headlineLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'This is the master key to your wallet.\n'
            "Don't share it with anyone.",
            textAlign: TextAlign.center,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (errorText == null && mnemonic != null) ...[
            _SeedWordsCard(
              words: mnemonic!.split(' '),
              bip39Passphrase: bip39Passphrase,
              phraseCopied: phraseCopied,
              bip39PassphraseCopied: bip39PassphraseCopied,
              onCopyPressed: onCopyPressed,
              onCopyBip39PassphrasePressed: onCopyBip39PassphrasePressed,
            ),
            const SizedBox(height: AppSpacing.s),
            _SeedBirthdayCard(
              birthdayHeight: birthdayHeight,
              birthdayBlockTime: birthdayBlockTime,
              birthdayHeightLoading: birthdayHeightLoading,
              birthdayDateLoading: birthdayDateLoading,
              birthdayDateCopied: birthdayDateCopied,
              birthdayHeightCopied: birthdayHeightCopied,
              onCopyBirthdayDatePressed: onCopyBirthdayDatePressed,
              onCopyBirthdayHeightPressed: onCopyBirthdayHeightPressed,
            ),
          ] else
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

class _SeedWordsCard extends StatelessWidget {
  const _SeedWordsCard({
    required this.words,
    required this.bip39Passphrase,
    required this.phraseCopied,
    required this.bip39PassphraseCopied,
    required this.onCopyPressed,
    required this.onCopyBip39PassphrasePressed,
  });

  final List<String> words;
  final String? bip39Passphrase;
  final bool phraseCopied;
  final bool bip39PassphraseCopied;
  final Future<void> Function() onCopyPressed;
  final Future<void> Function() onCopyBip39PassphrasePressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    final passphrase = bip39Passphrase;

    return Container(
      width: _seedPhraseCardWidth,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _seedCardShadows(colors.shadows.subtle),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(
                      AppIcons.key,
                      size: AppIconSize.medium,
                      color: cardTextColor,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Secret passphrase',
                      style: AppTypography.bodyLarge.copyWith(
                        color: cardTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    for (var i = 0; i < words.length; i++)
                      _SeedWordChip(
                        key: ValueKey('settings_seed_phrase_word_${i + 1}'),
                        index: i + 1,
                        word: words[i],
                        textColor: cardTextColor,
                      ),
                  ],
                ),
                if (passphrase != null && passphrase.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    height: 1,
                    color: cardTextColor.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  _Bip39PassphraseRow(
                    passphrase: passphrase,
                    copied: bip39PassphraseCopied,
                    textColor: cardTextColor,
                    onCopyPressed: onCopyBip39PassphrasePressed,
                  ),
                ],
              ],
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
              enabledBackgroundColor: colors.background.raised,
              pressedBackgroundColor: colors.background.overlay,
              enabledLabelColor: colors.text.accent,
              pressedLabelColor: colors.text.accent,
              trailing: AppIcon(phraseCopied ? AppIcons.check : AppIcons.copy),
              child: Text(phraseCopied ? 'Copied' : 'Copy'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeedWordChip extends StatelessWidget {
  const _SeedWordChip({
    required this.index,
    required this.word,
    required this.textColor,
    super.key,
  });

  final int index;
  final String word;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          children: [
            Text(
              index.toString().padLeft(2, '0'),
              style: AppTypography.codeSmall.copyWith(
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                word,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelLarge.copyWith(color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bip39PassphraseRow extends StatelessWidget {
  const _Bip39PassphraseRow({
    required this.passphrase,
    required this.copied,
    required this.textColor,
    required this.onCopyPressed,
  });

  final String passphrase;
  final bool copied;
  final Color textColor;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'BIP39 Passphrase',
          style: AppTypography.labelLarge.copyWith(color: textColor),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            _compactPassphrase(passphrase),
            key: const ValueKey('settings_bip39_passphrase_value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTypography.labelLarge.copyWith(color: textColor),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Semantics(
          button: true,
          label: copied ? 'BIP39 passphrase copied' : 'Copy BIP39 passphrase',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onCopyPressed(),
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: AppIcon(
                  copied ? AppIcons.check : AppIcons.copy,
                  size: AppIconSize.medium,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _compactPassphrase(String value) {
  final characters = value.characters;
  if (characters.length <= 24) return value;
  return '${characters.take(10)} ... ${characters.skip(characters.length - 10)}';
}

class _SeedBirthdayCard extends StatelessWidget {
  const _SeedBirthdayCard({
    required this.birthdayHeight,
    required this.birthdayBlockTime,
    required this.birthdayHeightLoading,
    required this.birthdayDateLoading,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final int? birthdayHeight;
  final int? birthdayBlockTime;
  final bool birthdayHeightLoading;
  final bool birthdayDateLoading;
  final bool birthdayDateCopied;
  final bool birthdayHeightCopied;
  final Future<void> Function() onCopyBirthdayDatePressed;
  final Future<void> Function() onCopyBirthdayHeightPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final blockTime = birthdayBlockTime;
    final birthdayDate = blockTime == null || blockTime <= 0
        ? '-'
        : _formatBirthdayDate(blockTime);
    final birthdayHeightText = birthdayHeight == null || birthdayHeight! <= 0
        ? '-'
        : birthdayHeight.toString();

    return Container(
      width: _seedPhraseCardWidth,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _seedCardShadows(colors.shadows.subtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SeedBirthdayRow(
            icon: AppIcons.calendar,
            label: 'Birthday date',
            value: birthdayDate,
            loading: birthdayDateLoading,
            copied: birthdayDateCopied,
            onCopyPressed:
                birthdayDateLoading || blockTime == null || blockTime <= 0
                ? null
                : () {
                    onCopyBirthdayDatePressed();
                  },
          ),
          const SizedBox(height: AppSpacing.s),
          _SeedBirthdayRow(
            icon: AppIcons.block,
            label: 'Birthday block height',
            value: birthdayHeightText,
            loading: birthdayHeightLoading,
            copied: birthdayHeightCopied,
            onCopyPressed:
                birthdayHeightLoading ||
                    birthdayHeight == null ||
                    birthdayHeight! <= 0
                ? null
                : () {
                    onCopyBirthdayHeightPressed();
                  },
          ),
        ],
      ),
    );
  }
}

class _SeedBirthdayRow extends StatelessWidget {
  const _SeedBirthdayRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.loading,
    required this.copied,
    required this.onCopyPressed,
  });

  final String icon;
  final String label;
  final String value;
  final bool loading;
  final bool copied;
  final VoidCallback? onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          AppIcon(icon, size: AppIconSize.medium, color: colors.icon.muted),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (loading)
            AppIcon(
              AppIcons.loader,
              size: AppIconSize.medium,
              color: colors.icon.muted,
            )
          else ...[
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            if (onCopyPressed != null) ...[
              const SizedBox(width: AppSpacing.xxs),
              Semantics(
                button: true,
                label: copied ? '$label copied' : 'Copy $label',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCopyPressed,
                  child: SizedBox.square(
                    dimension: 18,
                    child: Center(
                      child: AppIcon(
                        copied ? AppIcons.check : AppIcons.copy,
                        size: AppIconSize.medium,
                        color: colors.icon.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _formatBirthdayDate(int blockTime) {
  if (blockTime <= 0) return '-';
  final value = DateTime.fromMillisecondsSinceEpoch(
    blockTime * 1000,
    isUtc: true,
  ).toLocal();
  const months = <String>[
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month]} ${value.day}, ${value.year}';
}

class _SeedPhraseErrorCard extends StatelessWidget {
  const _SeedPhraseErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: _seedPhraseCardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _seedCardShadows(colors.shadows.subtle),
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
