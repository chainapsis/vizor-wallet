/// Older Keystone firmware needs legacy v5 PCZT compatibility for Orchard V2
/// transparent spends. Rust narrows this to proposals that actually select
/// those notes.
bool shouldAllowLegacyV5PcztFallbackForAccount({
  required String? accountUuid,
  required bool Function(String accountUuid) isHardwareAccount,
}) {
  if (accountUuid == null) return false;
  return isHardwareAccount(accountUuid);
}
