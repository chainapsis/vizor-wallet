import 'package:flutter/widgets.dart';

import '../../services/ledger_bluetooth_access.dart';
import '../../services/ledger_mobile_ble_service.dart';
import '../ledger_bluetooth_session.dart';
import '../ledger_bluetooth_restricted_help.dart';
import 'mobile_ledger_sheet_content.dart';

class MobileLedgerBluetoothContent extends StatelessWidget {
  const MobileLedgerBluetoothContent({
    required this.onRetry,
    required this.onClose,
    this.service,
    this.retryLabel = 'Reconnect',
    this.purpose = 'continue signing',
    super.key,
  });
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final LedgerMobileBleService? service;
  final String retryLabel;
  final String purpose;

  @override
  Widget build(BuildContext context) => LedgerBluetoothSession(
    service: service,
    onRetry: onRetry,
    onClose: onClose,
    retryLabel: retryLabel,
    builder: (context, model) => MobileLedgerSheetContent(
      title: model.ready ? 'Reconnect Ledger' : model.title,
      onClose: onClose,
      action: MobileLedgerAction(model.label, onPressed: model.onAction),
      children: [
        MobileLedgerMessage(_message(model)),
        LedgerBluetoothRestrictedHelp(model: model),
      ],
    ),
  );

  String _message(LedgerBluetoothPresentation model) {
    if (model.hasError) return model.message;
    final access = model.access;
    if (model.ready) {
      return 'Bluetooth is available. Unlock your Ledger to $purpose.';
    }
    if (access?.granted == true && access?.bluetoothEnabled == false) {
      return 'Turn on Bluetooth on your phone to $purpose.';
    }
    if (access?.permission == LedgerBluetoothPermission.settings &&
        !access!.locationPermission &&
        !access.macOS) {
      return 'Allow Bluetooth access for Vizor in your phone settings to $purpose.';
    }
    return model.message;
  }
}
