import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/e2e_namespace.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = kVizorE2eIosCohort || kVizorE2eMacosCohort;
  final hasRuntimeNamespace =
      (Platform.environment[kVizorE2eNamespaceEnvKey] ?? '').isNotEmpty;
  final hasRuntimeManifest = Platform.environment.containsKey(
    kVizorE2eCaseManifestEnvKey,
  );
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory support;
  late int pathReads;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('vizor-runtime-binding-');
    pathReads = 0;
    SharedPreferences.setMockInitialValues({'production_marker': true});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async {
          pathReads += 1;
          return support.path;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
    await support.delete(recursive: true);
  });

  test('ordinary startup does not open E2E support storage', () async {
    expect(await initializeE2eRuntimeConfiguration(), isNull);
    expect(pathReads, 0);
    expect(kVizorE2eNamespace, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getBool('production_marker'),
      isTrue,
    );
  }, skip: enabled || hasRuntimeNamespace || hasRuntimeManifest);

  test('ordinary startup rejects a stray manifest before storage', () async {
    await expectLater(initializeE2eRuntimeConfiguration(), throwsStateError);
    expect(pathReads, 0);
  }, skip: enabled || !hasRuntimeManifest);

  test(
    'ordinary startup rejects a stray native namespace before storage',
    () async {
      await expectLater(initializeE2eRuntimeConfiguration(), throwsStateError);
      expect(pathReads, 0);
    },
    skip: enabled || !hasRuntimeNamespace,
  );

  test(
    'real native environment binds all Dart-owned runtime locations',
    () async {
      final manifest = await initializeE2eRuntimeConfiguration();
      expect(manifest, isNotNull);
      final value = manifest!;
      expect(value.namespace, Platform.environment[kVizorE2eNamespaceEnvKey]);
      final ownedSupport = '${support.path}/e2e/${value.namespace}';
      expect((await getWalletSupportDirectory()).path, ownedSupport);
      expect(
        secureStoreServiceForNetwork('regtest'),
        'com.keplr.vizor.regtest.secure_store.e2e.${value.namespace}',
      );
      expect(kRegtestRpcEndpointPresets.first.url, value.lightwalletdUrl);
      expect(kRegtestRpcEndpointPresets[1].url, value.primaryProxyUrl);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('production_marker'), isNull);
      final context =
          jsonDecode(await File(value.contextPath).readAsString())
              as Map<String, dynamic>;
      expect(context['namespace'], value.namespace);
      expect(context['pid'], pid);
      expect(context['support_directory'], ownedSupport);
      expect(context['secure_store_services'], <String>[
        'com.keplr.vizor.regtest.secure_store.e2e.${value.namespace}',
        'com.keplr.vizor.regtest.secure_store.e2e.${value.namespace}.mnemonic',
      ]);
      expect(context['storage_cleanup_completed'], isFalse);
      expect(context['os_background_scheduling_enabled'], isFalse);
      expect(await initializeE2eRuntimeConfiguration(), value);
    },
    skip: !kVizorE2eMacosCohort,
  );
}
