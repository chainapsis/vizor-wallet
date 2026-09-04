import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;

/// Presents the mobile send scanner over the current send screen — Figma
/// `QR Scan` (4484:61584): a card-contained back camera scanner over the
/// dimmed app. Pops the scanned Zcash address string on success.
///
/// [networkName] is the wallet's active network, which the caller reads from
/// `rpcEndpointProvider`. It is required rather than defaulted because the
/// build constant is only right for a wallet that never moved off it, and a
/// scanned address is refused outright when it belongs to another network.
Future<String?> showMobileSendScanSheet(
  BuildContext context, {
  required String networkName,
  MobileScannerController? controller,
  MobileScanResolver? resolve,
}) {
  return showAppMobileSheet<String>(
    context: context,
    builder: (sheetContext) => MobileAddressScanCard(
      controller: controller,
      resolve:
          resolve ??
          (raw) => _resolveZcashAddress(raw, networkName: networkName),
      onScanned: (address) => Navigator.of(sheetContext).pop(address),
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

Future<MobileScanOutcome> _resolveZcashAddress(
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
  return const MobileScanOutcome.rejected(
    "This QR code isn't a Zcash address.",
  );
}
