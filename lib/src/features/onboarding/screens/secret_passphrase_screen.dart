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
import '../../../core/widgets/app_decorative_divider.dart';
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
        children: [
          const _BackRow(),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 433,
                child: _HeroLayout(
                  mnemonic: _mnemonic,
                  isPreparing: _isPreparing,
                  isCreating: _isCreating,
                  revealed: _revealed,
                  prepareError: _prepareError,
                  submitError: _submitError,
                  onPrimaryPressed: _handlePrimaryAction,
                  onCopyPressed: _copyMnemonic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(OnboardingStep.thingsToKnow.routePath),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
                color: colors.text.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
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
    required this.isCreating,
    required this.revealed,
    required this.prepareError,
    required this.submitError,
    required this.onPrimaryPressed,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isPreparing;
  final bool isCreating;
  final bool revealed;
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
              prepareError: prepareError,
              onCopyPressed: onCopyPressed,
            ),
          ),
        ),
        _BottomActions(
          isPreparing: isPreparing,
          isCreating: isCreating,
          revealed: revealed,
          submitError: submitError,
          onPrimaryPressed: onPrimaryPressed,
        ),
        const SizedBox(height: AppSpacing.s),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.mnemonic,
    required this.isPreparing,
    required this.revealed,
    required this.prepareError,
    required this.onCopyPressed,
  });

  final String? mnemonic;
  final bool isPreparing;
  final bool revealed;
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
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'The Master Key to your wallet.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        const AppDecorativeDivider(),
        const SizedBox(height: AppSpacing.s),
        _SeedPhraseCard(
          mnemonic: mnemonic,
          isLoading: isPreparing,
          revealed: revealed,
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
    required this.isCreating,
    required this.revealed,
    required this.submitError,
    required this.onPrimaryPressed,
  });

  final bool isPreparing;
  final bool isCreating;
  final bool revealed;
  final String? submitError;
  final Future<void> Function() onPrimaryPressed;

  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppButton(
          onPressed: !isPreparing && !isCreating ? onPrimaryPressed : null,
          variant: AppButtonVariant.primary,
          minWidth: _buttonWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: Text(
            isCreating
                ? 'Creating wallet...'
                : revealed
                ? 'I’m ready to use Vizor'
                : 'Reveal the Phrase',
          ),
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
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final hiddenBlurSigma = revealed ? 0.0 : 12.5;
    final hiddenWashColor = isDark
        ? colors.background.base.withValues(alpha: 0.16)
        : colors.background.base.withValues(alpha: 0.52);
    final radius = BorderRadius.circular(AppRadii.medium);

    return SizedBox(
      width: 433,
      height: 228,
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: IgnorePointer(
                      ignoring: !revealed,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: hiddenBlurSigma,
                          sigmaY: hiddenBlurSigma,
                        ),
                        child: revealed
                            ? _RevealedContents(
                                mnemonic: value,
                                onCopyPressed: onCopyPressed,
                              )
                            : _HiddenContents(
                                mnemonic: value,
                                onCopyPressed: onCopyPressed,
                              ),
                      ),
                    ),
                  ),
                ),
                if (!revealed)
                  Positioned.fill(child: ColoredBox(color: hiddenWashColor)),
                if (!revealed)
                  const Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: Center(child: _HiddenWarning()),
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

class _RevealedContents extends StatelessWidget {
  const _RevealedContents({
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Secret Passphrase',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            _CopyButton(onPressed: onCopyPressed),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 0,
          runSpacing: 0,
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
  const _CopyButton({required this.onPressed});

  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPressed(),
      child: Container(
        height: 24,
        padding: const EdgeInsets.all(AppSpacing.xxs),
        decoration: BoxDecoration(
          color: colors.button.primary.bg,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: DefaultTextStyle.merge(
          style: AppTypography.labelMedium.copyWith(
            color: colors.button.primary.label,
          ),
          child: IconTheme.merge(
            data: IconThemeData(
              color: colors.button.primary.label,
              size: AppIconSize.medium,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                  child: Text('Copy'),
                ),
                AppIcon(AppIcons.copy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HiddenContents extends StatelessWidget {
  const _HiddenContents({required this.mnemonic, required this.onCopyPressed});

  final String mnemonic;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    return _RevealedContents(mnemonic: mnemonic, onCopyPressed: onCopyPressed);
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
              const TextSpan(text: 'You are about to see\nyour '),
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
