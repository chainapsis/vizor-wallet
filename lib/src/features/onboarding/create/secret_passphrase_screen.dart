import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'onboarding_split_view.dart';
import '../shared/onboarding_chrome.dart';
import '../shared/onboarding_flow_args.dart';
import '../shared/onboarding_error_messages.dart';

class SecretPassphraseScreen extends ConsumerStatefulWidget {
  const SecretPassphraseScreen({
    this.args,
    this.privacyOverlayController,
    super.key,
  });

  final CreateSecretPassphraseArgs? args;
  final SensitivePrivacyOverlayController? privacyOverlayController;

  @override
  ConsumerState<SecretPassphraseScreen> createState() =>
      _SecretPassphraseScreenState();
}

enum _CreateWalletSubmitPhase { idle, stoppingSync, creating }

class _SecretPassphraseScreenState
    extends ConsumerState<SecretPassphraseScreen> {
  String? _mnemonic;
  bool _isPreparing = true;
  _CreateWalletSubmitPhase _submitPhase = _CreateWalletSubmitPhase.idle;
  bool _revealed = false;
  bool _copied = false;
  Timer? _copyResetTimer;
  String? _prepareError;
  String? _submitError;

  bool get _isSubmitting => _submitPhase != _CreateWalletSubmitPhase.idle;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args == null) {
      final existingMnemonic = ref.read(createOnboardingMnemonicProvider);
      if (existingMnemonic == null) {
        _scheduleSidebarRevealed(false);
        _prepareMnemonic();
      } else {
        _useMnemonic(
          existingMnemonic,
          revealed: ref.read(onboardingSecretPassphraseRevealedProvider),
        );
      }
    } else {
      _useMnemonic(args.mnemonic, revealed: true);
    }
  }

  void _useMnemonic(String mnemonic, {required bool revealed}) {
    _mnemonic = mnemonic;
    _isPreparing = false;
    _revealed = revealed;
    if (ref.read(createOnboardingMnemonicProvider) != mnemonic) {
      _scheduleCreateMnemonic(mnemonic);
    }
    _scheduleSidebarRevealed(revealed);
  }

  void _scheduleCreateMnemonic(String mnemonic) {
    Future<void>(() {
      if (!mounted) return;
      ref.read(createOnboardingMnemonicProvider.notifier).setMnemonic(mnemonic);
    });
  }

  void _scheduleSidebarRevealed(bool value) {
    if (ref.read(onboardingSecretPassphraseRevealedProvider) == value) return;
    Future<void>(() {
      if (!mounted) return;
      ref
          .read(onboardingSecretPassphraseRevealedProvider.notifier)
          .setRevealed(value);
    });
  }

  void _prepareMnemonic() {
    try {
      final mnemonic = rust_wallet.generateMnemonic();
      _mnemonic = mnemonic;
      _scheduleCreateMnemonic(mnemonic);
      _isPreparing = false;
    } catch (e, st) {
      log('SecretPassphraseScreen._prepareMnemonic: ERROR: $e\n$st');
      _prepareError = e.toString();
      _isPreparing = false;
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_isPreparing || _isSubmitting || _prepareError != null) return;
    if (!_revealed) {
      setState(() {
        _revealed = true;
        _copied = false;
        _submitError = null;
      });
      ref
          .read(onboardingSecretPassphraseRevealedProvider.notifier)
          .setRevealed(true);
      return;
    }
    final mnemonic = _mnemonic;
    if (mnemonic == null) return;
    final security = ref.read(appSecurityProvider);

    if (!security.isPasswordConfigured) {
      context.go(
        OnboardingStep.setPassword.routePath,
        extra: SetPasswordScreenArgs.create(mnemonic: mnemonic),
      );
      return;
    }

    setState(() {
      _submitPhase = _CreateWalletSubmitPhase.creating;
      _submitError = null;
    });
    final router = GoRouter.of(context);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      await runWithSyncPausedForAccountMutation(
        ref,
        () => accountNotifier.createAccountFromMnemonic(mnemonic: mnemonic),
        onStoppingSync: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _CreateWalletSubmitPhase.stoppingSync;
          });
        },
        onSyncPaused: () {
          if (!mounted) return;
          setState(() {
            _submitPhase = _CreateWalletSubmitPhase.creating;
          });
        },
      );
    } catch (e, st) {
      log('SecretPassphraseScreen._handlePrimaryAction: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitPhase = _CreateWalletSubmitPhase.idle;
        _submitError = onboardingSubmitErrorMessage(e);
      });
      return;
    }
    if (mounted) {
      clearCreateOnboardingSecretState(ref.read);
    }
    router.go('/home');
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null || !_revealed) return;
    await SensitiveClipboard.copyText(mnemonic);
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
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDesktopPane(
      padding: EdgeInsets.zero,
      paintBackground: false,
      child: SensitivePrivacyOverlay(
        sensitiveContentVisible: _revealed && _mnemonic != null,
        controller: widget.privacyOverlayController,
        borderRadius: BorderRadius.circular(
          AppDesktopSidebarSurface.glassRadius,
        ),
        child: OnboardingPaneScaffold(
          backTarget: OnboardingBackTarget.route(
            label: OnboardingStep.thingsToKnow.label,
            routePath: OnboardingStep.thingsToKnow.routePath,
          ),
          bodyPadding: EdgeInsets.zero,
          child: _HeroLayout(
            mnemonic: _mnemonic,
            isPreparing: _isPreparing,
            submitPhase: _submitPhase,
            revealed: _revealed,
            copied: _copied,
            prepareError: _prepareError,
            submitError: _submitError,
            onPrimaryPressed: _handlePrimaryAction,
            onCopyPressed: _copyMnemonic,
          ),
        ),
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({
    required this.mnemonic,
    required this.isPreparing,
    required this.submitPhase,
    required this.revealed,
    required this.copied,
    required this.prepareError,
    required this.submitError,
    required this.onPrimaryPressed,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isPreparing;
  final _CreateWalletSubmitPhase submitPhase;
  final bool revealed;
  final bool copied;
  final String? prepareError;
  final String? submitError;
  final Future<void> Function() onPrimaryPressed;
  final Future<void> Function() onCopyPressed;

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: _OnPageContent(
                        mnemonic: mnemonic,
                        isPreparing: isPreparing,
                        revealed: revealed,
                        copied: copied,
                        prepareError: prepareError,
                        onCopyPressed: onCopyPressed,
                      ),
                    ),
                    _BottomActions(
                      isPreparing: isPreparing,
                      submitPhase: submitPhase,
                      revealed: revealed,
                      submitError: submitError,
                      onPrimaryPressed: onPrimaryPressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent({
    required this.mnemonic,
    required this.isPreparing,
    required this.revealed,
    required this.copied,
    required this.prepareError,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isPreparing;
  final bool revealed;
  final bool copied;
  final String? prepareError;
  final Future<void> Function() onCopyPressed;

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _TitleBlock(),
        const SizedBox(height: _sectionGap),
        _SeedPhraseCard(
          mnemonic: mnemonic,
          isLoading: isPreparing,
          revealed: revealed,
          copied: copied,
          error: prepareError,
          onCopyPressed: onCopyPressed,
        ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            'Secret Passphrase',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'The master key to your wallet.',
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isPreparing,
    required this.submitPhase,
    required this.revealed,
    required this.submitError,
    required this.onPrimaryPressed,
  });

  final bool isPreparing;
  final _CreateWalletSubmitPhase submitPhase;
  final bool revealed;
  final String? submitError;
  final Future<void> Function() onPrimaryPressed;

  static const double _buttonWidth = 196;

  @override
  Widget build(BuildContext context) {
    final isSubmitting = submitPhase != _CreateWalletSubmitPhase.idle;
    return Column(
      children: [
        AppButton(
          key: const ValueKey('create_secret_phrase_primary_button'),
          onPressed: !isPreparing && !isSubmitting ? onPrimaryPressed : null,
          variant: AppButtonVariant.primary,
          minWidth: _buttonWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(switch (submitPhase) {
            _CreateWalletSubmitPhase.stoppingSync => 'Stop syncing...',
            _CreateWalletSubmitPhase.creating => 'Creating wallet...',
            _CreateWalletSubmitPhase.idle =>
              revealed ? 'Continue' : 'Reveal the phrase',
          }),
        ),
        if (submitError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: 320,
            child: Text(
              submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.warning,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SeedPhraseCard extends StatelessWidget {
  const _SeedPhraseCard({
    required this.mnemonic,
    required this.isLoading,
    required this.revealed,
    required this.copied,
    required this.error,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isLoading;
  final bool revealed;
  final bool copied;
  final String? error;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: switch ((isLoading, error != null, mnemonic)) {
        (true, _, _) => const Center(child: CircularProgressIndicator()),
        (_, true, _) => _ErrorState(message: error!),
        (_, _, String value) =>
          revealed
              ? _SeedPhraseRevealContent(
                  mnemonic: value,
                  copied: copied,
                  onCopyPressed: onCopyPressed,
                )
              : const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.base,
                  ),
                  child: Center(child: _HiddenWarning()),
                ),
        _ => const SizedBox.shrink(),
      },
    );

    return SizedBox(
      width: double.infinity,
      height: revealed ? null : 258,
      child: revealed
          ? ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 340),
              child: card,
            )
          : card,
    );
  }
}

class _HiddenWarning extends StatelessWidget {
  const _HiddenWarning();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textColor = colors.text.homeCard;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.background.brandCrimsonStrong,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: AppIcon(AppIcons.key, size: 24, color: textColor),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 202,
          child: Text.rich(
            TextSpan(
              style: AppTypography.headlineSmall.copyWith(color: textColor),
              children: const [
                TextSpan(text: 'You are about to see your '),
                TextSpan(text: 'Secret Passphrase.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 298,
          child: Text(
            'This phrase is the master key to your funds. Keep it safe, keep '
            'it secret. If you lose it, no one can help you recover your '
            'wallet. Not even us.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeedPhraseRevealContent extends StatelessWidget {
  const _SeedPhraseRevealContent({
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
    final textColor = colors.text.homeCard;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.base,
          ),
          child: _SeedGrid(mnemonic: mnemonic, textColor: textColor),
        ),
        Positioned(
          top: AppSpacing.s,
          right: AppSpacing.s,
          child: _CopyButton(copied: copied, onPressed: onCopyPressed),
        ),
      ],
    );
  }
}

class _SeedGrid extends StatelessWidget {
  const _SeedGrid({required this.mnemonic, required this.textColor});

  final String mnemonic;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final words = mnemonic.split(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Secret Passphrase',
                style: AppTypography.bodyLarge.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            for (var i = 0; i < words.length; i++)
              _SeedPhraseChip(
                index: i + 1,
                word: words[i],
                textColor: textColor,
              ),
          ],
        ),
      ],
    );
  }
}

class _SeedPhraseChip extends StatelessWidget {
  const _SeedPhraseChip({
    required this.index,
    required this.word,
    required this.textColor,
  });

  final int index;
  final String word;
  final Color textColor;

  static const double _minWidth = 90;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: ValueKey('seed_phrase_word_$index'),
      constraints: const BoxConstraints(minWidth: _minWidth, minHeight: 25),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              index.toString().padLeft(2, '0'),
              style: AppTypography.codeSmall.copyWith(
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              word,
              maxLines: 1,
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onPressed});

  final bool copied;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => onPressed(),
      variant: AppButtonVariant.primary,
      size: AppButtonSize.small,
      trailing: AppIcon(copied ? AppIcons.check : AppIcons.copy),
      child: Text(copied ? 'Copied' : 'Copy'),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.warning,
          ),
        ),
      ),
    );
  }
}
