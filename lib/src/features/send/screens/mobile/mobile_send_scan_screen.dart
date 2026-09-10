import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;
import '../../models/send_scan_result.dart';
import '../../services/send_flow.dart' show kWrongNetworkAddressMessage;

/// Presents the mobile send scanner over the current send screen — Figma
/// `QR Scan` (4484:61584): a card-contained back camera scanner over the
/// dimmed app. Pops what the scan turned out to be: a bare recipient, or a
/// ZIP-321 payment request the caller hands to the payment-request card.
///
/// [networkName] is the wallet's active network, which the caller reads from
/// `rpcEndpointProvider`. It is required rather than defaulted because the
/// build constant is only right for a wallet that never moved off it, and a
/// scanned address is refused outright when it belongs to another network.
Future<SendScanResult?> showMobileSendScanSheet(
  BuildContext context, {
  required String networkName,
  MobileScannerController? controller,
  MobileScanResolver? resolve,
}) {
  final resolver =
      resolve ??
      (raw) => resolveScannedZcashAddress(raw, networkName: networkName);
  // The card reports only the accepted address, but the ZIP-321 amount, memo
  // and label live in the payload around it. Keep the raw string the resolver
  // accepted so the pop value can be built from the whole request.
  String? acceptedRaw;

  return showAppMobileSheet<SendScanResult>(
    context: context,
    builder: (sheetContext) => MobileAddressScanCard(
      controller: controller,
      resolve: (raw) async {
        final outcome = await resolver(raw);
        acceptedRaw = outcome.isAccepted ? raw : null;
        return outcome;
      },
      onScanned: (address) {
        final result =
            resolveSendScanPayload(
              acceptedRaw ?? address,
              acceptedAddress: address,
            ) ??
            SendScanAddress(address);
        Navigator.of(sheetContext).pop(result);
      },
      onClose: () => Navigator.of(sheetContext).pop(),
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
  final address = normalizeAddressScanPayload(raw);
  if (address == null || address.isEmpty) {
    return const MobileScanOutcome.rejected(
      "This QR code isn't a Zcash address.",
    );
  }
  final result = await rust_sync.validateAddress(
    address: address,
    network: networkName,
  );
  if (result.isValid) return MobileScanOutcome.accepted(address);
  // A code that scanned cleanly and holds a real address for another network
  // is refused like any other unusable one, but saying "isn't a Zcash address"
  // about a Zcash address reads as a broken scanner.
  if (result.wrongNetwork) {
    return const MobileScanOutcome.rejected('$kWrongNetworkAddressMessage.');
  }
  return const MobileScanOutcome.rejected(
    "This QR code isn't a Zcash address.",
  );
}
