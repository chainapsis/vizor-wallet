class MultisigFinalizeArgs {
  const MultisigFinalizeArgs({
    required this.sessionStorageId,
    required this.sessionId,
    required this.backupArtifactJson,
    required this.backupPassphrase,
  });

  final String sessionStorageId;
  final String sessionId;
  final String backupArtifactJson;
  final String backupPassphrase;
}
