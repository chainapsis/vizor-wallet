import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/e2e_namespace.dart';

const _namespace = 'vizor_a1b2c3d4e5_w2_17';

void main() {
  test('runtime ownership lists the macOS wallet and mnemonic services', () {
    const walletService =
        'com.keplr.vizor.regtest.secure_store.e2e.$_namespace';
    expect(
      e2eRuntimeSecureStoreServices(walletService: walletService),
      <String>[walletService, '$walletService.mnemonic'],
    );
  });

  group('namespace validation', () {
    test('preserves the empty production namespace byte for byte', () {
      expect(
        validateE2eNamespace(
          namespace: '',
          defaultNetworkName: 'main',
          isDebug: false,
        ),
        '',
      );
      expect(
        () => validateE2eRuntimeNamespace(
          expectedNamespace: '',
          runtimeNamespace: null,
        ),
        returnsNormally,
      );
    });

    test('accepts only strict debug regtest namespaces', () {
      expect(
        validateE2eNamespace(
          namespace: _namespace,
          defaultNetworkName: 'regtest',
          isDebug: true,
        ),
        _namespace,
      );

      for (final namespace in <String>[
        'Vizor_a1b2c3d4e5_w2_17',
        'vizor.a1b2c3d4e5.w2.17',
        'vizor/a1b2c3d4e5/w2/17',
        'vizor a1b2c3d4e5 w2 17',
        'a' * 65,
      ]) {
        expect(
          () => validateE2eNamespace(
            namespace: namespace,
            defaultNetworkName: 'regtest',
            isDebug: true,
          ),
          throwsArgumentError,
          reason: namespace,
        );
      }
      expect(
        () => validateE2eNamespace(
          namespace: _namespace,
          defaultNetworkName: 'regtest',
          isDebug: false,
        ),
        throwsStateError,
      );
      expect(
        () => validateE2eNamespace(
          namespace: _namespace,
          defaultNetworkName: 'main',
          isDebug: true,
        ),
        throwsStateError,
      );
    });

    test(
      'requires an exact runtime identity and rejects environment-only use',
      () {
        expect(
          () => validateE2eRuntimeNamespace(
            expectedNamespace: _namespace,
            runtimeNamespace: _namespace,
          ),
          returnsNormally,
        );
        for (final pair in <(String, String?)>[
          (_namespace, null),
          (_namespace, ''),
          (_namespace, 'vizor_a1b2c3d4e5_w2_18'),
          ('', _namespace),
        ]) {
          expect(
            () => validateE2eRuntimeNamespace(
              expectedNamespace: pair.$1,
              runtimeNamespace: pair.$2,
            ),
            throwsStateError,
          );
        }
      },
    );
  });

  group('readE2eRuntimeNamespace', () {
    test('reads bounded ASCII identity through the native iOS boundary', () {
      expect(
        readE2eRuntimeNamespace(
          isIos: true,
          nativeReader: (key, maximumValueBytes) {
            expect(key, kVizorE2eNamespaceEnvKey);
            expect(maximumValueBytes, 64);
            return ascii.encode(_namespace);
          },
        ),
        _namespace,
      );
      expect(
        readE2eRuntimeNamespace(isIos: true, nativeReader: (_, _) => null),
        isNull,
      );
      expect(
        () => readE2eRuntimeNamespace(
          isIos: true,
          nativeReader: (_, _) => List<int>.filled(65, 0x61),
        ),
        throwsStateError,
      );
      expect(
        () => readE2eRuntimeNamespace(
          isIos: true,
          nativeReader: (_, _) => <int>[0xff],
        ),
        throwsStateError,
      );
    });

    test('uses the supplied process environment outside iOS', () {
      expect(
        readE2eRuntimeNamespace(
          isIos: false,
          environment: const <String, String>{
            kVizorE2eNamespaceEnvKey: _namespace,
          },
          nativeReader: (_, _) => throw StateError('must not read natively'),
        ),
        _namespace,
      );
      expect(
        readE2eRuntimeNamespace(
          isIos: false,
          environment: const <String, String>{},
        ),
        isNull,
      );
    });
  });

  test('production storage and preference values remain unchanged', () {
    expect(
      e2eSecureStoreService(
        baseService: 'com.keplr.vizor.secure_store',
        namespace: '',
        defaultNetworkName: 'main',
        isDebug: false,
      ),
      'com.keplr.vizor.secure_store',
    );
    expect(
      e2eSupportDirectoryPath(
        basePath: '/Library/Application Support/com.keplr.vizor',
        pathSeparator: '/',
        namespace: '',
        defaultNetworkName: 'main',
        isDebug: false,
      ),
      '/Library/Application Support/com.keplr.vizor',
    );
    expect(
      e2ePreferencesPrefix(
        namespace: '',
        defaultNetworkName: 'main',
        isDebug: false,
      ),
      'flutter.',
    );
  });

  test('canonical namespace isolates every Dart-owned storage surface', () {
    expect(
      e2eSecureStoreService(
        baseService: 'com.keplr.vizor.regtest.secure_store',
        namespace: _namespace,
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      'com.keplr.vizor.regtest.secure_store.e2e.$_namespace',
    );
    expect(
      e2eSupportDirectoryPath(
        basePath: '/support/com.keplr.vizor',
        pathSeparator: '/',
        namespace: _namespace,
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      '/support/com.keplr.vizor/e2e/$_namespace',
    );
    expect(
      e2ePreferencesPrefix(
        namespace: _namespace,
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      'flutter.vizor_e2e_$_namespace.',
    );
  });

  group('resolveE2eContextPath', () {
    test('preserves an empty production context path', () {
      expect(
        resolveE2eContextPath(
          configuredPath: '',
          namespace: '',
          defaultNetworkName: 'main',
          isDebug: false,
        ),
        '',
      );
      expect(
        () => resolveE2eContextPath(
          configuredPath: '/tmp/native-context.json',
          namespace: '',
          defaultNetworkName: 'main',
          isDebug: false,
        ),
        throwsStateError,
      );
    });

    test('preserves validated macOS paths', () {
      const macosPath =
          '/private/tmp/vizor/e2e/$_namespace/native-context.json';
      expect(
        resolveE2eContextPath(
          configuredPath: macosPath,
          namespace: _namespace,
          defaultNetworkName: 'regtest',
          isDebug: true,
        ),
        macosPath,
      );
    });

    test('rejects unowned macOS paths', () {
      for (final path in <String>[
        'relative/e2e/$_namespace/native-context.json',
        '/tmp/e2e/other/native-context.json',
        '/tmp/e2e/$_namespace/../native-context.json',
      ]) {
        expect(
          () => resolveE2eContextPath(
            configuredPath: path,
            namespace: _namespace,
            defaultNetworkName: 'regtest',
            isDebug: true,
          ),
          throwsArgumentError,
          reason: path,
        );
      }
    });
  });

  test('runtime context declares ownership without cleanup orchestration', () {
    expect(
      buildE2eRuntimeContext(
        namespace: _namespace,
        processId: 1234,
        supportDirectory: '/app/support/e2e/$_namespace',
        secureStoreServices: const <String>[
          'com.keplr.vizor.regtest.secure_store.e2e.$_namespace',
        ],
        preferencesPrefix: 'flutter.vizor_e2e_$_namespace.',
      ),
      <String, Object>{
        'schema_version': 1,
        'namespace': _namespace,
        'pid': 1234,
        'support_directory': '/app/support/e2e/$_namespace',
        'secure_store_services': <String>[
          'com.keplr.vizor.regtest.secure_store.e2e.$_namespace',
        ],
        'preferences_prefix': 'flutter.vizor_e2e_$_namespace.',
        'os_background_scheduling_enabled': false,
        'storage_cleanup_completed': false,
      },
    );
  });

  test('preferences configuration is idempotent and process-immutable', () {
    expect(
      () => configureE2ePreferences(
        namespace: '',
        defaultNetworkName: 'main',
        isDebug: false,
      ),
      returnsNormally,
    );
    expect(
      () => configureE2ePreferences(
        namespace: _namespace,
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      returnsNormally,
    );
    expect(
      () => configureE2ePreferences(
        namespace: _namespace,
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      returnsNormally,
    );
    expect(
      () => configureE2ePreferences(
        namespace: 'vizor_a1b2c3d4e5_w2_18',
        defaultNetworkName: 'regtest',
        isDebug: true,
      ),
      throwsStateError,
    );
  });
}
