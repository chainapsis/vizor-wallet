import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../models/vizor_payment_link.dart';
import '../widgets/mobile/payment_link_scan_sheet.dart';

typedef PaymentLinkScanner =
    Future<VizorPaymentLink?> Function(
      BuildContext context, {
      required String networkName,
    });

final paymentLinkScannerProvider = Provider<PaymentLinkScanner>((ref) {
  return (context, {required networkName}) {
    if (kAppFormFactor == AppFormFactor.desktop) {
      final location = GoRouterState.of(context).uri;
      final onboarding = location.path == '/gift';
      return context.push<VizorPaymentLink>(
        Uri(
          path: onboarding ? '/gift/scan' : '/payment-links/scan',
          queryParameters: {
            'network': networkName,
            if (onboarding && location.queryParameters['addAccount'] == 'true')
              'addAccount': 'true',
          },
        ).toString(),
      );
    }
    return showAppMobileSheet<VizorPaymentLink>(
      context: context,
      builder: (context) => PaymentLinkScanSheet(
        networkName: networkName,
        onScanned: (link) => Navigator.of(context).pop(link),
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  };
});
