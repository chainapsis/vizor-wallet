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
const _kClipboardReadError = "Can’t read clipboard data";
const _kClipboardEmptyError = "Clipboard doesn’t contain a Secret Passphrase";
const _kMnemonicWordCountError =
    'Secret Passphrase must be 12, 15, 18, 21, or 24 words';
const _kMnemonicUnknownWordsError =
    "Some words aren’t in the passphrase word list";
const _kMnemonicInvalidError = "That Secret Passphrase isn’t valid";
const _kMnemonicValidationUnavailableError =
    "That passphrase couldn't be checked. Try again.";

/// Words ready for review, carried between the import steps.
class MobileImportReviewArgs {
  const MobileImportReviewArgs({required this.words});

  final List<String> words;

  String get mnemonic => words.join(' ');
}

/// Normalises pasted mnemonic-like text into candidate BIP-39 words.
///
/// English BIP-39 words are lowercase ASCII letters, so numbers,
/// punctuation, commas, and copied list prefixes like `1.` are separators.
List<String> parseMnemonicWords(String raw) => raw
    .toLowerCase()
    .split(RegExp(r'[^a-z]+'))
    .where((word) => word.isNotEmpty)
    .toList();

/// Validates a candidate phrase; returns an error message or null.
String? validateImportedMnemonic(
  List<String> words, {
  Set<String>? wordList,
  bool Function(String mnemonic)? validateMnemonic,
}) {
  if (words.isEmpty) return _kClipboardEmptyError;
  if (!kMnemonicWordCounts.contains(words.length)) {
    return _kMnemonicWordCountError;
  }
  if (wordList != null && words.any((word) => !wordList.contains(word))) {
    return _kMnemonicUnknownWordsError;
  }
  try {
    final mnemonic = words.join(' ');
    final isValid =
        validateMnemonic?.call(mnemonic) ??
        rust_wallet.validateMnemonic(mnemonic: mnemonic);
    if (!isValid) {
      return _kMnemonicInvalidError;
    }
  } catch (e) {
    log('validateImportedMnemonic: ERROR: $e');
    return _kMnemonicValidationUnavailableError;
  }
  return null;
}

enum _ImportPastePhase { idle, reading, error }

/// Import entry — Figma `Import — Secret Passprhase Paste`
/// (4575:108577 / 4746:82920 / 4746:22880): a clipboard-reading card
/// with idle, loading, and error states, plus a manual-entry link.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({
    this.mnemonicWordListOverride,
    this.validateMnemonicOverride,
    super.key,
  });

  final List<String>? mnemonicWordListOverride;
  final bool Function(String mnemonic)? validateMnemonicOverride;

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen> {
  _ImportPastePhase _phase = _ImportPastePhase.idle;
  String _errorTitle = _kClipboardReadError;

  Set<String>? _wordList() {
    final override = widget.mnemonicWordListOverride;
    if (override != null) return override.toSet();
    try {
      return rust_wallet.mnemonicWordList().toSet();
    } catch (e) {
      log('MobileImport: ERROR loading mnemonic word list: $e');
      return null;
    }
  }

  void _showError(String title) {
    setState(() {
      _phase = _ImportPastePhase.error;
      _errorTitle = title;
    });
  }

  Future<void> _paste() async {
    if (_phase == _ImportPastePhase.reading) return;
    setState(() => _phase = _ImportPastePhase.reading);

    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImport: ERROR reading clipboard: $e');
      if (mounted) _showError(_kClipboardReadError);
      return;
    }
    if (!mounted) return;

    final words = parseMnemonicWords(text ?? '');
    final error = validateImportedMnemonic(
      words,
      wordList: kMnemonicWordCounts.contains(words.length) ? _wordList() : null,
      validateMnemonic: widget.validateMnemonicOverride,
    );
    if (error != null) {
      log('MobileImport: rejected clipboard mnemonic: $error');
      _showError(error);
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
          _ImportPasteCard(
            phase: _phase,
            errorTitle: _errorTitle,
            onPaste: _paste,
          ),
          const SizedBox(height: AppSpacing.base),
          _ManualImportLink(onTap: () => context.push('/import/manual')),
        ],
      ),
    );
  }
}

class _ImportPasteCard extends StatelessWidget {
  const _ImportPasteCard({
    required this.phase,
    required this.errorTitle,
    required this.onPaste,
  });

  final _ImportPastePhase phase;
  final String errorTitle;
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
                _ImportPasteCardText(isError: _isError, errorTitle: errorTitle),
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
  const _ImportPasteCardText({required this.isError, required this.errorTitle});

  final bool isError;
  final String errorTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Text(
          isError ? errorTitle : 'Paste from clipboard',
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
