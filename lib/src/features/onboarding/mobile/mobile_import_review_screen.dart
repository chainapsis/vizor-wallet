import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_screens.dart';
import 'mobile_onboarding_scaffold.dart';
import 'seed_card.dart';

/// Import review — Figma `Review Secret Phrase` (4562:105084): the
/// filled word grid for a last look before picking the wallet birthday,
/// with an edit escape back to the entry screen.
class MobileImportReviewScreen extends StatelessWidget {
  const MobileImportReviewScreen({required this.args, super.key});

  final MobileImportReviewArgs args;

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.6,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Review Import',
      subtitle: 'Review your Secret Passphrase before import starts.',
      bottomArea: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            key: const ValueKey('mobile_import_review_continue'),
            expand: true,
            onPressed: () => context.push(
              '/import/birthday',
              extra: ImportBirthdayArgs(mnemonic: args.mnemonic),
            ),
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text('Confirm & continue'),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey('mobile_import_review_edit'),
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  Navigator.of(context).pop(ImportReviewResult.cleared),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Clear secret phrase',
                    style: AppTypography.labelLarge.copyWith(
                      color: context.colors.text.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: SeedCard(words: args.words, showTitle: false),
    );
  }
}
