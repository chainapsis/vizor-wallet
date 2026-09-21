import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/ledger_shield_signing_overlay.dart';

class MobileLedgerShieldResult {
  const MobileLedgerShieldResult.succeeded();
}

class MobileLedgerShieldScreen extends StatelessWidget {
  const MobileLedgerShieldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LedgerShieldSigningOverlay(
      mobile: true,
      onCancel: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      onComplete: () {
        if (context.canPop()) {
          context.pop(const MobileLedgerShieldResult.succeeded());
        } else {
          context.go('/home');
        }
      },
    );
  }
}
