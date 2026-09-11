import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../services/qr_scanner.dart';
import '../../../address_scan/widgets/mobile_address_scan_card.dart';
import '../../models/vizor_payment_link.dart';

typedef PaymentLinkScanner =
    Future<VizorPaymentLink?> Function(
      BuildContext context, {
      required String networkName,
    });

final paymentLinkScannerProvider = Provider<PaymentLinkScanner>((ref) {
  return (context, {required networkName}) {
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

class PaymentLinkScanSheet extends StatefulWidget {
  const PaymentLinkScanSheet({
    required this.networkName,
    required this.onScanned,
    required this.onClose,
    this.controller,
    super.key,
  });

  final String networkName;
  final ValueChanged<VizorPaymentLink> onScanned;
  final VoidCallback onClose;
  final MobileScannerController? controller;

  @override
  State<PaymentLinkScanSheet> createState() => _PaymentLinkScanSheetState();
}

class _PaymentLinkScanSheetState extends State<PaymentLinkScanSheet> {
  late final MobileScannerController _controller;
  bool _finished = false;
  int _scanResetToken = 0;
  String? _error;

  bool get _canScan =>
      mounted && !_finished && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        MobileScannerController(
          formats: QrScanner.formats,
          detectionSpeed: QrScanner.detectionSpeed,
        );
  }

  @override
  void dispose() {
    if (widget.controller == null) unawaited(_controller.dispose());
    super.dispose();
  }

  void _accept(VizorPaymentLink link) {
    if (!_canScan) return;
    if (link.network != widget.networkName) {
      _reject('This gift card is for a different network.');
      return;
    }
    _finished = true;
    widget.onScanned(link);
  }

  void _reject(String message) {
    setState(() {
      _error = message;
      _scanResetToken++;
    });
  }

  void _scan(String raw) {
    if (!_canScan) return;
    try {
      _accept(VizorPaymentLink.parse(raw));
    } on FormatException {
      _reject("This isn't a gift card QR code.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileQrScanCard(
      controller: _controller,
      caption: 'Scan the gift card QR code',
      permissionTitle: 'Scan gift card QR',
      error: _error,
      onClose: () {
        _finished = true;
        widget.onClose();
      },
      cameraViewBuilder: (context, controller) => PlainQrScannerView(
        controller: controller,
        scanSessionResetToken: _scanResetToken,
        onComplete: _scan,
      ),
    );
  }
}
