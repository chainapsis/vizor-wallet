import 'package:flutter/material.dart' show TextField;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'mobile_import_screens.dart';
import 'mobile_onboarding_scaffold.dart';

/// Manual word-by-word import — Figma `Enter your Secret Passphrase`
/// (4562:106067): one large field per word with the position counter,
/// and BIP39 suggestions pinned above the keyboard. A word advances by
/// tapping a suggestion, or by space/return when it's a valid BIP39
/// word; backspace on an empty field steps back to the previous word.
class MobileImportManualScreen extends StatefulWidget {
  const MobileImportManualScreen({this.wordListOverride, super.key});

  /// Test seam — production loads the Rust BIP39 list.
  @visibleForTesting
  final List<String>? wordListOverride;

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

  bool get _canReview =>
      kMnemonicWordCounts.contains(_accepted.length) &&
      _controller.text.trim().isEmpty;

  /// "Continue to review" once accepting the typed word completes the
  /// 24-word phrase, or once a valid shorter phrase sits accepted with
  /// the field empty; otherwise the CTA accepts the next word.
  bool get _primaryIsReview {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return _canReview;
    return _accepted.length + 1 == kMnemonicMaxWords;
  }

  bool get _primaryEnabled => _controller.text.trim().isNotEmpty || _canReview;

  void _primaryAction() {
    final raw = _controller.text.trim();
    if (raw.isNotEmpty) {
      // Accepting the 24th word auto-advances to review (see
      // _acceptWord), so one tap covers both labels.
      _onSubmitted(raw);
      return;
    }
    if (_canReview) _review();
  }

  void _acceptWord(String word) {
    setState(() {
      _accepted.add(word);
      _controller.clear();
      _error = null;
    });
    if (_accepted.length >= kMnemonicMaxWords) {
      _review();
    }
  }

  /// Split arbitrary pasted/typed text into candidate words. BIP39 words
  /// are pure lowercase a–z, so anything else (spaces, commas, numbered
  /// "1." prefixes, punctuation) is treated as a separator — a phrase
  /// copied in almost any shape tokenises cleanly.
  List<String> _tokenize(String raw) => raw
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  void _onChanged(String value) {
    final tokens = _tokenize(value);
    // Two or more tokens in a single edit means a multi-word paste —
    // typing only ever produces one token per keystroke.
    if (tokens.length >= 2) {
      _distributePaste(tokens);
      return;
    }
    // A trailing space accepts the single word, like the keyboard's
    // suggestion flow.
    if (value.endsWith(' ')) _onSubmitted(value);
  }

  /// Fill consecutive slots from the current position with [tokens] (each
  /// already normalised to a–z). Stops at the first token that isn't a
  /// BIP39 word — that token and everything after it are ignored — and at
  /// the 24-word ceiling. Auto-advances to review when the phrase fills.
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
      _review();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _onSubmitted(String raw) {
    final tokens = _tokenize(raw);
    if (tokens.length >= 2) {
      _distributePaste(tokens);
      return;
    }
    final word = tokens.isEmpty ? '' : tokens.first;
    if (word.isEmpty) {
      if (_canReview) _review();
      return;
    }
    if (_wordList.contains(word)) {
      _acceptWord(word);
    } else {
      setState(() {
        _error = "'$word' isn't in the passphrase word list.";
      });
      _focusNode.requestFocus();
    }
  }

  void _stepBack() {
    if (_accepted.isEmpty) return;
    setState(() {
      _controller.text = _accepted.removeLast();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _error = null;
    });
    _focusNode.requestFocus();
  }

  void _review() {
    final words = [..._accepted];
    final error = validateImportedMnemonic(words);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    context.push('/import/review', extra: MobileImportReviewArgs(words: words));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final position = (_accepted.length + 1).clamp(1, kMnemonicMaxWords);

    return MobileOnboardingStepScaffold(
      progress: 0.4,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Enter your Secret Passphrase',
      subtitle: 'Accept 12, 15, 18, 21 or 24 words',
      // Only the BIP39 suggestions stay pinned above the keyboard; per
      // the Figma frame the CTA flows directly under the word field.
      bottomArea: _suggestions.isEmpty
          ? null
          : SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final word in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: _SuggestionChip(
                        word: word,
                        onTap: () => _acceptWord(word),
                      ),
                    ),
                ],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WordField(
            index: position,
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            onSubmitted: _onSubmitted,
          ),
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
          // 46 px from the field to the CTA in the Figma frame.
          const SizedBox(height: 46),
          AppButton(
            key: const ValueKey('mobile_import_manual_review'),
            expand: true,
            onPressed: _primaryEnabled ? _primaryAction : null,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(_primaryIsReview ? 'Continue to review' : 'Next word'),
          ),
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
    required this.onChanged,
    required this.onSubmitted,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
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
              // ("Agent |", 40 px line).
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
              cursorColor: colors.text.accent,
              decoration: null,
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.raised,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: Center(
          child: Text(
            word,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ),
      ),
    );
  }
}
