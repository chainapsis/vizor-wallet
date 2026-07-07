import '../../../providers/account_provider.dart';
import '../../address_book/models/address_book_contact.dart';

enum SetPasswordFlow { create, importWallet, importKeystone, importWalletLink }

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
      initialBirthdayHeight: importBirthdayHeight,
      selectedAdditionalAccountIndices: selectedAdditionalAccountIndices,
    ),
    SetPasswordFlow.importKeystone => this,
    SetPasswordFlow.importWalletLink => this,
  };
}
