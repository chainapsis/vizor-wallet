import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
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

/// Import entry — Figma `Import — Secret Passprhase Paste` /
/// `Clipboard Errors` (4575:108577 / 4575:108752): the empty numbered
/// slots with a paste action, clipboard problems surfaced as toasts,
/// and an Enter Manually link into the word-by-word wizard.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({super.key});

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen> {
  List<String> _words = const [];
  String? _error;

  Future<void> _paste() async {
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImport: ERROR reading clipboard: $e');
      if (mounted) {
        showAppToast(
          context,
          "Can't read clipboard data",
          iconName: AppIcons.cross,
        );
      }
      return;
    }
    final words = (text ?? '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    if (words.isEmpty) {
      if (!mounted) return;
      setState(() {
        _words = const [];
        _error = null;
      });
      showAppToast(context, 'Clipboard is empty', iconName: AppIcons.cross);
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
      progress: 0.2,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Import Your Wallet',
      subtitle:
          'Paste your Secret Passphrase or enter it manually word by '
          'word.',
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
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey('mobile_import_enter_manually'),
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/import/manual'),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.edit,
                        size: AppIconSize.medium,
                        color: colors.text.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Enter manually',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
