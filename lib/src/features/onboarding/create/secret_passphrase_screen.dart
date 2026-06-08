import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
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
    await Clipboard.setData(ClipboardData(text: mnemonic));
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
        child: OnboardingPaneScaffold(
          backTarget: OnboardingBackTarget.route(
            label: OnboardingStep.thingsToKnow.label,
            routePath: OnboardingStep.thingsToKnow.routePath,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: _HeroBlock(
              mnemonic: mnemonic,
              isPreparing: isPreparing,
              revealed: revealed,
              copied: copied,
              prepareError: prepareError,
              onCopyPressed: onCopyPressed,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _BottomActions(
          isPreparing: isPreparing,
          submitPhase: submitPhase,
          revealed: revealed,
          submitError: submitError,
          onPrimaryPressed: onPrimaryPressed,
        ),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Secret Passphrase',
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The master key to your wallet.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
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

  static const double _buttonWidth = 256;

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
              revealed ? 'Continue' : 'Reveal the Phrase',
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
    final hiddenBlurSigma = revealed ? 0.0 : 12.5;
    final radius = BorderRadius.circular(AppRadii.large);

    return SizedBox(
      width: 529,
      height: 348,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: switch ((isLoading, error != null, mnemonic)) {
            (true, _, _) => const Center(child: CircularProgressIndicator()),
            (_, true, _) => _ErrorState(message: error!),
            (_, _, String value) => Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: IgnorePointer(
                      ignoring: !revealed,
                      child: revealed
                          ? _SeedGrid(mnemonic: value)
                          : ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: hiddenBlurSigma,
                                sigmaY: hiddenBlurSigma,
                              ),
                              child: const _HiddenContents(),
                            ),
                    ),
                  ),
                ),
                if (!revealed)
                  const Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Center(child: _HiddenWarning()),
                    ),
                  ),
                if (revealed)
                  Positioned(
                    top: AppSpacing.s,
                    right: AppSpacing.s,
                    child: _CopyButton(
                      copied: copied,
                      onPressed: onCopyPressed,
                    ),
                  ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _SeedGrid extends StatelessWidget {
  const _SeedGrid({required this.mnemonic});

  final String mnemonic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = mnemonic.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Secret Passphrase',
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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
      minWidth: 61,
      trailing: AppIcon(copied ? AppIcons.check : AppIcons.copy),
      child: Text(copied ? 'Copied' : 'Copy'),
    );
  }
}

class _HiddenContents extends StatelessWidget {
  const _HiddenContents();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(opacity: 0.7, child: const _SeedPlaceholderGrid()),
    );
  }
}

class _SeedPlaceholderGrid extends StatelessWidget {
  const _SeedPlaceholderGrid();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
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
            for (var i = 0; i < 24; i++)
              AppChip(
                width: 90,
                leadingText: '${i + 1}'.padLeft(2, '0'),
                label: '------',
              ),
          ],
        ),
      ],
    );
  }
}

class _HiddenWarning extends StatelessWidget {
  const _HiddenWarning();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.warning, size: 24, color: colors.icon.destructive),
        const SizedBox(height: AppSpacing.md),
        Text.rich(
          TextSpan(
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
            children: [
              const TextSpan(text: 'You are about to see your '),
              TextSpan(
                text: 'Secret Passphrase.',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: 298,
          child: Text(
            'This phrase is the master key to your funds. Keep it safe, keep '
            'it secret. If you lose it, no one can help you recover your '
            'wallet. Not even us.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
      ],
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
