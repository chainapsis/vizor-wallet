import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

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
          } on FormatException catch (error) {
            decoded = null;
            return MobileScanOutcome.rejected(error.message);
          } catch (_) {
            decoded = null;
            return const MobileScanOutcome.rejected(
              "Couldn't check this QR code. Try again.",
            );
          }
        },
        onScanned: (_) => complete(decoded),
        onClose: () => complete(null),
      );
    },
  );
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
        throw const FormatException(kPaymentUriUnsupportedMessage);
      }
      return sendPrefillArgsFromZip321Payment(
        id: id,
        payment: request.primaryPayment,
      ).withRequestSource(PaymentRequestSource.qrCode);
    } on Zip321ParseException {
      throw const FormatException(
        "This QR code doesn't contain a valid payment request.",
      );
    }
  }
  final uri = Uri.tryParse(input);
  if (input.isEmpty || uri == null || uri.hasScheme) {
    throw const FormatException(
      "This QR code isn't a Zcash address or payment request.",
    );
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
    throw FormatException(
      address.wrongNetwork
          ? 'This address belongs to a different network.'
          : "This QR code isn't a valid Zcash address.",
    );
  }
  return prefill;
}
