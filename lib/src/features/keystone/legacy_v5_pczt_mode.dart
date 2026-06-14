/// Vizor currently treats Keystone hardware accounts as legacy v5 PCZT signers.
bool shouldUseLegacyV5PcztForAccount({
  required String? accountUuid,
  required bool Function(String accountUuid) isHardwareAccount,
}) {
  if (accountUuid == null) return false;
  return isHardwareAccount(accountUuid);
}
