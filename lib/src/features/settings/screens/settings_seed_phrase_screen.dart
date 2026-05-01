import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
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
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class SettingsSeedPhraseScreen extends ConsumerStatefulWidget {
  const SettingsSeedPhraseScreen({super.key});

  @override
  ConsumerState<SettingsSeedPhraseScreen> createState() =>
      _SettingsSeedPhraseScreenState();
}

enum _SettingsSeedPhraseStage { password, reveal }

enum _SeedPhraseCopyTarget { phrase, birthdayDate, birthdayHeight }

class _SeedBirthdayInfo {
  const _SeedBirthdayInfo({required this.blockHeight, required this.blockTime});

  final int blockHeight;
  final int blockTime;
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
  _SeedBirthdayInfo? _birthdayInfo;
  String? _birthdayError;
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
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _SettingsSeedPhraseStage.password;
    _passwordError = passwordError;
    _mnemonic = null;
    _birthdayInfo = null;
    _birthdayError = null;
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

      final mnemonic = await ref
          .read(accountProvider.notifier)
          .getMnemonicForAccount(activeAccountUuid);
      if (mnemonic == null || mnemonic.isEmpty) {
        throw const _SeedPhraseUnavailableException(
          'Secret passphrase is not available for this account.',
        );
      }

      _SeedBirthdayInfo? birthdayInfo;
      String? birthdayError;
      try {
        birthdayInfo = await _loadBirthdayInfo(activeAccountUuid);
      } catch (e, st) {
        log('SettingsSeedPhraseScreen._loadBirthdayInfo: ERROR: $e\n$st');
        birthdayError = "Couldn't load birthday info.";
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
        _birthdayInfo = birthdayInfo;
        _birthdayError = birthdayError;
        _stage = _SettingsSeedPhraseStage.reveal;
        _isSubmitting = false;
        _copiedTarget = null;
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

  Future<_SeedBirthdayInfo> _loadBirthdayInfo(String activeAccountUuid) async {
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    final info = await rust_sync.getExportBirthdayInfo(
      dbPath: dbPath,
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      accountUuid: activeAccountUuid,
    );
    return _SeedBirthdayInfo(
      blockHeight: info.blockHeight.toInt(),
      blockTime: info.blockTime.toInt(),
    );
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || mnemonic.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: mnemonic));
    _markCopied(_SeedPhraseCopyTarget.phrase);
  }

  Future<void> _copyBirthdayDate() async {
    final info = _birthdayInfo;
    if (info == null || info.blockTime <= 0) return;
    await Clipboard.setData(
      ClipboardData(text: _formatBirthdayDate(info.blockTime)),
    );
    _markCopied(_SeedPhraseCopyTarget.birthdayDate);
  }

  Future<void> _copyBirthdayHeight() async {
    final info = _birthdayInfo;
    if (info == null || info.blockHeight <= 0) return;
    await Clipboard.setData(ClipboardData(text: info.blockHeight.toString()));
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
              birthdayInfo: _birthdayInfo,
              birthdayError: _birthdayError,
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
    required this.birthdayInfo,
    required this.birthdayError,
    required this.errorText,
    required this.phraseCopied,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyPressed,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final String? mnemonic;
  final _SeedBirthdayInfo? birthdayInfo;
  final String? birthdayError;
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
              birthdayInfo: birthdayInfo,
              birthdayError: birthdayError,
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

class _SeedPhraseCard extends StatelessWidget {
  const _SeedPhraseCard({
    required this.mnemonic,
    required this.birthdayInfo,
    required this.birthdayError,
    required this.phraseCopied,
    required this.birthdayDateCopied,
    required this.birthdayHeightCopied,
    required this.onCopyPressed,
    required this.onCopyBirthdayDatePressed,
    required this.onCopyBirthdayHeightPressed,
  });

  final String mnemonic;
  final _SeedBirthdayInfo? birthdayInfo;
  final String? birthdayError;
  final bool phraseCopied;
  final bool birthdayDateCopied;
  final bool birthdayHeightCopied;
  final Future<void> Function() onCopyPressed;
  final Future<void> Function() onCopyBirthdayDatePressed;
  final Future<void> Function() onCopyBirthdayHeightPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = mnemonic.split(' ');
    final birthdayDate = birthdayInfo == null
        ? birthdayError ?? 'Unavailable'
        : _formatBirthdayDate(birthdayInfo!.blockTime);
    final birthdayHeight = birthdayInfo == null
        ? birthdayError ?? 'Unavailable'
        : birthdayInfo!.blockHeight.toString();

    return SizedBox(
      width: 529,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.large),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 348,
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
                        minWidth: phraseCopied ? 72 : 96,
                        trailing: AppIcon(
                          phraseCopied ? AppIcons.check : AppIcons.copy,
                        ),
                        child: Text(phraseCopied ? 'Copied' : 'Copy Phrase'),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: colors.border.subtle),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.s,
                ),
                child: Column(
                  children: [
                    _SeedBirthdayRow(
                      icon: AppIcons.calendar,
                      label: 'Birthday date',
                      value: birthdayDate,
                      copied: birthdayDateCopied,
                      copyLabel: 'Copy date',
                      onCopyPressed: birthdayInfo == null
                          ? null
                          : () {
                              onCopyBirthdayDatePressed();
                            },
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Container(height: 1, color: colors.border.subtle),
                    const SizedBox(height: AppSpacing.s),
                    _SeedBirthdayRow(
                      icon: AppIcons.block,
                      label: 'Birthday block height',
                      value: birthdayHeight,
                      copied: birthdayHeightCopied,
                      copyLabel: 'Copy height',
                      onCopyPressed: birthdayInfo == null
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
    );
  }
}

class _SeedBirthdayRow extends StatelessWidget {
  const _SeedBirthdayRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.copied,
    required this.copyLabel,
    required this.onCopyPressed,
  });

  final String icon;
  final String label;
  final String value;
  final bool copied;
  final String copyLabel;
  final VoidCallback? onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          AppIcon(icon, size: AppIconSize.medium, color: colors.icon.regular),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: ',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            onPressed: onCopyPressed,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.small,
            minWidth: copied ? 72 : 88,
            trailing: AppIcon(copied ? AppIcons.check : AppIcons.copy),
            child: Text(copied ? 'Copied' : copyLabel),
          ),
        ],
      ),
    );
  }
}

String _formatBirthdayDate(int blockTime) {
  if (blockTime <= 0) return 'Unavailable';
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
