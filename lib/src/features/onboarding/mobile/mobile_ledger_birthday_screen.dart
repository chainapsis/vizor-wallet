import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/app_security_provider.dart';
import '../ledger/ledger_setup_args.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_birthday_screen.dart';
import 'mobile_onboarding_progress.dart';

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
      progress: kMobileLedgerBirthdayProgress,
      loadChainMetadata: loadChainMetadata,
      onHeightConfirmed: (height) async {
        if (!context.mounted) return;
        if (!ref.read(appSecurityProvider).isPasswordConfigured) {
          context.push(
            '/onboarding/ledger/set-passcode',
            extra: LedgerSetPasswordArgs(
              account: args.account,
              birthdayHeight: height,
            ),
          );
          return;
        }
        context.push(
          '/onboarding/ledger/customise-account',
          extra: LedgerCustomiseAccountArgs(
            account: args.account,
            birthdayHeight: height,
          ),
        );
      },
    );
  }
}
