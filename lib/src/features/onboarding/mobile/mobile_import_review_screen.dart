import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_button.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_screens.dart';
import 'mobile_onboarding_scaffold.dart';
import 'seed_card.dart';

/// Import review — Figma `Review Secret Passphrase` (4562:105084): the
/// filled SeedCard for a last look before picking the wallet birthday.
class MobileImportReviewScreen extends StatelessWidget {
  const MobileImportReviewScreen({required this.args, super.key});

  final MobileImportReviewArgs args;

  @override
  Widget build(BuildContext context) {
    return MobileOnboardingStepScaffold(
      progress: 0.6,
      onBack: () => Navigator.of(context).maybePop(),
      title: 'Review Secret Passphrase',
      subtitle: 'Review before the import.',
      bottomArea: AppButton(
        key: const ValueKey('mobile_import_review_continue'),
        onPressed: () => context.push(
          '/import/birthday',
          extra: ImportBirthdayArgs(mnemonic: args.mnemonic),
        ),
        child: const Text('Continue'),
      ),
      child: SeedCard(words: args.words),
    );
  }
}
