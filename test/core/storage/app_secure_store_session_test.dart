import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _password = 'Oldpass1!';
const _newPassword = 'Newpass1!';
const _accountUuid = 'test-account';
const _mnemonic = 'abandon abandon abandon abandon abandon abandon';
const _mnemonicKey = 'zcash_account_mnemonic_test-account';
const _saltKey = 'zcash_secure_store_salt';
const _verifierKey = 'zcash_password_verifier';
const _verifierSaltKey = 'zcash_password_verifier_salt';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rust = _SecretApiFake();
  late _DelayedStorage storage;
  late AppSecureStore store;

  setUpAll(() => RustLib.initMock(api: rust));
  tearDownAll(RustLib.dispose);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    rust.reset();
    storage = _DelayedStorage();
    store = AppSecureStore.testing(
      storage: storage,
      enforceSessionGeneration: true,
    );
    await store.configurePassword(_password);
    await store.writeAccountMnemonic(_accountUuid, _mnemonic);
  });

  Future<void> expectSessionChanged(Future<Object?> operation) => expectLater(
    operation,
    throwsA(isA<SecureStorageSessionChangedException>()),
  );

  group('upstream Linux keyring recovery', () {
    late LinuxKeyringCoordinator coordinator;
    setUp(() {
      coordinator = LinuxKeyringCoordinator.testing();
      store = AppSecureStore.testing(
        storage: storage,
        keyringCoordinator: coordinator,
        enforceSessionGeneration: true,
      );
      store.setSessionPassword(_password);
    });
    tearDown(() => coordinator.dispose());

    test(
      'a locked DB locator never creates a replacement before retry',
      () async {
        const dbName = 'zcash_wallet_existing.db';
        await store.writePlain(kWalletDbNameKey, dbName);
        storage.failNextReadKey = kWalletDbNameKey;
        final writes = storage.writeCount;
        final pending = store.ensureWalletDbName();
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.state.phase, LinuxKeyringPhase.keyringLocked);
        expect(storage.writeCount, writes);
        await coordinator.retry(requestId: coordinator.state.requestId!);
        expect(await pending, dbName);
        expect(storage.writeCount, writes);
      },
    );

    test(
      'cancelled recovery preserves the original unavailable error boundary',
      () async {
        storage.failNextReadKey = kWalletDbNameKey;
        final failed = expectLater(
          store.ensureWalletDbName(),
          throwsA(
            isA<SecureStorageUnavailableException>().having(
              (error) => (error.cause as PlatformException).code,
              'cause code',
              'storage_cancelled',
            ),
          ),
        );
        final writes = storage.writeCount;
        await Future<void>.delayed(Duration.zero);
        await coordinator.cancel(requestId: coordinator.state.requestId!);
        await failed;
        expect(storage.writeCount, writes);
      },
    );

    test(
      'retry after lock discards the old secret without decrypting it',
      () async {
        storage.failNextReadKey = _mnemonicKey;
        final failed = expectSessionChanged(
          store.readAccountMnemonic(_accountUuid),
        );
        await Future<void>.delayed(Duration.zero);
        final decryptions = rust.decryptions;
        store.clearSessionPassword();
        store.setSessionPassword(_password);
        await coordinator.retry(requestId: coordinator.state.requestId!);
        await failed;
        expect(rust.decryptions, decryptions);
        expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
      },
    );

    test(
      'retry never submits an encrypted write from a replaced session',
      () async {
        storage.failNextWriteKey = _mnemonicKey;
        final failed = expectSessionChanged(
          store.writeAccountMnemonic(_accountUuid, 'replacement'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.state.phase, LinuxKeyringPhase.keyringLocked);
        final writes = storage.writeCount;
        store.clearSessionPassword();
        store.setSessionPassword(_password);
        await coordinator.retry(requestId: coordinator.state.requestId!);
        await failed;
        expect(storage.writeCount, writes);
        expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
      },
    );

    test(
      'secret encryption can initialize its salt without nesting the native queue',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        await store.writeSecretString('zcash_voting_hotkey_fixture', 'secret');
        expect(
          await store.readSecretStringWithOptions(
            'zcash_voting_hotkey_fixture',
          ),
          'secret',
        );
      },
    );
  });

  test(
    'an account mutation invalidates pending secrets without locking',
    () async {
      final gate = storage.delayRead(_mnemonicKey);
      final failed = expectSessionChanged(
        store.readAccountMnemonic(_accountUuid),
      );
      await gate.started.future;
      store.invalidatePendingSecretOperations();
      gate.release();
      await failed;
      expect(store.hasSessionPassword, isTrue);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
    },
  );

  for (final kind in [
    'mnemonic',
    'software secret',
    'bytes',
    'secret string',
  ]) {
    test('Linux discards a delayed $kind after lock and unlock', () async {
      final gate = storage.delayRead(_mnemonicKey);
      final generation = store.sessionGeneration;
      final Future<Object?> read = switch (kind) {
        'mnemonic' => store.readAccountMnemonic(_accountUuid),
        'software secret' => store.readAccountSoftwareWalletSecret(
          _accountUuid,
        ),
        'bytes' => store.readAccountMnemonicBytes(_accountUuid),
        _ => store.readSecretStringWithOptions(_mnemonicKey),
      };
      final failed = expectSessionChanged(read);
      await gate.started.future;

      store.clearSessionPassword();
      store.setSessionPassword(_password);
      gate.release();

      await failed;
      expect(store.isSessionGenerationCurrent(generation), isFalse);
      expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
    });
  }

  test('Linux rejects a secret read queued by the old session', () async {
    final gate = storage.delayRead(_mnemonicKey);
    final first = expectSessionChanged(store.readAccountMnemonic(_accountUuid));
    await gate.started.future;
    final reads = storage.readCount;
    final queued = expectSessionChanged(
      store.readAccountMnemonic(_accountUuid),
    );

    store.clearSessionPassword();
    store.setSessionPassword(_password);
    gate.release();

    await Future.wait([first, queued]);
    expect(storage.readCount, reads);
  });

  test('Linux rejects a secret write queued by the old session', () async {
    final gate = storage.delayRead(_mnemonicKey);
    final read = expectSessionChanged(store.readAccountMnemonic(_accountUuid));
    await gate.started.future;
    final write = expectSessionChanged(
      store.writeAccountMnemonic('queued-account', _mnemonic),
    );

    store.clearSessionPassword();
    store.setSessionPassword(_password);
    gate.release();

    await Future.wait([read, write]);
    expect(
      await storage.read(key: 'zcash_account_mnemonic_queued-account'),
      isNull,
    );
  });

  test(
    'Linux discards a delayed voting hotkey after the session changes',
    () async {
      await store.writeVotingHotkey(
        accountUuid: _accountUuid,
        roundId: 'round-1',
        hotkey: [1, 2, 3],
      );
      final gate = storage.delayRead(
        AppSecureStore.votingHotkeyStorageKey(
          accountUuid: _accountUuid,
          roundId: 'round-1',
        ),
      );
      final failed = expectSessionChanged(
        store.readVotingHotkey(accountUuid: _accountUuid, roundId: 'round-1'),
      );
      await gate.started.future;

      store.clearSessionPassword();
      store.setSessionPassword(_password);
      gate.release();

      await failed;
    },
  );

  test('Linux checks the session after the decryption salt read', () async {
    final gate = storage.delayRead(_saltKey);
    final decryptions = rust.decryptions;
    final failed = expectSessionChanged(
      store.readAccountMnemonicBytes(_accountUuid),
    );
    await gate.started.future;

    store.clearSessionPassword();
    gate.release();

    await failed;
    expect(rust.decryptions, decryptions);
  });

  test('Linux does not create a missing salt after an obsolete read', () async {
    await storage.delete(key: _saltKey);
    final gate = storage.delayRead(_saltKey);
    final failed = expectSessionChanged(
      store.readAccountMnemonic(_accountUuid),
    );
    await gate.started.future;

    store.clearSessionPassword();
    gate.release();

    await failed;
    expect(await storage.read(key: _saltKey), isNull);
  });

  test('Linux zeroizes plaintext returned by an obsolete decryption', () async {
    final gate = rust.delayDecryption();
    final failed = expectSessionChanged(
      store.readAccountMnemonicBytes(_accountUuid),
    );
    await gate.started.future;

    store.clearSessionPassword();
    store.setSessionPassword(_password);
    gate.release();

    await failed;
    expect(rust.lastPlaintext, isNotEmpty);
    expect(rust.lastPlaintext, everyElement(0));
  });

  test(
    'Linux does not store ciphertext encrypted by an obsolete session',
    () async {
      final gate = rust.delayEncryption();
      final failed = expectSessionChanged(
        store.writeAccountMnemonic('another-account', _mnemonic),
      );
      await gate.started.future;

      store.clearSessionPassword();
      gate.release();

      await failed;
      expect(
        await storage.read(key: 'zcash_account_mnemonic_another-account'),
        isNull,
      );
    },
  );

  test(
    'Linux lets an already dispatched write finish before deleteAll',
    () async {
      final gate = storage.delayWrite(_mnemonicKey);
      final write = store.writeAccountMnemonic(_accountUuid, _mnemonic);
      await gate.started.future;
      var deleted = false;
      final reset = store.deleteAll().then((_) => deleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(deleted, isFalse);
      expect(store.hasSessionPassword, isFalse);

      gate.release();
      await write;
      await reset;

      expect(await storage.read(key: _mnemonicKey), isNull);
      expect(store.hasSessionPassword, isFalse);
    },
  );

  for (final replacement in [_password, 'Wrongpass1!', '']) {
    test(
      'Linux a newer unlock supersedes a delayed unlock ($replacement)',
      () async {
        store.clearSessionPassword();
        final gate = storage.delayRead(_verifierSaltKey);
        final failed = expectSessionChanged(store.verifyPassword(_password));
        await gate.started.future;

        final latestSucceeded = await store.verifyPassword(replacement);
        final latestGeneration = store.sessionGeneration;
        gate.release();

        await failed;
        expect(latestSucceeded, replacement == _password);
        expect(store.hasSessionPassword, replacement == _password);
        expect(store.sessionGeneration, latestGeneration);
      },
    );
  }

  test('Linux checks a password read before starting its derivation', () async {
    final gate = storage.delayRead(_verifierKey);
    final derivations = rust.derivations;
    final failed = expectSessionChanged(store.verifyPasswordOnly(_password));
    await gate.started.future;

    store.clearSessionPassword();
    store.setSessionPassword(_password);
    gate.release();

    await failed;
    expect(rust.derivations, derivations);
  });

  test(
    'Linux does not open a session after a delayed verifier derivation',
    () async {
      store.clearSessionPassword();
      final gate = rust.delayDerivation();
      final failed = expectSessionChanged(store.verifyPassword(_password));
      await gate.started.future;

      store.clearSessionPassword();
      gate.release();

      await failed;
      expect(store.hasSessionPassword, isFalse);
    },
  );

  test(
    'Linux rotation finishes its writes without reopening a locked session',
    () async {
      final gate = storage.delayWrite(_mnemonicKey);
      final rotation = store.changePassword(
        currentPassword: _password,
        newPassword: _newPassword,
      );
      await gate.started.future;

      store.clearSessionPassword();
      gate.release();

      expect(await rotation, isTrue);
      expect(store.hasSessionPassword, isFalse);
      expect(await store.verifyPasswordOnly(_newPassword), isTrue);
      expect(await store.verifyPasswordOnly(_password), isFalse);
    },
  );

  test('Linux rotation keeps its own successful session usable', () async {
    final previousGeneration = store.sessionGeneration;

    expect(
      await store.changePassword(
        currentPassword: _password,
        newPassword: _newPassword,
      ),
      isTrue,
    );

    expect(store.isSessionGenerationCurrent(previousGeneration), isFalse);
    expect(store.hasSessionPassword, isTrue);
    expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
  });

  test(
    'Other platforms preserve their existing pending-read behavior',
    () async {
      store = AppSecureStore.testing(
        storage: storage,
        enforceSessionGeneration: false,
      );
      store.setSessionPassword(_password);
      final generation = store.sessionGeneration;
      final gate = storage.delayRead(_mnemonicKey);
      final read = store.readAccountMnemonic(_accountUuid);
      await gate.started.future;

      store.clearSessionPassword();
      store.setSessionPassword(_password);
      gate.release();

      expect(await read, _mnemonic);
      expect(store.isSessionGenerationCurrent(generation), isTrue);
    },
  );

  group('Linux AppSecurityNotifier', () {
    late ProviderContainer container;
    late AppSecurityNotifier security;
    late LinuxKeyringCoordinator coordinator;

    setUp(() {
      coordinator = LinuxKeyringCoordinator.testing();
      container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          appSecurityProvider.overrideWith(
            () => AppSecurityNotifier.testing(store: store),
          ),
          passwordChangePreflightProvider.overrideWithValue(() async {}),
          linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
        ],
      );
      security = container.read(appSecurityProvider.notifier);
    });
    tearDown(() {
      container.dispose();
      coordinator.dispose();
    });

    test(
      'locking during setup derivation prevents writing a new password',
      () async {
        await store.clearPasswordConfiguration();
        final gate = rust.delayDerivation();
        final failed = expectSessionChanged(
          security.preparePasswordSetup(_password),
        );
        await gate.started.future;
        security.lock();
        gate.release();
        await failed;
        expect(await store.isPasswordConfigured(), isFalse);
      },
    );

    test(
      'locking during setup writes permits an explicit setup retry',
      () async {
        await store.clearPasswordConfiguration();
        final gate = storage.delayWrite(_verifierKey);
        final failed = expectSessionChanged(
          security.preparePasswordSetup(_password),
        );
        await gate.started.future;
        expect(coordinator.hasPendingMutation, isTrue);
        security.lock();
        gate.release();
        await failed;
        expect(await store.isPasswordConfigured(), isTrue);
        expect(store.hasSessionPassword, isFalse);

        await security.preparePasswordSetup(_password);
        security.commitPasswordSetup();
        expect(container.read(appSecurityProvider).isUnlocked, isTrue);
        expect(await store.readAccountMnemonic(_accountUuid), _mnemonic);
      },
    );

    test(
      'committing setup does not reopen a session locked after preparation',
      () async {
        await store.clearPasswordConfiguration();
        await security.preparePasswordSetup(_password);
        security.lock();
        security.commitPasswordSetup();
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isTrue,
        );
        expect(container.read(appSecurityProvider).isUnlocked, isFalse);
        expect(store.hasSessionPassword, isFalse);
      },
    );

    test('a pending rotation rejects a second password mutation', () async {
      expect(await security.unlock(_password), isTrue);
      final gate = storage.delayWrite(_mnemonicKey);
      final rotating = security.changePassword(
        currentPassword: _password,
        newPassword: _newPassword,
      );
      await gate.started.future;
      await expectLater(
        security.changePassword(
          currentPassword: _password,
          newPassword: 'Otherpass1!',
        ),
        throwsA(isA<LinuxWalletMutationBusyException>()),
      );
      await expectLater(
        security.configurePassword('Otherpass1!'),
        throwsA(isA<LinuxWalletMutationBusyException>()),
      );
      expect(coordinator.hasPendingMutation, isTrue);
      gate.release();
      expect(await rotating, isTrue);
      expect(coordinator.hasPendingMutation, isFalse);
      expect(await store.verifyPasswordOnly(_newPassword), isTrue);
    });

    for (final action in ['lock', 'reset', 'dispose']) {
      test(
        '$action prevents the old unlock from opening the session',
        () async {
          security.lock();
          final gate = storage.delayRead(_verifierSaltKey);
          final failed = expectSessionChanged(security.unlock(_password));
          await gate.started.future;

          switch (action) {
            case 'lock':
              security.lock();
            case 'reset':
              security.reset();
            case 'dispose':
              container.dispose();
          }
          gate.release();

          await failed;
          expect(store.hasSessionPassword, isFalse);
          if (action != 'dispose') {
            expect(container.read(appSecurityProvider).isUnlocked, isFalse);
          }
        },
      );
    }

    test(
      'latest unlock wins and the older completion cannot clear it',
      () async {
        security.lock();
        final gate = storage.delayRead(_verifierSaltKey);
        final failed = expectSessionChanged(security.unlock(_password));
        await gate.started.future;

        expect(await security.unlock(_password), isTrue);
        gate.release();

        await failed;
        expect(container.read(appSecurityProvider).isUnlocked, isTrue);
        expect(store.hasSessionPassword, isTrue);
      },
    );

    test(
      'a newer password confirmation discards an older confirmation',
      () async {
        final gate = storage.delayRead(_verifierSaltKey);
        final failed = expectSessionChanged(
          security.confirmPassword(_password),
        );
        await gate.started.future;

        expect(await security.confirmPassword('Wrongpass1!'), isFalse);
        gate.release();

        await failed;
      },
    );

    test(
      'lock followed by unlock discards an old password confirmation',
      () async {
        final gate = storage.delayRead(_verifierSaltKey);
        final failed = expectSessionChanged(
          security.confirmPassword(_password),
        );
        await gate.started.future;

        security.lock();
        expect(await security.unlock(_password), isTrue);
        gate.release();

        await failed;
        expect(container.read(appSecurityProvider).isUnlocked, isTrue);
      },
    );

    test(
      'rotation success does not undo a lock while storage was pending',
      () async {
        expect(await security.unlock(_password), isTrue);
        final gate = storage.delayWrite(_mnemonicKey);
        final rotation = security.changePassword(
          currentPassword: _password,
          newPassword: _newPassword,
        );
        await gate.started.future;

        security.lock();
        gate.release();

        expect(await rotation, isTrue);
        expect(container.read(appSecurityProvider).isUnlocked, isFalse);
        expect(store.hasSessionPassword, isFalse);
        expect(await store.verifyPasswordOnly(_newPassword), isTrue);
      },
    );
  });
}

class _Gate {
  final started = Completer<void>();
  final _released = Completer<void>();

  Future<void> wait() {
    started.complete();
    return _released.future;
  }

  void release() => _released.complete();
}

class _DelayedStorage extends FlutterSecureStorage {
  String? failNextReadKey;
  String? failNextWriteKey;
  int writeCount = 0;
  String? _readKey;
  _Gate? _readGate;
  String? _writeKey;
  _Gate? _writeGate;
  int readCount = 0;

  _Gate delayRead(String key) {
    _readKey = key;
    return _readGate = _Gate();
  }

  _Gate delayWrite(String key) {
    _writeKey = key;
    return _writeGate = _Gate();
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readCount++;
    if (failNextReadKey == key) {
      failNextReadKey = null;
      throw PlatformException(code: 'KeyringLocked');
    }
    final gate = _readKey == key ? _readGate : null;
    if (gate != null) _readGate = null;
    final value = await super.read(key: key);
    if (gate != null) await gate.wait();
    return value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeCount++;
    if (failNextWriteKey == key) {
      failNextWriteKey = null;
      throw PlatformException(code: 'KeyringLocked');
    }
    final gate = _writeKey == key ? _writeGate : null;
    if (gate != null) {
      _writeGate = null;
      await gate.wait();
    }
    await super.write(key: key, value: value);
  }
}

class _SecretApiFake implements RustLibApi {
  _Gate? _decryptionGate;
  _Gate? _encryptionGate;
  _Gate? _derivationGate;
  Uint8List? lastPlaintext;
  int decryptions = 0;
  int derivations = 0;

  void reset() {
    _decryptionGate = null;
    _encryptionGate = null;
    _derivationGate = null;
    lastPlaintext = null;
    decryptions = 0;
    derivations = 0;
  }

  _Gate delayDecryption() => _decryptionGate = _Gate();
  _Gate delayEncryption() => _encryptionGate = _Gate();
  _Gate delayDerivation() => _derivationGate = _Gate();

  @override
  Future<Uint8List> crateApiSecretDecryptSecretPayload({
    required String payloadJson,
    required String password,
    required String saltBase64,
  }) async {
    decryptions++;
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    final cipher = payload['c'] as String;
    if (payload['m'] != _mac(password, saltBase64, cipher)) {
      throw StateError('Incorrect secret password');
    }
    final plaintext = Uint8List.fromList(base64Decode(cipher));
    lastPlaintext = plaintext;
    final gate = _decryptionGate;
    _decryptionGate = null;
    if (gate != null) await gate.wait();
    return plaintext;
  }

  @override
  Future<String> crateApiSecretDeriveSecretPasswordVerifier({
    required String password,
    required String saltBase64,
  }) async {
    derivations++;
    final gate = _derivationGate;
    _derivationGate = null;
    if (gate != null) await gate.wait();
    return '$password:$saltBase64';
  }

  @override
  Future<String> crateApiSecretEncryptSecretPayload({
    required List<int> plainBytes,
    required String password,
    required String saltBase64,
  }) async {
    final cipher = base64Encode(plainBytes);
    final gate = _encryptionGate;
    _encryptionGate = null;
    if (gate != null) await gate.wait();
    return jsonEncode({
      'v': 1,
      'n': base64Encode(utf8.encode('test-nonce')),
      'c': cipher,
      'm': _mac(password, saltBase64, cipher),
    });
  }

  String _mac(String password, String saltBase64, String cipher) =>
      base64Encode(utf8.encode('$password:$saltBase64:$cipher'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
