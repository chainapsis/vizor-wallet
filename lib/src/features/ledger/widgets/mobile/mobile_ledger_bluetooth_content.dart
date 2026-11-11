import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../services/ledger_bluetooth_access.dart';
import '../../services/ledger_mobile_ble_service.dart';
import '../ledger_bluetooth_session.dart';
import '../ledger_bluetooth_restricted_help.dart';
import 'mobile_ledger_sheet_content.dart';

/// What the user is trying to do, so the sheet can word a full sentence.
enum LedgerBluetoothPurpose { signing, addAccount, continueFlow }

class MobileLedgerBluetoothContent extends StatelessWidget {
  const MobileLedgerBluetoothContent({
    required this.onRetry,
    required this.onClose,
    this.service,
    this.retryLabel,
    this.purpose = LedgerBluetoothPurpose.signing,
    super.key,
  });
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final LedgerMobileBleService? service;
  final String? retryLabel;
  final LedgerBluetoothPurpose purpose;

  @override
  Widget build(BuildContext context) => LedgerBluetoothSession(
    service: service,
    onRetry: onRetry,
    onClose: onClose,
    retryLabel: retryLabel,
    builder: (context, model) => MobileLedgerSheetContent(
      title: model.ready ? context.l10n.ledgerReconnectTitle : model.title,
      onClose: onClose,
      action: MobileLedgerAction(model.label, onPressed: model.onAction),
      children: [
        MobileLedgerMessage(_message(context.l10n, model)),
        LedgerBluetoothRestrictedHelp(model: model),
      ],
    ),
  );

  String _message(AppLocalizations l10n, LedgerBluetoothPresentation model) {
    if (model.hasError) return model.message;
    final access = model.access;
    if (model.ready) {
      return switch (purpose) {
        LedgerBluetoothPurpose.signing => l10n.ledgerBtSheetReadySigning,
        LedgerBluetoothPurpose.addAccount => l10n.ledgerBtSheetReadyAddAccount,
        LedgerBluetoothPurpose.continueFlow => l10n.ledgerBtSheetReadyContinue,
      };
    }
    if (access?.granted == true && access?.bluetoothEnabled == false) {
      return switch (purpose) {
        LedgerBluetoothPurpose.signing => l10n.ledgerBtSheetTurnOnSigning,
        LedgerBluetoothPurpose.addAccount => l10n.ledgerBtSheetTurnOnAddAccount,
        LedgerBluetoothPurpose.continueFlow => l10n.ledgerBtSheetTurnOnContinue,
      };
    }
    if (access?.permission == LedgerBluetoothPermission.settings &&
        !access!.locationPermission &&
        !access.macOS) {
      return switch (purpose) {
        LedgerBluetoothPurpose.signing => l10n.ledgerBtSheetAllowSigning,
        LedgerBluetoothPurpose.addAccount => l10n.ledgerBtSheetAllowAddAccount,
        LedgerBluetoothPurpose.continueFlow => l10n.ledgerBtSheetAllowContinue,
      };
    }
    return model.message;
  }
}
