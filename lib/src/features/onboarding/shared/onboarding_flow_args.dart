import '../../../providers/account_provider.dart';
import '../../address_book/models/address_book_contact.dart';

enum SetPasswordFlow { create, importWallet, importKeystone, importWalletLink }

class CreateSecretPassphraseArgs {
  const CreateSecretPassphraseArgs({required this.mnemonic});

  final String mnemonic;
}

/// Ephemeral wallet-setup draft passed to the account-personalisation step.
///
/// [pendingPassword] is present only for the first wallet, before password
/// setup has been persisted. It stays in route memory and is intentionally not
/// carried when the user navigates back to the password screen.
class CustomiseAccountArgs {
  const CustomiseAccountArgs({required this.setupArgs, this.pendingPassword})
    : deriveFromAccountUuid = null;

  /// A derived account has no onboarding secret draft. Its create-flow setup
  /// args provide the existing customisation shell while the source UUID keeps
  /// the actual mutation secret-free.
  const CustomiseAccountArgs.derive({required this.deriveFromAccountUuid})
    : setupArgs = const SetPasswordScreenArgs.create(mnemonic: ''),
      pendingPassword = null;

  final SetPasswordScreenArgs setupArgs;
  final String? pendingPassword;
  final String? deriveFromAccountUuid;

  String get mnemonic => setupArgs.requiredMnemonic;
  SetPasswordFlow get flow => setupArgs.flow;
  bool get configuresPassword => pendingPassword != null;
  bool get isDeriveFlow => deriveFromAccountUuid != null;

  String get routePath => switch (flow) {
    SetPasswordFlow.create => '/onboarding/customise-account',
    SetPasswordFlow.importWallet => '/import/customise-account',
    SetPasswordFlow.importKeystone => '/onboarding/keystone/customise-account',
    SetPasswordFlow.importWalletLink => throw StateError(
      'Wallet Link does not use account customisation.',
    ),
  };
}

class ImportSecretPassphraseArgs {
  const ImportSecretPassphraseArgs({
    required this.mnemonic,
    this.bip39Passphrase = '',
  });

  final String mnemonic;
  final String bip39Passphrase;
}

class ImportBirthdayArgs {
  const ImportBirthdayArgs({
    required this.mnemonic,
    this.bip39Passphrase = '',
    this.initialBirthdayHeight,
    this.selectedAdditionalAccountIndices = const [],
  });

  final String mnemonic;
  final String bip39Passphrase;
  final int? initialBirthdayHeight;
  final List<int> selectedAdditionalAccountIndices;
}

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs._({
    required this.flow,
    this.mnemonic,
    this.bip39Passphrase = '',
    this.birthdayHeight,
    this.selectedAdditionalAccountIndices = const [],
    this.keystoneAccountName,
    this.keystoneUfvk,
    this.keystoneSeedFingerprint,
    this.keystoneZip32Index,
    this.walletLinkNetwork,
    this.walletLinkAccounts = const [],
    this.walletLinkContacts = const [],
    this.walletLinkPackageId,
    this.walletLinkCompletionToken,
    this.walletLinkKeyBytes = const [],
  });

  const SetPasswordScreenArgs.create({required String mnemonic})
    : this._(flow: SetPasswordFlow.create, mnemonic: mnemonic);

  const SetPasswordScreenArgs.importWallet({
    required String mnemonic,
    String bip39Passphrase = '',
    required int birthdayHeight,
    List<int> selectedAdditionalAccountIndices = const [],
  }) : this._(
         flow: SetPasswordFlow.importWallet,
         mnemonic: mnemonic,
         bip39Passphrase: bip39Passphrase,
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

  const SetPasswordScreenArgs.importWalletLink({
    required String network,
    required List<LinkedWalletAccountImport> accounts,
    required List<AddressBookContact> contacts,
    required String packageId,
    required String completionToken,
    required List<int> keyBytes,
  }) : this._(
         flow: SetPasswordFlow.importWalletLink,
         walletLinkNetwork: network,
         walletLinkAccounts: accounts,
         walletLinkContacts: contacts,
         walletLinkPackageId: packageId,
         walletLinkCompletionToken: completionToken,
         walletLinkKeyBytes: keyBytes,
       );

  final SetPasswordFlow flow;
  final String? mnemonic;
  final String bip39Passphrase;
  final int? birthdayHeight;
  final List<int> selectedAdditionalAccountIndices;
  final String? keystoneAccountName;
  final String? keystoneUfvk;
  final List<int>? keystoneSeedFingerprint;
  final int? keystoneZip32Index;
  final String? walletLinkNetwork;
  final List<LinkedWalletAccountImport> walletLinkAccounts;
  final List<AddressBookContact> walletLinkContacts;
  final String? walletLinkPackageId;
  final String? walletLinkCompletionToken;
  final List<int> walletLinkKeyBytes;

  bool get isImport => flow == SetPasswordFlow.importWallet;
  bool get isKeystoneImport => flow == SetPasswordFlow.importKeystone;

  int get importBirthdayHeight => birthdayHeight!;
  String get requiredMnemonic => mnemonic!;
  String get requiredKeystoneAccountName => keystoneAccountName!;
  String get requiredKeystoneUfvk => keystoneUfvk!;
  List<int> get requiredKeystoneSeedFingerprint => keystoneSeedFingerprint!;
  int get requiredKeystoneZip32Index => keystoneZip32Index!;
  String get requiredWalletLinkNetwork => walletLinkNetwork!;
  String get requiredWalletLinkPackageId => walletLinkPackageId!;
  String get requiredWalletLinkCompletionToken => walletLinkCompletionToken!;
  List<int> get requiredWalletLinkKeyBytes => walletLinkKeyBytes;

  String get backRoutePath => switch (flow) {
    SetPasswordFlow.create => '/onboarding/secret-passphrase',
    SetPasswordFlow.importWallet => '/import/birthday',
    SetPasswordFlow.importKeystone => '/onboarding/keystone/birthday',
    SetPasswordFlow.importWalletLink => '/onboarding/link-desktop/contacts',
  };

  Object get backRouteExtra => switch (flow) {
    SetPasswordFlow.create => CreateSecretPassphraseArgs(
      mnemonic: requiredMnemonic,
    ),
    SetPasswordFlow.importWallet => ImportBirthdayArgs(
      mnemonic: requiredMnemonic,
      bip39Passphrase: bip39Passphrase,
      initialBirthdayHeight: importBirthdayHeight,
      selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
    ),
    SetPasswordFlow.importKeystone => this,
    SetPasswordFlow.importWalletLink => this,
  };
}
