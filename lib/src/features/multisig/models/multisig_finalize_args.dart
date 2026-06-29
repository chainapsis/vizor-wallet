class MultisigFinalizeArgs {
  const MultisigFinalizeArgs({
    required this.sessionId,
    required this.backupArtifactJson,
    required this.backupPassphrase,
  });

  final String sessionId;
  final String backupArtifactJson;
  final String backupPassphrase;
}
