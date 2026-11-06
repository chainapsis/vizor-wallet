import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../main.dart' show log;
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'mobile_onboarding_scaffold.dart';

/// Mnemonic lengths the wallet accepts. The Figma frames show a fixed
/// 24-slot card; shorter standard phrases are accepted anyway and the
/// counter simply stops early (WIP-design gap filled deliberately).
const kMnemonicWordCounts = [12, 15, 18, 21, 24];
const kMnemonicMaxWords = 24;

/// Split arbitrary pasted/typed text into candidate BIP39 words. English
/// BIP39 words are pure lowercase a-z, so quotes, numbering, and punctuation
/// can all be treated as separators.
List<String> tokenizeMnemonicWords(String raw) => raw
    .toLowerCase()
    .split(RegExp(r'[^a-z]+'))
    .where((word) => word.isNotEmpty)
    .toList();

/// Validates a candidate phrase; returns an error message or null.
const _kMnemonicCheckFailedMessage =
    "That passphrase couldn't be checked. Try again."; // l10n-ignore: compared with == and returned by a context-free validator

String? validateImportedMnemonic(List<String> words) {
  if (!kMnemonicWordCounts.contains(words.length)) {
    return 'A secret passphrase has 12, 15, 18, 21, or 24 words — ' // l10n-ignore: context-free validator
        'found ${words.length}.';
  }
  try {
    if (!rust_wallet.validateMnemonic(mnemonic: words.join(' '))) {
      return 'These words are valid, but they do not form a valid secret ' // l10n-ignore: context-free validator
          'passphrase. Check the order or replace any word that looks wrong.';
    }
  } catch (e) {
    log('validateImportedMnemonic: ERROR: $e');
    return _kMnemonicCheckFailedMessage;
  }
  return null;
}

enum _ImportPasteState { idle, reading }

const _kImportManualCardHeight = 385.0;
const _kImportManualCardColumns = 3;
const _kImportManualWordLineHeight = 24.0;
const _kImportManualWordIndexWidth = 24.0;
const _kImportManualWordIndexStyle = TextStyle(
  fontFamily: 'Geist Mono',
  fontWeight: FontWeight.w500,
  fontSize: 15,
  height: 21 / 15,
);

/// Import entry — Figma `Import — Secret Passprhase Paste`: manual entry is
/// the primary card, while clipboard import sits in the pinned bottom action.
/// A valid paste advances directly to the review step.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({
    this.initialPreviewError,
    this.initialPreviewErrorDuration = AppToast.defaultDuration,
    this.readClipboardText,
    this.validatePastedWords,
    super.key,
  });

  /// Widgetbook/test seam for rendering the Figma clipboard-error state.
  @visibleForTesting
  final String? initialPreviewError;

  @visibleForTesting
  final Duration initialPreviewErrorDuration;

  /// Deterministic preview boundaries; production uses the clipboard and Rust.
  final Future<String?> Function()? readClipboardText;
  final String? Function(List<String> words)? validatePastedWords;

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen> {
  var _pasteState = _ImportPasteState.idle;
  var _initialPreviewToastShown = false;

  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initialError = widget.initialPreviewError;
    if (_initialPreviewToastShown || initialError == null) return;
    _initialPreviewToastShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppToast(
        context,
        initialError,
        duration: widget.initialPreviewErrorDuration,
        iconName: AppIcons.cancel,
        tone: AppToastTone.destructive,
      );
    });
  }

  Future<void> _paste() async {
    if (_pasteState == _ImportPasteState.reading) return;
    setState(() => _pasteState = _ImportPasteState.reading);

    String? text;
    try {
      text = widget.readClipboardText != null
          ? await widget.readClipboardText!()
          : (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImport: ERROR reading clipboard: $e');
      if (!mounted) return;
      setState(() => _pasteState = _ImportPasteState.idle);
      if (!_isCurrentRoute) return;
      showAppToast(
        context,
        context.l10n.onboardingImportClipboardReadError,
        iconName: AppIcons.cancel,
        tone: AppToastTone.destructive,
      );
      return;
    }

    final words = tokenizeMnemonicWords(text ?? '');
    if (words.isEmpty) {
      if (!mounted) return;
      setState(() => _pasteState = _ImportPasteState.idle);
      if (!_isCurrentRoute) return;
      showAppToast(
        context,
        context.l10n.onboardingImportClipboardEmpty,
        iconName: AppIcons.cancel,
        tone: AppToastTone.destructive,
      );
      return;
    }

    final pasteError = _validatePastedMnemonic(words);
    if (pasteError == null) {
      if (!mounted) return;
      setState(() => _pasteState = _ImportPasteState.idle);
      if (!_isCurrentRoute) return;
      context.pushOnboarding(
        '/import/review',
        extra: ImportSecretPassphraseArgs(mnemonic: words.join(' ')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _pasteState = _ImportPasteState.idle);
    if (!_isCurrentRoute) return;
    showAppToast(
      context,
      pasteError,
      iconName: AppIcons.cancel,
      tone: AppToastTone.destructive,
    );
  }

  String? _validatePastedMnemonic(List<String> words) {
    final validate = widget.validatePastedWords;
    if (validate != null) return validate(words);
    if (!kMnemonicWordCounts.contains(words.length)) {
      return context.l10n.onboardingImportNoPhraseError;
    }

    try {
      final wordList = rust_wallet.mnemonicWordList().toSet();
      if (wordList.isNotEmpty && !words.every(wordList.contains)) {
        return context.l10n.onboardingImportNoPhraseError;
      }
    } catch (e) {
      log('MobileImport: ERROR reading mnemonic word list: $e');
      return context.l10n.onboardingImportCheckFailedError;
    }

    final error = validateImportedMnemonic(words);
    if (error == null) return null;
    if (error == _kMnemonicCheckFailedMessage) {
      return context.l10n.onboardingImportCheckFailedError;
    }
    return context.l10n.onboardingImportInvalidPhraseError;
  }

  void _openManual() {
    context.pushOnboarding('/import/manual');
  }

  @override
  Widget build(BuildContext context) {
    final isReading = _pasteState == _ImportPasteState.reading;
    return MobileOnboardingStepScaffold(
      progress: MobileOnboardingProgressScope.of(
        context,
      ).at(OnboardingFlow.importWallet, OnboardingStage.phraseEntry).value,
      onBack: () => Navigator.of(context).maybePop(),
      title: context.l10n.onboardingImportWalletTitleMobile,
      subtitle: context.l10n.onboardingImportPasteHelper,
      bottomArea: _ImportPasteButton(state: _pasteState, onPaste: _paste),
      child: _ImportManualSeedCard(onTap: isReading ? null : _openManual),
    );
  }
}

class _ImportManualSeedCard extends StatelessWidget {
  const _ImportManualSeedCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final homeText = colors.text.homeCard;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.l10n.onboardingImportEnterManuallySemantics,
      child: GestureDetector(
        key: const ValueKey('mobile_import_enter_manually'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: const ValueKey('mobile_import_manual_card'),
          width: double.infinity,
          height: _kImportManualCardHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.xLarge),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _ImportManualFadedWords()),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.51,
                      colors: [
                        colors.background.homeCard,
                        colors.background.homeCard,
                        colors.background.homeCard.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.1827, 1],
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  key: const ValueKey('mobile_import_manual_card_content'),
                  opacity: enabled ? 1 : 0.25,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.edit,
                        size: AppIconSize.large,
                        color: homeText,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: 255,
                        child: Text(
                          context.l10n.onboardingImportManualCardTitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLarge.copyWith(
                            color: homeText,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        context.l10n.onboardingImportManualCardSubtitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: homeText.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportManualFadedWords extends StatelessWidget {
  const _ImportManualFadedWords();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      key: const ValueKey('mobile_import_manual_placeholder_fade'),
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x2EFFFFFF),
          Color(0x00FFFFFF),
          Color(0x2EFFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
        ],
        stops: [0, 0.15, 0.34, 0.5, 0.66, 0.85, 1],
      ).createShader(rect),
      child: const _ImportManualWordPlaceholders(),
    );
  }
}

class _ImportManualWordPlaceholders extends StatelessWidget {
  const _ImportManualWordPlaceholders();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lineColor = colors.text.homeCard.withValues(alpha: 0.24);
    final labelColor = colors.text.homeCard.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        32.5,
        AppSpacing.md,
        AppSpacing.base,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth =
              (constraints.maxWidth -
                  (AppSpacing.xs * (_kImportManualCardColumns - 1))) /
              _kImportManualCardColumns;
          return Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.sm,
            children: [
              for (
                var wordIndex = 1;
                wordIndex <= kMnemonicMaxWords;
                wordIndex++
              )
                SizedBox(
                  key: ValueKey(
                    'mobile_import_manual_placeholder_cell_$wordIndex',
                  ),
                  width: itemWidth,
                  height: _kImportManualWordLineHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: SizedBox(
                          width: _kImportManualWordIndexWidth,
                          child: Text(
                            key: ValueKey(
                              'mobile_import_manual_placeholder_index_$wordIndex',
                            ),
                            wordIndex.toString().padLeft(2, '0'),
                            style: _kImportManualWordIndexStyle.copyWith(
                              color: labelColor,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: _kImportManualWordIndexWidth + AppSpacing.xs,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          key: ValueKey(
                            'mobile_import_manual_placeholder_line_$wordIndex',
                          ),
                          decoration: BoxDecoration(color: lineColor),
                          child: const SizedBox(height: 1),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ImportPasteButton extends StatelessWidget {
  const _ImportPasteButton({required this.state, required this.onPaste});

  final _ImportPasteState state;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final isReading = state == _ImportPasteState.reading;
    return AppButton(
      key: const ValueKey('mobile_import_paste'),
      expand: true,
      constrainContent: true,
      onPressed: isReading ? null : onPaste,
      leading: AppIcon(isReading ? AppIcons.loader : AppIcons.paste, size: 20),
      child: Text(
        isReading
            ? context.l10n.onboardingImportReadingClipboard
            : context.l10n.onboardingImportPasteFromClipboard,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
