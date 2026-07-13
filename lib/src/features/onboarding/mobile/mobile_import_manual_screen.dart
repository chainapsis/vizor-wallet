import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_review_screen.dart';
import 'mobile_import_screens.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_scaffold.dart';

const _kManualInvalidWordMessage = 'Invalid secret passphrase word.';
const _kManualSuggestionsHeight = 60.0;
const _kManualSuggestionChipHeight = 36.0;

/// Manual word-by-word import — Figma `Enter your Secret Passphrase`
/// (4562:106067): one large field per word with the position counter,
/// and BIP39 suggestions pinned above the keyboard. A word advances by
/// tapping a suggestion, or by space/return when it's a valid BIP39
/// word; backspace on an empty field steps back to the previous word.
class MobileImportManualScreen extends StatefulWidget {
  const MobileImportManualScreen({
    this.wordListOverride,
    this.initialAcceptedWords = const [],
    this.initialTypedWord,
    this.initialError,
    super.key,
  });

  /// Test seam — production loads the Rust BIP39 list.
  @visibleForTesting
  final List<String>? wordListOverride;

  /// Test/Widgetbook seam for previewing later word-entry states.
  @visibleForTesting
  final List<String> initialAcceptedWords;

  /// Test/Widgetbook seam for previewing the active word field.
  @visibleForTesting
  final String? initialTypedWord;

  /// Test/Widgetbook seam for previewing invalid-word states.
  @visibleForTesting
  final String? initialError;

  @override
  State<MobileImportManualScreen> createState() =>
      _MobileImportManualScreenState();
}

class _MobileImportManualScreenState extends State<MobileImportManualScreen> {
  late final List<String> _wordList;
  final List<String> _accepted = [];
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    var words = widget.wordListOverride;
    if (words == null) {
      try {
        words = rust_wallet.mnemonicWordList();
      } catch (e) {
        log('MobileImportManual: ERROR loading word list: $e');
        words = const [];
      }
    }
    _wordList = words;
    _accepted.addAll(widget.initialAcceptedWords.take(kMnemonicMaxWords));
    final initialTypedWord = widget.initialTypedWord;
    if (initialTypedWord != null) {
      _controller.text = initialTypedWord;
      _controller.selection = TextSelection.collapsed(
        offset: initialTypedWord.length,
      );
    }
    _error = widget.initialError;
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<String> get _suggestions {
    final prefix = _controller.text.trim().toLowerCase();
    if (prefix.isEmpty) return const [];
    return _wordList.where((w) => w.startsWith(prefix)).take(12).toList();
  }

  String get _typed => _controller.text.trim();
  bool get _hasTyped => _typed.isNotEmpty;
  bool get _atMax => _accepted.length >= kMnemonicMaxWords;

  /// Total word count if the currently-typed word is accepted; just the
  /// accepted count when the field is empty.
  int get _pendingCount => _accepted.length + (_hasTyped ? 1 : 0);

  /// A valid-length phrase (12/15/18/21/24) is reachable, so offer
  /// "Finish & review" beside "Next word" (Figma 4746:83516).
  bool get _showFinish => kMnemonicWordCounts.contains(_pendingCount);

  /// Accept the typed word and advance to the next slot.
  void _acceptTyped() {
    if (_hasTyped) _onSubmitted(_controller.text);
  }

  bool _addAcceptedWord(String word) {
    if (_accepted.length >= kMnemonicMaxWords) {
      setState(() {
        _controller.clear();
        _error = null;
      });
      return false;
    }
    setState(() {
      _accepted.add(word);
      _controller.clear();
      _error = null;
    });
    return true;
  }

  /// Accept the typed word (if any), then validate the full phrase and
  /// move to the review step.
  void _finish() {
    if (_hasTyped) {
      final tokens = tokenizeMnemonicWords(_typed);
      final word = tokens.isEmpty ? '' : tokens.first;
      if (word.isEmpty || !_wordList.contains(word)) {
        setState(() => _error = _kManualInvalidWordMessage);
        _focusNode.requestFocus();
        return;
      }
      if (!_addAcceptedWord(word)) {
        _continueToReview();
        return;
      }
    }
    _continueToReview();
  }

  void _acceptWord(String word) {
    if (!_addAcceptedWord(word)) {
      _continueToReview();
      return;
    }
    if (_accepted.length >= kMnemonicMaxWords) {
      _continueToReview();
    }
  }

  void _onChanged(String value) {
    final tokens = tokenizeMnemonicWords(value);
    // Two or more tokens in a single edit means a multi-word paste —
    // typing only ever produces one token per keystroke.
    if (tokens.length >= 2) {
      _distributePaste(tokens);
      return;
    }
    // A trailing space accepts the single word, like the keyboard's
    // suggestion flow.
    if (value.endsWith(' ')) {
      _onSubmitted(value);
      return;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (_error != null) setState(() => _error = null);
      return;
    }

    final hasOnlyLetters = RegExp(r'^[A-Za-z]+$').hasMatch(trimmed);
    final prefix = trimmed.toLowerCase();
    final hasMatchingPrefix =
        _wordList.isEmpty || _wordList.any((word) => word.startsWith(prefix));
    final nextError = hasOnlyLetters && hasMatchingPrefix
        ? null
        : _kManualInvalidWordMessage;
    if (_error != nextError) setState(() => _error = nextError);
  }

  /// Fill consecutive slots from the current position with [tokens] (each
  /// already normalised to a–z). Stops at the first token that isn't a
  /// BIP39 word — that token and everything after it are ignored — and at
  /// the 24-word ceiling. Auto-advances to birthday when the phrase fills.
  void _distributePaste(List<String> tokens) {
    String? stoppedAt;
    setState(() {
      for (final word in tokens) {
        if (_accepted.length >= kMnemonicMaxWords) break;
        if (_wordList.contains(word)) {
          _accepted.add(word);
        } else {
          stoppedAt = word;
          break;
        }
      }
      _controller.clear();
      // Light heads-up so the user knows why the fill stopped early.
      _error = stoppedAt == null
          ? null
          : "Stopped at '$stoppedAt' — it isn't in the passphrase word list.";
    });
    if (_accepted.length >= kMnemonicMaxWords) {
      _continueToReview();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _onSubmitted(String raw) {
    final tokens = tokenizeMnemonicWords(raw);
    if (tokens.length >= 2) {
      _distributePaste(tokens);
      return;
    }
    final word = tokens.isEmpty ? '' : tokens.first;
    if (word.isEmpty) {
      if (kMnemonicWordCounts.contains(_accepted.length)) {
        _continueToReview();
      }
      return;
    }
    if (_wordList.contains(word)) {
      _acceptWord(word);
    } else {
      setState(() {
        _error = _kManualInvalidWordMessage;
      });
      _focusNode.requestFocus();
    }
  }

  void _stepBack() {
    if (_accepted.isEmpty) return;
    setState(() {
      _restoreLastWordToField();
      _error = null;
    });
    _focusNode.requestFocus();
  }

  void _restoreLastWordToField() {
    _controller.text = _accepted.removeLast();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _editLastWordAfterReviewBack() {
    if (_accepted.isEmpty) return;
    setState(() {
      _restoreLastWordToField();
      _error = null;
    });
    _focusNode.requestFocus();
  }

  void _continueToReview() {
    final words = [..._accepted];
    final error = validateImportedMnemonic(words);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    context
        .push<Object?>(
          '/import/review',
          extra: ImportSecretPassphraseArgs(mnemonic: words.join(' ')),
        )
        .then((result) {
          if (!mounted) return;
          if (result == MobileImportReviewResult.clear) {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/import');
            }
            return;
          }
          _editLastWordAfterReviewBack();
        });
  }

  /// The CTA block: a single "Next word" until a valid-length phrase is
  /// reachable, then "Finish & review" plus a
  /// secondary "Next word" to continue toward longer standard phrases.
  Widget _buildButtonRow() {
    final nextEnabled = _hasTyped && !_atMax;
    final nextButton = AppButton(
      key: const ValueKey('mobile_import_manual_next'),
      variant: _showFinish
          ? AppButtonVariant.secondary
          : AppButtonVariant.primary,
      expand: true,
      constrainContent: true,
      contentPadding: _showFinish
          ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
          : null,
      onPressed: nextEnabled ? _acceptTyped : null,
      trailing: _showFinish ? null : const AppIcon(AppIcons.chevronForward),
      child: const Text(
        'Next word',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!_showFinish) return nextButton;
    return Row(
      children: [
        SizedBox(width: 128, child: nextButton),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: AppButton(
            key: const ValueKey('mobile_import_manual_finish'),
            expand: true,
            constrainContent: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
            ),
            onPressed: _finish,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text(
              'Finish & review',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final position = (_accepted.length + 1).clamp(1, kMnemonicMaxWords);

    return MobileOnboardingStepScaffold(
      progress: mobileImportProgress(1),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Enter your Secret Passphrase',
      subtitle: 'Accept 12, 15, 18, 21 or 24 words',
      // Only the CTA is pinned — it rides up above the keyboard (Figma
      // 4746:83516). The autocomplete chips stay attached under the word
      // field and scroll with the content. The stretch Column gives the
      // expand:true button a tight width to fill.
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildButtonRow()],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WordField(
            index: position,
            controller: _controller,
            focusNode: _focusNode,
            hasError: _error != null,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              key: const ValueKey('mobile_import_manual_suggestions'),
              height: _kManualSuggestionsHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final word in _suggestions)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: _SuggestionChip(
                          word: word,
                          onTap: () => _acceptWord(word),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
          if (_accepted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _accepted.join(' · '),
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _stepBack,
                child: SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      'Undo last word',
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WordField extends StatelessWidget {
  const _WordField({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// When the typed word failed validation, the word renders destructive
  /// until the user edits it (Figma invalid-word state).
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textColor = hasError ? colors.text.destructive : colors.text.accent;
    return Container(
      key: const ValueKey('mobile_import_manual_input'),
      // Figma `Input` (4562:106067): 24 px padding around a 40 px serif
      // line makes the 88 px field.
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Row(
        children: [
          Text(
            '$index'.padLeft(2, '0'),
            style: AppTypography.codeMedium.copyWith(color: colors.text.muted),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // A real TextField (bare, no decoration) rather than raw
            // EditableText so long-press selection and the paste menu
            // work; the row container owns all visible chrome.
            child: TextField(
              key: const ValueKey('mobile_import_manual_field'),
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              // Full Headline XL serif per the Figma word field
              // ("Agent |", 40 px line). The display token's −1.35 title
              // tracking is dropped here: on an editable field it pulls the
              // caret into the glyph (visible on serif 'f'), so this field
              // uses neutral tracking.
              style: AppTypography.displayLarge.copyWith(
                color: textColor,
                letterSpacing: 0,
              ),
              cursorColor: textColor,
              decoration: null,
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
              // Keep the keyboard open when return/check submits a word.
              // onSubmitted still advances through the shared handler below.
              onEditingComplete: () {},
              onSubmitted: onSubmitted,
              // The parent decides: a multi-word paste distributes across
              // slots; a single word + trailing space accepts.
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      key: ValueKey('mobile_import_manual_suggestion_$word'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: _kManualSuggestionChipHeight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.raised,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Center(
            child: Text(
              word,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
