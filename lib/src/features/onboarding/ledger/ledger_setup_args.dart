import '../../ledger/services/ledger_account_service.dart';

class LedgerConnectArgs {
  const LedgerConnectArgs({this.sourceAccountUuid});

  final String? sourceAccountUuid;
}

class LedgerBirthdayArgs {
  const LedgerBirthdayArgs({required this.account, this.sourceAccountUuid});

  final LedgerDeviceAccount account;
  final String? sourceAccountUuid;
}

class LedgerSetPasswordArgs {
  const LedgerSetPasswordArgs({
    required this.account,
    required this.birthdayHeight,
    this.sourceAccountUuid,
  });

  final LedgerDeviceAccount account;
  final int birthdayHeight;
  final String? sourceAccountUuid;
}

class LedgerCustomiseAccountArgs {
  const LedgerCustomiseAccountArgs({
    required this.account,
    required this.birthdayHeight,
    this.pendingPassword,
    this.sourceAccountUuid,
  });

  final LedgerDeviceAccount account;
  final int birthdayHeight;
  final String? pendingPassword;
  final String? sourceAccountUuid;
}
