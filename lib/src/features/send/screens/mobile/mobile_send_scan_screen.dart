import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome, MobileScanResolver;

import '../../../../../l10n/app_localizations.dart';

/// Presents the mobile send scanner over the current send screen — Figma
/// `QR Scan` (4484:61584): a card-contained back camera scanner over the
/// dimmed app. Pops the scanned Zcash address string on success.
Future<String?> showMobileSendScanSheet(
  BuildContext context, {
  MobileScannerController? controller,
  MobileScanResolver? resolve,
}) {
  return showAppMobileSheet<String>(
    context: context,
    builder: (sheetContext) => MobileAddressScanCard(
      controller: controller,
      resolve:
          resolve ?? (raw) => _resolveZcashAddress(context, raw),
      onScanned: (address) => Navigator.of(sheetContext).pop(address),
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

Future<MobileScanOutcome> _resolveZcashAddress(
  BuildContext context,
  String raw,
) async {
  // Resolve the copy before any await: the sheet context can go stale while
  // the Rust validation runs.
  final notZcashMessage = AppLocalizations.of(context).sendQrNotZcash;
  final address = normalizeAddressScanPayload(raw);
  if (address == null || address.isEmpty) {
    return MobileScanOutcome.rejected(notZcashMessage);
  }
  final result = await rust_sync.validateAddress(address: address);
  if (result.isValid) return MobileScanOutcome.accepted(address);
  return MobileScanOutcome.rejected(notZcashMessage);
}
