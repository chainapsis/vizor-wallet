enum SetPasswordFlow { create, importWallet, importKeystone }

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
  });

  final String mnemonic;
  final int? initialBirthdayHeight;
}

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs._({
    required this.flow,
    this.mnemonic,
    this.birthdayHeight,
    this.keystoneAccountName,
    this.keystoneUfvk,
    this.keystoneSeedFingerprint,
    this.keystoneZip32Index,
  });

  const SetPasswordScreenArgs.create({required String mnemonic})
    : this._(flow: SetPasswordFlow.create, mnemonic: mnemonic);

  const SetPasswordScreenArgs.importWallet({
    required String mnemonic,
    required int birthdayHeight,
  }) : this._(
         flow: SetPasswordFlow.importWallet,
         mnemonic: mnemonic,
         birthdayHeight: birthdayHeight,
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

  final SetPasswordFlow flow;
  final String? mnemonic;
  final int? birthdayHeight;
  final String? keystoneAccountName;
  final String? keystoneUfvk;
  final List<int>? keystoneSeedFingerprint;
  final int? keystoneZip32Index;

  bool get isImport => flow == SetPasswordFlow.importWallet;
  bool get isKeystoneImport => flow == SetPasswordFlow.importKeystone;

  int get importBirthdayHeight => birthdayHeight!;
  String get requiredMnemonic => mnemonic!;
  String get requiredKeystoneAccountName => keystoneAccountName!;
  String get requiredKeystoneUfvk => keystoneUfvk!;
  List<int> get requiredKeystoneSeedFingerprint => keystoneSeedFingerprint!;
  int get requiredKeystoneZip32Index => keystoneZip32Index!;

  String get backRoutePath => switch (flow) {
    SetPasswordFlow.create => '/onboarding/secret-passphrase',
    SetPasswordFlow.importWallet => '/import/birthday',
    SetPasswordFlow.importKeystone => '/onboarding/keystone/birthday',
  };

  Object get backRouteExtra => switch (flow) {
    SetPasswordFlow.create => CreateSecretPassphraseArgs(
      mnemonic: requiredMnemonic,
    ),
    SetPasswordFlow.importWallet => ImportBirthdayArgs(
      mnemonic: requiredMnemonic,
      initialBirthdayHeight: importBirthdayHeight,
    ),
    SetPasswordFlow.importKeystone => this,
  };
}
