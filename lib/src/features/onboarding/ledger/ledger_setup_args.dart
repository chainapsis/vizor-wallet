import '../../ledger/services/ledger_account_service.dart';

class LedgerBirthdayArgs {
  const LedgerBirthdayArgs({required this.account});

  final LedgerDeviceAccount account;
}

class LedgerSetPasswordArgs {
  const LedgerSetPasswordArgs({
    required this.account,
    required this.birthdayHeight,
  });

  final LedgerDeviceAccount account;
  final int birthdayHeight;
}

class LedgerCustomiseAccountArgs {
  const LedgerCustomiseAccountArgs({
    required this.account,
    required this.birthdayHeight,
    this.pendingPassword,
  });

  final LedgerDeviceAccount account;
  final int birthdayHeight;
  final String? pendingPassword;
}
