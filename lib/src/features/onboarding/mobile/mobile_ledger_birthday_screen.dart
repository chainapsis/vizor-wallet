import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../ledger/ledger_setup_args.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_import_birthday_screen.dart';

class MobileLedgerBirthdayScreen extends StatelessWidget {
  const MobileLedgerBirthdayScreen({
    required this.args,
    this.loadChainMetadata = true,
    super.key,
  });

  final LedgerBirthdayArgs args;
  final bool loadChainMetadata;

  @override
  Widget build(BuildContext context) {
    return MobileImportBirthdayScreen(
      args: const ImportBirthdayArgs(mnemonic: ''),
      progress: 0.5,
      loadChainMetadata: loadChainMetadata,
      onHeightConfirmed: (height) async {
        if (!context.mounted) return;
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
