import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_scaffold.dart';

/// Mnemonic lengths the wallet accepts. The Figma frames show a fixed
/// 24-slot card; shorter standard phrases are accepted anyway and the
/// counter simply stops early (WIP-design gap filled deliberately).
const kMnemonicWordCounts = [12, 15, 18, 21, 24];
const kMnemonicMaxWords = 24;

/// Split arbitrary pasted/typed text into candidate BIP39 words. English
/// BIP39 words are pure lowercase a-z, so quotes, numbering, and punctuation
/// can all be treated as separators.
List<String> tokenizeMnemonicWords(String raw) =>
    raw
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((word) => word.isNotEmpty)
        .toList();

/// Validates a candidate phrase; returns an error message or null.
String? validateImportedMnemonic(List<String> words) {
  if (!kMnemonicWordCounts.contains(words.length)) {
    return 'A secret passphrase has 12, 15, 18, 21, or 24 words — '
        'found ${words.length}.';
  }
  try {
    if (!rust_wallet.validateMnemonic(mnemonic: words.join(' '))) {
      return 'These words are valid, but they do not form a valid secret '
          'passphrase. Check the order or replace any word that looks wrong.';
    }
  } catch (e) {
    log('validateImportedMnemonic: ERROR: $e');
    return "That passphrase couldn't be checked. Try again.";
  }
  return null;
}

enum _ImportPasteState { idle, reading, error }

const _kImportClipboardDataErrorMessage = "Can't read clipboard data";
const _kImportPasteHelperText =
    'Accept 12, 15, 18, 21 or 24-length Secret Passphrases';
const _kImportPasteCardHeight = 390.0;
const _kImportPasteCardTextWidth = 217.0;

/// Import entry — Figma `Import — Secret Passprhase Paste`: the primary
/// surface is a dark clipboard card, with a manual word-by-word escape hatch
/// beneath it. A valid paste advances directly to the review step.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({this.initialPreviewError, super.key});

  /// Widgetbook/test seam for rendering the Figma clipboard-error state.
  @visibleForTesting
  final String? initialPreviewError;

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen> {
  var _pasteState = _ImportPasteState.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialError = widget.initialPreviewError;
    if (initialError != null) {
      _pasteState = _ImportPasteState.error;
      _error = initialError;
    }
  }

  Future<void> _paste() async {
    if (_pasteState == _ImportPasteState.reading) return;
    setState(() {
      _pasteState = _ImportPasteState.reading;
      _error = null;
    });

    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (e) {
      log('MobileImport: ERROR reading clipboard: $e');
      if (!mounted) return;
      setState(() {
        _pasteState = _ImportPasteState.error;
        _error = _kImportClipboardDataErrorMessage;
      });
      return;
    }

    final words = tokenizeMnemonicWords(text ?? '');
    if (words.isEmpty) {
      if (!mounted) return;
      setState(() {
        _pasteState = _ImportPasteState.idle;
        _error = null;
      });
      showAppToast(context, 'Clipboard is empty', iconName: AppIcons.cross);
      return;
    }

    final error = validateImportedMnemonic(words);
    if (error == null) {
      if (!mounted) return;
      setState(() {
        _pasteState = _ImportPasteState.idle;
        _error = null;
      });
      context.push(
        '/import/review',
        extra: ImportSecretPassphraseArgs(mnemonic: words.join(' ')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _pasteState = _ImportPasteState.error;
      _error = _kImportClipboardDataErrorMessage;
    });
  }

  void _openManual() {
    context.push('/import/manual');
  }

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: mobileImportProgress(1),
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Import Wallet',
      // Line break matches the Figma subtitle wrap.
      subtitle:
          'Paste your Secret Passphrase or\nenter it manually word by word.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ImportClipboardCard(
            state: _pasteState,
            error: _error,
            onPaste: _pasteState == _ImportPasteState.reading ? null : _paste,
          ),
          const SizedBox(height: AppSpacing.base),
          _ManualImportLink(onTap: _openManual),
        ],
      ),
    );
  }
}

class _ImportClipboardCard extends StatelessWidget {
  const _ImportClipboardCard({
    required this.state,
    required this.error,
    required this.onPaste,
  });

  final _ImportPasteState state;
  final String? error;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isReading = state == _ImportPasteState.reading;
    final hasError = error != null;
    final titleText =
        hasError ? _kImportClipboardDataErrorMessage : 'Paste from clipboard';
    const bodyText = _kImportPasteHelperText;
    final buttonLabel =
        isReading
            ? 'Reading...'
            : hasError
            ? 'Try again'
            : 'Paste';

    return Container(
      key: const ValueKey('mobile_import_paste_card'),
      height: _kImportPasteCardHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(
            hasError ? AppIcons.warning : AppIcons.importWallet,
            size: 33,
            color:
                hasError
                    ? colors.icon.destructiveLight
                    : colors.text.homeCard.withValues(alpha: 0.55),
          ),
          const SizedBox(height: AppSpacing.base),
          SizedBox(
            width: _kImportPasteCardTextWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.text.homeCard,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  bodyText,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.homeCard.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          AppButton(
            key: const ValueKey('mobile_import_paste'),
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.mediumLarge,
            onPressed: onPaste,
            leading: AppIcon(
              isReading
                  ? AppIcons.loader
                  : hasError
                  ? AppIcons.renew
                  : AppIcons.copy,
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _ManualImportLink extends StatelessWidget {
  const _ManualImportLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('mobile_import_enter_manually'),
      variant: AppButtonVariant.ghost,
      expand: true,
      constrainContent: true,
      onPressed: onTap,
      leading: const AppIcon(AppIcons.edit),
      child: const Text(
        'Enter Secret Passphrase manually',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
