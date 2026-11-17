import '../../../core/l10n/l10n.dart';
import '../../address_book/models/address_book_contact.dart';
import '../domain/address_scan_resolution.dart';
import 'mobile_address_scan_view.dart';

/// The resolver of a scanner opened from an address field on [network]: Swap,
/// Pay and the address book. Rejections are worded for the scanner.
MobileScanResolver addressScanResolver(
  AppLocalizations l10n, {
  required AddressBookNetwork? network,
}) {
  return (raw) async => switch (resolveAddressScan(raw, network: network)) {
    AddressScanAccepted(:final address) => MobileScanOutcome.accepted(address),
    AddressScanRejected(
      :final reason,
      :final finding,
      network: final codeNetwork,
    ) =>
      MobileScanOutcome.rejected(switch (reason) {
        AddressScanRejection.unsupported => l10n.commonQrNoAddress,
        // Naming the chain lets the user pick it instead.
        AddressScanRejection.wrongNetwork =>
          codeNetwork == null
              ? l10n.addressScanWrongNetwork
              : l10n.addressScanWrongNetworkNamed(codeNetwork.label),
        AddressScanRejection.invalidAddress =>
          finding?.localizedMessage(l10n) ?? l10n.commonQrNoAddress,
      }),
  };
}
