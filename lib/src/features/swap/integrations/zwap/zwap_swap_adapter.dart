import '../../../../../main.dart' show log;
import '../../../../rust/api/swap_zwap.dart' as zwap;
import '../../domain/swap_asset.dart';
import '../../domain/swap_direction.dart';
import '../../domain/swap_intent_status.dart';
import '../../domain/swap_provider_contract.dart';
import '../../domain/swap_quote.dart';
import '../../models/swap_fiat_amount.dart';
import 'zwap_intent_store.dart';
import 'zwap_swap_client.dart';

/// `SwapProvider` backed by the non-custodial zwap atomic-swap engine.
///
/// Implements the same interface the NEAR adapter does, so the swap UI is
/// backend-agnostic. Two receive-ZEC directions are wired:
///  - **b2z** (BTC → ZEC): the user funds a BTC HTLC lock.
///  - **e2z** (ETH/USDC → ZEC, proxy mode): the user funds a CREATE2 proxy
///    deposit address with ETH or USDC.
///
/// Both settle the same way for the wallet: the solver funds a joint 2-of-2
/// Orchard note, the wallet reveals the swap secret, then discovers + sweeps
/// the joint note to a fresh receiver committed at order creation.
///
/// Injected dependencies:
///  - [seedHex] — the active account's 32-byte zwap identity seed (hex).
///  - [newReceiveRawAddress] — generates a FRESH Orchard receiver (43-byte raw
///    hex) per swap, the sweep destination committed at order creation.
class ZwapSwapAdapter implements SwapProvider, SwapPricingProvider {
  ZwapSwapAdapter({
    required this.client,
    required this.seedHex,
    required this.newReceiveRawAddress,
    this.store,
    this.externalPerZec,
    double? Function()? zecUsdUnitPrice,
    this.timelocks = const LockTimelocks(),
    this.sweepFeeZats = 15000,
    this.btcClaimFeeSat = 500,
    this.initiatorEvmAddr = _kRegtestInitiatorEvmAddr,
    this.usdcTokenAddr = _kRegtestUsdcAddr,
    this.usdcTokenAddrBase = _kRegtestUsdcAddrBase,
    this.evmChainIdByTicker = _kRegtestEvmChainIdByTicker,
  }) : _zecUsdUnitPrice = zecUsdUnitPrice;

  final ZwapSwapClient client;
  final Future<String> Function() seedHex;
  final Future<String> Function() newReceiveRawAddress;

  /// Durable persistence for in-flight swap recovery material, so a swap can be
  /// resumed after an app restart wipes [_intents]. Null disables persistence
  /// (tests / callers that don't need restart-survival).
  final ZwapIntentStore? store;

  /// External-asset units per ZEC used ONLY for the on-device quote preview.
  /// Null (the default) makes [SwapQuote.estimate] fall back to each asset's
  /// realistic `fallbackExternalPerZec`, so the preview shows a proper rate
  /// instead of a 1:1 output==input placeholder. The solver's live quote (shown
  /// at review) is authoritative for the actual settled amount.
  final double? externalPerZec;

  /// Lazily reads the app's live ZEC/USD spot price (the same source that prices
  /// the home balance). zwap has no price oracle of its own, so it reuses this
  /// to fill the fiat "$" values across the swap UI (composer, review,
  /// activity). Read lazily (rather than captured at construction) so the
  /// adapter is not recreated — and its in-flight `_intents` wiped — when the
  /// price ticks. Null / null-return (price not yet fetched, non-mainnet) leaves
  /// fiat as `$--`, unchanged.
  final double? Function()? _zecUsdUnitPrice;

  double? get zecUsdUnitPrice => _zecUsdUnitPrice?.call();

  final LockTimelocks timelocks;

  /// Orchard sweep fee (zats); the user receives note value minus this.
  final int sweepFeeZats;

  /// z2b BTC branch-1 claim fee (sats); the user receives lock value minus this.
  final int btcClaimFeeSat;

  /// The user's EVM refund destination for e2z/usdc2z (only exercised if the
  /// swap refunds; a successful settle never touches it). On regtest this is an
  /// anvil account.
  final String initiatorEvmAddr;

  /// The USDC ERC-20 contract for the usdc→ZEC flavour on the app's PRIMARY EVM
  /// chain ('ethereum' = chainId 31337 on regtest).
  final String usdcTokenAddr;

  /// The USDC ERC-20 contract on the SECOND EVM chain ('base' = chainId 31338 on
  /// regtest). Selected when the user picks a Base-chain USDC asset.
  final String usdcTokenAddrBase;

  /// Maps a [SwapAsset.chainTicker] to the EVM chainId the order/guard target.
  /// Regtest: 'eth'/'ethereum' -> 31337 (:8545), 'base' -> 31338 (:8546). For
  /// mainnet, inject the real chainIds (see the mainnet support plan).
  final Map<String, int> evmChainIdByTicker;

  /// Anvil account #1 — the e2z refund destination on regtest.
  static const _kRegtestInitiatorEvmAddr =
      '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

  /// The regtest solver's ERC-20 (USDC) contract (SOLVER_V3_ERC20_CONTRACT).
  ///
  /// This is the host `solver-v3`'s live `SOLVER_V3_ERC20_CONTRACT` on the
  /// `v3/up.sh` stack: the `TestERC20` deployed at deployer acct0 nonce 1
  /// (`docker-compose.v3.yml`'s `0x5fc8d326…` is stale — the host stack wins).
  static const _kRegtestUsdcAddr =
      '0xe7f1725e7734ce288f8367e1bb143e90bb3f0512';

  /// The regtest USDC ERC-20 on the SECOND EVM chain (chainId 31338 / :8546).
  static const _kRegtestUsdcAddrBase =
      '0x5fc8d32690cc91d4c39d9d3abcbd16989f875707';

  /// Regtest chainId per chain ticker. NOTE the runtime chain LABELS are inverted
  /// vs the static solver config (the indexer maps 31337 -> 'ethereum' @ :8545,
  /// 31338 -> 'base' @ :8546). The chainId is the ground truth; keep it in sync
  /// with the deployed backend, not the config labels.
  static const _kRegtestEvmChainIdByTicker = <String, int>{
    'eth': 31337,
    'ethereum': 31337,
    'base': 31338,
  };

  /// The EVM chainId an [asset] targets (defaults to the primary chain, 31337).
  int _evmChainId(SwapAsset asset) =>
      evmChainIdByTicker[asset.chainTicker] ?? 31337;

  /// The price-server chain name for an [asset] ('base' for Base, else the app's
  /// primary EVM chain name 'ethereum').
  String _evmChainName(SwapAsset asset) =>
      asset.chainTicker == 'base' ? 'base' : 'ethereum';

  /// The USDC ERC-20 contract for an [asset]'s chain.
  String _usdcAddrFor(SwapAsset asset) =>
      asset.chainTicker == 'base' ? usdcTokenAddrBase : usdcTokenAddr;

  /// True for the USDC token on any chain (Ethereum or Base variant).
  static bool _isUsdcAsset(SwapAsset asset) =>
      asset.symbol.toUpperCase() == 'USDC';

  final Map<String, _ZwapIntent> _intents = {};

  @override
  String get providerLabel => 'Zwap (atomic swap)';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async => const [
        SwapAsset.btc,
        SwapAsset.eth,
        SwapAsset.ethBase,
        SwapAsset.usdc,
        SwapAsset.usdcBase,
      ];

  /// zwap has no price oracle of its own. It reuses the wallet's ZEC/USD spot
  /// price ([zecUsdUnitPrice]) and derives each external leg's USD price from
  /// its ZEC exchange rate, so the composer's fiat "$" values render instead of
  /// `$--`. Empty when the ZEC price is unavailable — the state provider then
  /// keeps its previous `indicativeUsdPrices` unchanged.
  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    // Refresh the indicative composer rate from the SAME signed price server
    // the review + order use. Without this the composer derives its "You
    // receive" and "$" values from the coarse hardcoded
    // [SwapAsset.fallbackExternalPerZec] (ETH 0.0254 vs a real ~0.0148), so the
    // preview diverged sharply from the review and the delivered amount. Called
    // on composer open / refresh (not per keystroke); failures keep the last
    // rate or fall back to the hardcoded one. Rates barely move between opens,
    // so we only refetch when forced or a rate is still missing.
    if (forceRefresh || _indicativePerZec.length < _kIndicativeAssets.length) {
      await Future.wait([
        for (final asset in _kIndicativeAssets) _refreshIndicativePerZec(asset),
      ]);
    }
    return SwapPricingSnapshot(usdPrices: _usdPrices());
  }

  /// Representative give-ZEC amount (1 ZEC) used to sample the indicative
  /// external-per-ZEC rate for the composer preview.
  static final BigInt _kIndicativeZats = BigInt.from(100000000);

  /// External assets the composer samples an indicative rate for (one per
  /// pickable external asset, incl. both EVM chains' ETH/USDC).
  static const _kIndicativeAssets = <SwapAsset>[
    SwapAsset.btc,
    SwapAsset.eth,
    SwapAsset.ethBase,
    SwapAsset.usdc,
    SwapAsset.usdcBase,
  ];

  /// True for an EVM-chain token (ETH/USDC on Ethereum or Base) — the assets the
  /// price server prices per `chain`.
  static bool _isEvmAsset(SwapAsset asset) =>
      asset.chainTicker == 'eth' || asset.chainTicker == 'base';

  /// Last sampled indicative external-per-ZEC rate per asset, from the price
  /// server's signed attestation. Populated by [loadPricingSnapshot].
  final Map<SwapAsset, double> _indicativePerZec = {};

  Future<void> _refreshIndicativePerZec(SwapAsset asset) async {
    try {
      final ext = _attestKey(asset);
      final chain = _isEvmAsset(asset) ? _evmChainName(asset) : '';
      final a = await client.fetchAttestation(
        from: 'zec',
        to: ext,
        amountSmallest: _kIndicativeZats,
        chain: chain,
      );
      final extOut = a.outputSmallest.toDouble() / _decimals(asset);
      final zec = _kIndicativeZats.toDouble() / 1e8;
      if (extOut > 0 && zec > 0) _indicativePerZec[asset] = extOut / zec;
    } catch (_) {
      // Keep the last sampled rate (or fall through to the hardcoded fallback
      // in [_usdPrices]); an indicative-rate refresh must never break the
      // composer.
    }
  }

  /// Per-asset USD unit prices for the supported swap assets, derived from the
  /// single ZEC/USD spot price. Prefers the live attested indicative rate (so
  /// the composer "$" values and derived `externalPerZec` match the review),
  /// then any caller-provided rate, then the hardcoded fallback.
  /// See [swapUsdPricesFromZecPrice].
  Map<SwapAsset, double> _usdPrices() {
    return swapUsdPricesFromZecPrice(
      zecUsdUnitPrice: zecUsdUnitPrice,
      externalPerZec: {
        for (final asset in _kIndicativeAssets)
          asset: _indicativePerZec[asset] ??
              externalPerZec ??
              asset.fallbackExternalPerZec,
      },
    );
  }

  /// Last SUCCESSFUL attested external-per-ZEC rate, keyed by polarity+asset.
  /// The composer calls [quote] on every keystroke; a transient price-server
  /// hiccup would otherwise drop the preview back to the coarse hardcoded
  /// [SwapAsset.fallbackExternalPerZec] (e.g. ETH 0.0254 vs a real ~0.0148),
  /// making the preview diverge sharply from the review + delivered amount.
  /// Reusing the last real rate keeps the preview aligned with reality; the
  /// review always re-fetches a fresh signed attestation, so this never
  /// changes what the order actually binds.
  final Map<String, double> _lastAttestedPerZec = {};

  static String _attestCacheKey(SwapQuoteRequest request) =>
      '${request.direction.sendsZec ? 'give' : 'recv'}:'
      '${request.externalAsset.identityKey}';

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    // Both polarities are handled: receive-ZEC (b2z / e2z / usdc2z) and the
    // give-ZEC direction z2b (ZEC → BTC). z2e (ZEC → ETH/USDC) lands separately.
    final sellAsset = request.direction.fromAsset(request.externalAsset);
    final receiveAsset = request.direction.toAsset(request.externalAsset);
    // Reuse the wallet's ZEC/USD price to fill the fiat "$" values so the review
    // and activity screens show a real amount instead of `$--`. Priced off the
    // same ZEC/USD source as the home balance; null price leaves fiat as `$--`.
    final fiatValueBasis = swapFiatValueBasisFromUsdPrices(
      usdPrices: _usdPrices(),
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
    );
    // Use the price-server's SIGNED /v1/attest rate for the quote, so the amount
    // shown == what the order posts + the user receives (not a wallet-local
    // rate). Falls back to the local estimate if the price server is
    // unreachable or for exact-output requests (the attestation binds a source
    // amount). See [_attestedExternalPerZec].
    double? attestedRate;
    try {
      attestedRate = await _attestedExternalPerZec(request);
    } catch (_) {
      attestedRate = null;
    }
    final cacheKey = _attestCacheKey(request);
    if (attestedRate != null && attestedRate > 0) {
      _lastAttestedPerZec[cacheKey] = attestedRate;
    }
    // Prefer, in order: this call's fresh attestation → the last real attested
    // rate for this pair → the caller-provided rate → the coarse hardcoded
    // fallback. This keeps the preview aligned with the review even when a
    // per-keystroke attestation call transiently fails.
    final previewRate =
        attestedRate ?? _lastAttestedPerZec[cacheKey] ?? externalPerZec;
    return SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      amount: request.amount,
      mode: request.mode,
      destination: request.destination,
      providerLabel: providerLabel,
      externalPerZec: previewRate,
      fiatValueBasis: fiatValueBasis,
      // Non-null so the activity tracker treats zwap intents as persistable
      // and keeps polling getStatus (which drives reveal → claim → sweep).
      providerQuoteId: 'zwap-atomic',
    );
  }

  /// Decimal exponent (10^n smallest units) per asset. Chain-agnostic: an ETH
  /// on Base has the same 18 decimals as ETH on Ethereum.
  static double _decimals(SwapAsset a) {
    var v = 1.0;
    for (var i = 0; i < a.decimals; i++) {
      v *= 10;
    }
    return v;
  }

  /// The price-server token key for an asset, by symbol (chain-agnostic).
  static String _attestKey(SwapAsset a) => switch (a.symbol.toUpperCase()) {
        'BTC' => 'btc',
        'ETH' => 'eth',
        'USDC' => 'usdc',
        _ => 'zec',
      };

  /// The attested external-units-per-ZEC rate for the requested pair, from the
  /// price server (the rate `SwapQuote.estimate` multiplies by). Returns null
  /// for exact-output requests (the attestation binds a SOURCE amount) or a
  /// non-positive amount — the caller then falls back to the local rate.
  Future<double?> _attestedExternalPerZec(SwapQuoteRequest request) async {
    if (request.mode != SwapQuoteMode.exactInput) return null;
    final asset = request.externalAsset;
    final ext = _attestKey(asset);
    final chain = _isEvmAsset(asset) ? _evmChainName(asset) : '';
    if (request.direction.sendsZec) {
      // give-ZEC: source = ZEC. output = external. rate = external / zec.
      final payZec = request.amount;
      final zats = BigInt.from((payZec * 1e8).round());
      if (payZec <= 0 || zats <= BigInt.zero) return null;
      final a = await client.fetchAttestation(
          from: 'zec', to: ext, amountSmallest: zats, chain: chain);
      final extOut = a.outputSmallest.toDouble() / _decimals(asset);
      return extOut / payZec;
    }
    // receive-ZEC: source = external. output = ZEC. rate = external / zec.
    final payExt = request.amount;
    final smallest = BigInt.from((payExt * _decimals(asset)).round());
    if (payExt <= 0 || smallest <= BigInt.zero) return null;
    final a = await client.fetchAttestation(
        from: ext, to: 'zec', amountSmallest: smallest, chain: chain);
    final zecOut = a.outputSmallest.toDouble() / 1e8;
    if (zecOut <= 0) return null;
    return payExt / zecOut;
  }

  /// The minimum joint-ZEC note a receive-ZEC swap may produce. The wallet
  /// sweeps the note to itself minus [sweepFeeZats]; below ~2× that fee the
  /// note can't cover the sweep (net ≤ 0) and would strand as an unspendable
  /// dust note (the "note value N <= fee" sweep failure). Guarded at order time
  /// so such a swap is never created.
  int get _minReceiveZats => sweepFeeZats * 2;

  /// Reject a receive-ZEC swap whose ZEC output can't cover the sweep fee.
  void _assertReceiveSweepable(int noteZats) {
    if (noteZats < _minReceiveZats) {
      throw StateError(
          'Amount too small: this swap yields about $noteZats zatoshi of ZEC, '
          'below the $_minReceiveZats zat minimum needed to cover the '
          '$sweepFeeZats zat network sweep fee. Increase the amount and retry.');
    }
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    final seed = await seedHex();
    final token = await client.authenticate(seed);
    final asset = quote.externalAsset;

    // Give-ZEC directions: the wallet funds the joint UA from its own balance
    // (via the shared give-ZEC deposit sender, keyed off the deposit instruction
    // address below) and later CLAIMS the solver-funded external lock —
    //  - z2b (ZEC → BTC): claim a BTC P2WSH HTLC (branch-1 witness);
    //  - z2e (ZEC → ETH/USDC): claim a singleton ZwapHtlc EVM lock (adaptor).
    if (quote.direction.sendsZec) {
      final dest = (quote.destination ?? '').trim();
      final giveZats = (quote.sellAmount * 1e8).round();
      if (asset == SwapAsset.btc) {
        if (dest.isEmpty) {
          throw StateError('zwap z2b: a BTC receive address is required');
        }
        final destSpk = await zwap.zwapBtcAddressToSpkHex(address: dest);
        final amountSat = (quote.receiveAmount * 1e8).round();
        // The user claims the BTC lock minus [btcClaimFeeSat]; it must also clear
        // the ~294-sat p2wpkh dust floor, else the claim tx can't be built.
        const btcDustSat = 294;
        if (amountSat <= btcClaimFeeSat + btcDustSat) {
          throw StateError(
              'Amount too small: this swap yields about $amountSat sat of BTC, '
              'below the ${btcClaimFeeSat + btcDustSat} sat minimum needed to '
              'cover the claim fee + dust. Increase the amount and retry.');
        }
        final order = await client.createZ2bOrder(
          seedHex: seed,
          token: token,
          swapId: 'z2b-${DateTime.now().microsecondsSinceEpoch}',
          amountSat: amountSat,
          shieldedValueZats: giveZats,
          timelocks: timelocks,
        );
        final settle = _Settle.fromZ2b(order, destSpk);
        return await _giveZecSnapshot(quote, token, settle, 'BTC');
      }
      // z2e (ETH/USDC): the user receives the external asset at their EVM addr.
      if (dest.isEmpty) {
        throw StateError('zwap z2e: an ETH receive address is required');
      }
      final isUsdc = _isUsdcAsset(asset);
      final amountWei = isUsdc
          ? BigInt.from((quote.receiveAmount * 1e6).round()).toString()
          : (BigInt.from((quote.receiveAmount * 1e9).round()) *
                  BigInt.from(1000000000))
              .toString();
      final order = await client.createZ2eOrder(
        seedHex: seed,
        token: token,
        swapId: 'z2e-${DateTime.now().microsecondsSinceEpoch}',
        amountWei: amountWei,
        shieldedValueZats: giveZats,
        recipientEvmAddr: dest,
        erc20: isUsdc ? _usdcAddrFor(asset) : '',
        chainId: _evmChainId(asset),
        chainName: _evmChainName(asset),
      );
      final settle = _Settle.fromZ2e(order, asset);
      return await _giveZecSnapshot(quote, token, settle, asset.symbol);
    }

    // Fresh Orchard receiver, committed to the order at creation.
    final receiveRaw = await newReceiveRawAddress();

    final _Settle settle;
    if (asset == SwapAsset.btc) {
      // b2z: `amountSat` is the BTC deposit; the joint ZEC note is funded at the
      // price-server's ATTESTED rate (not 1:1). The sweepability check therefore
      // lives inside createB2zOrder against the attested ZEC output — checking
      // BTC sats here would be a unit error.
      final amountSat = (quote.sellAmount * 1e8).round();
      final order = await client.createB2zOrder(
        seedHex: seed,
        token: token,
        swapId: 'b2z-${DateTime.now().microsecondsSinceEpoch}',
        amountSat: amountSat,
        timelocks: timelocks,
        receiveRawAddress: receiveRaw,
        minReceiveZats: _minReceiveZats,
      );
      settle = _Settle.fromB2z(order);
    } else {
      // e2z / usdc2z: the ZEC leg (zatoshis) is what the solver funds; the EVM
      // deposit `amountWei` is the external unit in its smallest denomination
      // (ETH = 18 decimals, USDC = 6). `sellAmount` is the external amount.
      final amountZats = (quote.receiveAmount * 1e8).round();
      _assertReceiveSweepable(amountZats);
      final isUsdc = _isUsdcAsset(asset);
      final amountWei = isUsdc
          ? BigInt.from((quote.sellAmount * 1e6).round()).toString()
          : (BigInt.from((quote.sellAmount * 1e9).round()) *
                  BigInt.from(1000000000))
              .toString();
      final order = await client.createE2zProxyOrder(
        seedHex: seed,
        token: token,
        swapId: 'e2z-${DateTime.now().microsecondsSinceEpoch}',
        initiatorEvmAddr: initiatorEvmAddr,
        amountZats: amountZats,
        amountWei: amountWei,
        receiveRawAddress: receiveRaw,
        erc20: isUsdc ? _usdcAddrFor(asset) : '',
        chainId: _evmChainId(asset),
        chainName: _evmChainName(asset),
      );
      settle = _Settle.fromE2z(order, asset);
    }

    final intent = _ZwapIntent(token: token, settle: settle);
    _intents[settle.obSwapId] = intent;
    await _persist(intent);

    final deposit = SwapDepositInstruction(
      asset: asset,
      address: settle.depositAddress,
      expiresInLabel: quote.expiryLabel,
      reuseWarning: 'Fund this ${asset.symbol} deposit once from your wallet.',
    );
    final base = SwapIntentSnapshot.fromQuote(quote, id: settle.obSwapId);
    return _withDeposit(base, deposit,
        status: SwapIntentStatus.awaitingExternalDeposit,
        nextAction: 'Send ${asset.symbol} to ${settle.depositAddress}');
  }

  /// Recover an ORPHANED b2z (BTC→ZEC) swap whose full recovery record is gone
  /// (created before persistence existed, or otherwise lost) by REBUILDING the
  /// `_Settle` from a minimal record: `(seed, obSwapId, deriveId)`.
  ///
  /// Re-authenticates the orderbook, re-fetches the solver's Phase0 half, and
  /// deterministically re-derives the joint ZEC keys via the same path
  /// `startSwap` used. The original committed sweep address is not needed — a
  /// FRESH [newReceiveRawAddress] is used, and the ZEC still lands in the user's
  /// wallet because the sweep spends the joint note to whatever destination we
  /// pass. The rebuilt intent is dropped into [_intents] and persisted (so it is
  /// now a full record), then the normal poll → `_sweep` path settles it.
  ///
  /// Returns the current snapshot after one status pass (which, for a swap the
  /// solver has already funded + claimed, triggers the sweep immediately).
  Future<SwapIntentSnapshot> recoverOrphanedB2z({
    required String obSwapId,
    required String deriveId,
  }) async {
    final seed = await seedHex();
    final token = await client.authenticate(seed);
    final receiveRaw = await newReceiveRawAddress();
    final order = await client.deriveB2zMaterialForRecovery(
      seedHex: seed,
      token: token,
      obSwapId: obSwapId,
      deriveId: deriveId,
      receiveRawAddress: receiveRaw,
      timelocks: timelocks,
    );
    final settle = _Settle.fromB2z(order);
    final intent = _ZwapIntent(token: token, settle: settle);
    _intents[settle.obSwapId] = intent;
    await _persist(intent);
    log('[zwap] recoverOrphanedB2z rebuilt ob=$obSwapId deriveId=$deriveId '
        'joint=${settle.jointZecAddress}');
    // Drive one status pass — for an already-funded+claimed swap the reveal is
    // skipped (solver owns it) and the sweep runs.
    return getStatus(obSwapId);
  }

  /// Register a give-ZEC intent + return the deposit snapshot (the wallet
  /// auto-funds ZEC → the joint UA via the shared deposit sender).
  Future<SwapIntentSnapshot> _giveZecSnapshot(
      SwapQuote quote, String token, _Settle settle, String recvSymbol) async {
    final intent = _ZwapIntent(token: token, settle: settle);
    _intents[settle.obSwapId] = intent;
    await _persist(intent);
    final deposit = SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: settle.depositAddress,
      expiresInLabel: quote.expiryLabel,
      reuseWarning: 'Funds the joint note once from your wallet.',
    );
    final base = SwapIntentSnapshot.fromQuote(quote, id: settle.obSwapId);
    return _withDeposit(base, deposit,
        status: SwapIntentStatus.awaitingExternalDeposit,
        nextAction: 'Funding the joint note, then claiming $recvSymbol');
  }

  /// Recover the OB snapshot, transparently re-authenticating if the bearer
  /// token has expired (a stale token → HTTP 401, e.g. after an orderbook
  /// restart or a long-idle swap). Without this, an expired token surfaces as a
  /// scary "Swap service is temporarily unavailable" banner even though the swap
  /// is fine — mint a fresh token, persist it, and retry once.
  Future<Map<String, dynamic>> _recoverWithReauth(
      _ZwapIntent intent, String seed) async {
    try {
      return await client.recover(intent.token, intent.settle.obSwapId);
    } catch (e) {
      if (!e.toString().contains('401')) rethrow;
      log('[zwap] recover 401 — re-authenticating ob=${intent.settle.obSwapId}');
      intent.token = await client.authenticate(seed);
      await _persist(intent);
      return await client.recover(intent.token, intent.settle.obSwapId);
    }
  }

  @override
  Future<SwapIntentSnapshot> getStatus(String intentId,
      {String? depositMemo}) async {
    // The activity tracker polls with the intent's DEPOSIT ADDRESS (the BTC
    // lock / CREATE2 addr), not the OB swapId, so resolve by either.
    var intent = _resolveIntent(intentId);
    // Not in memory — the app may have restarted and wiped [_intents]. Rehydrate
    // from durable storage (re-authenticating the orderbook, since the bearer is
    // never persisted) before giving up.
    intent ??= await _rehydrate(intentId);
    if (intent == null) {
      log('[zwap] getStatus($intentId): unknown swap '
          '(known=${_intents.keys.toList()})');
      throw StateError('zwap: unknown swap $intentId');
    }
    final seed = await seedHex();
    final s = intent.settle;
    final snap = await _recoverWithReauth(intent, seed);
    final state = (snap['state'] ?? '') as String;
    log('[zwap] getStatus ob=${s.obSwapId} state=$state '
        'revealed=${intent.revealedSecret != null} swept=${intent.swept}');

    final claimTxidBefore = intent.claimTxid;
    final revealedBefore = intent.revealedSecret != null;
    final sweptBefore = intent.swept;
    try {
      if (s.isZ2b) {
        // Give-ZEC: no reveal (solver owns the secret), no sweep (solver drains
        // the joint note). Once the solver funds+reveals, CLAIM the BTC lock.
        await _maybeClaimZ2b(intent, seed, snap, state);
      } else if (s.isZ2e) {
        // Give-ZEC EVM: once the solver funds+reveals + posts its claim_buy
        // adaptor, complete it and relay the claim (revealing k_user).
        await _maybeClaimZ2e(intent, seed, snap, state);
      } else if ((state == 'SecretReveal' ||
              state == 'ShieldedFunded' ||
              state == 'BothFunded') &&
          intent.revealedSecret == null) {
        // Reveal derives from deriveId and is POSTed to the orderbook
        // (BothFunded → SecretRevealed) so the solver claims its leg. The OB
        // verifies SHA256(secret) == swap_hash.
        final secret =
            await zwap.zwapRevealSecretHex(seedHex: seed, swapId: s.deriveId);
        log('[zwap] revealing secret ob=${s.obSwapId} deriveId=${s.deriveId}');
        await client.revealSecret(intent.token, s.obSwapId, secret);
        intent.revealedSecret = secret;
        log('[zwap] reveal OK ob=${s.obSwapId}');
      } else if ((state == 'LockClaimed' ||
              state == 'SecretRevealed' ||
              state == 'EvmClaimSeen' ||
              // EVM legs stay revealed until the solver's on-chain claim shows
              // up; keep attempting the sweep (it no-ops until k is recoverable).
              (s.isEvmLeg && intent.revealedSecret != null)) &&
          !intent.swept) {
        log('[zwap] sweeping joint note ob=${s.obSwapId}');
        intent.swept = await _sweep(intent, seed, snap);
        log('[zwap] sweep result=${intent.swept} ob=${s.obSwapId}');
      }
    } catch (e, st) {
      // "note value X <= fee Y": the joint note the solver funded is smaller
      // than the sweep/claim network fee — the swap can't economically complete.
      // This is a terminal condition, NOT a transient service outage, so DON'T
      // rethrow (which spams the scary "service unavailable" banner every poll).
      // Surface a clear, specific message instead.
      final msg = e.toString();
      if (msg.contains('<= fee') || msg.contains('below the dust threshold')) {
        intent.belowFee = true;
        log('[zwap] getStatus: amount below network fee ob=${s.obSwapId}: $e');
      } else {
        log('[zwap] getStatus step FAILED state=$state ob=${s.obSwapId}: $e\n$st');
        rethrow;
      }
    }

    // Persist any flag flip so a restart mid-flow resumes from the latest state.
    if (intent.claimTxid != claimTxidBefore ||
        (intent.revealedSecret != null) != revealedBefore ||
        intent.swept != sweptBefore) {
      await _persist(intent);
    }

    final status = _mapState(state);

    // Partial-deposit progress: every RECEIVE-ZEC external deposit accepts
    // top-ups toward the required amount — b2z (BTC to the lock address) and
    // e2z/usdc2z (ETH/USDC to the CREATE2 proxy). The OB reports a running
    // deposited/owed total for all of them (`chain != "eth" || is_proxy`). While
    // still awaiting the deposit, surface how much is in vs owed so the deposit
    // screen shows "X received / send Y more", keeping the SAME address visible.
    // Give-ZEC (z2b/z2e) is exempt — the wallet auto-sends the full ZEC deposit
    // in one tx, so there is no user-driven partial. Best-effort: a poll failure
    // must not break the status refresh.
    SwapDepositProgress? depositProgress;
    if (!s.isZ2b &&
        !s.isZ2e &&
        status == SwapIntentStatus.awaitingExternalDeposit) {
      try {
        final d = await client.pollDepositStatus(intent.token, s.obSwapId);
        final remaining = d.required - d.deposited;
        // Only a genuine PARTIAL deposit (some in, some still owed) gets the
        // "send N more" line — a full deposit (remaining <= 0) leaves it null so
        // the page shows the normal amount and advances.
        if (d.deposited > BigInt.zero && remaining > BigInt.zero) {
          depositProgress = SwapDepositProgress(
            remainingText: _fmtDepositSmallest(remaining, s.depositAsset),
            depositedText: _fmtDepositSmallest(d.deposited, s.depositAsset),
          );
        }
      } catch (e) {
        log('[zwap] pollDepositStatus failed ob=${s.obSwapId}: $e');
      }
    }

    // Terminal → drop the persisted record to avoid unbounded growth.
    if (status.isTerminal) {
      await _forget(s.obSwapId);
    }

    return _statusSnapshot(intent, status, depositProgress: depositProgress);
  }

  /// Format a token amount in its smallest units (wei / 6-dec USDC) as a
  /// display string like "0.5 USDC" for the partial-deposit progress line.
  String _fmtDepositSmallest(BigInt smallest, SwapAsset asset) {
    final unit = BigInt.from(10).pow(asset.decimals).toDouble();
    return '${asset.formatAmount(smallest.toDouble() / unit)} ${asset.symbol}';
  }

  /// Resolve an in-memory intent by orderbook id or deposit address.
  _ZwapIntent? _resolveIntent(String intentId) {
    return _intents[intentId] ??
        _intents.values.cast<_ZwapIntent?>().firstWhere(
              (i) => i!.settle.depositAddress == intentId,
              orElse: () => null,
            );
  }

  /// Write one swap's recovery material to durable storage (no-op if [store] is
  /// null). Best-effort: a storage failure must not break an otherwise healthy
  /// swap step, so it is logged and swallowed.
  Future<void> _persist(_ZwapIntent intent) async {
    final store = this.store;
    if (store == null) return;
    try {
      await store.save(intent.settle.obSwapId, intent.toJson());
    } catch (e) {
      log('[zwap] persist FAILED ob=${intent.settle.obSwapId}: $e');
    }
  }

  /// Remove a terminal swap's persisted record (best-effort).
  Future<void> _forget(String obSwapId) async {
    final store = this.store;
    if (store == null) return;
    try {
      await store.delete(obSwapId);
    } catch (e) {
      log('[zwap] forget FAILED ob=$obSwapId: $e');
    }
  }

  /// Rehydrate a swap from durable storage after [_intents] was wiped (app
  /// restart). Loads every persisted swap for the active account, re-populates
  /// [_intents], re-authenticates the orderbook (the bearer is never persisted),
  /// and returns the intent matching [intentId] (by ob id or deposit address).
  Future<_ZwapIntent?> _rehydrate(String intentId) async {
    final store = this.store;
    if (store == null) return null;
    final List<Map<String, dynamic>> saved;
    try {
      saved = await store.loadAll();
    } catch (e) {
      log('[zwap] rehydrate load FAILED: $e');
      return null;
    }
    if (saved.isEmpty) return null;

    // Re-authenticate once; the fresh bearer is shared across every rehydrated
    // intent for this account.
    String token;
    try {
      final seed = await seedHex();
      token = await client.authenticate(seed);
    } catch (e) {
      log('[zwap] rehydrate auth FAILED: $e');
      return null;
    }

    for (final json in saved) {
      final restored = _ZwapIntent.fromJson(json, token);
      if (restored == null) continue;
      // Do not clobber a live in-memory intent (e.g. one just created).
      _intents.putIfAbsent(restored.settle.obSwapId, () => restored);
    }
    log('[zwap] rehydrated ${saved.length} swap(s) from storage');
    return _resolveIntent(intentId);
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    final intent = _intents.values.firstWhere(
      (i) => i.settle.depositAddress == depositAddress,
      orElse: () => throw StateError('zwap: no swap for $depositAddress'),
    );
    return getStatus(intent.settle.obSwapId, depositMemo: depositMemo);
  }

  /// Reconstruct the joint `ask`, discover the joint note LOCALLY (never trust
  /// the orderbook's note fields), and sweep it to the fresh receiver committed
  /// at order creation. Returns true once broadcast.
  Future<bool> _sweep(
      _ZwapIntent intent, String seed, Map<String, dynamic> snap) async {
    final s = intent.settle;
    String? kb;
    if (s.isEvmLeg) {
      // e2z/usdc2z: the indexer does NOT recover k for EVM legs (ASMR — it lacks
      // the adaptor), so the wallet recovers k_solver itself from the on-chain
      // completed `claim_buy` signature (`userRedeem.evmClaimSigB`) + its Phase0
      // adaptor.
      final urMap = snap['userRedeem'] as Map<String, dynamic>?;
      final sigB = (urMap?['evmClaimSigB'] ?? snap['evmClaimSigB']) as String?;
      if (sigB == null) return false; // EVM claim not on-chain yet
      try {
        kb = await zwap.zwapRecoverKFromClaimSig(
          adaptorHex: s.evmClaimAdaptorHex!,
          onchainSigHex: sigB,
          expectedSecpPubkeyHex: s.solverLockPubkeyHex!,
        );
      } catch (e) {
        log('[zwap] e2z k-recover failed: $e');
        return false;
      }
    } else {
      final ur = snap['userRedeem'] as Map<String, dynamic>?;
      kb = ur?['recoveredKb'] as String?;
    }
    if (kb == null) return false; // k_b not revealed yet

    final tip = await client.zecTipHeight();
    // The frontier anchor is fetched at `from - 1`; treestate at height 0 is
    // null (empty tree), so keep the scan start at >= 2 on a low/fresh chain.
    final from = tip > 200 ? tip - 200 : 2;

    final note = await client.discoverJointNoteLocally(
      toHeight: tip,
      scanHeight: from,
      akHex: s.jointZecAkHex,
      nkHex: s.jointZecNkHex,
      rivkHex: s.jointZecRivkHex,
      ivkHex: s.jointZecIvkHex,
      diversifierHex: s.jointZecDiversifierHex,
    );
    if (note == null) return false; // not on-chain yet — retry next poll

    await client.sweepJointNote(
      seedHex: seed,
      deriveId: s.deriveId,
      recoveredKbBeHex: kb,
      nkHex: s.jointZecNkHex,
      rivkHex: s.jointZecRivkHex,
      note: note,
      destRawAddressHex: s.receiveRawAddress,
      fee: sweepFeeZats,
    );
    return true;
  }

  /// z2b claim step: once the solver funds the BTC lock and reveals the secret
  /// (surfaced on the recover snapshot's `userRedeem`), build + sign + broadcast
  /// the branch-1 claim to the user's BTC receive spk, then report the txid.
  /// Idempotent (no-ops after the first broadcast, and until the solver funds).
  Future<void> _maybeClaimZ2b(_ZwapIntent intent, String seed,
      Map<String, dynamic> snap, String state) async {
    if (intent.claimTxid != null) return;
    const claimStates = {
      'ShieldedFunded',
      'SecretReveal',
      'SecretRevealed',
      'LockClaimed',
    };
    if (!claimStates.contains(state)) return;
    final ur = snap['userRedeem'] as Map<String, dynamic>?;
    final secret = ur?['swapSecret'] as String?;
    final outpoint = ur?['lockOutpoint'] as Map<String, dynamic>?;
    if (secret == null || outpoint == null) return; // solver not ready yet
    final valueSat = int.tryParse('${outpoint['value'] ?? ''}') ?? 0;
    if (valueSat <= 0 || outpoint['txid'] == null) return;
    final s = intent.settle;
    log('[zwap] z2b claiming BTC lock ob=${s.obSwapId} '
        'utxo=${outpoint['txid']}:${outpoint['vout']} value=$valueSat');
    final txid = await client.signAndBroadcastZ2bClaim(
      seedHex: seed,
      deriveId: s.deriveId,
      lockTxid: outpoint['txid'] as String,
      lockVout: (outpoint['vout'] as num).toInt(),
      lockValueSat: valueSat,
      witnessScriptHex: s.z2bWitnessScriptHex!,
      swapSecretHex: secret,
      destSpkHex: s.z2bDestSpkHex!,
      feeSat: btcClaimFeeSat,
    );
    intent.claimTxid = txid;
    log('[zwap] z2b BTC claim broadcast txid=$txid ob=${s.obSwapId}');
    await client.reportClaimResult(intent.token, s.obSwapId, txid);
  }

  /// z2e claim step: once the solver funds the EVM lock + reveals the secret +
  /// posts its `claim_buy` adaptor (surfaced on `userRedeem`), complete the
  /// adaptor with the user's `k_be` and relay `claim_buy` to the eth-relayer,
  /// then report the txid. Idempotent; no-ops until the solver posts the adaptor.
  Future<void> _maybeClaimZ2e(_ZwapIntent intent, String seed,
      Map<String, dynamic> snap, String state) async {
    if (intent.claimTxid != null) return;
    const claimStates = {
      'ShieldedFunded',
      'SecretReveal',
      'SecretRevealed',
      'LockClaimed',
    };
    if (!claimStates.contains(state)) return;
    final ur = snap['userRedeem'] as Map<String, dynamic>?;
    final secret = ur?['swapSecret'] as String?;
    final adaptor = ur?['evmClaimAdaptorSig'] as String?;
    if (secret == null || adaptor == null) return; // solver not ready yet
    final s = intent.settle;
    log('[zwap] z2e claiming EVM lock ob=${s.obSwapId} slot=${s.z2eSlotIdHex}');
    final txid = await client.relayZ2eClaim(
      seedHex: seed,
      deriveId: s.deriveId,
      swapId: s.obSwapId,
      slotIdHex: s.z2eSlotIdHex!,
      claimBuyDigestHex: s.z2eClaimBuyDigestHex!,
      solverClaimAddrHex: s.z2eSolverClaimAddrHex!,
      adaptorHex: adaptor,
      swapSecretHex: secret,
      chainId: s.z2eChainId ?? 31337,
    );
    intent.claimTxid = txid;
    log('[zwap] z2e EVM claim relayed txid=$txid ob=${s.obSwapId}');
    await client.reportClaimResult(intent.token, s.obSwapId, txid);
  }

  SwapIntentStatus _mapState(String state) => switch (state) {
        'Created' || 'Matched' || 'KeysExchanged' =>
          SwapIntentStatus.awaitingExternalDeposit,
        'LockFunded' || 'InitiatorFunded' => SwapIntentStatus.depositObserved,
        'ShieldedFunded' ||
        'SecretReveal' ||
        'SecretRevealed' ||
        'BothFunded' ||
        'FirstClaim' ||
        'LockClaimed' =>
          SwapIntentStatus.processing,
        'Settled' => SwapIntentStatus.complete,
        'Refunded' => SwapIntentStatus.refunded,
        'Expired' => SwapIntentStatus.expired,
        _ => SwapIntentStatus.providerStatusUnknown,
      };

  SwapIntentSnapshot _statusSnapshot(
      _ZwapIntent intent, SwapIntentStatus status,
      {SwapDepositProgress? depositProgress}) {
    final s = intent.settle;
    return SwapIntentSnapshot(
      id: s.obSwapId,
      depositProgress: depositProgress,
      providerLabel: providerLabel,
      pairText: s.isZ2b
          ? 'ZEC → BTC'
          : s.isZ2e
              ? 'ZEC → ${s.z2eReceiveAsset?.symbol ?? 'ETH'}'
              : '${s.depositAsset.symbol} → ZEC',
      sellAmountText: '',
      receiveEstimateText: '',
      status: status,
      nextAction: intent.belowFee
          ? 'Received amount is below the network fee — nothing to claim.'
          : switch (status) {
              SwapIntentStatus.awaitingExternalDeposit => (s.isZ2b || s.isZ2e)
                  ? 'Funding the joint note'
                  : 'Send ${s.depositAsset.symbol} to ${s.depositAddress}',
              SwapIntentStatus.complete => s.isZ2b
                  ? 'BTC sent to your wallet'
                  : s.isZ2e
                      ? '${s.z2eReceiveAsset?.symbol ?? 'ETH'} sent to your wallet'
                      : 'Swept to your Zcash wallet',
              _ => (s.isZ2b || s.isZ2e)
                  ? 'Claiming your funds'
                  : 'Processing atomic swap',
            },
      depositInstruction: SwapDepositInstruction(
        asset: s.depositAsset,
        address: s.depositAddress,
        expiresInLabel: '',
        reuseWarning: 'Fund this ${s.depositAsset.symbol} deposit once.',
      ),
      destinationChainTxHash: (s.isZ2b || s.isZ2e)
          ? intent.claimTxid
          : (intent.swept ? s.jointZecAddress : null),
    );
  }

  SwapIntentSnapshot _withDeposit(
    SwapIntentSnapshot base,
    SwapDepositInstruction deposit, {
    required SwapIntentStatus status,
    required String nextAction,
  }) {
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: status,
      nextAction: nextAction,
      depositInstruction: deposit,
      swapFeeText: base.swapFeeText,
      totalFeesText: base.totalFeesText,
      slippageToleranceText: base.slippageToleranceText,
      minimumReceiveText: base.minimumReceiveText,
      sellAmountBaseUnits: base.sellAmountBaseUnits,
      fiatValueBasis: base.fiatValueBasis,
    );
  }
}

/// Direction-agnostic settlement view: the fields the wallet needs to reveal +
/// discover + sweep the joint note, regardless of which external leg funded it.
class _Settle {
  const _Settle({
    required this.obSwapId,
    required this.deriveId,
    required this.depositAddress,
    required this.depositAsset,
    required this.jointZecAddress,
    required this.jointZecNkHex,
    required this.jointZecRivkHex,
    required this.jointZecAkHex,
    required this.jointZecIvkHex,
    required this.jointZecDiversifierHex,
    required this.receiveRawAddress,
    this.evmClaimAdaptorHex,
    this.solverLockPubkeyHex,
    this.z2bWitnessScriptHex,
    this.z2bDestSpkHex,
    this.z2eSlotIdHex,
    this.z2eClaimBuyDigestHex,
    this.z2eSolverClaimAddrHex,
    this.z2eChainId,
    this.z2eReceiveAsset,
  });

  /// z2e (ZEC→ETH/USDC): the user funds the joint UA and CLAIMS the solver-funded
  /// singleton ZwapHtlc lock by completing the solver's `claim_buy` adaptor.
  factory _Settle.fromZ2e(ZwapZ2eOrder o, SwapAsset asset) => _Settle(
        obSwapId: o.swapId,
        deriveId: o.deriveId,
        depositAddress: o.jointZecAddress,
        depositAsset: SwapAsset.zec,
        jointZecAddress: o.jointZecAddress,
        jointZecNkHex: '',
        jointZecRivkHex: '',
        jointZecAkHex: '',
        jointZecIvkHex: '',
        jointZecDiversifierHex: '',
        receiveRawAddress: '',
        z2eSlotIdHex: o.evmSlotIdHex,
        z2eClaimBuyDigestHex: o.claimBuyDigestHex,
        z2eSolverClaimAddrHex: o.solverClaimAddrHex,
        z2eChainId: o.chainId,
        z2eReceiveAsset: asset,
      );

  /// z2b (ZEC→BTC): the user funds the joint UA and CLAIMS the solver-funded BTC
  /// lock (branch-1) to [z2bDestSpkHex]. No reveal (solver owns the secret) and
  /// no sweep in the happy path — the solver drains the joint note.
  factory _Settle.fromZ2b(ZwapZ2bOrder o, String destSpkHex) => _Settle(
        obSwapId: o.swapId,
        deriveId: o.deriveId,
        depositAddress: o.jointZecAddress, // the wallet funds this
        depositAsset: SwapAsset.zec,
        jointZecAddress: o.jointZecAddress,
        jointZecNkHex: o.jointZecNkHex,
        jointZecRivkHex: o.jointZecRivkHex,
        jointZecAkHex: o.jointZecAkHex,
        jointZecIvkHex: o.jointZecIvkHex,
        jointZecDiversifierHex: o.jointZecDiversifierHex,
        receiveRawAddress: '', // no sweep destination on the happy path
        z2bWitnessScriptHex: o.witnessScriptHex,
        z2bDestSpkHex: destSpkHex,
      );

  factory _Settle.fromB2z(ZwapB2zOrder o) => _Settle(
        obSwapId: o.swapId,
        deriveId: o.deriveId,
        depositAddress: o.btcLockAddress,
        depositAsset: SwapAsset.btc,
        jointZecAddress: o.jointZecAddress,
        jointZecNkHex: o.jointZecNkHex,
        jointZecRivkHex: o.jointZecRivkHex,
        jointZecAkHex: o.jointZecAkHex,
        jointZecIvkHex: o.jointZecIvkHex,
        jointZecDiversifierHex: o.jointZecDiversifierHex,
        receiveRawAddress: o.receiveRawAddress,
      );

  factory _Settle.fromE2z(ZwapE2zOrder o, SwapAsset asset) => _Settle(
        obSwapId: o.swapId,
        deriveId: o.deriveId,
        depositAddress: o.depositAddress,
        depositAsset: asset,
        jointZecAddress: o.jointZecAddress,
        jointZecNkHex: o.jointZecNkHex,
        jointZecRivkHex: o.jointZecRivkHex,
        jointZecAkHex: o.jointZecAkHex,
        jointZecIvkHex: o.jointZecIvkHex,
        jointZecDiversifierHex: o.jointZecDiversifierHex,
        receiveRawAddress: o.receiveRawAddress,
        evmClaimAdaptorHex: o.evmClaimAdaptorHex,
        solverLockPubkeyHex: o.solverLockPubkeyHex,
      );

  final String obSwapId;
  final String deriveId;
  final String depositAddress;
  final SwapAsset depositAsset;
  final String jointZecAddress;
  final String jointZecNkHex;
  final String jointZecRivkHex;
  final String jointZecAkHex;
  final String jointZecIvkHex;
  final String jointZecDiversifierHex;
  final String receiveRawAddress;

  /// e2z/usdc2z only: the Phase0 adaptor + solver lockPubkey used to recover
  /// k_solver from the on-chain `claim_buy` sig (null for b2z, which reads
  /// `userRedeem.recoveredKb` from the orderbook instead).
  final String? evmClaimAdaptorHex;
  final String? solverLockPubkeyHex;

  /// z2b only: the lock witnessScript + the user's BTC receive scriptPubKey.
  final String? z2bWitnessScriptHex;
  final String? z2bDestSpkHex;

  /// z2e only: the EVM lock slot + claim digest + solver claim addr + chain.
  final String? z2eSlotIdHex;
  final String? z2eClaimBuyDigestHex;
  final String? z2eSolverClaimAddrHex;
  final int? z2eChainId;
  final SwapAsset? z2eReceiveAsset;

  bool get isEvmLeg => evmClaimAdaptorHex != null;
  bool get isZ2b => z2bWitnessScriptHex != null;
  bool get isZ2e => z2eSlotIdHex != null;

  /// Full serialization of every field across all leg variants (b2z / e2z /
  /// usdc2z receive-ZEC AND z2b / z2e give-ZEC). `SwapAsset` fields are stored
  /// by `.name` and looked up on load; the `isZ2b` / `isZ2e` / `isEvmLeg`
  /// discriminators are reconstructed from the presence of the optional fields.
  Map<String, Object?> toJson() => {
        'obSwapId': obSwapId,
        'deriveId': deriveId,
        'depositAddress': depositAddress,
        'depositAsset': depositAsset.name,
        'jointZecAddress': jointZecAddress,
        'jointZecNkHex': jointZecNkHex,
        'jointZecRivkHex': jointZecRivkHex,
        'jointZecAkHex': jointZecAkHex,
        'jointZecIvkHex': jointZecIvkHex,
        'jointZecDiversifierHex': jointZecDiversifierHex,
        'receiveRawAddress': receiveRawAddress,
        'evmClaimAdaptorHex': evmClaimAdaptorHex,
        'solverLockPubkeyHex': solverLockPubkeyHex,
        'z2bWitnessScriptHex': z2bWitnessScriptHex,
        'z2bDestSpkHex': z2bDestSpkHex,
        'z2eSlotIdHex': z2eSlotIdHex,
        'z2eClaimBuyDigestHex': z2eClaimBuyDigestHex,
        'z2eSolverClaimAddrHex': z2eSolverClaimAddrHex,
        'z2eChainId': z2eChainId,
        'z2eReceiveAsset': z2eReceiveAsset?.name,
      };

  static _Settle? fromJson(Map<String, dynamic> json) {
    String? str(Object? v) => v is String ? v : null;
    final obSwapId = str(json['obSwapId']);
    final deriveId = str(json['deriveId']);
    final depositAddress = str(json['depositAddress']);
    final depositAsset = SwapAsset.byName(str(json['depositAsset']) ?? '');
    if (obSwapId == null ||
        deriveId == null ||
        depositAddress == null ||
        depositAsset == null) {
      return null;
    }
    final chainId = json['z2eChainId'];
    final z2eAssetName = str(json['z2eReceiveAsset']);
    return _Settle(
      obSwapId: obSwapId,
      deriveId: deriveId,
      depositAddress: depositAddress,
      depositAsset: depositAsset,
      jointZecAddress: str(json['jointZecAddress']) ?? '',
      jointZecNkHex: str(json['jointZecNkHex']) ?? '',
      jointZecRivkHex: str(json['jointZecRivkHex']) ?? '',
      jointZecAkHex: str(json['jointZecAkHex']) ?? '',
      jointZecIvkHex: str(json['jointZecIvkHex']) ?? '',
      jointZecDiversifierHex: str(json['jointZecDiversifierHex']) ?? '',
      receiveRawAddress: str(json['receiveRawAddress']) ?? '',
      evmClaimAdaptorHex: str(json['evmClaimAdaptorHex']),
      solverLockPubkeyHex: str(json['solverLockPubkeyHex']),
      z2bWitnessScriptHex: str(json['z2bWitnessScriptHex']),
      z2bDestSpkHex: str(json['z2bDestSpkHex']),
      z2eSlotIdHex: str(json['z2eSlotIdHex']),
      z2eClaimBuyDigestHex: str(json['z2eClaimBuyDigestHex']),
      z2eSolverClaimAddrHex: str(json['z2eSolverClaimAddrHex']),
      z2eChainId: chainId is int ? chainId : null,
      z2eReceiveAsset:
          z2eAssetName == null ? null : SwapAsset.byName(z2eAssetName),
    );
  }
}

class _ZwapIntent {
  _ZwapIntent({required this.token, required this.settle});
  /// The orderbook bearer. Mutable so a status poll can transparently mint a
  /// fresh token when the old one expires (HTTP 401) instead of failing loud.
  String token;
  final _Settle settle;
  String? revealedSecret;
  bool swept = false;

  /// z2b: set once the BTC branch-1 claim is broadcast (its txid).
  String? claimTxid;

  /// Set when the received note is below the network fee (dust) — the swap can't
  /// complete; surfaced as a clear message instead of the generic error banner.
  bool belowFee = false;

  /// Serialize the recovery material + mutable flags. The [token] (orderbook
  /// bearer) is intentionally omitted — it is short-lived and re-acquired via
  /// `client.authenticate` on rehydrate.
  Map<String, Object?> toJson() => {
        'settle': settle.toJson(),
        'revealedSecret': revealedSecret,
        'swept': swept,
        'claimTxid': claimTxid,
      };

  /// Revive an intent from storage, pairing the persisted recovery material with
  /// a freshly re-authenticated [token]. Returns null if the payload is
  /// malformed (missing/corrupt settle block).
  static _ZwapIntent? fromJson(Map<String, dynamic> json, String token) {
    final settleJson = json['settle'];
    if (settleJson is! Map<String, dynamic>) return null;
    final settle = _Settle.fromJson(settleJson);
    if (settle == null) return null;
    final intent = _ZwapIntent(token: token, settle: settle);
    final revealed = json['revealedSecret'];
    if (revealed is String) intent.revealedSecret = revealed;
    intent.swept = json['swept'] == true;
    final claimTxid = json['claimTxid'];
    if (claimTxid is String) intent.claimTxid = claimTxid;
    return intent;
  }
}
