import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_scan/domain/address_scan_payload.dart';
import '../../../address_scan/widgets/mobile_address_scan_view.dart';

/// Address scanner for the mobile send flow — Figma `Mobile Scanner`
/// (4484:58700): full-bleed back camera under a dark scrim with the
/// shared scan chrome. Pops the scanned Zcash address string on success.
class MobileSendScanScreen extends StatelessWidget {
  const MobileSendScanScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MobileAddressScanView(
        resolve: _resolveZcashAddress,
        onScanned: (address) => context.pop(address),
        onClose: () => context.pop(),
      ),
    );
  }
}
