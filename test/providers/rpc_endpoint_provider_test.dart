import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  ProviderContainer container(Future<String> Function(String) lookup) {
    final result = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        rpcEndpointProvider.overrideWith(
          () => RpcEndpointNotifier(getChainName: lookup),
        ),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'normalizes and verifies before persisting or publishing an endpoint',
    () async {
      final verification = Completer<String>();
      String? requested;
      final state = container((url) {
        requested = url;
        return verification.future;
      });
      final previous = state.read(rpcEndpointProvider);
      final update = state
          .read(rpcEndpointProvider.notifier)
          .setCustom(' rpc.example:443 ');
      expect(requested, 'https://rpc.example:443');
      expect(state.read(rpcEndpointProvider), previous);
      expect(
        await const FlutterSecureStorage().read(key: kRpcEndpointUrlKey),
        isNull,
      );
      verification.complete('main');
      await update;
      expect(state.read(rpcEndpointProvider).hostPort, 'rpc.example:443');
      expect(
        await const FlutterSecureStorage().read(key: kRpcEndpointUrlKey),
        'https://rpc.example:443',
      );
    },
  );

  test('wrong network never persists the candidate', () async {
    final state = container((_) async => 'test');
    final previous = state.read(rpcEndpointProvider);
    await expectLater(
      state.read(rpcEndpointProvider.notifier).setCustom('rpc.example:443'),
      throwsA(isA<FormatException>()),
    );
    expect(state.read(rpcEndpointProvider), previous);
    expect(
      await const FlutterSecureStorage().read(key: kRpcEndpointUrlKey),
      isNull,
    );
  });

  test('failed verification cannot publish or save a late result', () async {
    final verification = Completer<String>();
    final state = container((_) => verification.future);
    final previous = state.read(rpcEndpointProvider);
    final failed = expectLater(
      state.read(rpcEndpointProvider.notifier).setCustom('rpc.example:443'),
      throwsA(isA<TimeoutException>()),
    );
    verification.completeError(
      TimeoutException('endpoint verification: timed out'),
    );
    await failed;
    await Future<void>.delayed(Duration.zero);
    expect(state.read(rpcEndpointProvider), previous);
    expect(
      await const FlutterSecureStorage().read(key: kRpcEndpointUrlKey),
      isNull,
    );
  });

  test('malformed input is rejected before the server is contacted', () async {
    var reads = 0;
    final state = container((_) async {
      reads++;
      return 'main';
    });
    await expectLater(
      state
          .read(rpcEndpointProvider.notifier)
          .setCustom('host with spaces:443'),
      throwsA(isA<FormatException>()),
    );
    expect(reads, 0);
  });
}
