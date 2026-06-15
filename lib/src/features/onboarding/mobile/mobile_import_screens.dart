import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'mobile_onboarding_scaffold.dart';

/// Mnemonic lengths the wallet accepts from clipboard or manual entry.
const kMnemonicWordCounts = [12, 15, 18, 21, 24];
const kMnemonicMaxWords = 24;
const _kImportSeedCardWidth = 361.0;

/// Words ready for review, carried between the import steps.
class MobileImportReviewArgs {
  const MobileImportReviewArgs({required this.words});

  final List<String> words;

  String get mnemonic => words.join(' ');
}

/// Validates a candidate phrase; returns an error message or null.
String? validateImportedMnemonic(List<String> words) {
  if (!kMnemonicWordCounts.contains(words.length)) {
    return 'A secret passphrase has 12, 15, 18, 21, or 24 words — '
        'found ${words.length}.';
  }
  try {
    if (!rust_wallet.validateMnemonic(mnemonic: words.join(' '))) {
      return "That passphrase isn't valid. Check the words and try again.";
    }
  } catch (e) {
    log('validateImportedMnemonic: ERROR: $e');
    return "That passphrase couldn't be checked. Try again.";
  }
  return null;
}

enum _ImportPastePhase { idle, reading, error }

/// Import entry — Figma `Import — Secret Passprhase Paste`
/// (4575:108577 / 4746:82920 / 4746:22880): a clipboard-reading card
/// with idle, loading, and error states, plus a manual-entry link.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({super.key});

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen> {
  _ImportPastePhase _phase = _ImportPastePhase.idle;

  Future<void> _paste() async {
    if (_phase == _ImportPastePhase.reading) return;
    setState(() => _phase = _ImportPastePhase.reading);

    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImport: ERROR reading clipboard: $e');
      if (mounted) setState(() => _phase = _ImportPastePhase.error);
      return;
    }
    if (!mounted) return;

    final words = (text ?? '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    if (words.isEmpty) {
      setState(() => _phase = _ImportPastePhase.error);
      return;
    }
    final error = validateImportedMnemonic(words);
    if (error != null) {
      log('MobileImport: rejected clipboard mnemonic: $error');
      setState(() => _phase = _ImportPastePhase.error);
      return;
    }
    setState(() => _phase = _ImportPastePhase.idle);
    if (!mounted) return;
    await context.push(
      '/import/review',
      extra: MobileImportReviewArgs(words: words),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.2,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Import Wallet',
      // Line break matches the Figma subtitle wrap.
      subtitle:
          'Paste your Secret Passphrase or\nenter it manually word by word.',
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xs),
          _ImportPasteCard(phase: _phase, onPaste: _paste),
          const SizedBox(height: AppSpacing.base),
          _ManualImportLink(onTap: () => context.push('/import/manual')),
        ],
      ),
    );
  }
}

class _ImportPasteCard extends StatelessWidget {
  const _ImportPasteCard({required this.phase, required this.onPaste});

  final _ImportPastePhase phase;
  final VoidCallback onPaste;

  bool get _isError => phase == _ImportPastePhase.error;
  bool get _isReading => phase == _ImportPastePhase.reading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardHeight = phase == _ImportPastePhase.idle ? 370.0 : 390.0;
    final verticalPadding = phase == _ImportPastePhase.idle
        ? AppSpacing.lg
        : AppSpacing.base;
    final contentGap = phase == _ImportPastePhase.idle
        ? AppSpacing.lg - 3
        : AppSpacing.base - 1;
    final iconColor = _isError
        ? colors.text.destructive
        : colors.text.homeCard.withValues(alpha: 0.5);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kImportSeedCardWidth),
      child: SizedBox(
        width: double.infinity,
        height: cardHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: verticalPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(AppIcons.importWallet, size: 33, color: iconColor),
                SizedBox(height: contentGap),
                _ImportPasteCardText(isError: _isError),
                SizedBox(height: contentGap),
                IgnorePointer(
                  ignoring: _isReading,
                  child: AppButton(
                    key: const ValueKey('mobile_import_paste'),
                    onPressed: onPaste,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.medium,
                    height: 36,
                    minWidth: 96,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    leading: AppIcon(
                      _isError
                          ? AppIcons.renew
                          : _isReading
                          ? AppIcons.loader
                          : AppIcons.copy,
                    ),
                    child: Text(
                      _isError
                          ? 'Try again'
                          : _isReading
                          ? 'Reading...'
                          : 'Paste',
                    ),
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

class _ImportPasteCardText extends StatelessWidget {
  const _ImportPasteCardText({required this.isError});

  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Text(
          isError ? "Can’t read clipboard data" : 'Paste from clipboard',
          textAlign: TextAlign.center,
          style: AppTypography.bodyLarge.copyWith(
            color: isError ? colors.text.destructive : colors.text.homeCard,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Accept 12, 15, 18, 21 or 24-\nword Secret Passphrases',
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.homeCard.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _ManualImportLink extends StatelessWidget {
  const _ManualImportLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _kImportSeedCardWidth),
      child: Semantics(
        button: true,
        child: GestureDetector(
          key: const ValueKey('mobile_import_enter_manually'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 50,
            width: double.infinity,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    AppIcons.edit,
                    size: 20,
                    color: colors.button.ghost.label,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Text(
                      'Enter Secret Passphrase manually',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.button.ghost.label,
                      ),
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
