import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import '../../../../../main.dart' show log;
import '../../../../rust/api/swap_zwap.dart' as zwap;

/// In-app driver for a non-custodial zwap **BTC→ZEC (b2z)** atomic swap.
///
/// This is the Flutter counterpart to the zwap SDK's `runB2z` orchestrator,
/// proven to settle end-to-end on regtest. All fund-critical crypto runs in
/// Rust over FRB ([zwap] bindings) — the wallet seed never leaves Rust; this
/// Dart layer only does the orderbook/indexer/poold HTTP plumbing and the
/// stateless FSM walk. Mirrors how the existing NEAR adapter is pure-Dart HTTP.
///
/// What it does NOT do yet (documented gaps, not stubs that pretend):
///  - **Hashbind proof for order creation.** b2z order creation needs a
///    ProveKit hashbind proof of the wallet's `k`. On-device proving (compiling
///    ProveKit into the Rust lib) is a separate effort; until then a
///    [hashbindProver] is injected (e.g. an HTTP prove helper for regtest).
///  - **BTC lock funding.** On a real chain the user funds the lock from their
///    own BTC wallet; this client surfaces the address + amount via [onDeposit].
///
/// The crypto path it DOES own in-process: derive the wallet's Phase0 half,
/// derive + re-verify the joint Orchard UA + the BTC P2WSH lock, reveal the
/// swap secret, and — once the solver reveals `k_b` on its BTC claim —
/// reconstruct the joint `ask`, trial-decrypt the joint note, build the Orchard
/// sweep, and broadcast it via the indexer.
class ZwapSwapClient {
  ZwapSwapClient({
    required this.orderbookUrl,
    required this.indexerUrl,
    required this.pooldUrl,
    required this.network,
    required this.hashbindProver,
    this.relayerUrl = 'http://localhost:3713',
    this.priceUrl = 'http://localhost:3600',
    this.evmRpcUrl = 'http://localhost:8545',
    this.evmRpcByChainId = const {},
    this.pollInterval = const Duration(seconds: 3),
    HttpClient? httpClient,
  }) : _http = httpClient ?? HttpClient();

  /// eth-relayer HTTP base (e.g. `http://localhost:3713`) — the gasless
  /// `claim_buy` submit path for z2e (the relayer pays gas + signs its own
  /// envelope; it never sees a user key).
  final String relayerUrl;

  /// Price-server base (e.g. `http://localhost:3600`) — serves the signed
  /// `/v1/attest` quotes (fee + spread baked in). The order MUST carry this
  /// attestation so the solver funds at the attested market price, not a
  /// wallet-chosen rate.
  final String priceUrl;

  /// Orderbook-v2 base (e.g. `http://localhost:3310` for regtest).
  final String orderbookUrl;

  /// Indexer base incl. `/v1` (e.g. `http://localhost:3500/v1`).
  final String indexerUrl;

  /// Poold base (e.g. `http://localhost:3720`).
  final String pooldUrl;

  /// EVM JSON-RPC base (e.g. `http://localhost:8545` for regtest anvil). Used
  /// ONLY by the z2e slot-divergence guard ([relayZ2eClaim]) to read the
  /// on-chain `ZwapHtlc.slots(evmSlotId)` state before relaying a claim. Read
  /// only; never signs.
  final String evmRpcUrl;

  /// Per-chainId JSON-RPC bases for the slot guard when a swap can target more
  /// than one EVM chain (in-app chain selector: 31337 'ethereum' :8545,
  /// 31338 'base' :8546 on regtest). Falls back to [evmRpcUrl] for any chainId
  /// not present here.
  final Map<int, String> evmRpcByChainId;

  /// The read-only JSON-RPC base for [chainId]'s slot guard, defaulting to the
  /// primary [evmRpcUrl] when the chain is not in [evmRpcByChainId].
  String _evmRpcFor(int chainId) => evmRpcByChainId[chainId] ?? evmRpcUrl;

  /// `mainnet` | `testnet` | `regtest`.
  final String network;

  /// Generates the ProveKit hashbind proof bytes for a 32-byte BE scalar (hex).
  /// Injected so the heavy prover stays pluggable (HTTP helper today,
  /// on-device Rust ProveKit later).
  final Future<List<int>> Function(String kBeHex) hashbindProver;

  final Duration pollInterval;
  final HttpClient _http;

  Future<Map<String, dynamic>> _getJson(String url, {String? bearer}) async {
    final req = await _http.getUrl(Uri.parse(url));
    if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return _decode('GET', url, res.statusCode, body);
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> payload, {
    String? bearer,
  }) async {
    final req = await _http.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    req.add(utf8.encode(jsonEncode(payload)));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return _decode('POST', url, res.statusCode, body);
  }

  /// POST a raw text body (used for `/v1/zec/broadcast`, which takes the raw tx
  /// hex verbatim). A 2xx is success; a rejection that means "this exact spend
  /// already landed" (duplicate tx / spent nullifier) is treated as benign
  /// success since the sweep goal — the note spent on-chain — is met.
  Future<void> _postRawText(String url, String body) async {
    final req = await _http.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.text;
    req.add(utf8.encode(body));
    final res = await req.close();
    final respBody = (await res.transform(utf8.decoder).join()).trim();
    if (res.statusCode < 400) return;
    final lower = respBody.toLowerCase();
    final benign = lower.contains('already') ||
        lower.contains('duplicate') ||
        lower.contains('spent') ||
        lower.contains('missing inputs');
    if (benign) return;
    throw StateError('zwap POST $url → HTTP ${res.statusCode}: $respBody');
  }

  Map<String, dynamic> _decode(String method, String url, int status, String body) {
    if (status >= 400) {
      throw StateError('zwap $method $url → HTTP $status: ${body.trim()}');
    }
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw StateError('zwap $method $url → non-JSON body: ${body.trim()}');
    }
  }

  /// ed25519 challenge–response auth → bearer session token. The seed is
  /// signed in Rust; only the pubkey + signature cross the wire.
  Future<String> authenticate(String seedHex) async {
    final pubkey = await zwap.zwapObIdentityPubkeyHex(seedHex: seedHex);
    // /auth/challenge takes an empty body and returns { challenge }.
    final ch = await _postJson('$orderbookUrl/auth/challenge', const {});
    final challenge = ch['challenge'] as String;
    final sigHex = await zwap.zwapObSignChallengeHex(seedHex: seedHex, challenge: challenge);
    // /auth/verify body: { authPubkey, sigHex, challenge } → { sessionToken, identityId }.
    final verify = await _postJson('$orderbookUrl/auth/verify', {
      'authPubkey': pubkey,
      'sigHex': sigHex,
      'challenge': challenge,
    });
    return verify['sessionToken'] as String;
  }

  static String _toHex(List<int> bytes) {
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(hex[(b >> 4) & 0xf]);
      sb.write(hex[b & 0xf]);
    }
    return sb.toString();
  }

  static List<int> _fromHex(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = <int>[];
    for (var i = 0; i + 1 < h.length; i += 2) {
      out.add(int.parse(h.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  /// Recover the authoritative swap snapshot from the orderbook.
  Future<Map<String, dynamic>> recover(String token, String swapId) =>
      _getJson('$orderbookUrl/recover?swapId=$swapId', bearer: token);

  /// GET `/v1/attest` — the price-server's SIGNED, fee-baked quote for
  /// `{from,to,amount(source-smallest),chain}`. The returned [ZwapAttestation]
  /// carries the raw signed payload (which MUST round-trip verbatim into the
  /// order's `priceAttestation` so the OB/solver re-verify the signature and
  /// fund at the attested price) plus the parsed dest output amount + USD sides.
  /// `chain` is the EVM chain name (`ethereum`) for EVM legs, empty otherwise.
  Future<ZwapAttestation> fetchAttestation({
    required String from,
    required String to,
    required BigInt amountSmallest,
    String chain = '',
  }) async {
    var qs = 'from=$from&to=$to&amount=$amountSmallest';
    if (chain.isNotEmpty) qs += '&chain=$chain';
    final raw = await _getJson('$priceUrl/v1/attest?$qs');
    final out = raw['outputAmount'] as Map<String, dynamic>?;
    final outSmallest = out?['smallest'];
    if (outSmallest == null) {
      throw StateError('zwap attest: no outputAmount for $from→$to amount=$amountSmallest');
    }
    double? toDouble(Object? v) =>
        v == null ? null : double.tryParse('$v');
    return ZwapAttestation(
      raw: raw,
      outputSmallest: BigInt.parse('$outSmallest'),
      sourceUsd: toDouble(raw['sourceUsd']),
      destUsd: toDouble(out?['usd']),
    );
  }

  /// The node's currently-active Orchard consensus branch id (int), from
  /// indexerd `/v1/zec/consensus` (`{"branchIdHex":"5437f330"}`). Null if the
  /// lookup fails — the Rust spend then falls back to its NU6 default.
  Future<int?> _consensusBranchId() async {
    try {
      final r = await _getJson('$_indexerBase/v1/zec/consensus');
      final hex = r['branchIdHex'] as String?;
      if (hex == null || hex.isEmpty) return null;
      return int.parse(hex, radix: 16);
    } catch (_) {
      return null;
    }
  }

  /// The current EVM tip height for `chainId` from the indexer `/v1/eth/tip`.
  /// The FE picks the proxy deadlines t0Abs/t1Abs as `tip + offset`.
  Future<int> ethTipHeight(int chainId) async {
    final r = await _getJson('$_indexerBase/v1/eth/tip');
    final chains = (r['chains'] as List?) ?? const [];
    for (final c in chains) {
      if (c is Map && (c['chainId'] as num?)?.toInt() == chainId) {
        return ((c['height'] ?? 0) as num).toInt();
      }
    }
    return 0;
  }

  /// The current ZEC tip height from the indexer — the upper bound for the
  /// joint-note range scan.
  Future<int> zecTipHeight() async {
    final r = await _getJson('$_indexerBase/v1/zec/tip');
    return ((r['height'] ?? r['tip'] ?? 0) as num).toInt();
  }

  /// Reveal the b2z swap secret to the orderbook (`BothFunded → SecretRevealed`)
  /// so the solver can claim the BTC lock. The OB verifies `SHA256(secret) ==
  /// swap_hash` before accepting. `secretHex` derives from the wallet seed +
  /// `deriveId` (`zwapRevealSecretHex`). Idempotent server-side.
  Future<void> revealSecret(String token, String obSwapId, String secretHex) async {
    await _postJson('$orderbookUrl/api/swaps/$obSwapId/reveal-secret',
        {'secret': secretHex}, bearer: token);
  }

  /// Create a b2z order and return the derived material the wallet presents.
  ///
  /// Assembles the flat `feMaterial` exactly like the SDK `buildFeMaterialAsync`
  /// (all fields from Rust via [zwap.zwapB2ZOrderInputs]), with the hashbind
  /// proof produced by feeding the raw scalar `k_a` to [hashbindProver]. Posts
  /// the order, then derives + re-verifies the joint ZEC UA + BTC lock address
  /// from the matched solver half.
  Future<ZwapB2zOrder> createB2zOrder({
    required String seedHex,
    required String token,
    required String swapId,
    required int amountSat,
    required LockTimelocks timelocks,
    required String receiveRawAddress,
    required int minReceiveZats,
  }) async {
    // The DLEq/hashbind circuits prove over k_a < 2^251; a raw reduced k_a
    // exceeds that often, so derive a "safe" id (matches the SDK). ALL key
    // material (swap_hash, joint ak, ask) binds to `deriveId` — settlement MUST
    // use it, never the base `swapId` or the OB-assigned `obSwapId`.
    final deriveId = await zwap.zwapFindSafeSwapId(seedHex: seedHex, baseId: swapId);
    final inputs = await zwap.zwapB2ZOrderInputs(seedHex: seedHex, swapId: deriveId);
    // The prover takes the raw k_a scalar; returns the NoirProof bytes whose hex
    // goes verbatim into feMaterial.hashbindProof (matches the SDK prover path).
    final proofBytes = await hashbindProver(inputs.kBeHex);
    final hashbindProofHex = _toHex(proofBytes);

    final nonceResp = await _getJson('$orderbookUrl/nonce/max', bearer: token);
    final nonce = (nonceResp['nextNonce'] ?? 0) as int;

    // Flat feMaterial — byte-for-byte the SDK `FeMaterial` shape for a BTC leg.
    final feMaterial = {
      'hA': inputs.hA,
      'swapHash': inputs.swapHash, // b2z: user owns the secret
      'akA': inputs.akA,
      'nskA': inputs.nskA,
      'lockPubkey': inputs.lockPubkey,
      'refundPubkey': inputs.refundPubkey,
      'hashbindProof': hashbindProofHex,
      'proofKind': 'hashbind',
    };
    // ATTESTED PRICE: the ZEC the solver funds (shieldedValueZats) is the
    // price-server's signed output for the BTC deposit — NOT a 1:1 / local rate.
    // The signed attestation rides along so the OB + solver re-verify it and
    // fund at exactly this price.
    final attest = await fetchAttestation(
        from: 'btc', to: 'zec', amountSmallest: BigInt.from(amountSat));
    // Dust guard on the ATTESTED ZEC output (what the solver actually funds the
    // joint note with) — NOT the BTC deposit sats. The wallet later sweeps this
    // note minus the network fee, so a note at/below the sweep floor is
    // unrecoverable dust. Checking BTC sats here would be a unit error (BTC
    // satoshis vs ZEC zatoshis) that only looked right under a 1:1 price.
    final fundedZats = attest.outputSmallest;
    if (fundedZats < BigInt.from(minReceiveZats)) {
      throw StateError(
          'Amount too small: this swap funds about $fundedZats zatoshi of ZEC, '
          'below the $minReceiveZats zat minimum needed to cover the network '
          'sweep fee. Increase the amount and retry.');
    }
    final orderResp = await _postJson('$orderbookUrl/api/orders', {
      'direction': 'b2z',
      'amount': '$amountSat',
      'nonce': nonce,
      'clientSwapId': deriveId, // stable deriveId — key material hangs off this
      'shieldedValueZats': '${attest.outputSmallest}',
      // The wallet's fresh Orchard sweep destination, committed at creation
      // (43-byte raw hex). The wallet sweeps the joint note here after claim.
      'recvAddr': receiveRawAddress,
      'feMaterial': feMaterial,
      'priceAttestation': attest.raw,
    }, bearer: token);
    // The orderbook assigns its OWN swapId for FSM / recover ops; key material
    // stays bound to our `deriveId` (== clientSwapId). Keep the two SEPARATE:
    // OB calls use obSwapId; all derivation uses deriveId.
    final obSwapId = (orderResp['swapId'] ?? deriveId) as String;

    // Wait for the matcher to assign a poold pair, then fetch the solver half.
    final solver = await _awaitSolverHalf(token, obSwapId);
    final material = await zwap.zwapDeriveB2ZMaterial(
      seedHex: seedHex,
      swapId: deriveId, // derive against our deriveId, not the OB swapId
      solverAkSec1: solver['akSec1'] as String,
      solverNskLe: solver['nskLe'] as String,
      solverBB: solver['bB'] as String,
      solverHB: solver['hB'] as String,
      t1: timelocks.t1,
      t2: timelocks.t2,
      network: network,
    );

    // Phase0: report the derived watch material so the OB writes the BTC + ZEC
    // leg descriptors and indexer-v2 watches the lock address for the deposit.
    // WITHOUT this the OB never links the on-chain deposit to the order and the
    // reaper cancels it as stale. `btcScriptHex` is the P2WSH scriptPubKey
    // (`OP_0 <sha256(witnessScript)>`) — the watch target.
    final wsBytes = _fromHex(material.witnessScriptHex);
    final spkHex = '0020${_toHex(sha256.convert(wsBytes).bytes)}';
    await _postJson('$orderbookUrl/api/swaps/$obSwapId/phase0', {
      'btcScriptHex': spkHex,
      'lockWitnessScriptHex': material.witnessScriptHex,
      'hashes': {
        'hA': material.hAHex,
        'hB': solver['hB'],
        'swapHash': material.swapHashHex,
      },
      'zecJointAddress': material.jointZecAddress,
      'zecJointUfvk': material.jointZecUfvk,
      'zecIvk': material.jointZecIvkHex,
      'zecDiversifier': material.jointZecDiversifierHex,
      'zecAk': material.jointZecAkHex,
      'zecNk': material.jointZecNkHex,
      'zecRivk': material.jointZecRivkHex,
    }, bearer: token);

    return ZwapB2zOrder(
      swapId: obSwapId,
      deriveId: deriveId,
      btcLockAddress: material.btcLockAddress,
      witnessScriptHex: material.witnessScriptHex,
      jointZecAddress: material.jointZecAddress,
      jointZecUfvk: material.jointZecUfvk,
      jointZecNkHex: material.jointZecNkHex,
      jointZecRivkHex: material.jointZecRivkHex,
      jointZecAkHex: material.jointZecAkHex,
      jointZecIvkHex: material.jointZecIvkHex,
      jointZecDiversifierHex: material.jointZecDiversifierHex,
      receiveRawAddress: receiveRawAddress,
    );
  }

  /// Re-derive the full b2z settlement material for an EXISTING order without
  /// creating a new one. This is the recovery counterpart to [createB2zOrder]:
  /// it re-fetches the solver's already-published Phase0 half from poold (via
  /// the OB `recover` → `pooldAssignment` path) and re-runs [zwap.zwapDeriveB2ZMaterial]
  /// against the wallet seed + the order's `deriveId`. Because the derivation is
  /// deterministic in `(seed, deriveId, solverHalf, t1, t2, network)`, it
  /// reproduces the identical joint ZEC keys / lock the wallet saw at creation.
  ///
  /// Used to rebuild a `_Settle` from a minimal record (seed + obSwapId +
  /// deriveId) so an orphaned swap can be resumed after all in-memory + full
  /// persisted state is gone. Does NOT re-post the order or re-run phase0 — the
  /// order already exists in the orderbook. `receiveRawAddress` is the (possibly
  /// fresh) sweep destination; the ZEC lands there regardless of the address the
  /// original order committed to, since the sweep spends the joint note.
  Future<ZwapB2zOrder> deriveB2zMaterialForRecovery({
    required String seedHex,
    required String token,
    required String obSwapId,
    required String deriveId,
    required String receiveRawAddress,
    LockTimelocks timelocks = const LockTimelocks(),
  }) async {
    final solver = await _awaitSolverHalf(token, obSwapId);
    final material = await zwap.zwapDeriveB2ZMaterial(
      seedHex: seedHex,
      swapId: deriveId, // derive against deriveId, not the OB swapId
      solverAkSec1: solver['akSec1'] as String,
      solverNskLe: solver['nskLe'] as String,
      solverBB: solver['bB'] as String,
      solverHB: solver['hB'] as String,
      t1: timelocks.t1,
      t2: timelocks.t2,
      network: network,
    );
    return ZwapB2zOrder(
      swapId: obSwapId,
      deriveId: deriveId,
      btcLockAddress: material.btcLockAddress,
      witnessScriptHex: material.witnessScriptHex,
      jointZecAddress: material.jointZecAddress,
      jointZecUfvk: material.jointZecUfvk,
      jointZecNkHex: material.jointZecNkHex,
      jointZecRivkHex: material.jointZecRivkHex,
      jointZecAkHex: material.jointZecAkHex,
      jointZecIvkHex: material.jointZecIvkHex,
      jointZecDiversifierHex: material.jointZecDiversifierHex,
      receiveRawAddress: receiveRawAddress,
    );
  }

  /// Create a **z2b** (ZEC→BTC) order — the give-ZEC direction. The user funds
  /// the joint ZEC note and CLAIMS the solver-funded BTC lock. Mirrors
  /// [createB2zOrder] with the role-flip: the FE material posts the user's
  /// per-swap BTC CLAIM pubkey (as `refundPubkey`) and NO `swapHash` (the solver
  /// owns the secret), and the derived lock/hashlocks are role-flipped inside
  /// `zwap_derive_z2b_material`.
  ///
  /// [amountSat] is the BTC the user RECEIVES; [shieldedValueZats] is the ZEC the
  /// user deposits into the joint note (distinct amounts, WP-5).
  Future<ZwapZ2bOrder> createZ2bOrder({
    required String seedHex,
    required String token,
    required String swapId,
    required int amountSat,
    required int shieldedValueZats,
    required LockTimelocks timelocks,
  }) async {
    final deriveId = await zwap.zwapFindSafeSwapId(seedHex: seedHex, baseId: swapId);
    final inputs = await zwap.zwapZ2BOrderInputs(seedHex: seedHex, swapId: deriveId);
    final proofBytes = await hashbindProver(inputs.kBeHex);
    final hashbindProofHex = _toHex(proofBytes);

    final nonceResp = await _getJson('$orderbookUrl/nonce/max', bearer: token);
    final nonce = (nonceResp['nextNonce'] ?? 0) as int;

    // z2b feMaterial: no `swapHash` (solver owns the secret); `refundPubkey`
    // carries the user's per-swap BTC CLAIM pubkey `b_b`.
    final feMaterial = {
      'hA': inputs.hA,
      'akA': inputs.akA,
      'nskA': inputs.nskA,
      'lockPubkey': inputs.lockPubkey,
      'refundPubkey': inputs.claimPubkey,
      'hashbindProof': hashbindProofHex,
      'proofKind': 'hashbind',
    };
    // ATTESTED PRICE: the BTC the solver locks (`amount`) is the price-server's
    // signed output for the ZEC the user deposits (source), not a local rate.
    final attest = await fetchAttestation(
        from: 'zec', to: 'btc', amountSmallest: BigInt.from(shieldedValueZats));
    final orderResp = await _postJson('$orderbookUrl/api/orders', {
      'direction': 'z2b',
      'amount': '${attest.outputSmallest}',
      'nonce': nonce,
      'clientSwapId': deriveId,
      'shieldedValueZats': '$shieldedValueZats',
      'feMaterial': feMaterial,
      'priceAttestation': attest.raw,
    }, bearer: token);
    final obSwapId = (orderResp['swapId'] ?? deriveId) as String;

    final solver = await _awaitSolverHalfZ2b(token, obSwapId);
    final material = await zwap.zwapDeriveZ2BMaterial(
      seedHex: seedHex,
      swapId: deriveId,
      solverAkSec1: solver['akSec1'] as String,
      solverNskLe: solver['nskLe'] as String,
      solverHB: solver['hB'] as String,
      solverRefundPubkey: solver['refundPubkey'] as String,
      solverSwapHash: solver['swapHash'] as String,
      t1: timelocks.t1,
      t2: timelocks.t2,
      network: network,
    );

    // Phase0: report the role-flipped watch material so the OB writes the BTC +
    // ZEC leg descriptors and the indexer watches the joint UA for the deposit.
    final wsBytes = _fromHex(material.witnessScriptHex);
    final spkHex = '0020${_toHex(sha256.convert(wsBytes).bytes)}';
    await _postJson('$orderbookUrl/api/swaps/$obSwapId/phase0', {
      'btcScriptHex': spkHex,
      'lockWitnessScriptHex': material.witnessScriptHex,
      'hashes': {
        'hA': solver['hB'], // lock hA = solver's hashlock
        'hB': material.hBHex, // lock hB = SHA256(user k_be)
        'swapHash': material.swapHashHex, // solver-owned
      },
      'zecJointAddress': material.jointZecAddress,
      'zecJointUfvk': material.jointZecUfvk,
      'zecIvk': material.jointZecIvkHex,
      'zecDiversifier': material.jointZecDiversifierHex,
      'zecAk': material.jointZecAkHex,
      'zecNk': material.jointZecNkHex,
      'zecRivk': material.jointZecRivkHex,
    }, bearer: token);

    return ZwapZ2bOrder(
      swapId: obSwapId,
      deriveId: deriveId,
      btcLockAddress: material.btcLockAddress,
      witnessScriptHex: material.witnessScriptHex,
      jointZecAddress: material.jointZecAddress,
      jointZecUfvk: material.jointZecUfvk,
      jointZecNkHex: material.jointZecNkHex,
      jointZecRivkHex: material.jointZecRivkHex,
      jointZecAkHex: material.jointZecAkHex,
      jointZecIvkHex: material.jointZecIvkHex,
      jointZecDiversifierHex: material.jointZecDiversifierHex,
    );
  }

  /// z2b solver-half resolution — same pool-pair fetch as [_awaitSolverHalf] but
  /// extracts the fields the role-flipped lock needs: `refundPubkey` (the
  /// solver's `br_a`) and `swapHash` (the solver-owned secret hash) from the
  /// LOCK entry, `akSec1`/`nskLe` from the SHIELDED entry.
  Future<Map<String, dynamic>> _awaitSolverHalfZ2b(String token, String swapId) async {
    for (var i = 0; i < 60; i++) {
      final snap = await recover(token, swapId);
      final assignment = snap['pooldAssignment'];
      if (assignment is Map<String, dynamic> &&
          assignment['lockId'] != null &&
          assignment['shieldedId'] != null) {
        final lock = (await _getJson('$pooldUrl/pool/${assignment['lockId']}'))['public']
            as Map<String, dynamic>;
        final shielded =
            (await _getJson('$pooldUrl/pool/${assignment['shieldedId']}'))['public']
                as Map<String, dynamic>;
        final swapHash = lock['swapHash'] ?? shielded['swapHash'];
        if (swapHash == null) {
          throw StateError('zwap z2b: solver swapHash missing from pool pair');
        }
        return {
          'akSec1': shielded['akSec1'],
          'nskLe': shielded['nskLe'],
          'hB': lock['hB'] ?? shielded['hB'],
          'refundPubkey': lock['refundPubkey'],
          'swapHash': swapHash,
        };
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError('zwap: pooldAssignment not published for $swapId');
  }

  /// Build + sign the z2b BTC branch-1 claim in Rust and broadcast it via
  /// indexerd's esplora-compat `POST /v1/btc/tx` (text/plain raw hex, matching
  /// the SDK `claimBtcInBrowser`). Returns the txid; a benign "already
  /// claimed/spent" response still yields the local txid (a real on-chain spend
  /// exists for the OB watcher to confirm).
  Future<String> signAndBroadcastZ2bClaim({
    required String seedHex,
    required String deriveId,
    required String lockTxid,
    required int lockVout,
    required int lockValueSat,
    required String witnessScriptHex,
    required String swapSecretHex,
    required String destSpkHex,
    required int feeSat,
  }) async {
    final signed = await zwap.zwapSignZ2BBtcClaimTx(
      seedHex: seedHex,
      swapId: deriveId,
      lockTxid: lockTxid,
      lockVout: lockVout,
      lockValueSat: BigInt.from(lockValueSat),
      witnessScriptHex: witnessScriptHex,
      swapSecretHex: swapSecretHex,
      destSpkHex: destSpkHex,
      feeSat: BigInt.from(feeSat),
    );
    await _postRawText('$_indexerBase/v1/btc/tx', signed.rawTxHex);
    return signed.txid;
  }

  /// Report a claim txid to the OB (`POST /api/swaps/{id}/claim-result`) so the
  /// FSM advances even if the on-chain watcher is slow (symmetry with the SDK
  /// `reportClaimResult`). Best-effort; the watcher is the source of truth.
  Future<void> reportClaimResult(String token, String obSwapId, String txid) async {
    await _postJson('$orderbookUrl/api/swaps/$obSwapId/claim-result', {'txid': txid},
        bearer: token);
  }

  /// Create a **z2e** (ZEC→ETH/USDC) order — the EVM give-ZEC direction. The
  /// user funds the joint ZEC note and CLAIMS a solver-funded singleton
  /// `ZwapHtlc` lock by completing the solver's `claim_buy` adaptor with its own
  /// `k_be`. Uses the DLEq FE proof (EVM leg), posts the user's per-swap claim
  /// pubkey as `refundPubkey` + NO `swapHash` (solver-owned), and pre-shares the
  /// `refund_to_initiator` sig_b (the solver's t1 inactivity-refund half).
  Future<ZwapZ2eOrder> createZ2eOrder({
    required String seedHex,
    required String token,
    required String swapId,
    required String amountWei,
    required int shieldedValueZats,
    required String recipientEvmAddr,
    String erc20 = '',
    int chainId = 31337,
    // The price-server chain name for the attestation ('ethereum' = 31337,
    // 'base' = 31338 on regtest). MUST agree with [chainId] — a mismatch quotes
    // the wrong chain's market. Driven by the in-app chain selector.
    String chainName = 'ethereum',
    // MUST equal the solver/OB z2e EVM-leg `t1Blocks` (config-v3: z2e =>
    // {t1Blocks: 200, t2Blocks: 400}). The EVM slotId folds `timelock`
    // (keccak(swap_hash ‖ b_a ‖ b_b ‖ buyer ‖ initiator ‖ timelock_be ‖ token)),
    // and the solver funds its FundLock with `ev.timelocks.t1_blocks` = 200.
    // Any other value here derives a slotId that DIVERGES from the on-chain lock
    // → the eth leg wedges `pending`, the user's claim targets an empty slot.
    // (The old 5000 default was a stale value from before the solver moved to the
    // config-driven t1Blocks; e2z is unaffected — it uses a CREATE2-salt slot.)
    int timelock = 200,
  }) async {
    final deriveId = await zwap.zwapFindSafeSwapId(seedHex: seedHex, baseId: swapId);
    final inputs = await zwap.zwapZ2EOrderInputs(seedHex: seedHex, swapId: deriveId);

    final nonceResp = await _getJson('$orderbookUrl/nonce/max', bearer: token);
    final nonce = (nonceResp['nextNonce'] ?? 0) as int;

    // ATTESTED PRICE: the ETH/USDC the solver locks (`amount`) is the
    // price-server's signed output for the ZEC deposit (source), not a local
    // rate. The passed `amountWei` (a local estimate) is superseded by this.
    final attest = await fetchAttestation(
      from: 'zec',
      to: erc20.isNotEmpty ? 'usdc' : 'eth',
      amountSmallest: BigInt.from(shieldedValueZats),
      chain: chainName,
    );

    final orderResp = await _postJson('$orderbookUrl/api/orders', {
      'direction': 'z2e',
      'amount': '${attest.outputSmallest}',
      'nonce': nonce,
      'clientSwapId': deriveId,
      'shieldedValueZats': '$shieldedValueZats',
      'priceAttestation': attest.raw,
      'recipientEvmAddr': recipientEvmAddr,
      'evmChainId': chainId,
      if (erc20.isNotEmpty) 'erc20': erc20,
      'feMaterial': {
        'hA': inputs.hA,
        'akA': inputs.akA,
        'nskA': inputs.nskA,
        'lockPubkey': inputs.lockPubkey,
        'refundPubkey': inputs.claimPubkey,
        'hashbindProof': inputs.dleqProof,
        'proofKind': 'dleq',
      },
    }, bearer: token);
    final obSwapId = (orderResp['swapId'] ?? deriveId) as String;

    final s = await _awaitSolverHalfZ2e(token, obSwapId);
    final token20 = erc20.isNotEmpty
        ? erc20
        : '0x0000000000000000000000000000000000000000';
    final m = await zwap.zwapDeriveZ2EMaterial(
      seedHex: seedHex,
      swapId: deriveId,
      solverAkSec1: s['akSec1'] as String,
      solverNskLe: s['nskLe'] as String,
      solverLockPubkey: s['lockPubkey'] as String,
      solverRefundPubkey: s['refundPubkey'] as String,
      solverHB: s['hB'] as String,
      solverSwapHash: s['swapHash'] as String,
      // Derive the slotId from the OB's CANONICAL recipientEvmAddr (echoed in the
      // snapshot), not our local copy — guarantees the FE slotId's `buyer` matches
      // the solver's lock exactly (b216c2d). They're the same value, but sourcing
      // from the OB removes any casing/normalization divergence risk.
      recipientEvmAddr: s['recipientEvmAddr'] as String,
      solverEvmAddr: s['solverEvmAddr'] as String,
      timelock: BigInt.from(timelock),
      chainId: BigInt.from(chainId),
      contractHex: _kZwapHtlc,
      tokenHex: token20,
      network: network,
    );
    // ignore: avoid_print
    log('[zwap] z2e material ob=$obSwapId solverEvm=${s['solverEvmAddr']} '
        'slot=${m.evmSlotIdHex.substring(0, 16)} '
        'solverClaimAddr=${m.solverClaimAddrHex}');

    // Pre-share the refund sig_b (the solver's t1 inactivity-refund half).
    final refundSigB = await zwap.zwapZ2ERefundSigB(
      seedHex: seedHex,
      swapId: deriveId,
      refundToInitiatorDigestHex: m.refundToInitiatorDigestHex,
    );

    await _postJson('$orderbookUrl/api/swaps/$obSwapId/phase0', {
      'evmSlotId': m.evmSlotIdHex,
      'evmRefundSigB': refundSigB,
      'hashes': {
        'hA': s['hB'], // lock hA = solver's hashlock
        'hB': m.hBHex, // SHA256(user k_be)
        'swapHash': m.swapHashHex,
      },
      'zecJointAddress': m.jointZecAddress,
      'zecJointUfvk': m.jointZecUfvk,
      'zecIvk': m.jointZecIvkHex,
      'zecDiversifier': m.jointZecDiversifierHex,
      'zecAk': m.jointZecAkHex,
      'zecNk': m.jointZecNkHex,
      'zecRivk': m.jointZecRivkHex,
    }, bearer: token);

    return ZwapZ2eOrder(
      swapId: obSwapId,
      deriveId: deriveId,
      jointZecAddress: m.jointZecAddress,
      evmSlotIdHex: m.evmSlotIdHex,
      claimBuyDigestHex: m.claimBuyDigestHex,
      solverClaimAddrHex: m.solverClaimAddrHex,
      chainId: chainId,
    );
  }

  /// The singleton `ZwapHtlc` contract (regtest anvil, up.sh acct0-nonce-0).
  static const _kZwapHtlc = '0x5fbdb2315678afecb367f032d93f642f64180aa3';

  /// `ZwapHtlc.slots(bytes32)` returns a `Slot.State` enum; `0` == `Empty`
  /// (no lock funded at that slotId). Selector = `keccak256("slots(bytes32)")[:4]`.
  static const int _kHtlcSlotEmpty = 0;
  static const String _kSlotsSelector = '0xa52b4b2e';

  /// Read the on-chain `ZwapHtlc.slots(slotId)` state via a single `eth_call`.
  /// Returns the state enum int (0 == Empty), or `null` if the RPC is
  /// unreachable / returns an unexpected shape — callers MUST treat `null` as
  /// "unknown" (do not block a valid claim on a flaky RPC). Read-only.
  Future<int?> _evmSlotState(String slotIdHex, int chainId) async {
    try {
      var slot = slotIdHex.startsWith('0x') ? slotIdHex.substring(2) : slotIdHex;
      if (slot.length != 64) slot = slot.padLeft(64, '0');
      final data = '$_kSlotsSelector$slot';
      final req = await _http.postUrl(Uri.parse(_evmRpcFor(chainId)));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'eth_call',
        'params': [
          {'to': _kZwapHtlc, 'data': data},
          'latest',
        ],
      })));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final result = decoded['result'] as String?;
      if (result == null || !result.startsWith('0x') || result.length < 4) {
        return null;
      }
      // uint8 return is right-aligned in the 32-byte word → last 2 hex chars.
      return int.parse(result.substring(result.length - 2), radix: 16);
    } catch (_) {
      return null; // unreachable / malformed → "unknown", not a divergence
    }
  }

  /// z2e solver-half resolution — like [_awaitE2zSolver] but also extracts the
  /// solver-owned `swapHash` (give-ZEC) needed for the role-flipped lock.
  Future<Map<String, dynamic>> _awaitSolverHalfZ2e(String token, String swapId) async {
    for (var i = 0; i < 60; i++) {
      final snap = await recover(token, swapId);
      final assignment = snap['pooldAssignment'];
      if (assignment is Map<String, dynamic> &&
          assignment['lockId'] != null &&
          assignment['shieldedId'] != null) {
        final lock = (await _getJson(
            '$pooldUrl/pool/${assignment['lockId']}'))['public'] as Map<String, dynamic>;
        final shielded = (await _getJson(
            '$pooldUrl/pool/${assignment['shieldedId']}'))['public'] as Map<String, dynamic>;
        final swapHash = lock['swapHash'] ?? shielded['swapHash'];
        // FUND-SAFETY (z2e stuck-lock race): the EVM slotId folds BOTH
        // `initiator` (= solverEvmAddr, the solver's EVM home bound at match) AND
        // `buyer` (= recipientEvmAddr, the user's ETH/USDC payout wallet committed
        // at order intake). The pool pair resolves the instant the matcher assigns
        // it, but the OB-relayed addresses can LAG by a tick. Freezing the slotId
        // before EITHER arrives makes the material fall back to a per-swap derived
        // addr (`b_a`/`b_b`) → a slotId that DIVERGES from the one the solver locks
        // at → the lock lands on a slot the indexer never watches → the eth leg
        // wedges `pending` forever (and a `b_b` buyer also mis-routes the claimed
        // ETH to an addr the wallet can't see). The OB REQUIRES recipientEvmAddr at
        // intake, so this gate can never hang. Mirror the SDK (b216c2d): wait for
        // both valid, non-zero addresses and derive from the OB's canonical copies.
        final solverEvm = snap['solverEvmAddr'] as String?;
        final recipientEvm = snap['recipientEvmAddr'] as String?;
        bool validEvm(String? a) =>
            a != null &&
            a.length == 42 &&
            a != '0x0000000000000000000000000000000000000000';
        if (swapHash == null || !validEvm(solverEvm) || !validEvm(recipientEvm)) {
          await Future<void>.delayed(pollInterval);
          continue;
        }
        return {
          'akSec1': shielded['akSec1'],
          'nskLe': shielded['nskLe'],
          'lockPubkey': lock['lockPubkey'],
          'refundPubkey': lock['refundPubkey'],
          'hB': lock['hB'] ?? shielded['hB'],
          'swapHash': swapHash,
          'solverEvmAddr': solverEvm,
          'recipientEvmAddr': recipientEvm,
        };
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError('zwap z2e: solver pool pair / solverEvmAddr not assigned in time');
  }

  /// Complete the solver's `claim_buy` adaptor (in Rust) → sig_a + sig_b, then
  /// submit them + the preimage to the eth-relayer's gasless `claim_buy` and
  /// poll for the tx hash. Returns the txid (or a `relayer:<id>` placeholder if
  /// the broadcast is slow — the indexer settles authoritatively).
  Future<String> relayZ2eClaim({
    required String seedHex,
    required String deriveId,
    required String swapId,
    required String slotIdHex,
    required String claimBuyDigestHex,
    required String solverClaimAddrHex,
    required String adaptorHex,
    required String swapSecretHex,
    required int chainId,
  }) async {
    // SLOT-DIVERGENCE GUARD (loud-fail). By the time we relay the claim the
    // solver has already funded its ZwapHtlc lock (the swap advanced past
    // KeysExchanged). If OUR posted `slotIdHex` reads Empty on-chain, the solver
    // locked a DIFFERENT slot than we posted — a slotId-preimage mismatch
    // (historically `b_a` = the solver pool claim pubkey, or a `timelock` skew).
    // Proceeding would submit a claim against an empty slot that silently fails,
    // so throw an actionable error instead. RPC-unreachable (null) is treated as
    // "can't check" and does NOT block the claim (never fail a valid claim on a
    // flaky RPC — the indexer settles authoritatively).
    final slotState = await _evmSlotState(slotIdHex, chainId);
    if (slotState == _kHtlcSlotEmpty) {
      throw StateError(
        'z2e slotId divergence: the solver funded its lock on a different slot '
        'than the client posted (our slot $slotIdHex reads Empty on-chain). '
        'Check the slotId preimage inputs — b_a (solver pool claim pubkey) and '
        'timelock must match the solver. Not relaying the claim.',
      );
    }

    final sigs = await zwap.zwapZ2EClaimSigs(
      seedHex: seedHex,
      swapId: deriveId,
      adaptorHex: adaptorHex,
      claimBuyDigestHex: claimBuyDigestHex,
      solverClaimAddrHex: solverClaimAddrHex,
    );
    var base = relayerUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    await _postJson('$base/v1/jobs/claim_buy', {
      'swap_id': swapId,
      'slot_id_hex': slotIdHex,
      'preimage_hex': swapSecretHex,
      'sig_a_hex': sigs.sigAHex,
      'sig_b_hex': sigs.sigBHex,
      if (chainId != 0) 'chainId': chainId,
    });
    // Poll the job for the on-chain tx hash (mirrors the SDK waitForTx).
    for (var i = 0; i < 40; i++) {
      try {
        final job = await _getJson('$base/v1/jobs/$swapId/claim_buy');
        if ((job['state'] as String?) == 'failed') {
          throw StateError('eth-relayer claim_buy failed: ${job['error']}');
        }
        final tx = job['tx_hash_hex'] as String?;
        if (tx != null && tx.isNotEmpty) return tx;
      } catch (_) {
        // transient; retry
      }
      await Future<void>.delayed(pollInterval);
    }
    return 'relayer:$swapId';
  }

  /// Poll `/recover` until the matcher publishes the `pooldAssignment`, then
  /// fetch BOTH poold entries (`/pool/{lockId}` + `/pool/{shieldedId}`) and
  /// assemble the solver's public half exactly as the SDK
  /// `resolveVerifiedSolverHalf`: `akSec1`/`nskLe` from the shielded entry,
  /// `lockPubkey` (b_b)/`hB` from the lock entry. Returns `{akSec1, nskLe, bB, hB}`.
  ///
  /// FUND-SAFETY NOTE: production must RE-VERIFY the shared hashbind/DLEq proof
  /// over the combined points before deriving (the documented verify gate).
  Future<Map<String, dynamic>> _awaitSolverHalf(String token, String swapId) async {
    for (var i = 0; i < 60; i++) {
      final snap = await recover(token, swapId);
      final assignment = snap['pooldAssignment'];
      if (assignment is Map<String, dynamic> &&
          assignment['lockId'] != null &&
          assignment['shieldedId'] != null) {
        final lock = (await _getJson('$pooldUrl/pool/${assignment['lockId']}'))['public']
            as Map<String, dynamic>;
        final shielded =
            (await _getJson('$pooldUrl/pool/${assignment['shieldedId']}'))['public']
                as Map<String, dynamic>;
        return {
          'akSec1': shielded['akSec1'],
          'nskLe': shielded['nskLe'],
          'bB': lock['lockPubkey'],
          'hB': lock['hB'] ?? shielded['hB'],
        };
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError('zwap: pooldAssignment not published for $swapId');
  }

  /// Indexer base with any trailing `/v1` stripped (paths below are
  /// absolute-from-`/v1`, matching the SDK sweep client).
  String get _indexerBase {
    var b = indexerUrl;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/v1')) b = b.substring(0, b.length - 3);
    return b;
  }

  Future<List<dynamic>> _getJsonList(String url) async {
    final req = await _http.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return body.isEmpty ? const [] : jsonDecode(body) as List<dynamic>;
  }

  /// FUND-SAFETY (#7): discover the joint note by trial-decrypting the chain
  /// LOCALLY with the joint viewing key — the orderbook is NEVER trusted for
  /// note value/rseed/rho/position/merkle-path. It supplies at most a height
  /// hint; a wrong hint just finds nothing (retry), it cannot misdirect funds.
  ///
  /// Mirrors the SDK `sweepZec`: treestate frontier at `scanHeight-1`, compact
  /// blocks at `scanHeight`, `orchard_trial_decrypt`. Returns the found note
  /// (with `value/rseed/rho/diversifier/pkd/position/merkle_path/anchor`) or
  /// null if not yet on-chain.
  Future<Map<String, dynamic>?> discoverJointNoteLocally({
    required int scanHeight,
    required String akHex,
    required String nkHex,
    required String rivkHex,
    required String ivkHex,
    required String diversifierHex,
    int? toHeight,
  }) async {
    final base = _indexerBase;
    final ts = await _getJson('$base/v1/zec/treestate?height=${scanHeight - 1}');
    // The indexer returns the Orchard frontier under `frontierHex`; keep the
    // older key names as fallbacks for compatibility.
    final frontier =
        (ts['frontierHex'] ?? ts['finalState'] ?? ts['frontier']) as String?;
    if (frontier == null || frontier.isEmpty) return null; // wrong anchor otherwise
    // Scan a RANGE (the exact joint-note height isn't relayed): from `scanHeight`
    // to `toHeight` (the current ZEC tip). The frontier at `scanHeight-1` seeds
    // globally-correct positions/anchors across the whole range.
    final end = toHeight ?? scanHeight;
    final blocks = await _getJsonList(
        '$base/v1/orchard/compact-blocks?fromHeight=$scanHeight&toHeight=$end');
    final req = jsonEncode({
      'ivk': ivkHex,
      'diversifier': diversifierHex,
      'blocks': blocks,
      'ak': akHex,
      'nk': nkHex,
      'rivk': rivkHex,
      'frontier_hex': frontier,
    });
    final resp = jsonDecode(await zwap.zwapOrchardTrialDecrypt(requestJson: req))
        as Map<String, dynamic>;
    final notes = (resp['notes'] as List?) ?? const [];
    return notes.isEmpty ? null : notes.first as Map<String, dynamic>;
  }

  /// Reconstruct the joint `ask` (LE hex) from `deriveId`'s `k_a` + the revealed
  /// `k_b`, then sweep the LOCALLY-discovered joint `note` to `destRawAddressHex`
  /// (the fresh receiver committed at order creation) and broadcast. `nk`/`rivk`
  /// are the raw 32-byte joint values (never the UFVK string). Amount is the
  /// note value minus `fee` so change is zero.
  Future<String> sweepJointNote({
    required String seedHex,
    required String deriveId,
    required String recoveredKbBeHex,
    required String nkHex,
    required String rivkHex,
    required Map<String, dynamic> note, // from discoverJointNoteLocally
    required String destRawAddressHex,
    required int fee,
  }) async {
    final kA = await zwap.zwapKUserBeHex(seedHex: seedHex, swapId: deriveId);
    final askLe = await zwap.zwapJointAskLeHex(kABeHex: kA, kBBeHex: recoveredKbBeHex);
    final value = (note['value'] as num).toInt();
    if (value <= fee) {
      throw StateError('zwap sweep: note value $value <= fee $fee');
    }
    // Bind the sweep tx to the node's CURRENTLY-ACTIVE consensus branch (regtest
    // may run NU6.2 = 0x5437f330). A stale hardcoded branch id yields a tx the
    // node rejects for the current epoch, so the sweep never lands. Matches the
    // SDK `sweepZec` — fetch the live branch from indexerd `/v1/zec/consensus`.
    final branchId = await _consensusBranchId();
    final spendReq = jsonEncode({
      'ask': askLe,
      'nk': nkHex,
      'rivk': rivkHex,
      'note': {
        'value': value,
        'rseed': note['rseed'],
        'rho': note['rho'],
        'diversifier': note['diversifier'],
        'pkd': note['pkd'],
        'position': note['position'],
      },
      'merkle_path': (note['merkle_path'] as List).cast<String>(),
      'dest_raw_address': destRawAddressHex,
      'amount': value - fee, // change = value - amount - fee = 0
      'fee': fee,
      'branch_id': ?branchId,
    });
    final resp = jsonDecode(await zwap.zwapOrchardSpend(requestJson: spendReq))
        as Map<String, dynamic>;
    final rawTxHex = resp['raw_tx_hex'] as String;
    // The indexer's /v1/zec/broadcast takes the raw tx hex as a PLAIN-TEXT body
    // (matches the SDK `sweepZec`), NOT a JSON envelope. Sending JSON makes
    // zebrad parse the JSON string as hex → "Odd number of digits".
    await _postRawText('$_indexerBase/v1/zec/broadcast', rawTxHex);
    return resp['txid'] as String;
  }

  /// Create a **deposit-based e2z (ETH→ZEC) proxy** order and return the
  /// artifacts the wallet presents: the CREATE2 ETH deposit address the user
  /// funds (partial top-ups allowed) + the joint ZEC UA it later sweeps.
  ///
  /// Deposit-based ⇒ the user signs NO EVM tx to fund — they just send ETH to
  /// the derived address; the solver deploys the proxy + claims. The wallet
  /// still proves its `k` (hashbind) and re-derives the deposit address LOCALLY
  /// from pinned bytecode (never solver-trusted). `initiatorEvmAddr` is the
  /// user's own ETH wallet (the refund destination).
  Future<ZwapE2zOrder> createE2zProxyOrder({
    required String seedHex,
    required String token,
    required String swapId,
    required String initiatorEvmAddr,
    required int amountZats,
    required String amountWei,
    required String receiveRawAddress,
    int chainId = 31337,
    String chainName = 'ethereum',
    String erc20 = '',
  }) async {
    final deriveId = await zwap.zwapFindSafeSwapId(seedHex: seedHex, baseId: swapId);
    final inputs = await zwap.zwapB2ZOrderInputs(seedHex: seedHex, swapId: deriveId);
    // EVM-leg swaps (e2z/usdc2z) require a Pallas DLEq FE proof binding
    // ak_a ↔ lock_pubkey, NOT the b2z hashbind SNARK — the solver's
    // `DepositShielded` fund-safety gate rejects `proofKind='hashbind'`.
    final dleq = await zwap.zwapE2ZDleqMaterial(seedHex: seedHex, swapId: deriveId);

    final nonceResp = await _getJson('$orderbookUrl/nonce/max', bearer: token);
    final nonce = (nonceResp['nextNonce'] ?? 0) as int;

    // ATTESTED PRICE: the ZEC the solver funds is the price-server's signed
    // output for the ETH/USDC deposit (source), not a local rate.
    final attest = await fetchAttestation(
      from: erc20.isNotEmpty ? 'usdc' : 'eth',
      to: 'zec',
      amountSmallest: BigInt.parse(amountWei),
      chain: chainName,
    );

    // Order in proxy lock-mode; the OB assigns the solver + relays proxy terms.
    // `erc20` non-empty routes the USDC (ERC-20) flavour; empty ⇒ native ETH.
    final orderResp = await _postJson('$orderbookUrl/api/orders', {
      'direction': 'e2z',
      'lockMode': 'proxy',
      // The source-leg owed amount is the EVM deposit (wei), NOT the ZEC value —
      // the solver's ClaimLock fund-safety gate compares this to
      // `proxyTerms.amount` (also wei); a zats mismatch → "no EVM material".
      'amount': amountWei,
      'nonce': nonce,
      'clientSwapId': deriveId,
      'shieldedValueZats': '${attest.outputSmallest}',
      'priceAttestation': attest.raw,
      'initiatorEvmAddr': initiatorEvmAddr,
      // The wallet's fresh Orchard sweep destination, committed at creation.
      'recvAddr': receiveRawAddress,
      if (erc20.isNotEmpty) 'erc20': erc20,
      // Flat feMaterial — the DLEq variant: `lockPubkey` = k_a·G_secp (the DLEq
      // secp witness, NOT a BTC key), `hashbindProof` = the serialized Pallas
      // DLEq proof, `proofKind='dleq'`. akA/nskA/hA/swapHash/refundPubkey are the
      // same seed-derived values as b2z.
      'feMaterial': {
        'hA': inputs.hA,
        'swapHash': inputs.swapHash,
        'akA': inputs.akA,
        'nskA': inputs.nskA,
        'lockPubkey': dleq.lockPubkeySecpHex,
        'refundPubkey': inputs.refundPubkey,
        'hashbindProof': dleq.dleqProofHex,
        'proofKind': 'dleq',
      },
    }, bearer: token);
    final obSwapId = (orderResp['swapId'] ?? deriveId) as String;

    // Wait for the matcher to relay the solver half, then derive the deposit
    // address + joint ZEC UA locally. The FE picks the proxy deadlines from the
    // eth tip (t0Abs = user refund cutoff, t1Abs = solver force-claim cutoff);
    // generous offsets so neither side times out during a regtest drive.
    final s = await _awaitE2zSolver(token, obSwapId);
    final ethTip = await ethTipHeight(chainId);
    final t0Abs = (s['t0Abs'] != null && s['t0Abs'] != 'null')
        ? s['t0Abs'] as String
        : '${ethTip + 5000}';
    final t1Abs = (s['t1Abs'] != null && s['t1Abs'] != 'null')
        ? s['t1Abs'] as String
        : '${ethTip + 10000}';
    // ignore: avoid_print
    log('[zwap] e2z half ok ak=${(s['akSec1'] as String?)?.substring(0, 8)} '
        'lockPub=${(s['lockPubkey'] as String?)?.substring(0, 8)} '
        'solverEvm=${s['solverEvmAddr']} t0=$t0Abs t1=$t1Abs wei=$amountWei');
    final m = await zwap.zwapDeriveE2ZProxyMaterial(
      seedHex: seedHex,
      swapId: deriveId,
      solverAkSec1: s['akSec1'] as String,
      solverNskLe: s['nskLe'] as String,
      solverLockPubkey: s['lockPubkey'] as String,
      solverRefundPubkey: s['refundPubkey'] as String,
      solverHB: s['hB'] as String,
      solverEvmAddr: s['solverEvmAddr'] as String,
      // The ETH/USDC deposit amount (FE-known, part of SwapTerms → the CREATE2
      // salt and the solver's deposit check).
      amountWei: amountWei,
      // Native ETH ⇒ zero address; usdc2z ⇒ the ERC-20 contract. Part of the
      // CREATE2 salt, so it must equal what the solver used.
      tokenAddr: erc20.isNotEmpty
          ? erc20
          : '0x0000000000000000000000000000000000000000',
      t0Abs: t0Abs,
      t1Abs: t1Abs,
      // regtest anvil constants — not relayed by the OB. The material
      // fail-closes if these disagree with the solver's pinned pair.
      chainId: BigInt.from(chainId),
      factoryAddr: '0x057ef64E23666F000b34aE31332854aCBd1c8544',
      implementationAddr: '0x3b3112c4376d037822DECFf3Fe6CD30E1E726517',
      initiatorEvmAddr: initiatorEvmAddr,
      network: network,
    ).catchError((Object e) {
      // ignore: avoid_print
      log('[zwap] e2z material FAILED: $e');
      throw StateError('e2z material: $e');
    });
    // ignore: avoid_print
    log('[zwap] e2z material ok deposit=${m.depositAddress} salt=${m.saltHex}');
    // Phase0 (e2z proxy): the OB's e2z FSM starts at `Phase0Received` — it will
    // NOT relay watch material or advance until the FE posts its Phase0 half.
    // Unlike b2z (which posts the BTC lock script), e2z posts the CREATE2
    // slotId, the canonical proxyTerms, and the user's `claim_buy` ADAPTOR
    // signature (signed with the user's k_be, encrypted under the solver's
    // lockPubkey). Without this, order creation deadlocks at "Locking quote".
    // The Rust hex decoders don't strip a `0x` prefix; the material returns the
    // claim_buy digest 0x-prefixed, so strip it here.
    String noHex(String v) => v.startsWith('0x') ? v.substring(2) : v;
    final adaptorHex = await zwap
        .zwapBuildClaimBuyAdaptor(
          seedHex: seedHex,
          swapId: deriveId,
          encryptionPointHex: noHex(s['lockPubkey'] as String),
          claimBuyDigestHex: noHex(m.claimBuyDigest),
        )
        .catchError((Object e) {
      // ignore: avoid_print
      log('[zwap] e2z adaptor FAILED: $e');
      throw StateError('e2z adaptor: $e');
    });
    // ignore: avoid_print
    log('[zwap] e2z adaptor ok len=${adaptorHex.length}');
    await _postJson('$orderbookUrl/api/swaps/$obSwapId/phase0', {
      'evmSlotId': m.saltHex,
      'evmClaimAdaptorSig': adaptorHex,
      'hashes': {
        'hA': inputs.hA,
        'hB': s['hB'],
        'swapHash': inputs.swapHash,
      },
      'zecJointAddress': m.jointZecAddress,
      'zecJointUfvk': m.jointZecUfvk,
      'zecIvk': m.jointZecIvkHex,
      'zecDiversifier': m.jointZecDiversifierHex,
      'zecAk': m.jointZecAkHex,
      'zecNk': m.jointZecNkHex,
      'zecRivk': m.jointZecRivkHex,
      'lockMode': 'proxy',
      'proxyTerms': m.proxyTermsJson,
    }, bearer: token).catchError((Object e) {
      // ignore: avoid_print
      log('[zwap] e2z phase0 POST FAILED: $e');
      throw StateError('e2z phase0: $e');
    });
    // ignore: avoid_print
    log('[zwap] e2z phase0 posted ob=$obSwapId');

    return ZwapE2zOrder(
      swapId: obSwapId,
      deriveId: deriveId,
      depositAddress: m.depositAddress,
      jointZecAddress: m.jointZecAddress,
      jointZecUfvk: m.jointZecUfvk,
      jointZecNkHex: m.jointZecNkHex,
      jointZecRivkHex: m.jointZecRivkHex,
      jointZecAkHex: m.jointZecAkHex,
      jointZecIvkHex: m.jointZecIvkHex,
      jointZecDiversifierHex: m.jointZecDiversifierHex,
      receiveRawAddress: receiveRawAddress,
      amountWei: amountWei,
      // Retained for the ASMR sweep: the wallet recovers k_solver from the
      // on-chain `claim_buy` sig + this adaptor, candidate-selected by the
      // solver's lockPubkey (the adaptor encryption point).
      evmClaimAdaptorHex: adaptorHex,
      solverLockPubkeyHex: s['lockPubkey'] as String,
    );
  }

  /// Poll the proxy deposit status for the partial-deposit UX: returns
  /// `(deposited, required)` in the deposit asset's smallest units. `deposited`
  /// is the running partial total observed; `required` is the FULL amount the
  /// leg must hold to be funded (NOT the remaining — the caller computes
  /// `required - deposited`). The OB surfaces both under a nested `deposit`
  /// object in the recover snapshot (routes.rs: `v["deposit"] = { deposited,
  /// owed, ... }`, where `owed` is the total required), so read from there.
  Future<({BigInt deposited, BigInt required})> pollDepositStatus(
    String token,
    String swapId,
  ) async {
    final snap = await recover(token, swapId);
    final deposit = snap['deposit'];
    final dep = deposit is Map<String, dynamic>
        ? (deposit['deposited'] ?? deposit['depositedWei'])
        : (snap['depositedWei'] ?? snap['deposited']);
    // `owed` from the OB is the total required to fund the leg; fall back to the
    // order's total `amount` if the OB omitted it.
    final req = (deposit is Map<String, dynamic>
            ? (deposit['owed'] ?? deposit['owedWei'])
            : (snap['owedWei'] ?? snap['owed'])) ??
        snap['amount'];
    return (
      deposited: BigInt.tryParse('${dep ?? '0'}') ?? BigInt.zero,
      required: BigInt.tryParse('${req ?? '0'}') ?? BigInt.zero,
    );
  }

  /// Poll `/recover` until the matched solver's e2z HALF is available. The FE is
  /// authoritative for the proxy terms (it posts them at Phase0), so this does
  /// NOT wait for a solver-relayed `proxyTerms` — the deadlines t0Abs/t1Abs are
  /// FE-chosen (eth block + offsets), and factory/impl/chainId/token are pinned.
  Future<Map<String, dynamic>> _awaitE2zSolver(String token, String swapId) async {
    for (var i = 0; i < 60; i++) {
      final snap = await recover(token, swapId);
      final assignment = snap['pooldAssignment'];
      final terms = snap['proxyTerms'];
      // Same shape as b2z: the matcher assigns a pool PAIR (lockId + shieldedId);
      // the FE fetches each entry's `public` half from poold. The EVM lock half
      // carries lockPubkey/refundPubkey/hB (lockPubkey = the solver's k_be·G_secp
      // = the adaptor encryption point); the shielded half carries the joint ZEC
      // akSec1/nskLe. Both are the SAME solver scalar (DLEq-bound across curves).
      if (assignment is Map<String, dynamic> &&
          assignment['lockId'] != null &&
          assignment['shieldedId'] != null) {
        final lock = (await _getJson(
            '$pooldUrl/pool/${assignment['lockId']}'))['public'] as Map<String, dynamic>;
        final shielded = (await _getJson(
            '$pooldUrl/pool/${assignment['shieldedId']}'))['public'] as Map<String, dynamic>;
        // FUND-SAFETY (b1b5b59): e2z folds `buyer = solverEvmAddr` into the EVM
        // slotId. The pool pair resolves the instant the matcher assigns it, but
        // the OB-relayed `solverEvmAddr` can lag by a tick. Building before it
        // arrives falls back to a per-swap `b_a` → a slotId that diverges from
        // the solver's lock → the indexer never watches it → wedge. Wait for a
        // valid, non-zero 20-byte address (from the snapshot, or a partial
        // proxyTerms' `buyer`) before returning.
        final solverEvm = (snap['solverEvmAddr'] ??
            (terms is Map<String, dynamic> ? terms['buyer'] : null)) as String?;
        final validSolverEvm = solverEvm != null &&
            solverEvm.length == 42 &&
            solverEvm != '0x0000000000000000000000000000000000000000';
        if (!validSolverEvm) {
          await Future<void>.delayed(pollInterval);
          continue;
        }
        return {
          'akSec1': shielded['akSec1'],
          'nskLe': shielded['nskLe'],
          'lockPubkey': lock['lockPubkey'],
          'refundPubkey': lock['refundPubkey'],
          'hB': lock['hB'] ?? shielded['hB'],
          // solverEvmAddr (buyer) relayed at match; deadlines from a partial
          // proxyTerms if present, else the FE fills them from the eth tip.
          'solverEvmAddr': solverEvm,
          't0Abs':
              terms is Map<String, dynamic> ? '${terms['t0Abs']}' : null,
          't1Abs':
              terms is Map<String, dynamic> ? '${terms['t1Abs']}' : null,
        };
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError('zwap e2z: solver pool pair not assigned in time');
  }

  void dispose() => _http.close(force: true);
}

/// The displayable artifacts of a created e2z (ETH→ZEC) proxy order.
class ZwapE2zOrder {
  const ZwapE2zOrder({
    required this.swapId,
    required this.deriveId,
    required this.depositAddress,
    required this.jointZecAddress,
    required this.jointZecUfvk,
    required this.jointZecNkHex,
    required this.jointZecRivkHex,
    required this.jointZecAkHex,
    required this.jointZecIvkHex,
    required this.jointZecDiversifierHex,
    required this.receiveRawAddress,
    required this.amountWei,
    required this.evmClaimAdaptorHex,
    required this.solverLockPubkeyHex,
  });

  /// The serialized Phase0 claim_buy adaptor + the solver's lockPubkey — the two
  /// inputs the wallet needs to recover k_solver from the on-chain EVM claim.
  final String evmClaimAdaptorHex;
  final String solverLockPubkeyHex;

  /// The CREATE2 ETH deposit address the user funds (partial top-ups allowed).
  final String depositAddress;
  final String swapId;

  /// DLEq-safe derive id — all key material (reveal, k_a, joint ask) binds here.
  final String deriveId;
  final String jointZecAddress;
  final String jointZecUfvk;

  /// Raw 32-byte joint `nk`/`rivk` (hex) for the sweep; joint `ak`/`ivk`/
  /// `diversifier` (hex) for local trial-decryption. NOT the UFVK string.
  final String jointZecNkHex;
  final String jointZecRivkHex;
  final String jointZecAkHex;
  final String jointZecIvkHex;
  final String jointZecDiversifierHex;

  /// The wallet's fresh Orchard receiver (43-byte raw hex) the joint note is
  /// swept to, committed at order creation.
  final String receiveRawAddress;

  /// Total owed, in wei (decimal string).
  final String amountWei;
}

/// CSV timelocks (blocks) for the BTC HTLC: `t1` initiator refund, `t2` solver
/// force-claim. Must satisfy `16 < t1 < t2`.
class LockTimelocks {
  const LockTimelocks({this.t1 = 72, this.t2 = 144});
  final int t1;
  final int t2;
}

/// The displayable + settlement artifacts of a created b2z order.
/// A price-server `/v1/attest` result: the signed payload (posted verbatim as
/// the order's `priceAttestation`) + the parsed dest output amount and USD sides.
class ZwapAttestation {
  const ZwapAttestation({
    required this.raw,
    required this.outputSmallest,
    this.sourceUsd,
    this.destUsd,
  });

  /// The full signed attestation JSON — round-trips verbatim into the order so
  /// the OB/solver re-verify the ed25519 signature + pair/amount/chain binding.
  final Map<String, dynamic> raw;

  /// The attested DEST amount in smallest units (fee + spread + fixed deduction
  /// already baked in) — use this for the counter-leg amount, NOT a local rate.
  final BigInt outputSmallest;

  /// USD value of the source / dest legs (unsigned display extras), for fiat.
  final double? sourceUsd;
  final double? destUsd;
}

class ZwapB2zOrder {
  const ZwapB2zOrder({
    required this.swapId,
    required this.deriveId,
    required this.btcLockAddress,
    required this.witnessScriptHex,
    required this.jointZecAddress,
    required this.jointZecUfvk,
    required this.jointZecNkHex,
    required this.jointZecRivkHex,
    required this.jointZecAkHex,
    required this.jointZecIvkHex,
    required this.jointZecDiversifierHex,
    required this.receiveRawAddress,
  });

  /// The orderbook-assigned id — use for ALL orderbook FSM/recover calls.
  final String swapId;

  /// The DLEq-safe derive id — use for ALL key-material derivation (reveal,
  /// k_a, joint ask). Distinct from [swapId].
  final String deriveId;

  final String btcLockAddress;
  final String witnessScriptHex;
  final String jointZecAddress;
  final String jointZecUfvk;

  /// Raw 32-byte joint `nk`/`rivk` (hex) — required to build the sweep. NOT the
  /// UFVK string.
  final String jointZecNkHex;
  final String jointZecRivkHex;

  /// Joint `ak`/`ivk` (32-byte hex) + `diversifier` (11-byte hex) — to
  /// trial-decrypt the joint note locally (never trust the OB for it).
  final String jointZecAkHex;
  final String jointZecIvkHex;
  final String jointZecDiversifierHex;

  /// The wallet's fresh Orchard receiver (43-byte raw hex) the joint note is
  /// swept to, committed at order creation.
  final String receiveRawAddress;

  /// Minimal on-device persistence: the fields that cannot be re-derived from
  /// `(seed, deriveId)` + a live `recover()` — the id pair + the chosen sweep
  /// destination. nk/rivk are re-derivable from the solver half at sweep time.
  Map<String, dynamic> toPersistedJson() => {
        'swapId': swapId,
        'deriveId': deriveId,
        'receiveRawAddress': receiveRawAddress,
      };
}

/// A created z2b (ZEC→BTC) order. The user funds [jointZecAddress] from its own
/// wallet, then claims the solver-funded lock (branch-1) to its BTC receive
/// address. The joint fields are retained only for the REFUND path (if the swap
/// fails the user reclaims the joint note); the happy path never sweeps.
class ZwapZ2bOrder {
  const ZwapZ2bOrder({
    required this.swapId,
    required this.deriveId,
    required this.btcLockAddress,
    required this.witnessScriptHex,
    required this.jointZecAddress,
    required this.jointZecUfvk,
    required this.jointZecNkHex,
    required this.jointZecRivkHex,
    required this.jointZecAkHex,
    required this.jointZecIvkHex,
    required this.jointZecDiversifierHex,
  });

  /// The orderbook-assigned id — use for ALL orderbook FSM/recover calls.
  final String swapId;

  /// The DLEq-safe derive id — use for ALL key-material derivation (claim key,
  /// k_be). Distinct from [swapId].
  final String deriveId;

  /// The lock the solver funds (informational; the user watches the recover
  /// snapshot's `lockOutpoint` for the actual UTXO to claim).
  final String btcLockAddress;

  /// The lock witnessScript (hex) — required to build the branch-1 claim.
  final String witnessScriptHex;

  /// The joint UA the USER funds from its wallet. The solver drains it after the
  /// user's `k_be` is revealed on-chain by the BTC claim.
  final String jointZecAddress;
  final String jointZecUfvk;
  final String jointZecNkHex;
  final String jointZecRivkHex;
  final String jointZecAkHex;
  final String jointZecIvkHex;
  final String jointZecDiversifierHex;

  Map<String, dynamic> toPersistedJson() => {
        'swapId': swapId,
        'deriveId': deriveId,
      };
}

/// A created z2e (ZEC→ETH/USDC) order. The user funds [jointZecAddress], then
/// claims the solver-funded EVM lock by completing the solver's adaptor and
/// relaying `claim_buy` (revealing k_user so the solver drains the joint note).
class ZwapZ2eOrder {
  const ZwapZ2eOrder({
    required this.swapId,
    required this.deriveId,
    required this.jointZecAddress,
    required this.evmSlotIdHex,
    required this.claimBuyDigestHex,
    required this.solverClaimAddrHex,
    required this.chainId,
  });

  final String swapId;
  final String deriveId;
  final String jointZecAddress;
  final String evmSlotIdHex;
  final String claimBuyDigestHex;
  final String solverClaimAddrHex;
  final int chainId;

  Map<String, dynamic> toPersistedJson() => {
        'swapId': swapId,
        'deriveId': deriveId,
      };
}
