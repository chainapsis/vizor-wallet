import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class SettingsSeedPhraseScreen extends ConsumerStatefulWidget {
  const SettingsSeedPhraseScreen({this.privacyOverlayController, super.key});

  final SensitivePrivacyOverlayController? privacyOverlayController;

  @override
  ConsumerState<SettingsSeedPhraseScreen> createState() =>
      _SettingsSeedPhraseScreenState();
}

enum _SettingsSeedPhraseStage { password, reveal }

enum _SeedPhraseCopyTarget { phrase, birthdayDate, birthdayHeight }

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
    _birthdayHeight = null;
    _birthdayBlockTime = null;
    _isBirthdayHeightLoading = false;
    _isBirthdayDateLoading = false;
    _revealError = null;
    _copiedTarget = null;
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
          _passwordError = 'Incorrect password. Please try again.';
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

      final birthdayLoadGeneration = _birthdayLoadGeneration + 1;
      setState(() {
        _mnemonic = mnemonic;
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
        _loadBirthdayHeightForReveal(activeAccountUuid, birthdayLoadGeneration),
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

  bool _canApplyBirthdayLoad(String activeAccountUuid, int generation) {
    if (!mounted) return false;
    if (_birthdayLoadGeneration != generation) return false;
    if (_stage != _SettingsSeedPhraseStage.reveal || _mnemonic == null) {
      return false;
    }
    return !_activeAccountChanged(activeAccountUuid);
  }

  Future<void> _loadBirthdayHeightForReveal(
    String activeAccountUuid,
    int generation,
  ) async {
    try {
      final height = await _loadBirthdayHeight(activeAccountUuid);
      if (!_canApplyBirthdayLoad(activeAccountUuid, generation)) return;
      setState(() {
        _birthdayHeight = height;
        _isBirthdayHeightLoading = false;
        _isBirthdayDateLoading = true;
      });
      unawaited(
        _loadBirthdayDateForReveal(activeAccountUuid, generation, height),
      );
    } catch (e, st) {
      log('SettingsSeedPhraseScreen._loadBirthdayHeight: ERROR: $e\n$st');
      if (!_canApplyBirthdayLoad(activeAccountUuid, generation)) return;
      setState(() {
        _birthdayHeight = null;
        _birthdayBlockTime = null;
        _isBirthdayHeightLoading = false;
        _isBirthdayDateLoading = false;
      });
    }
  }

  Future<void> _loadBirthdayDateForReveal(
    String activeAccountUuid,
    int generation,
    int height,
  ) async {
    try {
      final blockTime = await _loadBirthdayBlockTime(
        height,
      ).timeout(const Duration(seconds: 10));
      if (!_canApplyBirthdayLoad(activeAccountUuid, generation)) return;
      setState(() {
        _birthdayBlockTime = blockTime > 0 ? blockTime : null;
        _isBirthdayDateLoading = false;
      });
    } catch (e, st) {
      log('SettingsSeedPhraseScreen._loadBirthdayDate: ERROR: $e\n$st');
      if (!_canApplyBirthdayLoad(activeAccountUuid, generation)) return;
      setState(() {
        _birthdayBlockTime = null;
        _isBirthdayDateLoading = false;
      });
    }
  }

  Future<int> _loadBirthdayHeight(String activeAccountUuid) async {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    final height = await rust_sync.getExportBirthdayHeight(
      dbPath: dbPath,
      network: endpoint.walletNetworkName,
      accountUuid: activeAccountUuid,
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
    await Clipboard.setData(ClipboardData(text: mnemonic));
    _markCopied(_SeedPhraseCopyTarget.phrase);
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
    ref.listen<String?>(
      accountProvider.select((state) => state.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next) return;
        _handleActiveAccountChanged();
      },
    );

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible:
              _stage == _SettingsSeedPhraseStage.reveal && _mnemonic != null,
          controller: widget.privacyOverlayController,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _SettingsSeedPhrasePane(
              onBeforeNavigateBack: () => _clearSensitiveState(),
              child: switch (_stage) {
                _SettingsSeedPhraseStage.password => _PasswordGateView(
                  passwordController: _passwordController,
                  messageText: _passwordError ?? _passwordPolicyMessage,
                  isSubmitting: _isSubmitting,
                  canSubmit: _canSubmit,
                  onChanged: _handlePasswordChanged,
                  onSubmit: _submitPassword,
                ),
                _SettingsSeedPhraseStage.reveal => _SeedPhraseRevealView(
                  mnemonic: _mnemonic,
                  birthdayHeight: _birthdayHeight,
                  birthdayBlockTime: _birthdayBlockTime,
                  birthdayHeightLoading: _isBirthdayHeightLoading,
                  birthdayDateLoading: _isBirthdayDateLoading,
                  errorText: _revealError,
                  phraseCopied: _copiedTarget == _SeedPhraseCopyTarget.phrase,
                  birthdayDateCopied:
                      _copiedTarget == _SeedPhraseCopyTarget.birthdayDate,
                  birthdayHeightCopied:
                      _copiedTarget == _SeedPhraseCopyTarget.birthdayHeight,
                  onCopyPressed: _copyMnemonic,
                  onCopyBirthdayDatePressed: _copyBirthdayDate,
                  onCopyBirthdayHeightPressed: _copyBirthdayHeight,
                ),
              },
            ),
          ),
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
          Align(
            alignment: Alignment.centerLeft,
            child: AppRouteBackLink(onBeforeNavigate: onBeforeNavigateBack),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(child: child),
        ],
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
    required this.birthdayHeight,
    required this.birthdayBlockTime,
    required this.birthdayHeightLoading,
    required this.birthdayDateLoading,
    required this.errorText,
    required this.phraseCopied,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyPressed,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final String? mnemonic;
  final int? birthdayHeight;
  final int? birthdayBlockTime;
  final bool birthdayHeightLoading;
  final bool birthdayDateLoading;
  final String? errorText;
  final bool phraseCopied;
  final bool birthdayDateCopied;
  final bool birthdayHeightCopied;
  final Future<void> Function() onCopyPressed;
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
            'Secret Passphrase',
            textAlign: TextAlign.center,
            style: AppTypography.displaySmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppDecorativeDivider(width: 256),
          const SizedBox(height: AppSpacing.md),
          if (errorText == null && mnemonic != null)
            _SeedPhraseCard(
              mnemonic: mnemonic!,
              birthdayHeight: birthdayHeight,
              birthdayBlockTime: birthdayBlockTime,
              birthdayHeightLoading: birthdayHeightLoading,
              birthdayDateLoading: birthdayDateLoading,
              phraseCopied: phraseCopied,
              birthdayDateCopied: birthdayDateCopied,
              birthdayHeightCopied: birthdayHeightCopied,
              onCopyPressed: onCopyPressed,
              onCopyBirthdayDatePressed: onCopyBirthdayDatePressed,
              onCopyBirthdayHeightPressed: onCopyBirthdayHeightPressed,
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

const _seedPhraseCardWidth = 537.0;
const _seedPhraseOuterRadius = 28.0;
const _seedPhraseInnerRadius = AppRadii.large;

class _SeedPhraseCard extends StatelessWidget {
  const _SeedPhraseCard({
    required this.mnemonic,
    required this.birthdayHeight,
    required this.birthdayBlockTime,
    required this.birthdayHeightLoading,
    required this.birthdayDateLoading,
    required this.phraseCopied,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyPressed,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final String mnemonic;
  final int? birthdayHeight;
  final int? birthdayBlockTime;
  final bool birthdayHeightLoading;
  final bool birthdayDateLoading;
  final bool phraseCopied;
  final bool birthdayDateCopied;
  final bool birthdayHeightCopied;
  final Future<void> Function() onCopyPressed;
  final Future<void> Function() onCopyBirthdayDatePressed;
  final Future<void> Function() onCopyBirthdayHeightPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final words = mnemonic.split(' ');
    final blockTime = birthdayBlockTime;
    final birthdayDate = blockTime == null || blockTime <= 0
        ? '-'
        : _formatBirthdayDate(blockTime);
    final birthdayHeightText = birthdayHeight == null || birthdayHeight! <= 0
        ? '-'
        : birthdayHeight.toString();

    return SizedBox(
      width: _seedPhraseCardWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_seedPhraseOuterRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SeedWordsCard(
                  words: words,
                  isDark: isDark,
                  phraseCopied: phraseCopied,
                  onCopyPressed: onCopyPressed,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      _SeedBirthdayRow(
                        icon: AppIcons.calendar,
                        label: 'Birthday date',
                        value: birthdayDate,
                        loading: birthdayDateLoading,
                        copied: birthdayDateCopied,
                        copyLabel: 'Copy date',
                        onCopyPressed:
                            birthdayDateLoading ||
                                blockTime == null ||
                                blockTime <= 0
                            ? null
                            : () {
                                onCopyBirthdayDatePressed();
                              },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s,
                          vertical: AppSpacing.xs,
                        ),
                        child: Container(
                          height: 1,
                          color: colors.border.regular,
                        ),
                      ),
                      _SeedBirthdayRow(
                        icon: AppIcons.block,
                        label: 'Birthday block height',
                        value: birthdayHeightText,
                        loading: birthdayHeightLoading,
                        copied: birthdayHeightCopied,
                        copyLabel: 'Copy height',
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeedWordsCard extends StatelessWidget {
  const _SeedWordsCard({
    required this.words,
    required this.isDark,
    required this.phraseCopied,
    required this.onCopyPressed,
  });

  final List<String> words;
  final bool isDark;
  final bool phraseCopied;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(_seedPhraseInnerRadius),
            boxShadow: isDark
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0xFFE1E1E1),
                      offset: Offset(0, 2),
                      blurRadius: 2,
                    ),
                    BoxShadow(
                      color: Color(0xFFE1E1E1),
                      offset: Offset(0, 10),
                      blurRadius: 15,
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_seedPhraseInnerRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
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
                  const SizedBox(height: AppSpacing.md),
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
        ),
        if (isDark)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_seedPhraseInnerRadius),
                    side: BorderSide(
                      color: colors.border.subtle,
                      width: 1,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
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
            size: AppButtonSize.medium,
            minWidth: 96,
            iconGap: 0,
            trailing: AppIcon(phraseCopied ? AppIcons.check : AppIcons.copy),
            child: Text(phraseCopied ? 'Copied' : 'Copy Phrase'),
          ),
        ),
      ],
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
    required this.copyLabel,
    required this.onCopyPressed,
  });

  final String icon;
  final String label;
  final String value;
  final bool loading;
  final bool copied;
  final String copyLabel;
  final VoidCallback? onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hideCopyButton = onCopyPressed == null;

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Row(
                children: [
                  AppIcon(
                    icon,
                    size: AppIconSize.medium,
                    color: colors.icon.muted,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: loading
                        ? _BirthdayLoadingValue(label: label)
                        : Text(
                            '$label: $value',
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.primary,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            ignoring: hideCopyButton,
            child: Opacity(
              opacity: hideCopyButton ? 0 : 1,
              child: AppButton(
                onPressed: onCopyPressed,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.medium,
                minWidth: 96,
                iconGap: 0,
                trailing: AppIcon(copied ? AppIcons.check : AppIcons.copy),
                child: Text(copied ? 'Copied' : copyLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BirthdayLoadingValue extends StatelessWidget {
  const _BirthdayLoadingValue({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.labelLarge.copyWith(color: colors.text.primary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '$label: ',
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        SizedBox(
          width: 16,
          height: 18,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppIcon(
              AppIcons.loader,
              size: AppIconSize.medium,
              color: colors.icon.muted,
            ),
          ),
        ),
      ],
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

    return SizedBox(
      width: _seedPhraseCardWidth,
      height: 348,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_seedPhraseOuterRadius),
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
