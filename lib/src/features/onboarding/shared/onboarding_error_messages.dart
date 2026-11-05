import 'package:flutter/foundation.dart' show immutable;

import '../../../core/l10n/l10n.dart';
import '../../../providers/account_provider.dart';

/// A submit error shown on an onboarding step: either already-produced text
/// (an exception message) or fixed copy resolved against the current locale
/// when it is displayed.
@immutable
class OnboardingSubmitError {
  const OnboardingSubmitError.text(String this._text) : _localize = null;
  const OnboardingSubmitError.localized(
    String Function(AppLocalizations l10n) this._localize,
  ) : _text = null;

  factory OnboardingSubmitError.setupInterrupted() =>
      OnboardingSubmitError.localized(
        (l10n) => l10n.onboardingSetupInterrupted,
      );

  factory OnboardingSubmitError.resumeFailed() =>
      OnboardingSubmitError.localized(
        (l10n) => l10n.onboardingResumeSetupFailed,
      );

  /// A failed submit: recovery state takes precedence over the error text.
  factory OnboardingSubmitError.fromError(
    Object error, {
    required bool requiresRecovery,
  }) => requiresRecovery
      ? OnboardingSubmitError.setupInterrupted()
      : OnboardingSubmitError.localized(
          (l10n) => onboardingSubmitErrorMessage(l10n, error),
        );

  final String? _text;
  final String Function(AppLocalizations l10n)? _localize;

  String resolve(AppLocalizations l10n) => _text ?? _localize!(l10n);
}

const kDuplicateSecretPassphraseImportErrorMessage =
    'This account is already in your wallet.'; // l10n-ignore: context-free producer
const kDuplicateKeystoneAccountImportErrorMessage =
    'This Keystone account is already in your wallet.'; // l10n-ignore: context-free producer
const kDuplicateAccountImportErrorMessage =
    'This account is already in your wallet.'; // l10n-ignore: context-free producer

String onboardingSubmitErrorMessage(AppLocalizations l10n, Object error) {
  if (error is WalletCreationCurrentBlockHeightException) {
    return l10n.onboardingBlockHeightRequired;
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
