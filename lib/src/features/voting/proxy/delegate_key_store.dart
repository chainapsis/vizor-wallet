import '../../../core/storage/app_secure_store.dart';

/// Where delegate mode keeps the secret of its one delegate key, as the
/// key's `zvdsk1…` export (contracts-v1 section 11.2): app-level secure
/// storage, the way vote hotkeys are kept. It is read only while the wallet
/// is unlocked, after the app's re-auth: to sign, or to show the export.
abstract interface class DelegateKeyStore {
  /// Stores [secret] as the export of key [dk] (`zvdk1…`).
  Future<void> write(String dk, String secret);

  /// The stored export of [dk], or null when the device has none or the
  /// wallet is locked.
  Future<String?> read(String dk);

  /// Deletes the stored export of [dk].
  Future<void> delete(String dk);
}

/// [DelegateKeyStore] over [AppSecureStore]: the export is an app-managed
/// secret encrypted with the wallet password, so a password change rotates
/// it and a wallet reset deletes it.
class SecureStoreDelegateKeyStore implements DelegateKeyStore {
  /// Creates the store over [store].
  const SecureStoreDelegateKeyStore(this.store);

  /// The app's secure storage.
  final AppSecureStore store;

  @override
  Future<void> write(String dk, String secret) =>
      store.writeSecretString(AppSecureStore.delegateKeyStorageKey(dk), secret);

  @override
  Future<String?> read(String dk) => store.readSecretStringWithOptions(
    AppSecureStore.delegateKeyStorageKey(dk),
    requireUnlockedSession: true,
  );

  @override
  Future<void> delete(String dk) =>
      store.delete(AppSecureStore.delegateKeyStorageKey(dk));
}
