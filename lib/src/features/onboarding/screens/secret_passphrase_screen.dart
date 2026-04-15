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
import '../../../rust/api/wallet.dart' as rust_wallet;
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
  bool _isPreparing = true;
  bool _isCreating = false;
  bool _revealed = false;
  String? _prepareError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _prepareMnemonic();
  }

  void _prepareMnemonic() {
    try {
      _mnemonic = rust_wallet.generateMnemonic();
      _isPreparing = false;
    } catch (e, st) {
      log('SecretPassphraseScreen._prepareMnemonic: ERROR: $e\n$st');
      _prepareError = e.toString();
      _isPreparing = false;
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_isPreparing || _isCreating || _prepareError != null) return;
    if (!_revealed) {
      setState(() {
        _revealed = true;
        _submitError = null;
      });
      return;
    }
    final mnemonic = _mnemonic;
    if (mnemonic == null) return;

    setState(() {
      _isCreating = true;
      _submitError = null;
    });
    try {
      await ref
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(mnemonic: mnemonic);
    } catch (e, st) {
      log('SecretPassphraseScreen._handlePrimaryAction: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _submitError = e.toString();
      });
      return;
    }
    if (!mounted) return;
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
            isLoading: _isPreparing,
            isCreating: _isCreating,
            revealed: _revealed,
            error: _prepareError,
            submitError: _submitError,
            onPrimaryPressed: () {
              _handlePrimaryAction();
            },
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
    required this.isCreating,
    required this.revealed,
    required this.error,
    required this.submitError,
    required this.onPrimaryPressed,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isLoading;
  final bool isCreating;
  final bool revealed;
  final String? error;
  final String? submitError;
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
          onPressed: error == null && !isLoading && !isCreating
              ? onPrimaryPressed
              : null,
          variant: AppButtonVariant.primary,
          minWidth: 196,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(
            isCreating
                ? 'Creating wallet...'
                : revealed
                ? 'Start using Zeplr'
                : 'Show my Passphrase',
          ),
        ),
        if (submitError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: 320,
            child: Text(
              submitError!,
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
          clipBehavior: Clip.none,
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
            if (!revealed)
              const Positioned.fill(
                child: ColoredBox(color: Color(0x1A000000)),
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
    const verticalGap = AppSpacing.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Secret Passphrase',
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: verticalGap),
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
        const SizedBox(height: verticalGap),
        Container(
          width: double.infinity,
          height: 1,
          color: colors.border.strong,
        ),
        const SizedBox(height: verticalGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Make sure you keep it in safe place',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
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
