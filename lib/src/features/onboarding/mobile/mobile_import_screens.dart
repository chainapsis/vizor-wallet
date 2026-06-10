import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'mobile_onboarding_scaffold.dart';

/// Mnemonic lengths the wallet accepts. The Figma frames show a fixed
/// 24-slot card; shorter standard phrases are accepted anyway and the
/// counter simply stops early (WIP-design gap filled deliberately).
const kMnemonicWordCounts = [12, 15, 18, 21, 24];
const kMnemonicMaxWords = 24;

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

/// Import entry — method choice between manual word-by-word entry and
/// clipboard paste (Figma 4575:106622).
class MobileImportMethodScreen extends StatelessWidget {
  const MobileImportMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.2,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Import Your Wallet',
      subtitle: 'Restore a wallet from its Secret Passphrase.',
      child: Column(
        children: [
          _MethodCard(
            key: const ValueKey('mobile_import_manual'),
            dark: true,
            title: 'Import manually',
            body:
                'Import Secret Passphrase by entering words one by one, '
                'from 1 to 24.',
            onTap: () => context.push('/import/manual'),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MethodCard(
            key: const ValueKey('mobile_import_clipboard'),
            dark: false,
            title: 'Import from Clipboard',
            body: 'Paste your Secret Passphrase.',
            onTap: () => context.push('/import/clipboard'),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.dark,
    required this.title,
    required this.body,
    required this.onTap,
    super.key,
  });

  final bool dark;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = dark ? colors.background.homeCard : colors.background.raised;
    final titleColor = dark ? colors.text.homeCard : colors.text.accent;
    final bodyColor = dark
        ? colors.text.homeCard.withValues(alpha: 0.8)
        : colors.text.secondary;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 200,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
          ),
          child: Stack(
            children: [
              Positioned(
                top: AppSpacing.xxs,
                right: AppSpacing.xxs,
                child: AppIcon(AppIcons.scroll, size: 28, color: titleColor),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headlineMedium.copyWith(
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: AppTypography.bodyMedium.copyWith(
                        color: bodyColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clipboard import — empty numbered slots and a paste action (Figma
/// 4575:107016). A valid pasted phrase fills the card and continues to
/// review.
class MobileImportClipboardScreen extends StatefulWidget {
  const MobileImportClipboardScreen({super.key});

  @override
  State<MobileImportClipboardScreen> createState() =>
      _MobileImportClipboardScreenState();
}

class _MobileImportClipboardScreenState
    extends State<MobileImportClipboardScreen> {
  List<String> _words = const [];
  String? _error;

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImportClipboard: ERROR reading clipboard: $e');
    }
    final words = (text ?? '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    if (words.isEmpty) {
      setState(() {
        _words = const [];
        _error = 'Your clipboard has no passphrase.';
      });
      return;
    }
    final error = validateImportedMnemonic(words);
    setState(() {
      _words = words;
      _error = error;
    });
    if (error == null && mounted) {
      context.push(
        '/import/review',
        extra: MobileImportReviewArgs(words: words),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileOnboardingStepScaffold(
      progress: 0.4,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Import Your Secret Passphrase',
      subtitle: 'Import from clipboard.',
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
          AppButton(
            key: const ValueKey('mobile_import_paste'),
            onPressed: _paste,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.copy,
                  size: 20,
                  color: DefaultTextStyle.of(context).style.color,
                ),
                const SizedBox(width: AppSpacing.xs),
                const Text('Paste secret phrase'),
              ],
            ),
          ),
        ],
      ),
      child: ImportSlotsCard(words: _words),
    );
  }
}

/// The dark numbered-slot card from the clipboard frame: empty
/// underlined slots that fill as words arrive.
class ImportSlotsCard extends StatelessWidget {
  const ImportSlotsCard({required this.words, super.key});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final slotCount = words.length > kMnemonicMaxWords
        ? words.length
        : kMnemonicMaxWords;
    final rows = (slotCount / 3).ceil();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: AppSpacing.s),
                  Expanded(child: _slot(context, row * 3 + col)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _slot(BuildContext context, int index) {
    final colors = context.colors;
    final word = index < words.length ? words[index] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${index + 1}'.padLeft(2, '0'),
              style: AppTypography.codeSmall.copyWith(
                color: colors.text.homeCard.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                word ?? '',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.homeCard,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          height: 1,
          color: colors.text.homeCard.withValues(alpha: 0.25),
        ),
      ],
    );
  }
}
