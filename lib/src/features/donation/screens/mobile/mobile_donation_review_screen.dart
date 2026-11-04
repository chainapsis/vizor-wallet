import 'package:flutter/widgets.dart';

import '../../../send/screens/mobile/mobile_send_screen.dart';
import '../../../send/services/send_flow.dart';
import '../../donation_config.dart';

class MobileDonationReviewArgs {
  const MobileDonationReviewArgs({
    required this.amountText,
    required this.sendFlowId,
  });

  final String amountText;
  final String sendFlowId;
}

/// Uses the ordinary mobile send's fee, cancellation and hardware-signing
/// lifecycle. Only the recipient and the review presentation are fixed.
class MobileDonationReviewScreen extends StatelessWidget {
  const MobileDonationReviewScreen({required this.args, super.key});

  final MobileDonationReviewArgs args;

  @override
  Widget build(BuildContext context) => MobileSendScreen(
    useRouteSteps: true,
    initialReview: true,
    initialAmountReady: true,
    refreshReviewFeeOnInit: true,
    initialSendFlowId: args.sendFlowId,
    initialRecipient: kVizorDonationAddress,
    initialAddressType: 'unified',
    initialAmount: args.amountText,
    flowKind: SendFlowKind.donation,
  );
}
