import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;
import '../../models/send_scan_result.dart';

/// Presents the mobile send scanner over the current send screen — Figma
/// `QR Scan` (4484:61584): a card-contained back camera scanner over the
/// dimmed app. Pops what the scan turned out to be: a bare recipient, or a
/// ZIP-321 payment request the caller hands to the payment-request card.
Future<SendScanResult?> showMobileSendScanSheet(
  BuildContext context, {
  MobileScannerController? controller,
  MobileScanResolver? resolve,
}) {
  final resolver = resolve ?? _resolveZcashAddress;
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

Future<MobileScanOutcome> _resolveZcashAddress(String raw) async {
  final address = normalizeAddressScanPayload(raw);
  if (address == null || address.isEmpty) {
    return const MobileScanOutcome.rejected(
      "This QR code isn't a Zcash address.",
    );
  }
  final result = await rust_sync.validateAddress(address: address);
  if (result.isValid) return MobileScanOutcome.accepted(address);
  return const MobileScanOutcome.rejected(
    "This QR code isn't a Zcash address.",
  );
}
