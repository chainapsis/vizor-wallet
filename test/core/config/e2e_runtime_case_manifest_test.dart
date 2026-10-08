import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';

const _namespace = 'vizor_a1b2c3d4e5_w2_17';
const _namespaceBytes = <int>[
  0x76,
  0x69,
  0x7a,
  0x6f,
  0x72,
  0x5f,
  0x61,
  0x31,
  0x62,
  0x32,
  0x63,
  0x33,
  0x64,
  0x34,
  0x65,
  0x35,
  0x5f,
  0x77,
  0x32,
  0x5f,
  0x31,
  0x37,
];

Map<String, Object> _iosManifest({
  String scenarioId = 'flutter.ios.contract-probe',
  String runId = 'a1b2c3d4e5',
  int workerId = 2,
  int caseIndex = 17,
  int activationHeight = 500,
}) => <String, Object>{
  'schema_version': 1,
  'scenario_id': scenarioId,
  'run_id': runId,
  'worker_id': workerId,
  'case_index': caseIndex,
  'namespace': 'vizor_${runId}_w${workerId}_$caseIndex',
  'context_path': 'app-support',
  'lightwalletd_port': 29067,
  'primary_proxy_port': 29068,
  'zcashd_rpc_port': 28232,
  'regtest_ironwood_activation_height': activationHeight,
};

Map<String, Object> _macosManifest({
  String scenarioId = 'flutter.macos.contract-probe',
}) => <String, Object>{
  ..._iosManifest(scenarioId: scenarioId),
  'context_path': '/private/tmp/vizor/e2e/$_namespace/native-context.json',
};

void main() {
  group('E2eRuntimeCaseManifest', () {
    test('preserves the canonical cross-language fixture byte for byte', () {
      final value = _iosManifest();
      final manifest = parseE2eRuntimeCaseManifest(jsonEncode(value));

      expect(manifest.scenarioId, 'flutter.ios.contract-probe');
      expect(manifest.runId, 'a1b2c3d4e5');
      expect(manifest.workerId, 2);
      expect(manifest.caseIndex, 17);
      expect(manifest.namespace, _namespace);
      expect(manifest.contextPath, 'app-support');
      expect(manifest.lightwalletdPort, 29067);
      expect(manifest.primaryProxyPort, 29068);
      expect(manifest.zcashdRpcPort, 28232);
      expect(manifest.regtestIronwoodActivationHeight, 500);
      expect(manifest.lightwalletdUrl, 'http://127.0.0.1:29067');
      expect(manifest.primaryProxyUrl, 'http://127.0.0.1:29068');
      expect(manifest.zcashdRpcUrl, 'http://127.0.0.1:28232');
      expect(manifest.toJson(), value);
      expect(jsonEncode(manifest.toJson()), jsonEncode(value));
      expect(manifest, parseE2eRuntimeCaseManifest(jsonEncode(value)));
      expect(
        manifest.hashCode,
        parseE2eRuntimeCaseManifest(jsonEncode(value)).hashCode,
      );
    });

    test('accepts platform-shaped scenario IDs without a catalog registry', () {
      expect(
        parseE2eRuntimeCaseManifest(
          jsonEncode(_iosManifest(scenarioId: 'flutter.ios.future-case-42')),
        ).scenarioId,
        'flutter.ios.future-case-42',
      );
      expect(
        parseE2eRuntimeCaseManifest(
          jsonEncode(
            _macosManifest(scenarioId: 'flutter.macos.future-case-42'),
          ),
          isIos: false,
          isMacos: true,
        ).scenarioId,
        'flutter.macos.future-case-42',
      );
    });

    test('rejects malformed platform-shaped scenario IDs', () {
      for (final scenarioId in <String>[
        'flutter.ios.',
        'flutter.ios.trailing-',
        'flutter.ios.two..segments',
        'flutter.ios.Uppercase',
        'flutter.android.contract-probe',
      ]) {
        expect(
          () => parseE2eRuntimeCaseManifest(
            jsonEncode(_iosManifest(scenarioId: scenarioId)),
          ),
          throwsFormatException,
          reason: scenarioId,
        );
      }
    });

    test(
      'rejects invalid JSON, non-objects, missing, unknown, and typed fields',
      () {
        final missing = _iosManifest()..remove('namespace');
        final unknown = _iosManifest()..['extra'] = true;
        final wrongType = _iosManifest()..['worker_id'] = 2.0;

        for (final encoded in <String>[
          '{',
          '[]',
          jsonEncode(missing),
          jsonEncode(unknown),
          jsonEncode(wrongType),
        ]) {
          expect(
            () => parseE2eRuntimeCaseManifest(encoded),
            throwsFormatException,
            reason: encoded,
          );
        }
      },
    );

    test('rejects schema, run identity, and derived namespace mismatches', () {
      final wrongSchema = _iosManifest()..['schema_version'] = 2;
      final wrongNamespace = _iosManifest()..['namespace'] = 'vizor_other';

      for (final value in <Map<String, Object>>[
        wrongSchema,
        _iosManifest(runId: 'A1B2C3D4E5'),
        _iosManifest(runId: 'a1b2c3d4e'),
        _iosManifest(runId: 'a1b2c3d4e5f'),
        wrongNamespace,
      ]) {
        expect(
          () => parseE2eRuntimeCaseManifest(jsonEncode(value)),
          throwsFormatException,
          reason: jsonEncode(value),
        );
      }
    });

    test('accepts inclusive worker, case, port, and activation boundaries', () {
      final lower = _iosManifest(workerId: 0, caseIndex: 0, activationHeight: 1)
        ..['lightwalletd_port'] = 1
        ..['primary_proxy_port'] = 2
        ..['zcashd_rpc_port'] = 65535;
      final upper = _iosManifest(
        workerId: 1000000,
        caseIndex: 1000000,
        activationHeight: 4294967295,
      );

      expect(parseE2eRuntimeCaseManifest(jsonEncode(lower)).toJson(), lower);
      expect(parseE2eRuntimeCaseManifest(jsonEncode(upper)).toJson(), upper);
    });

    test('rejects out-of-range identities, ports, and activation heights', () {
      final duplicatePorts = _iosManifest()..['zcashd_rpc_port'] = 29067;
      final fractionalActivation = _iosManifest()
        ..['regtest_ironwood_activation_height'] = 500.0;

      for (final value in <Map<String, Object>>[
        _iosManifest(workerId: -1),
        _iosManifest(workerId: 1000001),
        _iosManifest(caseIndex: -1),
        _iosManifest(caseIndex: 1000001),
        _iosManifest()..['lightwalletd_port'] = 0,
        _iosManifest()..['lightwalletd_port'] = 65536,
        duplicatePorts,
        _iosManifest(activationHeight: 0),
        _iosManifest(activationHeight: 4294967296),
        fractionalActivation,
      ]) {
        expect(
          () => parseE2eRuntimeCaseManifest(jsonEncode(value)),
          throwsFormatException,
          reason: jsonEncode(value),
        );
      }
    });

    test('cross-rejects scenarios and context paths between platforms', () {
      expect(
        () => parseE2eRuntimeCaseManifest(
          jsonEncode(_iosManifest(scenarioId: 'flutter.macos.probe')),
        ),
        throwsFormatException,
      );
      expect(
        () => parseE2eRuntimeCaseManifest(
          jsonEncode(_macosManifest(scenarioId: 'flutter.ios.probe')),
          isIos: false,
          isMacos: true,
        ),
        throwsFormatException,
      );
      expect(
        () => parseE2eRuntimeCaseManifest(
          jsonEncode(_iosManifest()),
          isIos: false,
          isMacos: true,
        ),
        throwsFormatException,
      );
      expect(
        () => parseE2eRuntimeCaseManifest(
          jsonEncode(_macosManifest()),
          isIos: true,
          isMacos: false,
        ),
        throwsFormatException,
      );
      expect(
        () => parseE2eRuntimeCaseManifest(
          jsonEncode(_iosManifest()),
          isIos: false,
          isMacos: false,
        ),
        throwsArgumentError,
      );
    });

    test('requires an absolute clean namespaced macOS context path', () {
      for (final path in <String>[
        'relative/e2e/$_namespace/native-context.json',
        '/private/tmp/e2e/other/native-context.json',
        '/private/tmp/e2e/$_namespace/../native-context.json',
        '/private/tmp/./e2e/$_namespace/native-context.json',
        '/e2e/$_namespace/native-context.json',
        '/private/tmp/e2e/$_namespace/context.json',
      ]) {
        final value = _macosManifest()..['context_path'] = path;
        expect(
          () => parseE2eRuntimeCaseManifest(
            jsonEncode(value),
            isIos: false,
            isMacos: true,
          ),
          throwsFormatException,
          reason: path,
        );
      }
    });
  });

  test('installer gates before reads and locks one process identity', () {
    var readCount = 0;
    List<int>? unread(String _, int _) {
      readCount += 1;
      throw StateError('must not read');
    }

    expect(
      installE2eRuntimeCaseManifest(
        isDebug: false,
        isIos: false,
        isMacos: false,
        defaultNetworkName: 'main',
        iosCohortEnabled: false,
        macosCohortEnabled: false,
        nativeReader: unread,
      ),
      isNull,
    );
    for (final profile in <(bool, bool, bool, String)>[
      (false, true, false, 'regtest'),
      (true, false, true, 'regtest'),
      (true, true, false, 'main'),
    ]) {
      expect(
        () => installE2eRuntimeCaseManifest(
          isDebug: profile.$1,
          isIos: profile.$2,
          isMacos: profile.$3,
          defaultNetworkName: profile.$4,
          iosCohortEnabled: true,
          macosCohortEnabled: false,
          nativeReader: unread,
        ),
        throwsStateError,
      );
    }
    expect(
      () => installE2eRuntimeCaseManifest(
        isDebug: true,
        isIos: true,
        isMacos: false,
        defaultNetworkName: 'regtest',
        iosCohortEnabled: true,
        macosCohortEnabled: true,
        nativeReader: unread,
      ),
      throwsStateError,
    );
    expect(readCount, 0);

    E2eRuntimeCaseManifest? installWith(
      List<int>? bytes, {
      List<int>? namespaceBytes = _namespaceBytes,
    }) => installE2eRuntimeCaseManifest(
      isDebug: true,
      isIos: true,
      isMacos: false,
      defaultNetworkName: 'regtest',
      iosCohortEnabled: true,
      macosCohortEnabled: false,
      nativeReader: (key, maximumBytes) {
        if (key == kVizorE2eCaseManifestEnvKey) {
          expect(maximumBytes, kVizorE2eCaseManifestMaximumBytes);
          return bytes;
        }
        expect(key, 'VIZOR_E2E_NAMESPACE');
        expect(maximumBytes, 64);
        return namespaceBytes;
      },
    );

    expect(() => installWith(null), throwsStateError);
    expect(() => installWith(<int>[0xff]), throwsStateError);
    expect(
      () => installWith(
        List<int>.filled(kVizorE2eCaseManifestMaximumBytes + 1, 0x61),
      ),
      throwsStateError,
    );

    final canonicalBytes = ascii.encode(jsonEncode(_iosManifest()));
    expect(
      () => installWith(canonicalBytes, namespaceBytes: null),
      throwsStateError,
    );
    expect(
      () => installWith(
        canonicalBytes,
        namespaceBytes: List<int>.filled(65, 0x61),
      ),
      throwsStateError,
    );
    expect(
      () => installWith(canonicalBytes, namespaceBytes: <int>[0xff]),
      throwsStateError,
    );
    expect(
      () => installWith(
        canonicalBytes,
        namespaceBytes: ascii.encode('vizor_a1b2c3d4e5_w2_18'),
      ),
      throwsStateError,
    );
    final installed = installWith(canonicalBytes)!;
    expect(installed.toJson(), _iosManifest());
    expect(installWith(canonicalBytes), installed);

    final changed = ascii.encode(
      jsonEncode(_iosManifest(activationHeight: 501)),
    );
    expect(() => installWith(changed), throwsStateError);
  });
}
