import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kIronwoodMigrationBackgroundCredentialService =
    'com.keplr.vizor.ironwood-migration-background.v1';

typedef IronwoodMigrationSecureRandomBytes = Uint8List Function(int length);

class IronwoodMigrationBackgroundCredentialRunMismatchException
    implements Exception {
  const IronwoodMigrationBackgroundCredentialRunMismatchException({
    required this.expectedRunId,
    required this.activeRunId,
  });

  final String expectedRunId;
  final String activeRunId;

  @override
  String toString() =>
      'Ironwood migration credential belongs to run $expectedRunId, '
      'not $activeRunId.';
}

class IronwoodMigrationBackgroundCredentialManifest {
  factory IronwoodMigrationBackgroundCredentialManifest({
    required int version,
    required String network,
    required String accountUuid,
    required String dbPath,
    required String lightwalletdUrl,
    required String credentialHex,
    required String saltBase64,
    required String? expectedRunId,
  }) {
    _validateManifestValues(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      credentialHex: credentialHex,
      saltBase64: saltBase64,
      expectedRunId: expectedRunId,
    );
    return IronwoodMigrationBackgroundCredentialManifest._(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      credentialHex: credentialHex,
      saltBase64: saltBase64,
      expectedRunId: expectedRunId,
    );
  }

  const IronwoodMigrationBackgroundCredentialManifest._({
    required this.version,
    required this.network,
    required this.accountUuid,
    required this.dbPath,
    required this.lightwalletdUrl,
    required this.credentialHex,
    required this.saltBase64,
    required this.expectedRunId,
  });

  factory IronwoodMigrationBackgroundCredentialManifest.decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('Invalid Ironwood migration manifest JSON.', error);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Ironwood migration manifest must be a JSON object.',
      );
    }
    if (decoded.length != _manifestKeys.length ||
        !_manifestKeys.every(decoded.containsKey)) {
      throw const FormatException(
        'Ironwood migration manifest fields do not match version 1.',
      );
    }

    final version = decoded['version'];
    final network = decoded['network'];
    final accountUuid = decoded['accountUuid'];
    final dbPath = decoded['dbPath'];
    final lightwalletdUrl = decoded['lightwalletdUrl'];
    final credentialHex = decoded['credentialHex'];
    final saltBase64 = decoded['saltBase64'];
    final expectedRunId = decoded['expectedRunId'];
    if (version is! int ||
        network is! String ||
        accountUuid is! String ||
        dbPath is! String ||
        lightwalletdUrl is! String ||
        credentialHex is! String ||
        saltBase64 is! String ||
        (expectedRunId != null && expectedRunId is! String)) {
      throw const FormatException(
        'Ironwood migration manifest contains an invalid field type.',
      );
    }

    try {
      return IronwoodMigrationBackgroundCredentialManifest(
        version: version,
        network: network,
        accountUuid: accountUuid,
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        credentialHex: credentialHex,
        saltBase64: saltBase64,
        expectedRunId: expectedRunId as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Ironwood migration manifest.', error);
    }
  }

  final int version;
  final String network;
  final String accountUuid;
  final String dbPath;
  final String lightwalletdUrl;
  final String credentialHex;
  final String saltBase64;
  final String? expectedRunId;

  String encode() => jsonEncode(<String, Object?>{
    'version': version,
    'network': network,
    'accountUuid': accountUuid,
    'dbPath': dbPath,
    'lightwalletdUrl': lightwalletdUrl,
    'credentialHex': credentialHex,
    'saltBase64': saltBase64,
    'expectedRunId': expectedRunId,
  });

  IronwoodMigrationBackgroundCredentialManifest bindToRun(String runId) {
    if (expectedRunId != null && expectedRunId != runId) {
      throw IronwoodMigrationBackgroundCredentialRunMismatchException(
        expectedRunId: expectedRunId!,
        activeRunId: runId,
      );
    }
    return IronwoodMigrationBackgroundCredentialManifest(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      credentialHex: credentialHex,
      saltBase64: saltBase64,
      expectedRunId: runId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IronwoodMigrationBackgroundCredentialManifest &&
          version == other.version &&
          network == other.network &&
          accountUuid == other.accountUuid &&
          dbPath == other.dbPath &&
          lightwalletdUrl == other.lightwalletdUrl &&
          credentialHex == other.credentialHex &&
          saltBase64 == other.saltBase64 &&
          expectedRunId == other.expectedRunId;

  @override
  int get hashCode => Object.hash(
    version,
    network,
    accountUuid,
    dbPath,
    lightwalletdUrl,
    credentialHex,
    saltBase64,
    expectedRunId,
  );
}

class IronwoodMigrationBackgroundCredentialStore {
  IronwoodMigrationBackgroundCredentialStore({
    FlutterSecureStorage? storage,
    IronwoodMigrationSecureRandomBytes? randomBytes,
  }) : _storage = storage ?? _defaultStorage(),
       _randomBytes = randomBytes ?? _defaultRandomBytes;

  IronwoodMigrationBackgroundCredentialStore.testing({
    required FlutterSecureStorage storage,
    required IronwoodMigrationSecureRandomBytes randomBytes,
  }) : _storage = storage,
       _randomBytes = randomBytes;

  static final instance = IronwoodMigrationBackgroundCredentialStore();

  final FlutterSecureStorage _storage;
  final IronwoodMigrationSecureRandomBytes _randomBytes;

  static String storageKey({
    required String network,
    required String accountUuid,
  }) => '$network:$accountUuid';

  Future<IronwoodMigrationBackgroundCredentialManifest?> read({
    required String network,
    required String accountUuid,
  }) async {
    final raw = await _storage.read(
      key: storageKey(network: network, accountUuid: accountUuid),
    );
    if (raw == null) return null;
    final manifest = IronwoodMigrationBackgroundCredentialManifest.decode(raw);
    if (manifest.network != network || manifest.accountUuid != accountUuid) {
      throw const FormatException(
        'Ironwood migration manifest does not match its storage scope.',
      );
    }
    return manifest;
  }

  Future<IronwoodMigrationBackgroundCredentialManifest> prepare({
    required String network,
    required String accountUuid,
    required String dbPath,
    required String lightwalletdUrl,
  }) async {
    final credentialBytes = _randomBytes(32);
    final saltBytes = _randomBytes(16);
    if (credentialBytes.length != 32 || saltBytes.length != 16) {
      throw StateError(
        'Ironwood migration secure random source returned the wrong length.',
      );
    }
    final manifest = IronwoodMigrationBackgroundCredentialManifest(
      version: 1,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      credentialHex: credentialBytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(),
      saltBase64: base64Encode(saltBytes),
      expectedRunId: null,
    );
    await _write(manifest);
    return manifest;
  }

  Future<bool> bindExpectedRunId({
    required String network,
    required String accountUuid,
    required String expectedRunId,
  }) async {
    final manifest = await read(network: network, accountUuid: accountUuid);
    if (manifest == null) {
      throw StateError('Ironwood migration credential manifest is missing.');
    }
    final bound = manifest.bindToRun(expectedRunId);
    if (manifest.expectedRunId == expectedRunId) return false;
    await _write(bound);
    return true;
  }

  Future<void> delete({required String network, required String accountUuid}) {
    return _storage.delete(
      key: storageKey(network: network, accountUuid: accountUuid),
    );
  }

  Future<void> deleteAll() => _storage.deleteAll();

  Future<void> _write(IronwoodMigrationBackgroundCredentialManifest manifest) {
    return _storage.write(
      key: storageKey(
        network: manifest.network,
        accountUuid: manifest.accountUuid,
      ),
      value: manifest.encode(),
    );
  }

  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accountName: kIronwoodMigrationBackgroundCredentialService,
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
      aOptions: AndroidOptions(
        sharedPreferencesName: kIronwoodMigrationBackgroundCredentialService,
      ),
    );
  }

  static Uint8List _defaultRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

class IronwoodMigrationBackgroundLifecycle {
  IronwoodMigrationBackgroundLifecycle({
    IronwoodMigrationBackgroundCredentialStore? credentialStore,
    MethodChannel? channel,
    bool? isIOS,
    bool? isAndroid,
  }) : _credentialStore =
           credentialStore ??
           IronwoodMigrationBackgroundCredentialStore.instance,
       _channel =
           channel ??
           const MethodChannel('com.zcash.wallet/background_migration'),
       _isIOS = isIOS ?? Platform.isIOS,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  static final instance = IronwoodMigrationBackgroundLifecycle();

  final IronwoodMigrationBackgroundCredentialStore _credentialStore;
  final MethodChannel _channel;
  final bool _isIOS;
  final bool _isAndroid;

  Future<void> revokeAccount({
    required String network,
    required String accountUuid,
  }) async {
    if (_isIOS) {
      final revoked = await _channel.invokeMethod<bool>('revokeAccount', {
        'network': network,
        'accountUuid': accountUuid,
      });
      if (revoked != true) {
        throw StateError(
          'Failed to stop Ironwood migration before account removal.',
        );
      }
      return;
    }
    if (_isAndroid) {
      await _credentialStore.delete(network: network, accountUuid: accountUuid);
    }
  }

  Future<void> revokeAll() async {
    if (_isIOS) {
      final revoked = await _channel.invokeMethod<bool>('revokeAll');
      if (revoked != true) {
        throw StateError(
          'Failed to stop Ironwood migration before wallet reset.',
        );
      }
      return;
    }
    if (_isAndroid) {
      await _credentialStore.deleteAll();
    }
  }
}

const _manifestKeys = <String>{
  'version',
  'network',
  'accountUuid',
  'dbPath',
  'lightwalletdUrl',
  'credentialHex',
  'saltBase64',
  'expectedRunId',
};
const _supportedNetworks = <String>{'main', 'test', 'regtest'};
final _lowercaseCredentialPattern = RegExp(r'^[0-9a-f]{64}$');
final _canonicalSaltPattern = RegExp(r'^[A-Za-z0-9+/]{22}==$');

void _validateManifestValues({
  required int version,
  required String network,
  required String accountUuid,
  required String dbPath,
  required String lightwalletdUrl,
  required String credentialHex,
  required String saltBase64,
  required String? expectedRunId,
}) {
  if (version != 1) {
    throw ArgumentError.value(version, 'version', 'must be 1');
  }
  if (!_supportedNetworks.contains(network)) {
    throw ArgumentError.value(network, 'network', 'is unsupported');
  }
  _requireNonEmpty(accountUuid, 'accountUuid');
  _requireNonEmpty(dbPath, 'dbPath');
  _requireNonEmpty(lightwalletdUrl, 'lightwalletdUrl');
  if (!_lowercaseCredentialPattern.hasMatch(credentialHex)) {
    throw ArgumentError.value(
      credentialHex,
      'credentialHex',
      'must be 64 lowercase hexadecimal characters',
    );
  }
  if (!_canonicalSaltPattern.hasMatch(saltBase64)) {
    throw ArgumentError.value(
      saltBase64,
      'saltBase64',
      'must be canonical base64 for 16 bytes',
    );
  }
  final List<int> salt;
  try {
    salt = base64Decode(saltBase64);
  } on FormatException {
    throw ArgumentError.value(saltBase64, 'saltBase64', 'must be valid base64');
  }
  if (salt.length != 16 || base64Encode(salt) != saltBase64) {
    throw ArgumentError.value(
      saltBase64,
      'saltBase64',
      'must encode exactly 16 bytes',
    );
  }
  if (expectedRunId != null) {
    _requireNonEmpty(expectedRunId, 'expectedRunId');
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, name, 'must be non-empty and trimmed');
  }
}
