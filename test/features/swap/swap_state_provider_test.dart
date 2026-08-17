import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/naming/ens_name_resolver.dart';
import 'package:zcash_wallet/src/core/naming/ens_rpc_transport.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/pay_selected_asset_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_composer_preferences_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/ens_resolver_provider.dart';

void main() {
  // evmChainIdFor / chainSupportsEnsNames now live in
  // lib/src/core/naming/ens_chains.dart and are covered by
  // test/core/naming/ens_chains_test.dart.
  group('submitDestinationAddress', () {
    late ProviderContainer container;
    late _FakeEnsNameResolver resolver;

    ProviderContainer buildContainer({
      _FakeEnsNameResolver? ensResolver,
      SwapAsset externalAsset = SwapAsset.usdc,
    }) {
      resolver = ensResolver ?? _FakeEnsNameResolver();
      final c = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_FakeAccountNotifier.new),
          swapIntentProvider.overrideWithValue(_FakeSwapProvider()),
          swapActivityStoreProvider.overrideWithValue(_FakeSwapStore()),
          swapComposerPreferencesStoreProvider.overrideWithValue(
            _FakeSwapStore(),
          ),
          paySelectedAssetStoreProvider.overrideWithValue(_FakeSwapStore()),
          ensResolverProvider.overrideWithValue(resolver),
        ],
      );
      addTearDown(c.dispose);
      // Seed the external asset before any assertions run.
      c.read(swapStateProvider.notifier).selectExternalAsset(externalAsset);
      return c;
    }

    setUp(() {
      container = buildContainer();
    });

    test('resolves an ENS name on an EVM chain and commits the address', () async {
      resolver.nextResult =
          '0x00000000219ab540356cbb839cbe05303d7705fa';

      final notifier = container.read(swapStateProvider.notifier);
      final ok = await notifier.submitDestinationAddress('vitalik.eth');

      expect(ok, isTrue);
      final state = container.read(swapStateProvider);
      expect(state.destinationText, resolver.nextResult);
      expect(state.destinationEnsName, 'vitalik.eth');
      expect(state.destinationResolveStatus, SwapDestinationResolveStatus.idle);
      expect(state.destinationResolveError, isNull);
      expect(resolver.calls, hasLength(1));
      expect(resolver.calls.single.chainId, 1);

      // The resolved 0x is what a built SwapAddressPlan carries forward.
      final plan = state.draftAddressPlan!;
      expect(plan.oneClickRecipient, resolver.nextResult);
    });

    test(
      'EVM→ZEC direction: the resolved address (not the name) lands in the '
      'refund role of the address plan',
      () async {
        resolver.nextResult = '0x00000000219ab540356cbb839cbe05303d7705fa';

        final notifier = container.read(swapStateProvider.notifier);
        notifier.selectDirection(SwapDirection.externalToZec);
        final ok = await notifier.submitDestinationAddress('vitalik.eth');

        expect(ok, isTrue);
        final state = container.read(swapStateProvider);
        expect(state.destinationText, resolver.nextResult);
        expect(state.destinationEnsName, 'vitalik.eth');

        final plan = state.draftAddressPlan!;
        expect(plan.oneClickRefundTo, resolver.nextResult);
        expect(plan.oneClickRefundTo.contains('.eth'), isFalse);
      },
    );

    test('a plain address commits unchanged with no ENS name', () async {
      final notifier = container.read(swapStateProvider.notifier);
      final ok = await notifier.submitDestinationAddress(
        '0x1111111111111111111111111111111111111111',
      );

      expect(ok, isTrue);
      final state = container.read(swapStateProvider);
      expect(
        state.destinationText,
        '0x1111111111111111111111111111111111111111',
      );
      expect(state.destinationEnsName, isNull);
      expect(state.destinationResolveStatus, SwapDestinationResolveStatus.idle);
      expect(resolver.calls, isEmpty);
    });

    test('an ENS name on a non-EVM chain fails closed', () async {
      container = buildContainer(externalAsset: SwapAsset.sol);
      final notifier = container.read(swapStateProvider.notifier);

      final ok = await notifier.submitDestinationAddress('vitalik.eth');

      expect(ok, isFalse);
      final state = container.read(swapStateProvider);
      expect(
        state.destinationResolveStatus,
        SwapDestinationResolveStatus.failed,
      );
      expect(
        state.destinationResolveError,
        'Names are not supported on this chain',
      );
      // destinationText must be untouched (still the default empty string).
      expect(state.destinationText, '');
      expect(resolver.calls, isEmpty);
    });

    test('resolver network failure sets failed status and does not commit', () async {
      resolver.nextError = const EnsResolutionException(
        EnsResolutionFailure.network,
        'gateway unreachable',
      );

      final notifier = container.read(swapStateProvider.notifier);
      final ok = await notifier.submitDestinationAddress('vitalik.eth');

      expect(ok, isFalse);
      final state = container.read(swapStateProvider);
      expect(
        state.destinationResolveStatus,
        SwapDestinationResolveStatus.failed,
      );
      expect(state.destinationResolveError, 'Could not resolve name');
      expect(state.destinationText, '');
      expect(state.destinationEnsName, isNull);
    });

    test('notRegistered/noRecord map to the no-address message', () async {
      resolver.nextError = const EnsResolutionException(
        EnsResolutionFailure.noRecord,
        'Name has no address for this chain',
      );
      final notifier = container.read(swapStateProvider.notifier);

      final ok = await notifier.submitDestinationAddress('vitalik.eth');

      expect(ok, isFalse);
      final state = container.read(swapStateProvider);
      expect(
        state.destinationResolveError,
        'Name has no address for this chain',
      );
    });

    test(
      'updateDestination after a successful name commit clears destinationEnsName',
      () async {
        resolver.nextResult =
            '0x00000000219ab540356cbb839cbe05303d7705fa';
        final notifier = container.read(swapStateProvider.notifier);
        await notifier.submitDestinationAddress('vitalik.eth');
        expect(
          container.read(swapStateProvider).destinationEnsName,
          'vitalik.eth',
        );

        notifier.updateDestination('0xother00000000000000000000000000000000');

        final state = container.read(swapStateProvider);
        expect(state.destinationEnsName, isNull);
        expect(state.destinationResolveError, isNull);
        expect(
          state.destinationText,
          '0xother00000000000000000000000000000000',
        );
      },
    );

    test('resolving status is observable before the resolver future settles', () async {
      final gate = _GatedFakeEnsNameResolver();
      final gatedContainer = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_FakeAccountNotifier.new),
          swapIntentProvider.overrideWithValue(_FakeSwapProvider()),
          swapActivityStoreProvider.overrideWithValue(_FakeSwapStore()),
          swapComposerPreferencesStoreProvider.overrideWithValue(
            _FakeSwapStore(),
          ),
          paySelectedAssetStoreProvider.overrideWithValue(_FakeSwapStore()),
          ensResolverProvider.overrideWithValue(gate),
        ],
      );
      addTearDown(gatedContainer.dispose);
      gatedContainer
          .read(swapStateProvider.notifier)
          .selectExternalAsset(SwapAsset.usdc);
      final notifier = gatedContainer.read(swapStateProvider.notifier);

      final future = notifier.submitDestinationAddress('vitalik.eth');
      // Yield one microtask so the pre-await state assignment is applied.
      await Future<void>.delayed(Duration.zero);
      expect(
        gatedContainer.read(swapStateProvider).destinationResolveStatus,
        SwapDestinationResolveStatus.resolving,
      );

      gate.complete('0x00000000219ab540356cbb839cbe05303d7705fa');
      final ok = await future;
      expect(ok, isTrue);
      expect(
        gatedContainer.read(swapStateProvider).destinationResolveStatus,
        SwapDestinationResolveStatus.idle,
      );
    });
  });
}

class _FakeAccountNotifier extends AccountNotifier {
  // Synchronous (not `async`) so the account state is already resolved by
  // the time the container is constructed. An async build() resolves one
  // microtask later and fires the notifier's account-change listener
  // (`_clearAccountScopedTransientState`) after test setup has already run,
  // stomping state the test just set.
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1testaddress',
  );
}

class _FakeSwapProvider implements SwapProvider {
  @override
  String get providerLabel => 'Fake';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async =>
      swapExternalAssets;

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}

class _FakeSwapStore
    implements SwapActivityStore, SwapComposerPreferencesStore,
        PaySelectedAssetStore {
  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => const [];

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {}

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async => null;

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {}

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async =>
      null;

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {}
}

class _UnusedEnsRpcTransport implements EnsRpcTransport {
  @override
  Future<String> ethCall({required String to, required String data}) {
    throw UnimplementedError('not used by fake resolver');
  }

  @override
  Future<String> ccipFetch({
    required String url,
    required String sender,
    required String data,
  }) {
    throw UnimplementedError('not used by fake resolver');
  }
}

class _ResolveCall {
  const _ResolveCall({required this.name, required this.chainId});
  final String name;
  final int chainId;
}

class _FakeEnsNameResolver extends EnsNameResolver {
  _FakeEnsNameResolver() : super(_UnusedEnsRpcTransport());

  String? nextResult;
  EnsResolutionException? nextError;
  final calls = <_ResolveCall>[];

  @override
  Future<String> resolveEvmAddress(
    String name, {
    required int chainId,
  }) async {
    calls.add(_ResolveCall(name: name, chainId: chainId));
    final error = nextError;
    if (error != null) throw error;
    return nextResult!;
  }
}

class _GatedFakeEnsNameResolver extends EnsNameResolver {
  _GatedFakeEnsNameResolver() : super(_UnusedEnsRpcTransport());

  final calls = <_ResolveCall>[];
  final _completer = Completer<String>();

  void complete(String result) {
    _completer.complete(result);
  }

  @override
  Future<String> resolveEvmAddress(
    String name, {
    required int chainId,
  }) async {
    calls.add(_ResolveCall(name: name, chainId: chainId));
    return _completer.future;
  }
}
