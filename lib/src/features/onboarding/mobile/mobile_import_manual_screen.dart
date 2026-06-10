import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
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

  void _onSubmitted(String raw) {
    final word = raw.trim().toLowerCase();
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
      subtitle: 'Word $position/$kMnemonicMaxWords',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (_canReview)
            AppButton(
              key: const ValueKey('mobile_import_manual_review'),
              onPressed: _review,
              child: const Text('Review'),
            ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
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
          ],
        ],
      ),
      child: Column(
        children: [
          _WordField(
            index: position,
            controller: _controller,
            focusNode: _focusNode,
            onSubmitted: _onSubmitted,
          ),
          if (_accepted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
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
    required this.onSubmitted,
  });

  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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
            child: EditableText(
              key: const ValueKey('mobile_import_manual_field'),
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
                fontSize: 28,
              ),
              cursorColor: colors.text.accent,
              backgroundCursorColor: colors.background.overlay,
              keyboardType: TextInputType.visiblePassword,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: onSubmitted,
              onChanged: (value) {
                // A trailing space accepts the word, like the system
                // keyboard's suggestion flow.
                if (value.endsWith(' ')) {
                  onSubmitted(value);
                }
              },
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
