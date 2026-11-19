import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_security_provider.dart';
import 'biometric_unlock_provider.dart';
import 'mobile_account_visibility_provider.dart';

final mobilePasscodeAuthProvider = Provider<MobilePasscodeAuth>(
  MobilePasscodeAuth.new,
);

enum MobilePasscodeFailure { incorrect, biometric }

class MobilePasscodeRejected implements Exception {
  const MobilePasscodeRejected(this.failure);

  final MobilePasscodeFailure failure;
}

/// Authentication held only for the current UI attempt. A rule selects the
/// accounts to show, while only the wallet passcode can open secret storage.
class MobilePasscodeProof {
  const MobilePasscodeProof(this.walletPasscode, this.ruleId);

  final String? walletPasscode;
  final String? ruleId;

  bool get needsWalletPasscode => walletPasscode == null;
}

class MobilePasscodeAuth {
  MobilePasscodeAuth(this._ref);

  final Ref _ref;

  Future<MobilePasscodeProof> check({
    required String code,
    required String biometricReason,
    required bool Function() isCurrent,
    bool management = false,
    bool walletOnly = false,
    String? selectedRule,
  }) async {
    final session = _ref.read(appSecurityProvider);
    final security = _ref.read(appSecurityProvider.notifier);
    final biometric = await _ref.read(biometricUnlockProvider.future);
    final configuration = _ref.read(mobileAccountVisibilityProvider);
    void checkCurrent() {
      if (!_ref.mounted ||
          !isCurrent() ||
          !identical(session, _ref.read(appSecurityProvider)) ||
          !identical(
            configuration,
            _ref.read(mobileAccountVisibilityProvider),
          )) {
        throw const MobilePasscodeRejected(MobilePasscodeFailure.incorrect);
      }
    }

    checkCurrent();

    if (selectedRule != null && configuration.rule(selectedRule) == null) {
      throw const MobilePasscodeRejected(MobilePasscodeFailure.incorrect);
    }

    final isWalletCode = !management && await security.confirmPassword(code);
    checkCurrent();
    if (isWalletCode) {
      if (biometric.enabled) {
        final escrowed = await _ref
            .read(biometricUnlockProvider.notifier)
            .readPasscode(reason: biometricReason);
        checkCurrent();
        if (escrowed == null) {
          throw const MobilePasscodeRejected(MobilePasscodeFailure.biometric);
        }
      }
      return MobilePasscodeProof(code, selectedRule);
    }

    if (walletOnly) {
      throw const MobilePasscodeRejected(MobilePasscodeFailure.incorrect);
    }
    final rule = await _ref
        .read(mobileAccountVisibilityStoreProvider)
        .match(configuration, code);
    checkCurrent();
    if (rule == null) {
      throw const MobilePasscodeRejected(MobilePasscodeFailure.incorrect);
    }
    if (!biometric.enabled) return MobilePasscodeProof(null, rule.id);
    final walletPasscode = await _ref
        .read(biometricUnlockProvider.notifier)
        .readPasscode(reason: biometricReason);
    checkCurrent();
    final verified =
        walletPasscode != null &&
        await security.confirmPassword(walletPasscode);
    checkCurrent();
    if (!verified) {
      throw const MobilePasscodeRejected(MobilePasscodeFailure.biometric);
    }
    return MobilePasscodeProof(walletPasscode, rule.id);
  }
}
