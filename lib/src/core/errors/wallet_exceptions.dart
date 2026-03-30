sealed class WalletException implements Exception {
  final String message;
  const WalletException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class WalletCreationException extends WalletException {
  const WalletCreationException(super.message);
}

class WalletImportException extends WalletException {
  const WalletImportException(super.message);
}

class KeyDerivationException extends WalletException {
  const KeyDerivationException(super.message);
}

class DatabaseException extends WalletException {
  const DatabaseException(super.message);
}
