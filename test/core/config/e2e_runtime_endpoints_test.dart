import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_case_manifest.dart';
import 'package:zcash_wallet/src/core/config/e2e_runtime_endpoints.dart';

void main() {
  const manifest = E2eRuntimeCaseManifest(
    scenarioId: 'flutter.ios.contract-probe',
    runId: 'a1b2c3d4e5',
    workerId: 2,
    caseIndex: 17,
    namespace: 'vizor_a1b2c3d4e5_w2_17',
    contextPath: 'app-support',
    lightwalletdPort: 29067,
    primaryProxyPort: 29068,
    zcashdRpcPort: 28232,
    regtestIronwoodActivationHeight: 500,
  );

  test('preserves production endpoint values without a manifest', () {
    expect(
      resolveE2eRuntimeLightwalletdUrl(defaultPort: 9067),
      'http://127.0.0.1:9067',
    );
    expect(
      resolveE2eRuntimePrimaryProxyUrl(defaultPort: 19067),
      'http://127.0.0.1:19067',
    );
  });

  test('resolves only the endpoint ports carried by the manifest', () {
    expect(
      resolveE2eRuntimeLightwalletdUrl(defaultPort: 9067, manifest: manifest),
      'http://127.0.0.1:29067',
    );
    expect(
      resolveE2eRuntimePrimaryProxyUrl(defaultPort: 19067, manifest: manifest),
      'http://127.0.0.1:29068',
    );
  });

  test(
    'does not dispatch endpoints from the scenario or activation height',
    () {
      const unrelatedScenario = E2eRuntimeCaseManifest(
        scenarioId: 'flutter.ios.some-future-case',
        runId: 'a1b2c3d4e5',
        workerId: 2,
        caseIndex: 17,
        namespace: 'vizor_a1b2c3d4e5_w2_17',
        contextPath: 'app-support',
        lightwalletdPort: 30001,
        primaryProxyPort: 30002,
        zcashdRpcPort: 30003,
        regtestIronwoodActivationHeight: 4294967295,
      );

      expect(
        resolveE2eRuntimeLightwalletdUrl(
          defaultPort: 9067,
          manifest: unrelatedScenario,
        ),
        'http://127.0.0.1:30001',
      );
      expect(
        resolveE2eRuntimePrimaryProxyUrl(
          defaultPort: 19067,
          manifest: unrelatedScenario,
        ),
        'http://127.0.0.1:30002',
      );
    },
  );
}
