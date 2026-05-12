import '../../../providers/account_provider.dart';

const kDuplicateSecretPassphraseImportErrorMessage =
    'This account is already in your wallet.';
const kDuplicateKeystoneAccountImportErrorMessage =
    'This Keystone account is already in your wallet.';
const kDuplicateAccountImportErrorMessage =
    'This account is already in your wallet.';

String onboardingSubmitErrorMessage(Object error) {
  if (error is WalletCreationCurrentBlockHeightException) {
    return kWalletCreationCurrentBlockHeightErrorMessage;
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
  if (_isAccountCollisionMessage(message)) {
    return kDuplicateAccountImportErrorMessage;
  }
  return message;
}

bool _isAccountCollisionMessage(String message) {
  return message.contains('account corresponding to the data provided') &&
      message.contains('already exists in the wallet');
}
