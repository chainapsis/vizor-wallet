import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_runtime_case_manifest.dart';

const kVizorE2eNamespaceEnvKey = 'VIZOR_E2E_NAMESPACE';
const kVizorE2eAppSupportContextPath = 'app-support';
const kVizorE2eContextFileName = 'native-context.json';

String get kVizorE2eNamespace =>
    installedE2eRuntimeCaseManifest?.namespace ?? '';
String get kVizorE2eContextPath =>
    installedE2eRuntimeCaseManifest?.contextPath ?? '';

final _namespacePattern = RegExp(r'^[a-z0-9_-]{1,64}$');
String? _configuredPreferencesPrefix;

String? readE2eRuntimeNamespace({
  required bool isIos,
  Map<String, String>? environment,
  E2eCaseManifestNativeEnvironmentReader? nativeReader,
}) {
  if (!isIos) {
    return (environment ?? Platform.environment)[kVizorE2eNamespaceEnvKey];
  }
  final bytes = (nativeReader ?? readE2eNativeEnvironmentBytes)(
    kVizorE2eNamespaceEnvKey,
    64,
  );
  if (bytes == null) return null;
  if (bytes.length > 64 || bytes.any((byte) => byte < 0 || byte > 127)) {
    throw StateError(
      '$kVizorE2eNamespaceEnvKey must be at most 64 ASCII bytes.',
    );
  }
  return ascii.decode(bytes);
}

String validateE2eNamespace({
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  if (namespace.isEmpty) return namespace;
  if (!_namespacePattern.hasMatch(namespace)) {
    throw ArgumentError.value(
      namespace,
      kVizorE2eNamespaceEnvKey,
      'must contain 1-64 lowercase letters, digits, underscores, or hyphens',
    );
  }
  if (!isDebug || defaultNetworkName != 'regtest') {
    throw StateError(
      '$kVizorE2eNamespaceEnvKey requires a debug regtest build.',
    );
  }
  return namespace;
}

void validateE2eRuntimeNamespace({
  required String expectedNamespace,
  required String? runtimeNamespace,
}) {
  if (expectedNamespace.isEmpty &&
      (runtimeNamespace == null || runtimeNamespace.isEmpty)) {
    return;
  }
  if (runtimeNamespace != expectedNamespace) {
    throw StateError(
      '$kVizorE2eNamespaceEnvKey does not match the installed case manifest.',
    );
  }
}

String e2eSecureStoreService({
  required String baseService,
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  return validated.isEmpty ? baseService : '$baseService.e2e.$validated';
}

List<String> e2eRuntimeSecureStoreServices({
  required String walletService,
  required String namespace,
  required bool isIos,
  required bool isMacos,
}) => <String>[
  walletService,
  if (isMacos) '$walletService.mnemonic',
  if (isIos) ...<String>[
    '$walletService.accessibility-migration-v1',
    'com.zcash.wallet.biometric-unlock.e2e.$namespace',
    'com.keplr.vizor.ironwood-migration-background.v1.e2e.$namespace',
    'com.keplr.vizor.ironwood-migration-outbox-key.v1.e2e.$namespace',
  ],
];

String e2eSupportDirectoryPath({
  required String basePath,
  required String pathSeparator,
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  return validated.isEmpty
      ? basePath
      : '$basePath${pathSeparator}e2e$pathSeparator$validated';
}

String e2ePreferencesPrefix({
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  return validated.isEmpty ? 'flutter.' : 'flutter.vizor_e2e_$validated.';
}

String e2ePreferenceKey({
  required String key,
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  return validated.isEmpty
      ? key
      : '${e2ePreferencesPrefix(namespace: validated, defaultNetworkName: defaultNetworkName, isDebug: isDebug)}$key';
}

void configureE2ePreferences({
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  if (validated.isEmpty) return;
  final prefix = e2ePreferencesPrefix(
    namespace: validated,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  if (_configuredPreferencesPrefix == prefix) return;
  if (_configuredPreferencesPrefix != null) {
    throw StateError(
      'E2E preferences are already configured for another case.',
    );
  }
  SharedPreferences.setPrefix(prefix);
  _configuredPreferencesPrefix = prefix;
}

String resolveE2eContextPath({
  required String configuredPath,
  required String supportDirectory,
  required String pathSeparator,
  required String namespace,
  required String defaultNetworkName,
  required bool isDebug,
  required bool isIos,
}) {
  final validated = validateE2eNamespace(
    namespace: namespace,
    defaultNetworkName: defaultNetworkName,
    isDebug: isDebug,
  );
  if (validated.isEmpty) {
    if (configuredPath.isNotEmpty) {
      throw StateError('An E2E context requires a case namespace.');
    }
    return '';
  }
  if (isIos) {
    if (configuredPath != kVizorE2eAppSupportContextPath ||
        !Directory(supportDirectory).isAbsolute) {
      throw ArgumentError(
        'The iOS E2E context requires an absolute app-support directory.',
      );
    }
    return '$supportDirectory$pathSeparator$kVizorE2eContextFileName';
  }
  if (!File(configuredPath).isAbsolute ||
      !configuredPath.endsWith('/e2e/$validated/$kVizorE2eContextFileName') ||
      configuredPath
          .split('/')
          .any((segment) => segment == '.' || segment == '..')) {
    throw ArgumentError(
      'The macOS E2E context must be an absolute namespaced context path.',
    );
  }
  return configuredPath;
}

/// Declares owned storage locations; it does not attest successful I/O or cleanup.
Map<String, Object> buildE2eRuntimeContext({
  required String namespace,
  required int processId,
  required String supportDirectory,
  required List<String> secureStoreServices,
  required String preferencesPrefix,
  String? nativePreferencesSuite,
  String? notificationIdentifierPrefix,
}) => <String, Object>{
  'schema_version': 1,
  'namespace': namespace,
  'pid': processId,
  'support_directory': supportDirectory,
  'secure_store_services': secureStoreServices,
  'preferences_prefix': preferencesPrefix,
  'native_preferences_suite': ?nativePreferencesSuite,
  'notification_identifier_prefix': ?notificationIdentifierPrefix,
  'os_background_scheduling_enabled': false,
  'storage_cleanup_completed': false,
};

Future<void> writeE2eRuntimeContext({
  required String contextPath,
  required Map<String, Object> context,
}) async {
  final file = File(contextPath);
  if (!file.isAbsolute || !await file.parent.exists()) {
    throw StateError(
      'The E2E context parent must be an existing absolute directory.',
    );
  }
  final temporary = File('$contextPath.$pid.tmp');
  try {
    await temporary.writeAsString(jsonEncode(context), flush: true);
    await temporary.rename(contextPath);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
