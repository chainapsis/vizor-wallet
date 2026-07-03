import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/platform/screenshot_observer.dart';
import '../../../core/privacy/route_coverage_aware.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../settings/screens/mobile/mobile_seed_phrase_screen.dart'
    show MobileSeedScreenshotWarningSheet;
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
List<String> tokenizeMnemonicWords(String raw) => raw
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

/// Import entry — Figma `Import — Secret Passprhase Paste` /
/// `Clipboard Errors` (4575:108577 / 4575:108752): the empty numbered
/// slots with a paste action, clipboard problems surfaced as toasts,
/// and an Enter Manually link into the word-by-word wizard.
class MobileImportScreen extends StatefulWidget {
  const MobileImportScreen({
    this.screenshotStream,
    this.privacyOverlayController,
    super.key,
  });

  /// Test seam — production listens to the platform screenshot events.
  @visibleForTesting
  final Stream<void>? screenshotStream;

  @visibleForTesting
  final SensitivePrivacyOverlayController? privacyOverlayController;

  @override
  State<MobileImportScreen> createState() => _MobileImportScreenState();
}

class _MobileImportScreenState extends State<MobileImportScreen>
    with RouteCoverageAware<MobileImportScreen> {
  List<String> _words = const [];
  String? _error;

  StreamSubscription<void>? _screenshotSub;
  bool _screenshotSheetShowing = false;
  late final bool _ownsPrivacyController;
  late final SensitivePrivacyOverlayController _privacyController;

  @override
  void initState() {
    super.initState();
    _ownsPrivacyController = widget.privacyOverlayController == null;
    _privacyController =
        widget.privacyOverlayController ??
        SensitivePrivacyEnvironmentController();
    _screenshotSub = (widget.screenshotStream ?? screenshotEvents()).listen(
      (_) => _onScreenshot(),
    );
  }

  @override
  void dispose() {
    _screenshotSub?.cancel();
    if (_ownsPrivacyController) _privacyController.dispose();
    super.dispose();
  }

  Future<void> _onScreenshot() async {
    // Only warn once pasted words are on screen — the empty paste form has
    // nothing to protect. Mirrors the reveal screens' _onScreenshot guard.
    if (_words.isEmpty ||
        _screenshotSheetShowing ||
        !_isCurrentRoute ||
        !mounted) {
      return;
    }
    _screenshotSheetShowing = true;
    // Suppress the privacy shield through the iOS screenshot preview/editor
    // flow — the native blanking already blacks out the capture, so the extra
    // blur flash is redundant noise.
    _privacyController.beginScreenshotSuppression();
    unawaited(AppHaptics.privacyToggle());
    try {
      await showAppMobileSheet<void>(
        context: context,
        builder: (_) => const MobileSeedScreenshotWarningSheet(),
      );
    } finally {
      _screenshotSheetShowing = false;
      // Release the shield suppression now the warning sheet is gone, so a
      // genuine later backgrounding still blurs.
      _privacyController.endScreenshotSuppression();
    }
  }

  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? true;

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
    final words = tokenizeMnemonicWords(text ?? '');
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
  }

  void _clear() {
    setState(() {
      _words = const [];
      _error = null;
    });
  }

  void _confirm() {
    // The shield stays engaged through the push transition and drops only once
    // this screen is fully covered (RouteCoverageAware), so birthday and the
    // screens after it are not blanked while the seed is no longer visible.
    context.push(
      '/import/birthday',
      extra: ImportBirthdayArgs(mnemonic: _words.join(' ')),
    );
  }

  void _openManual() {
    context.push('/import/manual');
  }

  bool get _filled => _words.isNotEmpty && _error == null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SensitivePrivacyOverlay(
      // Protect only once words are on screen — the empty paste form has
      // nothing to blank. Matches the `_onScreenshot` guard. Drops once a next
      // step has fully covered this screen so it does not blank those screens.
      sensitiveContentVisible: _words.isNotEmpty && !isCoveredByNextRoute,
      controller: _privacyController,
      child: MobileOnboardingStepScaffold(
        progress: mobileImportProgress(1),
        onBack: () => Navigator.of(context).maybePop(),
        title: 'Import Wallet',
        // Line break matches the Figma subtitle wrap.
        subtitle:
            'Paste your Secret Passphrase or\nenter it manually word by word.',
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
            if (_filled) ...[
              // Pasted state — Figma fills the slots in place and swaps
              // the actions for confirm / clear.
              AppButton(
                key: const ValueKey('mobile_import_confirm'),
                expand: true,
                onPressed: _confirm,
                trailing: const AppIcon(AppIcons.chevronForward),
                child: const Text('Confirm & import'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_import_clear'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _clear,
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        'Clear secret phrase',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              AppButton(
                key: const ValueKey('mobile_import_paste'),
                expand: true,
                onPressed: _paste,
                // No explicit icon color: AppButton's IconTheme tints it
                // with the label color (white on the primary fill).
                leading: const AppIcon(AppIcons.copy),
                child: const Text('Paste secret phrase'),
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey('mobile_import_enter_manually'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openManual,
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
          ],
        ),
        // VZR-71: users instinctively tap the slot grid expecting to
        // type — route the tap into the manual wizard, same as the Enter
        // manually link. Once a valid phrase fills the card it is a
        // confirmed phrase surface and the tap is disabled.
        child: _filled
            ? ImportSlotsCard(words: _words)
            : Semantics(
                button: true,
                label: 'Enter secret phrase manually',
                child: GestureDetector(
                  key: const ValueKey('mobile_import_slots'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openManual,
                  child: ImportSlotsCard(words: _words),
                ),
              ),
      ),
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
            // 8 px between rows puts the underlines on the 37 px pitch
            // of the Figma slot grid.
            if (row > 0) const SizedBox(height: AppSpacing.xs),
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
