import '../../../../l10n/app_localizations.dart';
import '../../../providers/account_provider.dart';

const kDuplicateSecretPassphraseImportErrorMessage =
    'This account is already in your wallet.';
const kDuplicateKeystoneAccountImportErrorMessage =
    'This Keystone account is already in your wallet.';
const kDuplicateAccountImportErrorMessage =
    'This account is already in your wallet.';

String onboardingSubmitErrorMessage(Object error, AppLocalizations l10n) {
  if (error is WalletCreationCurrentBlockHeightException) {
    return l10n.onbErrorCurrentBlockHeight;
  }

  const exceptionPrefix = 'Exception: ';
  var message = error.toString();
  if (message.startsWith(exceptionPrefix)) {
    message = message.substring(exceptionPrefix.length);
  }
  final anyhowMatch = RegExp(r'^AnyhowException\((.*)\)$').firstMatch(message);
  if (anyhowMatch != null) {
    message = anyhowMatch.group(1)!;
  }
  if (message == kDuplicateKeystoneAccountImportErrorMessage) {
    return l10n.onbErrorDuplicateKeystoneAccount;
  }
  if (message == kDuplicateSecretPassphraseImportErrorMessage ||
      _isAccountCollisionMessage(message)) {
    return l10n.onbErrorDuplicateAccount;
  }
  return message;
}

bool _isAccountCollisionMessage(String message) {
  return message.contains('account corresponding to the data provided') &&
      message.contains('already exists in the wallet');
}
