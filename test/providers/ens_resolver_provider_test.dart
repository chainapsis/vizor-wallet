import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/providers/ens_resolver_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensResolverProvider returns an EnsNameResolver instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final resolver = container.read(ensResolverProvider);

    expect(resolver, isA<EnsNameResolver>());
  });

  test('ensResolverProvider can be overridden with a fake resolver', () {
    final fakeTransport = _FakeEnsRpcTransport();
    final fakeResolver = EnsNameResolver(fakeTransport);

    final container = ProviderContainer(
      overrides: [
        ensResolverProvider.overrideWithValue(fakeResolver),
      ],
    );
    addTearDown(container.dispose);

    final resolver = container.read(ensResolverProvider);

    expect(identical(resolver, fakeResolver), isTrue);
  });
}

class _FakeEnsRpcTransport implements EnsRpcTransport {
  @override
  Future<String> ethCall({required String to, required String data}) async {
    return '0x';
  }

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) async {
    return '0x';
  }
}
