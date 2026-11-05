import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/navigation/payment_uri_drain_policy.dart';
import '../../../core/zcash/zip321_payment_request.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../address_scan/widgets/mobile_address_scan_view.dart';
import '../models/send_prefill_args.dart';

typedef PaymentRequestScanner =
    Future<SendPrefillArgs?> Function(
      BuildContext context, {
      required GoRouter router,
      required String networkName,
    });

final paymentRequestScannerProvider = Provider<PaymentRequestScanner>((ref) {
  return (context, {required router, required networkName}) {
    if (kAppFormFactor == AppFormFactor.desktop) {
      return router.push<SendPrefillArgs>(
        Uri(
          path: '/send/request-scan',
          queryParameters: {'network': networkName},
        ).toString(),
      );
    }
    return showPaymentRequestScanSheet(context, networkName: networkName);
  };
});

Future<SendPrefillArgs?> showPaymentRequestScanSheet(
  BuildContext context, {
  required String networkName,
  MobileScannerController? controller,
}) {
  SendPrefillArgs? decoded;
  var finished = false;
  return showAppMobileSheet<SendPrefillArgs>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      void complete(SendPrefillArgs? result) {
        // A dismissed sheet remains mounted during its reverse transition.
        // Its late validation must not pop the screen underneath it.
        if (finished ||
            !sheetContext.mounted ||
            ModalRoute.of(sheetContext)?.isCurrent != true) {
          return;
        }
        finished = true;
        Navigator.of(sheetContext).pop(result);
      }

      return MobileAddressScanCard(
        controller: controller,
        resolve: (raw) async {
          try {
            decoded = await decodePaymentRequestQr(
              raw,
              networkName: networkName,
            );
            return MobileScanOutcome.accepted(decoded!.address);
          } on PaymentRequestQrException catch (error) {
            decoded = null;
            return MobileScanOutcome.rejected(error.issue.text(l10n));
          } catch (_) {
            decoded = null;
            return MobileScanOutcome.rejected(l10n.sendRequestScanCheckFailed);
          }
        },
        onScanned: (_) => complete(decoded),
        onClose: () => complete(null),
      );
    },
  );
}

/// Why a scanned QR code was refused. The scan surfaces resolve it with
/// [text] in the locale they are shown in.
enum PaymentRequestQrIssue {
  unsupportedRequest,
  invalidRequest,
  notRequest,
  wrongNetwork,
  invalidAddress;

  String text(AppLocalizations l10n) => switch (this) {
    unsupportedRequest => PaymentUriNotice.unsupported.text(l10n),
    invalidRequest => l10n.sendRequestScanInvalidRequest,
    notRequest => l10n.sendRequestScanNotRequest,
    wrongNetwork => l10n.sendRequestScanWrongNetwork,
    invalidAddress => l10n.sendRequestScanInvalidAddress,
  };
}

class PaymentRequestQrException implements Exception {
  const PaymentRequestQrException(this.issue);

  final PaymentRequestQrIssue issue;

  @override
  String toString() => 'PaymentRequestQrException($issue)';
}

var _scanSequence = 0;

/// A re-scan replaces the entire request. Unsupported payment terms must not
/// silently downgrade to an address, or retain fields from the external link.
SendPrefillArgs parsePaymentRequestQr(String raw) {
  final input = raw.trim();
  final id = 'payment-rescan-${++_scanSequence}';
  if (input.toLowerCase().startsWith('zcash:')) {
    try {
      final request = Zip321PaymentRequest.parse(input);
      if (!request.isSupported) {
        throw const PaymentRequestQrException(
          PaymentRequestQrIssue.unsupportedRequest,
        );
      }
      return sendPrefillArgsFromZip321Payment(
        id: id,
        payment: request.primaryPayment,
      ).withRequestSource(PaymentRequestSource.qrCode);
    } on Zip321ParseException {
      throw const PaymentRequestQrException(
        PaymentRequestQrIssue.invalidRequest,
      );
    }
  }
  final uri = Uri.tryParse(input);
  if (input.isEmpty || uri == null || uri.hasScheme) {
    throw const PaymentRequestQrException(PaymentRequestQrIssue.notRequest);
  }
  return SendPrefillArgs(
    id: id,
    source: kPaymentUriPrefillSource,
    address: input,
    requestSource: PaymentRequestSource.qrCode,
  );
}

Future<SendPrefillArgs> decodePaymentRequestQr(
  String raw, {
  required String networkName,
}) async {
  final prefill = parsePaymentRequestQr(raw);
  final address = await rust_sync.validateAddress(
    address: prefill.address,
    network: networkName,
  );
  if (!address.isValid) {
    throw PaymentRequestQrException(
      address.wrongNetwork
          ? PaymentRequestQrIssue.wrongNetwork
          : PaymentRequestQrIssue.invalidAddress,
    );
  }
  return prefill;
}
