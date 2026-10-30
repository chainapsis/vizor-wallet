import '../../../core/input/app_password_input_source.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../shared/account_persona_draft.dart';

class LedgerBirthdayArgs {
  const LedgerBirthdayArgs({required this.account});

  final LedgerDeviceAccount account;
}

class LedgerCustomiseAccountArgs {
  const LedgerCustomiseAccountArgs({
    required this.account,
    required this.birthdayHeight,
    this.persona,
    this.pendingPassword,
    this.passwordInputSource,
  });

  final LedgerDeviceAccount account;
  final int birthdayHeight;
  final AccountPersona? persona;
  final String? pendingPassword;
  final PasswordInputSourceCandidate? passwordInputSource;
}
