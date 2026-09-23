import 'package:flutter/widgets.dart';

import '../../services/ledger_mobile_ble_service.dart';
import '../ledger_bluetooth_session.dart';
import 'mobile_ledger_sheet_content.dart';

class MobileLedgerBluetoothContent extends StatelessWidget {
  const MobileLedgerBluetoothContent({
    required this.onRetry,
    required this.onClose,
    this.service,
    this.retryLabel = 'Reconnect',
    super.key,
  });
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final LedgerMobileBleService? service;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => LedgerBluetoothSession(
    service: service,
    onRetry: onRetry,
    onClose: onClose,
    retryLabel: retryLabel,
    builder: (context, model) => MobileLedgerSheetContent(
      title: model.title,
      onClose: onClose,
      children: [
        MobileLedgerMessage(model.message),
        if (model.busy)
          const MobileLedgerStatus('Checking Bluetooth access…')
        else
          MobileLedgerAction(model.label, onPressed: model.onAction),
      ],
    ),
  );
}
