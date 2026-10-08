import 'dart:convert';
import 'dart:ffi';

const kVizorE2eIosCohortEnvKey = 'VIZOR_E2E_IOS_COHORT';
const kVizorE2eIosCohort = bool.fromEnvironment(kVizorE2eIosCohortEnvKey);
const kVizorE2eMacosCohortEnvKey = 'VIZOR_E2E_MACOS_COHORT';
const kVizorE2eMacosCohort = bool.fromEnvironment(kVizorE2eMacosCohortEnvKey);
const kVizorE2eCaseManifestEnvKey = 'VIZOR_E2E_CASE_MANIFEST';
const kVizorE2eCaseManifestMaximumBytes = 2048;

final _runIdPattern = RegExp(r'^[0-9a-f]{10}$');
final _scenarioIdPattern = RegExp(
  r'^flutter\.(ios|macos)\.[a-z0-9]+(?:-[a-z0-9]+)*$',
);

typedef E2eCaseManifestNativeEnvironmentReader =
    List<int>? Function(String key, int maximumValueBytes);

typedef _NativeGetenv = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _DartGetenv = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _NativeMalloc = Pointer<Void> Function(IntPtr);
typedef _DartMalloc = Pointer<Void> Function(int);
typedef _NativeFree = Void Function(Pointer<Void>);
typedef _DartFree = void Function(Pointer<Void>);

final class E2eRuntimeCaseManifest {
  const E2eRuntimeCaseManifest({
    required this.scenarioId,
    required this.runId,
    required this.workerId,
    required this.caseIndex,
    required this.namespace,
    required this.contextPath,
    required this.lightwalletdPort,
    required this.primaryProxyPort,
    required this.zcashdRpcPort,
    required this.regtestIronwoodActivationHeight,
  });

  final String scenarioId;
  final String runId;
  final int workerId;
  final int caseIndex;
  final String namespace;
  final String contextPath;
  final int lightwalletdPort;
  final int primaryProxyPort;
  final int zcashdRpcPort;
  final int regtestIronwoodActivationHeight;

  String get lightwalletdUrl => _loopbackUrl(lightwalletdPort);
  String get primaryProxyUrl => _loopbackUrl(primaryProxyPort);
  String get zcashdRpcUrl => _loopbackUrl(zcashdRpcPort);

  Map<String, Object> toJson() => <String, Object>{
    'schema_version': 1,
    'scenario_id': scenarioId,
    'run_id': runId,
    'worker_id': workerId,
    'case_index': caseIndex,
    'namespace': namespace,
    'context_path': contextPath,
    'lightwalletd_port': lightwalletdPort,
    'primary_proxy_port': primaryProxyPort,
    'zcashd_rpc_port': zcashdRpcPort,
    'regtest_ironwood_activation_height': regtestIronwoodActivationHeight,
  };

  @override
  bool operator ==(Object other) =>
      other is E2eRuntimeCaseManifest &&
      scenarioId == other.scenarioId &&
      runId == other.runId &&
      workerId == other.workerId &&
      caseIndex == other.caseIndex &&
      namespace == other.namespace &&
      contextPath == other.contextPath &&
      lightwalletdPort == other.lightwalletdPort &&
      primaryProxyPort == other.primaryProxyPort &&
      zcashdRpcPort == other.zcashdRpcPort &&
      regtestIronwoodActivationHeight == other.regtestIronwoodActivationHeight;

  @override
  int get hashCode => Object.hash(
    scenarioId,
    runId,
    workerId,
    caseIndex,
    namespace,
    contextPath,
    lightwalletdPort,
    primaryProxyPort,
    zcashdRpcPort,
    regtestIronwoodActivationHeight,
  );
}

E2eRuntimeCaseManifest? _installedE2eRuntimeCaseManifest;

E2eRuntimeCaseManifest? get installedE2eRuntimeCaseManifest {
  if (!kVizorE2eIosCohort && !kVizorE2eMacosCohort) return null;
  return _installedE2eRuntimeCaseManifest ??
      (throw StateError('The E2E cohort case manifest is not installed.'));
}

E2eRuntimeCaseManifest parseE2eRuntimeCaseManifest(
  String encoded, {
  bool isIos = true,
  bool isMacos = false,
}) {
  if (isIos == isMacos) {
    throw ArgumentError('Exactly one E2E cohort platform must be selected.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    throw const FormatException('The E2E case manifest is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The E2E case manifest must be an object.');
  }
  const expectedKeys = <String>{
    'schema_version',
    'scenario_id',
    'run_id',
    'worker_id',
    'case_index',
    'namespace',
    'context_path',
    'lightwalletd_port',
    'primary_proxy_port',
    'zcashd_rpc_port',
    'regtest_ironwood_activation_height',
  };
  if (decoded.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(decoded.keys.toSet()).isNotEmpty) {
    throw const FormatException(
      'The E2E case manifest has missing or unknown fields.',
    );
  }
  if (decoded['schema_version'] is! int || decoded['schema_version'] != 1) {
    throw const FormatException('Unsupported E2E case manifest schema.');
  }

  final scenarioId = _requiredString(decoded, 'scenario_id');
  final scenarioPrefix = isIos ? 'flutter.ios.' : 'flutter.macos.';
  if (!_scenarioIdPattern.hasMatch(scenarioId) ||
      !scenarioId.startsWith(scenarioPrefix)) {
    throw const FormatException('Unsupported E2E scenario for this platform.');
  }
  final runId = _requiredString(decoded, 'run_id');
  if (!_runIdPattern.hasMatch(runId)) {
    throw const FormatException(
      'The E2E run ID must be 10 lowercase hex digits.',
    );
  }
  final workerId = _boundedInteger(
    decoded,
    'worker_id',
    minimum: 0,
    maximum: 1000000,
  );
  final caseIndex = _boundedInteger(
    decoded,
    'case_index',
    minimum: 0,
    maximum: 1000000,
  );
  final expectedNamespace = 'vizor_${runId}_w${workerId}_$caseIndex';
  if (_requiredString(decoded, 'namespace') != expectedNamespace) {
    throw const FormatException(
      'The E2E namespace does not match its run, worker, and case identity.',
    );
  }
  final contextPath = _requiredString(decoded, 'context_path');
  if (isIos && contextPath != 'app-support') {
    throw const FormatException(
      'The iOS E2E context path must be app-support.',
    );
  }
  if (isMacos && !_isMacosContextPath(contextPath, expectedNamespace)) {
    throw const FormatException(
      'The macOS E2E context path must be an absolute namespaced '
      'native-context.json path.',
    );
  }
  final lightwalletdPort = _port(decoded, 'lightwalletd_port');
  final primaryProxyPort = _port(decoded, 'primary_proxy_port');
  final zcashdRpcPort = _port(decoded, 'zcashd_rpc_port');
  if (<int>{lightwalletdPort, primaryProxyPort, zcashdRpcPort}.length != 3) {
    throw const FormatException('The E2E case ports must be distinct.');
  }

  final activationHeight = _boundedInteger(
    decoded,
    'regtest_ironwood_activation_height',
    minimum: 1,
    maximum: 4294967295,
  );

  return E2eRuntimeCaseManifest(
    scenarioId: scenarioId,
    runId: runId,
    workerId: workerId,
    caseIndex: caseIndex,
    namespace: expectedNamespace,
    contextPath: contextPath,
    lightwalletdPort: lightwalletdPort,
    primaryProxyPort: primaryProxyPort,
    zcashdRpcPort: zcashdRpcPort,
    regtestIronwoodActivationHeight: activationHeight,
  );
}

E2eRuntimeCaseManifest? installE2eRuntimeCaseManifest({
  required bool isDebug,
  required bool isIos,
  required bool isMacos,
  required String defaultNetworkName,
  bool iosCohortEnabled = kVizorE2eIosCohort,
  bool macosCohortEnabled = kVizorE2eMacosCohort,
  E2eCaseManifestNativeEnvironmentReader? nativeReader,
}) {
  if (iosCohortEnabled && macosCohortEnabled) {
    throw StateError('Only one E2E cohort profile may be enabled.');
  }
  if (!iosCohortEnabled && !macosCohortEnabled) return null;
  final profileMatchesPlatform =
      (iosCohortEnabled && isIos && !isMacos) ||
      (macosCohortEnabled && isMacos && !isIos);
  if (!isDebug || !profileMatchesPlatform || defaultNetworkName != 'regtest') {
    final profileKey = iosCohortEnabled
        ? kVizorE2eIosCohortEnvKey
        : kVizorE2eMacosCohortEnvKey;
    throw StateError(
      '$profileKey is only supported by its debug regtest platform build.',
    );
  }
  final bytes = (nativeReader ?? readE2eNativeEnvironmentBytes)(
    kVizorE2eCaseManifestEnvKey,
    kVizorE2eCaseManifestMaximumBytes,
  );
  if (bytes == null) {
    throw StateError('$kVizorE2eCaseManifestEnvKey is missing.');
  }
  if (bytes.length > kVizorE2eCaseManifestMaximumBytes) {
    throw StateError(
      '$kVizorE2eCaseManifestEnvKey exceeds the maximum length.',
    );
  }
  final encoded = _decodeAscii(bytes);
  final manifest = parseE2eRuntimeCaseManifest(
    encoded,
    isIos: isIos,
    isMacos: isMacos,
  );
  final namespaceBytes = (nativeReader ?? readE2eNativeEnvironmentBytes)(
    'VIZOR_E2E_NAMESPACE',
    64,
  );
  if (namespaceBytes == null ||
      namespaceBytes.length > 64 ||
      namespaceBytes.any((byte) => byte < 0 || byte > 127) ||
      ascii.decode(namespaceBytes) != manifest.namespace) {
    throw StateError('VIZOR_E2E_NAMESPACE does not match the case manifest.');
  }
  final installed = _installedE2eRuntimeCaseManifest;
  if (installed != null && installed != manifest) {
    throw StateError('A different E2E case manifest is already installed.');
  }
  _installedE2eRuntimeCaseManifest = manifest;
  return manifest;
}

bool _isMacosContextPath(String contextPath, String namespace) {
  if (!contextPath.startsWith('/') || contextPath.contains('\u0000')) {
    return false;
  }
  final segments = contextPath.split('/');
  if (segments.any((segment) => segment == '.' || segment == '..')) {
    return false;
  }
  final suffix = '/e2e/$namespace/native-context.json';
  return contextPath.endsWith(suffix) && contextPath.length > suffix.length;
}

String _requiredString(Map<String, dynamic> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return field;
}

int _boundedInteger(
  Map<String, dynamic> value,
  String key, {
  required int minimum,
  required int maximum,
}) {
  final field = value[key];
  if (field is! int || field < minimum || field > maximum) {
    throw FormatException('$key must be an integer from $minimum to $maximum.');
  }
  return field;
}

int _port(Map<String, dynamic> value, String key) =>
    _boundedInteger(value, key, minimum: 1, maximum: 65535);

String _loopbackUrl(int port) => 'http://127.0.0.1:$port';

String _decodeAscii(List<int> bytes) {
  try {
    return ascii.decode(bytes);
  } on FormatException {
    throw StateError('$kVizorE2eCaseManifestEnvKey must be ASCII.');
  }
}

List<int>? readE2eNativeEnvironmentBytes(String key, int maximumValueBytes) {
  final library = DynamicLibrary.process();
  final malloc = library.lookupFunction<_NativeMalloc, _DartMalloc>('malloc');
  final free = library.lookupFunction<_NativeFree, _DartFree>('free');
  final getenv = library.lookupFunction<_NativeGetenv, _DartGetenv>('getenv');
  final keyBytes = ascii.encode(key);
  final allocation = malloc(keyBytes.length + 1);
  if (allocation == nullptr) {
    throw StateError('Could not allocate the E2E environment key.');
  }
  final keyPointer = allocation.cast<Uint8>();
  try {
    for (var index = 0; index < keyBytes.length; index += 1) {
      keyPointer[index] = keyBytes[index];
    }
    keyPointer[keyBytes.length] = 0;
    final valuePointer = getenv(keyPointer);
    if (valuePointer == nullptr) return null;
    final value = <int>[];
    for (var index = 0; index <= maximumValueBytes; index += 1) {
      final byte = valuePointer[index];
      if (byte == 0) return value;
      if (index == maximumValueBytes) {
        throw StateError('$key exceeds the maximum length.');
      }
      value.add(byte);
    }
    throw StateError('Unreachable E2E environment read state.');
  } finally {
    free(allocation);
  }
}
