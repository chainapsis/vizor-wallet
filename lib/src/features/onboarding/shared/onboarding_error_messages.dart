import '../../../providers/account_provider.dart';

String onboardingSubmitErrorMessage(Object error) {
  if (error is WalletCreationCurrentBlockHeightException) {
    return kWalletCreationCurrentBlockHeightErrorMessage;
  }

  const exceptionPrefix = 'Exception: ';
  final message = error.toString();
  if (message.startsWith(exceptionPrefix)) {
    return message.substring(exceptionPrefix.length);
  }
  return message;
}
