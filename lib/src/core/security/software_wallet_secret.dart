import 'dart:convert';

class SoftwareWalletSecretFormatException implements Exception {
  const SoftwareWalletSecretFormatException(this.message);

  final String message;

  @override
  String toString() => 'SoftwareWalletSecretFormatException: $message';
}

/// Versioned software-wallet recovery material stored under the existing
/// per-account encrypted mnemonic key.
///
/// Legacy entries contain the mnemonic as a raw string. New passphrase-backed
/// entries use this envelope so the mnemonic and BIP39 passphrase remain
/// atomic while preserving backward compatibility.
class SoftwareWalletSecret {
  const SoftwareWalletSecret({
    required this.mnemonic,
    this.bip39Passphrase = '',
  });

  static const version = 1;

  final String mnemonic;
  final String bip39Passphrase;

  bool get hasBip39Passphrase => bip39Passphrase.isNotEmpty;

  static SoftwareWalletSecret decode(String storedValue) {
    final envelope = storedValue.trimLeft();
    if (!envelope.startsWith('{')) {
      return SoftwareWalletSecret(mnemonic: storedValue);
    }

    late final Object? json;
    try {
      json = jsonDecode(envelope);
    } on FormatException {
      throw const SoftwareWalletSecretFormatException(
        'Stored software wallet secret is malformed.',
      );
    }

    if (json is! Map<String, dynamic>) {
      throw const SoftwareWalletSecretFormatException(
        'Stored software wallet secret is malformed.',
      );
    }
    if (json['version'] != version) {
      throw const SoftwareWalletSecretFormatException(
        'Stored software wallet secret uses an unsupported version.',
      );
    }
    final mnemonic = json['mnemonic'];
    final bip39Passphrase = json['bip39Passphrase'];
    if (mnemonic is! String || mnemonic.isEmpty || bip39Passphrase is! String) {
      throw const SoftwareWalletSecretFormatException(
        'Stored software wallet secret is malformed.',
      );
    }
    return SoftwareWalletSecret(
      mnemonic: mnemonic,
      bip39Passphrase: bip39Passphrase,
    );
  }

  String encodeForStorage() {
    if (!hasBip39Passphrase) return mnemonic;
    return jsonEncode({
      'version': version,
      'mnemonic': mnemonic,
      'bip39Passphrase': bip39Passphrase,
    });
  }
}
