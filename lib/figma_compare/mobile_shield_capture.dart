import '../src/features/home/widgets/mobile/shield/keystone_shield_morph.dart';
import 'keystone_shield_capture.dart';
import 'package:flutter/widgets.dart';
import '../src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import '../src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import '../src/features/ledger/widgets/mobile/mobile_ledger_signing_content.dart';
import '../src/features/ledger/services/ledger_signing_progress.dart';
import '../src/features/ledger/services/ledger_app_readiness_service.dart';

Widget buildMobileShieldReview(BuildContext context) => const MobileShieldScene(
  phase: MobileShieldPhase.review,
  amount: '0.9912331',
  resultAmount: '0.9911331',
  title: 'Transparent Balance',
  onCommit: _noop,
  onClose: _noop,
);
Widget buildMobileShieldCloud(BuildContext context) => const MobileShieldScene(
  phase: MobileShieldPhase.working,
  amount: '0.9912331',
  title: 'Shielding your balance…',
  canLeave: false,
);
Widget buildMobileShieldResult(BuildContext context) => const MobileShieldScene(
  phase: MobileShieldPhase.succeeded,
  amount: '0.9912331',
  resultAmount: '0.9911331',
  title: 'Shielded successfully',
  onComplete: _noop,
  onClose: _noop,
);
Widget buildMobileShieldKeystone(BuildContext context) => MobileShieldScene(
  phase: MobileShieldPhase.hardware,
  amount: '0.9912331',
  title: 'Approve with Keystone',
  keystoneFocus: KeystoneShieldFocus(
    stage: KeystoneShieldFocusStage.qr,
    urParts: keystoneShieldPreviewParts,
    scannerBuilder: (_, _) => const SizedBox.shrink(),
  ),
  onClose: _noop,
);
Widget buildMobileShieldLedger(BuildContext context) => const MobileShieldScene(
  phase: MobileShieldPhase.hardware,
  amount: '0.9912331',
  title: 'Shield with Ledger',
  focusChild: LedgerInlinePresentation(
    child: MobileLedgerSigningContent(
      title: 'Check your Ledger',
      message: 'Review and approve when prompted on your Ledger.',
      status: 'Review on device',
      active: true,
      failed: false,
      stage: LedgerSigningStage.reviewing,
      readiness: LedgerAppReadinessPhase.ready,
      saving: false,
      finishing: false,
      broadcasting: false,
      declined: false,
      roundNumber: 1,
      roundCount: 3,
      onClose: _noop,
      onAction: null,
    ),
  ),
  onClose: _noop,
);
void _noop() {}

Widget buildMobileShieldReferenceReview(BuildContext context) =>
    _referenceViewport(
      context,
      const MobileShieldScene(
        phase: MobileShieldPhase.review,
        amount: '14.12',
        resultAmount: '14.12',
        title: 'Transparent Balance',
        onCommit: _noop,
        onClose: _noop,
      ),
    );
Widget buildMobileShieldReferenceResult(BuildContext context) =>
    _referenceViewport(
      context,
      const MobileShieldScene(
        phase: MobileShieldPhase.succeeded,
        amount: '14.12',
        resultAmount: '14.12',
        title: 'Shielded successfully',
        onComplete: _noop,
        onClose: _noop,
      ),
    );

Widget _referenceViewport(BuildContext context, Widget child) => MediaQuery(
  data: MediaQuery.of(
    context,
  ).copyWith(padding: const EdgeInsets.only(top: 59, bottom: 34)),
  child: child,
);
