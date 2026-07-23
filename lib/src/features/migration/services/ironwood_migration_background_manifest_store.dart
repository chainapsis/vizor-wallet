import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kIronwoodMigrationBackgroundManifestService =
    'com.keplr.vizor.ironwood-migration-background.v1';

class IronwoodMigrationBackgroundManifestRunMismatchException
    implements Exception {
  const IronwoodMigrationBackgroundManifestRunMismatchException({
    required this.expectedRunId,
    required this.activeRunId,
  });

  final String expectedRunId;
  final String activeRunId;

  @override
  String toString() =>
      'Ironwood migration manifest belongs to run $expectedRunId, '
      'not $activeRunId.';
}

class IronwoodMigrationBackgroundManifest {
  factory IronwoodMigrationBackgroundManifest({
    required int version,
    required String network,
    required String accountUuid,
    required String dbPath,
    required String lightwalletdUrl,
    required String? expectedRunId,
  }) {
    _validateManifestValues(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      expectedRunId: expectedRunId,
    );
    return IronwoodMigrationBackgroundManifest._(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      expectedRunId: expectedRunId,
    );
  }

  const IronwoodMigrationBackgroundManifest._({
    required this.version,
    required this.network,
    required this.accountUuid,
    required this.dbPath,
    required this.lightwalletdUrl,
    required this.expectedRunId,
  });

  factory IronwoodMigrationBackgroundManifest.decode(String raw) {
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
    final expectedRunId = decoded['expectedRunId'];
    if (version is! int ||
        network is! String ||
        accountUuid is! String ||
        dbPath is! String ||
        lightwalletdUrl is! String ||
        (expectedRunId != null && expectedRunId is! String)) {
      throw const FormatException(
        'Ironwood migration manifest contains an invalid field type.',
      );
    }

    try {
      return IronwoodMigrationBackgroundManifest(
        version: version,
        network: network,
        accountUuid: accountUuid,
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
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
  final String? expectedRunId;

  String encode() => jsonEncode(<String, Object?>{
    'version': version,
    'network': network,
    'accountUuid': accountUuid,
    'dbPath': dbPath,
    'lightwalletdUrl': lightwalletdUrl,
    'expectedRunId': expectedRunId,
  });

  IronwoodMigrationBackgroundManifest bindToRun(String runId) {
    if (expectedRunId != null && expectedRunId != runId) {
      throw IronwoodMigrationBackgroundManifestRunMismatchException(
        expectedRunId: expectedRunId!,
        activeRunId: runId,
      );
    }
    return IronwoodMigrationBackgroundManifest(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      expectedRunId: runId,
    );
  }

  IronwoodMigrationBackgroundManifest replaceDbPath(String value) {
    return IronwoodMigrationBackgroundManifest(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: value,
      lightwalletdUrl: lightwalletdUrl,
      expectedRunId: expectedRunId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IronwoodMigrationBackgroundManifest &&
          version == other.version &&
          network == other.network &&
          accountUuid == other.accountUuid &&
          dbPath == other.dbPath &&
          lightwalletdUrl == other.lightwalletdUrl &&
          expectedRunId == other.expectedRunId;

  @override
  int get hashCode => Object.hash(
    version,
    network,
    accountUuid,
    dbPath,
    lightwalletdUrl,
    expectedRunId,
  );
}

class IronwoodMigrationBackgroundManifestStore {
  IronwoodMigrationBackgroundManifestStore({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  IronwoodMigrationBackgroundManifestStore.testing({
    required FlutterSecureStorage storage,
  }) : _storage = storage;

  static final instance = IronwoodMigrationBackgroundManifestStore();

  final FlutterSecureStorage _storage;

  static String storageKey({
    required String network,
    required String accountUuid,
  }) => '$network:$accountUuid';

  Future<IronwoodMigrationBackgroundManifest?> read({
    required String network,
    required String accountUuid,
  }) async {
    final raw = await _storage.read(
      key: storageKey(network: network, accountUuid: accountUuid),
    );
    if (raw == null) return null;
    final manifest = IronwoodMigrationBackgroundManifest.decode(raw);
    if (manifest.network != network || manifest.accountUuid != accountUuid) {
      throw const FormatException(
        'Ironwood migration manifest does not match its storage scope.',
      );
    }
    return manifest;
  }

  Future<IronwoodMigrationBackgroundManifest> prepare({
    required String network,
    required String accountUuid,
    required String dbPath,
    required String lightwalletdUrl,
  }) async {
    final manifest = IronwoodMigrationBackgroundManifest(
      version: 1,
      network: network,
      accountUuid: accountUuid,
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
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
      throw StateError('Ironwood migration background manifest is missing.');
    }
    final bound = manifest.bindToRun(expectedRunId);
    if (manifest.expectedRunId == expectedRunId) return false;
    await _write(bound);
    return true;
  }

  Future<IronwoodMigrationBackgroundManifest> replaceDbPath({
    required String network,
    required String accountUuid,
    required String expectedDbPath,
    required String dbPath,
  }) async {
    final manifest = await read(network: network, accountUuid: accountUuid);
    if (manifest == null) {
      throw StateError('Ironwood migration background manifest is missing.');
    }
    if (manifest.dbPath != expectedDbPath) {
      throw StateError(
        'Ironwood migration background manifest changed while it was being '
        'updated.',
      );
    }
    if (manifest.dbPath == dbPath) return manifest;

    final updated = manifest.replaceDbPath(dbPath);
    await _write(updated);
    return updated;
  }

  Future<void> delete({required String network, required String accountUuid}) {
    return _storage.delete(
      key: storageKey(network: network, accountUuid: accountUuid),
    );
  }

  Future<void> deleteAll() => _storage.deleteAll();

  Future<void> _write(IronwoodMigrationBackgroundManifest manifest) {
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
        accountName: kIronwoodMigrationBackgroundManifestService,
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
      aOptions: AndroidOptions(
        sharedPreferencesName: kIronwoodMigrationBackgroundManifestService,
      ),
    );
  }
}

class IronwoodMigrationBackgroundLifecycle {
  IronwoodMigrationBackgroundLifecycle({
    IronwoodMigrationBackgroundManifestStore? manifestStore,
    MethodChannel? channel,
    bool? isIOS,
    bool? isAndroid,
    List<Duration>? resumeRetryDelays,
  }) : _manifestStore =
           manifestStore ?? IronwoodMigrationBackgroundManifestStore.instance,
       _channel =
           channel ??
           const MethodChannel('com.zcash.wallet/background_migration'),
       _isIOS = isIOS ?? Platform.isIOS,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _resumeRetryDelays =
           resumeRetryDelays ??
           const [
             Duration.zero,
             Duration(milliseconds: 100),
             Duration(milliseconds: 300),
           ];

  static final instance = IronwoodMigrationBackgroundLifecycle();
  static final Object _callerManagedQuiescenceZoneKey = Object();

  final IronwoodMigrationBackgroundManifestStore _manifestStore;
  final MethodChannel _channel;
  final bool _isIOS;
  final bool _isAndroid;
  final List<Duration> _resumeRetryDelays;

  bool get isQuiescenceManagedByCaller =>
      Zone.current[_callerManagedQuiescenceZoneKey] == true;

  Future<T> runWithCallerManagedQuiescence<T>(Future<T> Function() action) {
    return runZoned(
      action,
      zoneValues: {_callerManagedQuiescenceZoneKey: true},
    );
  }

  Future<void> quiesce() async {
    if (!_isIOS) return;
    final quiesced = await _channel.invokeMethod<bool>('quiesce');
    if (quiesced != true) {
      throw StateError(
        'Failed to pause Ironwood migration before wallet data changed.',
      );
    }
  }

  Future<void> resumeAfterMutation() async {
    if (!_isIOS) return;
    Object? lastError;
    for (final delay in _resumeRetryDelays) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      try {
        final resumed = await _channel.invokeMethod<bool>('resume');
        if (resumed == true) return;
        lastError = StateError('Native migration resume returned false.');
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'Failed to resume Ironwood migration after wallet data changed'
      '${lastError == null ? '.' : ': $lastError'}',
    );
  }

  Future<void> resumeAfterFailedMutation() => resumeAfterMutation();

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
      await _manifestStore.delete(network: network, accountUuid: accountUuid);
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
      await _manifestStore.deleteAll();
    }
  }
}

const _manifestKeys = <String>{
  'version',
  'network',
  'accountUuid',
  'dbPath',
  'lightwalletdUrl',
  'expectedRunId',
};
const _supportedNetworks = <String>{'main', 'test', 'regtest'};

void _validateManifestValues({
  required int version,
  required String network,
  required String accountUuid,
  required String dbPath,
  required String lightwalletdUrl,
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
  if (expectedRunId != null) {
    _requireNonEmpty(expectedRunId, 'expectedRunId');
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, name, 'must be non-empty and trimmed');
  }
}
