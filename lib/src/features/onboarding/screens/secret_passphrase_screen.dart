import 'dart:ui';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import 'onboarding_split_view.dart';

class SecretPassphraseScreen extends ConsumerStatefulWidget {
  const SecretPassphraseScreen({super.key});

  @override
  ConsumerState<SecretPassphraseScreen> createState() =>
      _SecretPassphraseScreenState();
}

class _SecretPassphraseScreenState
    extends ConsumerState<SecretPassphraseScreen> {
  String? _mnemonic;
  bool _isLoading = true;
  bool _revealed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _createWallet();
  }

  Future<void> _createWallet() async {
    try {
      final mnemonic = await ref.read(accountProvider.notifier).createAccount();
      if (!mounted) return;
      setState(() {
        _mnemonic = mnemonic;
        _isLoading = false;
      });
    } catch (e, st) {
      log('SecretPassphraseScreen._createWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handlePrimaryAction() {
    if (_isLoading || _error != null) return;
    if (!_revealed) {
      setState(() => _revealed = true);
      return;
    }
    context.go('/home');
  }

  Future<void> _copyMnemonic() async {
    final mnemonic = _mnemonic;
    if (mnemonic == null) return;
    await Clipboard.setData(ClipboardData(text: mnemonic));
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingTrailingPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _Title(),
          _BottomContent(
            mnemonic: _mnemonic,
            isLoading: _isLoading,
            revealed: _revealed,
            error: _error,
            onPrimaryPressed: _handlePrimaryAction,
            onCopyPressed: _copyMnemonic,
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Secret Passphrase',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'The Master Key to your wallet.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _BottomContent extends StatelessWidget {
  const _BottomContent({
    required this.mnemonic,
    required this.isLoading,
    required this.revealed,
    required this.error,
    required this.onPrimaryPressed,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isLoading;
  final bool revealed;
  final String? error;
  final VoidCallback onPrimaryPressed;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SeedPhraseCard(
          mnemonic: mnemonic,
          isLoading: isLoading,
          revealed: revealed,
          error: error,
          onCopyPressed: onCopyPressed,
        ),
        const SizedBox(height: AppSpacing.base),
        AppButton(
          onPressed: error == null && !isLoading ? onPrimaryPressed : null,
          variant: AppButtonVariant.primary,
          minWidth: 196,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(revealed ? 'Start using Zeplr' : 'Show my Passphrase'),
        ),
      ],
    );
  }
}

class _SeedPhraseCard extends StatelessWidget {
  const _SeedPhraseCard({
    required this.mnemonic,
    required this.isLoading,
    required this.revealed,
    required this.error,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isLoading;
  final bool revealed;
  final String? error;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 588,
      height: 315,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: switch ((isLoading, error != null, mnemonic)) {
        (true, _, _) => const Center(child: CircularProgressIndicator()),
        (_, true, _) => _ErrorState(message: error!),
        (_, _, String value) => Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !revealed,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: revealed ? 0 : 15,
                    sigmaY: revealed ? 0 : 15,
                  ),
                  child: _SeedPhraseContents(
                    mnemonic: value,
                    onCopyPressed: onCopyPressed,
                  ),
                ),
              ),
            ),
            if (!revealed) const _HiddenWarning(),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _SeedPhraseContents extends StatelessWidget {
  const _SeedPhraseContents({
    required this.mnemonic,
    required this.onCopyPressed,
  });

  final String mnemonic;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final words = mnemonic.split(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Secret Passphrase',
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 424,
          child: Wrap(
            spacing: 0,
            runSpacing: 0,
            children: [
              for (var index = 0; index < words.length; index++)
                AppChip(
                  width: 104,
                  leadingText: '${index + 1}'.padLeft(2, '0'),
                  label: words[index],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          height: 1,
          color: colors.border.strong,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 222,
              child: Text(
                'Make sure you keep it in safe place',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            AppButton(
              onPressed: () {
                onCopyPressed();
              },
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              trailing: const AppIcon(AppIcons.copy),
              child: const Text('Copy'),
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
        AppIcon(AppIcons.warning, size: 24, color: colors.icon.warning),
        const SizedBox(height: AppSpacing.s),
        Text.rich(
          TextSpan(
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
            children: [
              const TextSpan(text: "You're about to see your "),
              TextSpan(
                text: 'Secret Passphrase.',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.warning,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        SizedBox(
          width: 298,
          child: Text(
            'This phrase is the master key to your funds. Keep it safe, keep '
            'it secret. If you lose it, no one can help you recover your '
            'wallet. Not even us.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
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
    final colors = context.colors;
    return Center(
      child: SizedBox(
        width: 320,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
        ),
      ),
    );
  }
}
