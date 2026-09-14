import '../../../../core/navigation/payment_request_intake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../address_scan/domain/address_input_policy.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;
import '../../models/send_scan_result.dart';
import '../../services/send_address_input.dart';

/// Presents the mobile send scanner over the current send screen — Figma
/// `QR Scan` (4484:61584): a card-contained back camera scanner over the
/// dimmed app. Pops what the scan turned out to be: a bare recipient, or a
/// ZIP-321 payment request the caller hands to the payment-request card.
///
/// [networkName] is the caller's opening network. While the sheet is open,
/// the provider's active network and account keep its validation context fresh;
/// a result from the previous context must not close the sheet.
Future<SendScanResult?> showMobileSendScanSheet(
  BuildContext context, {
  required String networkName,
  MobileScannerController? controller,
  MobileScanResolver? resolve,
}) {
  (String, String?, int)? openingContext;
  var closing = false;
  return showAppMobileSheet<SendScanResult>(
    context: context,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final activeNetwork = ref.watch(rpcEndpointProvider).networkName;
        final account = ref.watch(
          accountProvider.select((value) => value.value?.activeAccountUuid),
        );
        final arrival = ref.watch(paymentRequestArrivalProvider);
        openingContext ??= (networkName, account, arrival);
        if (!closing && openingContext != (activeNetwork, account, arrival)) {
          closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (sheetContext.mounted &&
                (ModalRoute.of(sheetContext)?.isCurrent ?? false)) {
              Navigator.of(sheetContext).pop();
            }
          });
        }
        final resolver =
            resolve ??
            (raw) =>
                resolveScannedZcashAddress(raw, networkName: activeNetwork);
        String? acceptedRaw;
        return MobileAddressScanCard(
          validationContext: (activeNetwork, account, arrival),
          caption: 'Scan an address or payment request QR code',
          controller: controller,
          resolve: (raw) async {
            final outcome = await resolver(raw);
            acceptedRaw = outcome.isAccepted ? raw : null;
            return outcome;
          },
          onScanned: (address) {
            if (closing) return;
            final raw = acceptedRaw ?? address;
            final result = resolveSendScanPayload(
              raw,
              acceptedAddress: address,
            );
            if (result == null) return;
            Navigator.of(sheetContext).pop(result);
          },
          onClose: () => Navigator.of(sheetContext).pop(),
        );
      },
    ),
  );
}

/// The sheet's default resolver: what a scanned code has to be for the send
/// flow to accept it. Public so it can be exercised on its own — the scanner
/// itself is a camera, and the decision it feeds is the part worth pinning.
///
/// [networkName] is the network the wallet is on; an address for any other
/// network is refused, and named as such.
Future<MobileScanOutcome> resolveScannedZcashAddress(
  String raw, {
  required String networkName,
}) async {
  final result = await resolveSendAddressInput(raw, networkName: networkName);
  return switch (result.kind) {
    AddressInputResultKind.address => MobileScanOutcome.accepted(
      result.address!,
    ),
    AddressInputResultKind.paymentRequest => MobileScanOutcome.accepted(
      result.zcashRequest!.primaryPayment.address,
    ),
    AddressInputResultKind.rejected => MobileScanOutcome.rejected(
      result.reason!,
    ),
  };
}
