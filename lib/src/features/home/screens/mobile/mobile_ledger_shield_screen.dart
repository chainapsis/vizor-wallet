import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/ledger_shield_signing_overlay.dart';
import '../../widgets/mobile/shield/mobile_shield_backdrop.dart';

class MobileLedgerShieldResult {
  const MobileLedgerShieldResult.succeeded();
}

class MobileLedgerShieldScreen extends StatelessWidget {
  const MobileLedgerShieldScreen({this.backdrop, super.key});
  final MobileShieldBackdrop? backdrop;

  @override
  Widget build(BuildContext context) {
    return LedgerShieldSigningOverlay(
      mobile: true,
      mobileBackdrop: backdrop,
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
