const kKeystoneTransparentShieldingUnavailableMessage =
    'Transparent shielding is not available for Keystone accounts yet.';

bool transparentShieldingAvailableForAccount({
  required bool isHardwareAccount,
}) {
  return !isHardwareAccount;
}
