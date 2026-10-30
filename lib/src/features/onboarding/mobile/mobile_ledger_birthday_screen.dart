import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import '../ledger/ledger_setup_args.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_birthday_screen.dart';

class MobileLedgerBirthdayScreen extends ConsumerWidget {
  const MobileLedgerBirthdayScreen({
    required this.args,
    this.loadChainMetadata = true,
    super.key,
  });

  final LedgerBirthdayArgs args;
  final bool loadChainMetadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MobileImportBirthdayScreen(
      args: const ImportBirthdayArgs(mnemonic: ''),
      position: MobileOnboardingProgressScope.of(
        context,
      ).at(OnboardingFlow.ledger, OnboardingStage.birthday),
      loadChainMetadata: loadChainMetadata,
      onHeightConfirmed: (height) async {
        if (!context.mounted) return;
        final setupArgs = SetPasswordScreenArgs.importLedger(
          account: args.account,
          birthdayHeight: height,
        );
        context.pushOnboarding(
          '/onboarding/customise-account',
          extra: CustomiseAccountArgs(setupArgs: setupArgs),
        );
      },
    );
  }
}
