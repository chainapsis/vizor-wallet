import 'dart:convert';

import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';

/// Recreates the retired v1 writer for legacy reader and recovery tests.
Uri legacyPaymentLinkUri(VizorPaymentLink link) {
  final recovery = link.toRecoveryUri();
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(recovery.fragment.substring(3))))
          as Map<String, dynamic>;
  payload['v'] = 1;
  payload['address'] = link.address;
  payload['createdAt'] = link.createdAt.toUtc().toIso8601String();
  return recovery.replace(
    fragment: 'v1=${base64UrlEncode(utf8.encode(jsonEncode(payload)))}',
  );
}
