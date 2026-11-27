import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_service_sources.dart';

import 'support/proxy_registry_fakes.dart';
import 'support/proxy_rust_fake.dart';

void main() {
  useProxyRustFake();
  late ProxyServiceSources sources;
  setUp(() {
    proxyRust.registry = FakeProxyRegistryRust();
    sources = ProxyServiceSources();
  });

  test('the last fetched document with the extension names the URLs, per '
      'network', () async {
    await sources.ingest(
      fakeConfigFetch([
        fakeDynamicConfig(proofRpcUrls: ['https://rpc-a.example']),
        fakeDynamicConfig(
          proofRpcUrls: ['https://rpc-b.example'],
          verifierApiUrls: ['https://verifier.example'],
        ),
        fakeDynamicConfig(proxy: false),
      ]),
      network: 'main',
    );

    final main = sources.of('main');
    expect(main?.proofRpcUrls, ['https://rpc-b.example']);
    expect(main?.verifierApiUrls, ['https://verifier.example']);
    expect(sources.of('test'), isNull);
  });

  test('a document that does not parse changes nothing and never '
      'throws', () async {
    await sources.ingest(
      fakeConfigFetch([fakeDynamicConfig()]),
      network: 'main',
    );
    await sources.ingest(
      fakeConfigFetch([fakeDynamicConfig(proxy: false)]),
      network: 'main',
    );
    expect(sources.of('main')?.proofRpcUrls, ['https://rpc-a.example']);
  });

  test('clear forgets every network', () async {
    await sources.ingest(
      fakeConfigFetch([fakeDynamicConfig()]),
      network: 'main',
    );
    sources.clear();
    expect(sources.of('main'), isNull);
  });
}
