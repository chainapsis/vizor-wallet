import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/proxy/proxy_delegator_client.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegate.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegation.dart';
import 'package:zcash_wallet/src/rust/api/proxy_delegator.dart';
import 'package:zcash_wallet/src/rust/api/proxy_registry.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart';

import 'proxy_delegator_fakes.dart';
import 'proxy_registry_fakes.dart';
import 'proxy_registry_proof_fakes.dart';

/// Rust as the proxy tests see it: the one [RustLibApi] a test file
/// installs, which hands each proxy call to the fake a test put in
/// [registry], [delegator] or [proofs]. A call whose fake is missing, and
/// every other Rust call, fails the test.
///
/// `RustLib.initMock` runs once per isolate, so the shell stays and its
/// parts change: [useProxyRustFake] installs it for the file and empties it
/// before each test.
class ProxyRustFake implements RustLibApi {
  /// zcash_voting's registry client (`rust/src/api/proxy_registry.rs`).
  FakeProxyRegistryRust? registry;

  /// zcash_voting's delegator calls (`rust/src/api/proxy_delegator.rs`),
  /// and the ballot list paging the delegator client reads.
  FakeProxyDelegatorRust? delegator;

  /// The participation reader for registry entries
  /// (`rust/src/api/proxy_delegation.rs`).
  FakeRegistryProofRust? proofs;

  /// Removes every part.
  void clear() {
    registry = null;
    delegator = null;
    proofs = null;
  }

  FakeProxyRegistryRust get _registry =>
      registry ?? (throw StateError('no fake registry is installed'));

  FakeProxyDelegatorRust get _delegator =>
      delegator ?? (throw StateError('no fake delegator is installed'));

  FakeRegistryProofRust get _proofs =>
      proofs ?? (throw StateError('no fake proof reader is installed'));

  @override
  Future<ApiProxyServiceUrls?> crateApiProxyRegistryProxyServiceUrls({
    required List<int> dynamicConfigBytes,
  }) => _registry.serviceUrls(dynamicConfigBytes);

  @override
  String crateApiProxyRegistryProxyRegistryPagePath({
    required int startAfter,
  }) => _registry.registryPagePath(startAfter);

  @override
  Future<int?> crateApiProxyRegistryProxyRegistryNextStartAfter({
    required int startAfter,
    required int status,
    required List<int> body,
  }) => _registry.registryNextStartAfter(
    startAfter: startAfter,
    status: status,
    body: body,
  );

  @override
  Future<ApiProxyRegistryCache> crateApiProxyRegistryBuildProxyRegistryCache({
    required String network,
    required List<ApiRegistryPage> pages,
  }) => _registry.buildRegistryCache(network: network, pages: pages);

  @override
  Future<void> crateApiProxyRegistryConfigureRegtestWalletListKey({
    required String keyId,
    required String publicKey,
  }) => _registry.configureRegtestWalletListKey(
    keyId: keyId,
    publicKey: publicKey,
  );

  @override
  Future<ApiWalletListResolution> crateApiProxyRegistryResolveProxyWalletList({
    required String network,
    required List<int> document,
    Uint8List? stored,
  }) => _registry.resolveWalletList(
    network: network,
    document: document,
    stored: stored,
  );

  @override
  Future<Uint8List?> crateApiProxyRegistryProxyWalletListPicture({
    required String network,
    required List<int> walletList,
    required int delegateIndex,
  }) => _registry.walletListPicture(
    network: network,
    walletList: walletList,
    delegateIndex: delegateIndex,
  );

  @override
  Future<ProxyDelegateBrowse> crateApiProxyRegistryProxyBrowse({
    required ApiProxyRegistryView view,
  }) => _registry.browse(view);

  @override
  Future<ApiDelegateLookup> crateApiProxyRegistryLookupProxyDelegate({
    required ApiProxyRegistryView view,
    required String text,
  }) => _registry.lookup(view, text);

  @override
  Future<List<ApiConfirmedDelegate>> crateApiProxyRegistryCheckProxyDelegates({
    required String network,
    Uint8List? walletList,
    int? firstNewIndex,
    required ProxyAllocationRequest request,
    required List<ApiProvenRegistryEntry> proven,
  }) => _registry.checkDelegates(
    network: network,
    walletList: walletList,
    firstNewIndex: firstNewIndex,
    request: request,
    proven: proven,
  );

  @override
  Future<List<String>> crateApiProxyDelegationProxyRegistryEntryKeys({
    required List<int> delegateIndices,
  }) => _proofs.entryKeys(delegateIndices);

  @override
  Future<List<ApiProvenRegistryEntry>>
  crateApiProxyDelegationVerifyProxyRegistryEntries({
    required String network,
    required List<int> delegateIndices,
    required String evidence,
    required PlatformInt64 nowSeconds,
  }) => _proofs.verify(
    network: network,
    delegateIndices: delegateIndices,
    evidence: evidence,
  );

  @override
  Future<ApiProxyAvailability>
  crateApiProxyDelegatorProxyDelegationAvailability({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required ApiProxyChainAnswers chain,
    required ApiGovNullifierProof govNullifiers,
    required ApiProxyRoundTiming timing,
  }) => _delegator.availability(
    account: ProxyDelegatorAccount(dbPath: dbPath, accountUuid: accountUuid),
    roundId: roundId,
    chain: chain,
    govNullifiers: govNullifiers,
    timing: timing,
  );

  @override
  Future<ProxyAllocationPreview> crateApiProxyDelegatorPreviewProxyAllocation({
    required String dbPath,
    required String accountUuid,
    required ProxyAllocationRequest request,
    required ApiProxyRoundTiming timing,
  }) => _delegator.preview(
    account: ProxyDelegatorAccount(dbPath: dbPath, accountUuid: accountUuid),
    request: request,
    timing: timing,
  );

  @override
  Future<void> crateApiProxyDelegatorCommitProxyAllocation({
    required String dbPath,
    required String accountUuid,
    required ProxyAllocationRequest request,
    required ProxyAllocationPreview confirmed,
    required List<DelegateCheck> checks,
    required ApiProxyRoundTiming timing,
    required List<int> roster,
  }) => _delegator.commit(
    account: ProxyDelegatorAccount(dbPath: dbPath, accountUuid: accountUuid),
    request: request,
    confirmed: confirmed,
    checks: checks,
    timing: timing,
    roster: roster,
  );

  @override
  Future<ApiProxyAllocationStatus?>
  crateApiProxyDelegatorProxyAllocationStatus({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<Uint8List> ballotPages,
    required ApiProxyRoundPhase phase,
  }) => _delegator.status(
    account: ProxyDelegatorAccount(dbPath: dbPath, accountUuid: accountUuid),
    roundId: roundId,
    ballotPages: ballotPages,
    phase: phase,
  );

  @override
  Future<ApiProxyDelegationProgress?>
  crateApiProxyDelegatorProxyDelegationProgress({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<Uint8List> ballotPages,
    required ApiProxyRoundPhase phase,
  }) => _delegator.progress(
    account: ProxyDelegatorAccount(dbPath: dbPath, accountUuid: accountUuid),
    roundId: roundId,
    ballotPages: ballotPages,
    phase: phase,
  );

  /// The ballot list's paging the delegator client reads.
  @override
  Future<ApiDelegateBallotSearch> crateApiProxyDelegateDelegateBallotPage({
    required String roundId,
    required int startAfter,
    required List<int> page,
    int? delegateIndex,
  }) async {
    return ApiDelegateBallotSearch(
      nextStartAfter: await _delegator.ballotsNextStartAfter(
        roundId: roundId,
        startAfter: startAfter,
        page: Uint8List.fromList(page),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// The shell every proxy test file shares.
final proxyRust = ProxyRustFake();

bool _installed = false;

/// Installs [proxyRust] as Rust for this test file and empties it before
/// each test. Call it once at the top of `main`; a test then sets the parts
/// it needs.
void useProxyRustFake() {
  setUpAll(() {
    if (_installed) return;
    RustLib.initMock(api: proxyRust);
    _installed = true;
  });
  setUp(proxyRust.clear);
}
