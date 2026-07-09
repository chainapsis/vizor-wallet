enum SetPasswordFlow {
  create,
  importWallet,
  importKeystone,
  multisigCreateSession,
  multisigJoinSession,
  multisigFinalize,
  multisigRestore,
}

class CreateSecretPassphraseArgs {
  const CreateSecretPassphraseArgs({required this.mnemonic});

  final String mnemonic;
}

class ImportSecretPassphraseArgs {
  const ImportSecretPassphraseArgs({required this.mnemonic});

  final String mnemonic;
}

class ImportBirthdayArgs {
  const ImportBirthdayArgs({
    required this.mnemonic,
    this.initialBirthdayHeight,
    this.selectedAdditionalAccountIndices = const [],
  });

  final String mnemonic;
  final int? initialBirthdayHeight;
  final List<int> selectedAdditionalAccountIndices;
}

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs._({
    required this.flow,
    this.mnemonic,
    this.birthdayHeight,
    this.selectedAdditionalAccountIndices = const [],
    this.keystoneAccountName,
    this.keystoneUfvk,
    this.keystoneSeedFingerprint,
    this.keystoneZip32Index,
    this.multisigSessionStorageId,
    this.multisigSessionId,
    this.multisigBackupArtifactJson,
    this.multisigBackupPassphrase,
    this.multisigBackupFilePath,
    this.multisigCoordinatorUrl,
    this.multisigInviteCode,
    this.multisigParticipantCount,
    this.multisigThreshold,
  });

  const SetPasswordScreenArgs.create({required String mnemonic})
    : this._(flow: SetPasswordFlow.create, mnemonic: mnemonic);

  const SetPasswordScreenArgs.importWallet({
    required String mnemonic,
    required int birthdayHeight,
    List<int> selectedAdditionalAccountIndices = const [],
  }) : this._(
         flow: SetPasswordFlow.importWallet,
         mnemonic: mnemonic,
         birthdayHeight: birthdayHeight,
         selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
       );

  const SetPasswordScreenArgs.importKeystone({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
  }) : this._(
         flow: SetPasswordFlow.importKeystone,
         birthdayHeight: birthdayHeight,
         keystoneAccountName: name,
         keystoneUfvk: ufvk,
         keystoneSeedFingerprint: seedFingerprint,
         keystoneZip32Index: zip32Index,
       );

  const SetPasswordScreenArgs.multisigFinalize({
    required String sessionStorageId,
    required String sessionId,
    required String backupArtifactJson,
    required String backupPassphrase,
  }) : this._(
         flow: SetPasswordFlow.multisigFinalize,
         multisigSessionStorageId: sessionStorageId,
         multisigSessionId: sessionId,
         multisigBackupArtifactJson: backupArtifactJson,
         multisigBackupPassphrase: backupPassphrase,
       );

  const SetPasswordScreenArgs.multisigCreateSession({
    required String coordinatorUrl,
    required int participantCount,
    required int threshold,
  }) : this._(
         flow: SetPasswordFlow.multisigCreateSession,
         multisigCoordinatorUrl: coordinatorUrl,
         multisigParticipantCount: participantCount,
         multisigThreshold: threshold,
       );

  const SetPasswordScreenArgs.multisigJoinSession({
    required String coordinatorUrl,
    required String inviteCode,
  }) : this._(
         flow: SetPasswordFlow.multisigJoinSession,
         multisigCoordinatorUrl: coordinatorUrl,
         multisigInviteCode: inviteCode,
       );

  const SetPasswordScreenArgs.multisigRestore({
    required String backupArtifactJson,
    required String backupPassphrase,
    String? backupFilePath,
    required String coordinatorUrl,
  }) : this._(
         flow: SetPasswordFlow.multisigRestore,
         multisigBackupArtifactJson: backupArtifactJson,
         multisigBackupPassphrase: backupPassphrase,
         multisigBackupFilePath: backupFilePath,
         multisigCoordinatorUrl: coordinatorUrl,
       );

  final SetPasswordFlow flow;
  final String? mnemonic;
  final int? birthdayHeight;
  final List<int> selectedAdditionalAccountIndices;
  final String? keystoneAccountName;
  final String? keystoneUfvk;
  final List<int>? keystoneSeedFingerprint;
  final int? keystoneZip32Index;
  final String? multisigSessionStorageId;
  final String? multisigSessionId;
  final String? multisigBackupArtifactJson;
  final String? multisigBackupPassphrase;
  final String? multisigBackupFilePath;
  final String? multisigCoordinatorUrl;
  final String? multisigInviteCode;
  final int? multisigParticipantCount;
  final int? multisigThreshold;

  bool get isImport => flow == SetPasswordFlow.importWallet;
  bool get isKeystoneImport => flow == SetPasswordFlow.importKeystone;

  int get importBirthdayHeight => birthdayHeight!;
  String get requiredMnemonic => mnemonic!;
  String get requiredKeystoneAccountName => keystoneAccountName!;
  String get requiredKeystoneUfvk => keystoneUfvk!;
  List<int> get requiredKeystoneSeedFingerprint => keystoneSeedFingerprint!;
  int get requiredKeystoneZip32Index => keystoneZip32Index!;
  String get requiredMultisigSessionStorageId => multisigSessionStorageId!;
  String get requiredMultisigSessionId => multisigSessionId!;
  String get requiredMultisigBackupArtifactJson => multisigBackupArtifactJson!;
  String get requiredMultisigBackupPassphrase => multisigBackupPassphrase!;
  String get requiredMultisigCoordinatorUrl => multisigCoordinatorUrl!;
  String get requiredMultisigInviteCode => multisigInviteCode!;
  int get requiredMultisigParticipantCount => multisigParticipantCount!;
  int get requiredMultisigThreshold => multisigThreshold!;

  String get backRoutePath => switch (flow) {
    SetPasswordFlow.create => '/onboarding/secret-passphrase',
    SetPasswordFlow.importWallet => '/import/birthday',
    SetPasswordFlow.importKeystone => '/onboarding/keystone/birthday',
    SetPasswordFlow.multisigCreateSession => '/multisig/create',
    SetPasswordFlow.multisigJoinSession => '/multisig/join',
    SetPasswordFlow.multisigFinalize =>
      '/multisig/session/${Uri.encodeComponent(requiredMultisigSessionStorageId)}',
    SetPasswordFlow.multisigRestore => '/multisig/connect',
  };

  Object? get backRouteExtra => switch (flow) {
    SetPasswordFlow.create => CreateSecretPassphraseArgs(
      mnemonic: requiredMnemonic,
    ),
    SetPasswordFlow.importWallet => ImportBirthdayArgs(
      mnemonic: requiredMnemonic,
      initialBirthdayHeight: importBirthdayHeight,
      selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
    ),
    SetPasswordFlow.importKeystone => this,
    SetPasswordFlow.multisigCreateSession => null,
    SetPasswordFlow.multisigJoinSession => null,
    SetPasswordFlow.multisigFinalize => null,
    SetPasswordFlow.multisigRestore => null,
  };
}
