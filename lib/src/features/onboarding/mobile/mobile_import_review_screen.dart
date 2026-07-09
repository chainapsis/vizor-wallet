import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/platform/screenshot_observer.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_flow_args.dart';
import '../../settings/screens/mobile/mobile_seed_phrase_screen.dart'
    show MobileSeedScreenshotWarningSheet;
import 'mobile_onboarding_scaffold.dart';

const _kImportReviewProgress = 60 / 196;
const _kImportReviewSeedCardHeight = 385.0;
const _kImportReviewSeedChipWidth = 90.0;
const _kImportReviewSeedColumns = 3;
const _kImportReviewSeedCardPadding = EdgeInsets.fromLTRB(
  AppSpacing.md,
  AppSpacing.lg,
  AppSpacing.md,
  AppSpacing.xl,
);
const _kImportReviewDenseSeedCardPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.md,
  vertical: AppSpacing.md,
);

enum MobileImportReviewResult { clear }

/// Review step for software wallet import. Figma `Review Import`: after
/// clipboard paste or manual word entry, the user gets one final seed phrase
/// confirmation before birthday selection starts.
class MobileImportReviewScreen extends StatefulWidget {
  const MobileImportReviewScreen({
    required this.args,
    this.screenshotStream,
    this.privacyOverlayController,
    super.key,
  });

  final ImportSecretPassphraseArgs args;

  /// Test seam — production listens to the platform screenshot events.
  @visibleForTesting
  final Stream<void>? screenshotStream;

  @visibleForTesting
  final SensitivePrivacyOverlayController? privacyOverlayController;

  @override
  State<MobileImportReviewScreen> createState() =>
      _MobileImportReviewScreenState();
}

class _MobileImportReviewScreenState extends State<MobileImportReviewScreen> {
  StreamSubscription<void>? _screenshotSub;
  late final bool _ownsPrivacyController;
  late final SensitivePrivacyOverlayController _privacyController;
  bool _screenshotSheetShowing = false;

  List<String> get _words => widget.args.mnemonic
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

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

  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? true;

  Future<void> _onScreenshot() async {
    if (_screenshotSheetShowing || !_isCurrentRoute || !mounted) return;
    _screenshotSheetShowing = true;
    unawaited(AppHaptics.privacyToggle());
    try {
      await showAppMobileSheet<void>(
        context: context,
        builder: (_) => const MobileSeedScreenshotWarningSheet(),
      );
    } finally {
      _screenshotSheetShowing = false;
    }
  }

  void _continue(BuildContext context) {
    context.push(
      '/import/birthday',
      extra: ImportBirthdayArgs(mnemonic: widget.args.mnemonic),
    );
  }

  void _clear(BuildContext context) {
    if (context.canPop()) {
      context.pop(MobileImportReviewResult.clear);
      return;
    }
    context.go('/import');
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    return SensitivePrivacyOverlay(
      sensitiveContentVisible: words.isNotEmpty,
      controller: _privacyController,
      child: MobileOnboardingStepScaffold(
        progress: _kImportReviewProgress,
        onBack: () => Navigator.of(context).maybePop(),
        title: 'Review Import',
        subtitle: 'Review your secret passphrase\nbefore import starts.',
        bottomArea: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppButton(
              key: const ValueKey('mobile_import_review_clear'),
              variant: AppButtonVariant.ghost,
              expand: true,
              constrainContent: true,
              onPressed: () => _clear(context),
              child: const Text(
                'Clear secret passphrase',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              key: const ValueKey('mobile_import_review_continue'),
              expand: true,
              onPressed: () => _continue(context),
              trailing: const AppIcon(AppIcons.chevronForward),
              child: const Text('Confirm & continue'),
            ),
          ],
        ),
        child: MobileImportReviewSeedCard(words: words),
      ),
    );
  }
}

class MobileImportReviewSeedCard extends StatelessWidget {
  const MobileImportReviewSeedCard({required this.words, super.key});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardPadding = words.length > 18
        ? _kImportReviewDenseSeedCardPadding
        : _kImportReviewSeedCardPadding;
    return Container(
      key: const ValueKey('mobile_import_review_seed_card'),
      width: double.infinity,
      height: _kImportReviewSeedCardHeight,
      alignment: Alignment.center,
      padding: cardPadding,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: SizedBox(
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final chipWidth = _chipWidthFor(constraints.maxWidth);
            return Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (var index = 0; index < words.length; index++)
                  _wordChip(context, index, chipWidth),
              ],
            );
          },
        ),
      ),
    );
  }

  double _chipWidthFor(double availableWidth) {
    if (!availableWidth.isFinite) return _kImportReviewSeedChipWidth;
    final gapWidth = AppSpacing.s * (_kImportReviewSeedColumns - 1);
    final responsiveWidth =
        (availableWidth - gapWidth) / _kImportReviewSeedColumns;
    return math.min(
      _kImportReviewSeedChipWidth,
      math.max(0.0, responsiveWidth),
    );
  }

  Widget _wordChip(BuildContext context, int index, double width) {
    final colors = context.colors;
    return SizedBox(
      key: ValueKey('mobile_import_review_word_chip_${index + 1}'),
      width: width,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (index + 1).toString().padLeft(2, '0'),
              key: ValueKey('mobile_import_review_word_index_${index + 1}'),
              style: AppTypography.codeSmall.copyWith(color: colors.text.muted),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    words[index],
                    key: ValueKey('mobile_import_review_word_${index + 1}'),
                    maxLines: 1,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.homeCard,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
