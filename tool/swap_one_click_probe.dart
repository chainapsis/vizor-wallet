import 'dart:io';

import 'package:zcash_wallet/src/features/swap/domain/near_intents_one_click_swap_provider.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_failure_policy.dart';

Future<void> main(List<String> args) async {
  late final OneClickProbeOptions options;
  try {
    options = OneClickProbeOptions.parse(args);
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln('');
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final provider = NearIntentsOneClickSwapProvider(
    baseUri: Uri.parse(options.baseUrl),
    bearerToken: options.jwt,
    referral: options.referral,
    assetIdOverrides: options.assetIdOverrides,
  );

  var operation = SwapFailureOperation.tokenList;
  try {
    stdout.writeln('1Click base: ${options.baseUrl}');
    stdout.writeln('JWT configured: ${options.jwt == null ? 'no' : 'yes'}');

    final assets = await provider.listSupportedExternalAssets();
    var quoteValidated = false;
    var statusValidated = false;
    _writeSupportedAssets(assets);

    if (options.quoteRequested) {
      operation = SwapFailureOperation.quote;
      final asset = options.resolveAsset(assets);
      final quote = await provider.quote(
        SwapQuoteRequest(
          direction: options.direction,
          externalAsset: asset,
          sellAmount: options.amount,
          sellAmountText: options.amountText,
          destination: options.destination!,
          refundAddress: options.refund!,
          dryRun: options.dryRun,
        ),
      );
      stdout.writeln(
        '${options.dryRun ? 'dry' : 'live'} quote: ${quote.pairText}',
      );
      stdout.writeln('sell: ${quote.sellAmountText}');
      stdout.writeln('receive: ${quote.receiveEstimateText}');
      stdout.writeln('minimum receive: ${quote.minimumReceiveText}');
      stdout.writeln('rate: ${quote.rateText}');
      stdout.writeln('fee: ${quote.feeLabel}');
      stdout.writeln('expiry: ${quote.expiryLabel}');
      stdout.writeln('deposit asset: ${quote.depositInstruction.asset.symbol}');
      stdout.writeln('deposit address: ${quote.depositInstruction.address}');
      if (quote.depositInstruction.memo != null) {
        stdout.writeln('deposit memo: ${quote.depositInstruction.memo}');
      }
      stdout.writeln('provider quote id: ${quote.providerQuoteId ?? '-'}');
      stdout.writeln(
        'provider signature: ${quote.providerSignature == null ? '-' : 'present'}',
      );
      quoteValidated = true;
    }

    final statusDeposit = options.statusDeposit;
    if (!options.tokensOnly && statusDeposit != null) {
      operation = SwapFailureOperation.refreshStatus;
      final status = await provider.getStatus(
        statusDeposit,
        depositMemo: options.statusMemo,
      );
      stdout.writeln('status id: ${status.id}');
      stdout.writeln('status: ${status.status.label}');
      stdout.writeln('next action: ${status.nextAction}');
      stdout.writeln('pair: ${status.pairText}');
      statusValidated = true;
    }
    stdout.writeln(
      'validation summary: '
      'tokens=ok '
      'quote=${quoteValidated ? 'ok' : 'skipped'} '
      'status=${statusValidated ? 'ok' : 'skipped'}',
    );
  } catch (error) {
    stderr.writeln(swapFailureMessage(operation, error));
    exitCode = 1;
  }
}

class OneClickProbeOptions {
  const OneClickProbeOptions({
    required this.baseUrl,
    required this.jwt,
    required this.referral,
    required this.tokensOnly,
    required this.quoteRequested,
    required this.direction,
    required this.asset,
    required this.assetId,
    required this.amount,
    required this.amountText,
    required this.destination,
    required this.refund,
    required this.statusDeposit,
    required this.statusMemo,
    required this.dryRun,
    required this.assetIdOverrides,
    required this.help,
  });

  factory OneClickProbeOptions.parse(List<String> args) {
    final help = args.contains('--help') || args.contains('-h');
    final tokensOnly = args.contains('--tokens-only');
    final statusDeposit = _option(args, '--status-deposit');
    final quoteRequested =
        !tokensOnly && (statusDeposit == null || _hasQuoteOption(args));
    final direction = _parseDirection(
      _option(args, '--direction') ?? 'zec-to-external',
    );
    final asset = _parseAsset(_option(args, '--asset') ?? 'USDC');
    final amountText = _option(args, '--amount') ?? '0';
    final amount = double.tryParse(amountText);
    final destination = _option(args, '--destination');
    final refund = _option(args, '--refund');
    final env = Platform.environment;
    final jwt = _nonEmpty(
      _option(args, '--jwt') ?? env['ZCASH_SWAP_1CLICK_JWT'],
    );
    final dryRun = _parseDryRun(
      _option(args, '--dry-run') ?? env['ZCASH_SWAP_PROBE_DRY_RUN'],
    );
    final assetId = _nonEmpty(
      _option(args, '--asset-id') ?? env['ZCASH_SWAP_PROBE_ASSET_ID'],
    );
    final usdcAssetId = _parseUsdcAssetIdOverride(args, env);
    if (assetId != null && usdcAssetId != null) {
      throw const _UsageException(
        'Use either --asset-id or a USDC-specific override, not both.',
      );
    }
    final assetIdOverrides = <SwapAsset, String>{};
    if (usdcAssetId != null) {
      assetIdOverrides[SwapAsset.usdc] = usdcAssetId;
    }
    if (!help && quoteRequested) {
      if (amount == null || amount <= 0) {
        throw const _UsageException('Provide --amount with a positive number.');
      }
      if (destination == null || destination.trim().isEmpty) {
        throw const _UsageException('Provide --destination for the dry quote.');
      }
      if (refund == null || refund.trim().isEmpty) {
        throw const _UsageException('Provide --refund for the dry quote.');
      }
    }
    if (!help &&
        !tokensOnly &&
        (quoteRequested || statusDeposit != null) &&
        jwt == null) {
      throw const _UsageException(
        'Provide --jwt or ZCASH_SWAP_1CLICK_JWT for quote/status live validation.',
      );
    }

    return OneClickProbeOptions(
      baseUrl:
          _option(args, '--base-url') ??
          env['ZCASH_SWAP_1CLICK_BASE_URL'] ??
          'https://1click.chaindefuser.com',
      jwt: jwt,
      referral: _nonEmpty(
        _option(args, '--referral') ?? env['ZCASH_SWAP_1CLICK_REFERRAL'],
      ),
      tokensOnly: tokensOnly,
      quoteRequested: quoteRequested,
      direction: direction,
      asset: asset,
      assetId: assetId,
      amount: amount ?? 0,
      amountText: amountText,
      destination: destination,
      refund: refund,
      statusDeposit: statusDeposit,
      statusMemo: _option(args, '--status-memo'),
      dryRun: dryRun,
      assetIdOverrides: assetIdOverrides,
      help: help,
    );
  }

  final String baseUrl;
  final String? jwt;
  final String? referral;
  final bool tokensOnly;
  final bool quoteRequested;
  final SwapDirection direction;
  final SwapAsset asset;
  final String? assetId;
  final double amount;
  final String amountText;
  final String? destination;
  final String? refund;
  final String? statusDeposit;
  final String? statusMemo;
  final bool dryRun;
  final Map<SwapAsset, String> assetIdOverrides;
  final bool help;

  SwapAsset resolveAsset(List<SwapAsset> supportedAssets) {
    final exactAssetId = assetId;
    if (exactAssetId == null) return asset;
    for (final supportedAsset in supportedAssets) {
      if (supportedAsset.assetId == exactAssetId) {
        return supportedAsset;
      }
    }
    throw OneClickApiException(
      '1Click token list does not include asset id $exactAssetId',
      operation: 'token list',
    );
  }
}

String? _option(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

bool _hasQuoteOption(List<String> args) {
  return _option(args, '--amount') != null ||
      _option(args, '--destination') != null ||
      _option(args, '--refund') != null ||
      _option(args, '--direction') != null ||
      _option(args, '--asset') != null ||
      _option(args, '--asset-id') != null ||
      _option(args, '--usdc-chain') != null ||
      _option(args, '--usdc-asset-id') != null;
}

String? _nonEmpty(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

bool _parseDryRun(String? value) {
  if (value == null || value.trim().isEmpty) return true;
  return switch (value.trim().toLowerCase()) {
    '1' || 'true' || 'yes' || 'dry' => true,
    '0' || 'false' || 'no' || 'live' => false,
    _ => throw _UsageException('Unsupported --dry-run: $value'),
  };
}

SwapDirection _parseDirection(String value) {
  return switch (value.toLowerCase()) {
    'zec-to-external' || 'send-zec' || 'out' => SwapDirection.zecToExternal,
    'external-to-zec' || 'receive-zec' || 'in' => SwapDirection.externalToZec,
    _ => throw _UsageException('Unsupported --direction: $value'),
  };
}

SwapAsset _parseAsset(String value) {
  return switch (value.toUpperCase()) {
    'USDC' => SwapAsset.usdc,
    'ETH' => SwapAsset.eth,
    'BTC' => SwapAsset.btc,
    'SOL' => SwapAsset.sol,
    'USDT' => SwapAsset.usdt,
    'DAI' => SwapAsset.dai,
    'WBTC' => SwapAsset.wbtc,
    'NEAR' => SwapAsset.near,
    'DOGE' => SwapAsset.doge,
    _ => throw _UsageException('Unsupported --asset: $value'),
  };
}

String _assetListLabel(SwapAsset asset) {
  final assetId = asset.assetId;
  final suffix = assetId == null ? '' : ' [$assetId]';
  return '${asset.symbol} on ${asset.chainLabel}$suffix';
}

void _writeSupportedAssets(List<SwapAsset> assets) {
  stdout.writeln('supported external assets (${assets.length}):');
  for (final asset in assets) {
    stdout.writeln('  - ${_assetListLabel(asset)}');
  }
}

String? _parseUsdcAssetIdOverride(List<String> args, Map<String, String> env) {
  final direct = _nonEmpty(
    _option(args, '--usdc-asset-id') ?? env['ZCASH_SWAP_PROBE_USDC_ASSET_ID'],
  );
  final chain = _nonEmpty(
    _option(args, '--usdc-chain') ?? env['ZCASH_SWAP_PROBE_USDC_CHAIN'],
  );
  if (direct != null && chain != null) {
    throw const _UsageException(
      'Use either --usdc-asset-id or --usdc-chain, not both.',
    );
  }
  if (direct != null) return direct;
  if (chain == null) return null;
  return _usdcAssetIdForChain(chain);
}

String _usdcAssetIdForChain(String value) {
  return switch (value.toLowerCase()) {
    'eth' || 'ethereum' =>
      'nep141:eth-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48.omft.near',
    'base' =>
      'nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near',
    'arb' || 'arbitrum' =>
      'nep141:arb-0xaf88d065e77c8cc2239327c5edb3a432268e5831.omft.near',
    'near' =>
      'nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1',
    _ => throw _UsageException('Unsupported --usdc-chain: $value'),
  };
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _usage = '''
Probe the NEAR Intents 1Click provider using the same parser used by /swap.

Examples:
  fvm dart run tool/swap_one_click_probe.dart --tokens-only

  scripts/e2e/swap-one-click-live-validation.sh --help

  scripts/e2e/swap-one-click-live-validation.sh --tokens-only

  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  ZCASH_SWAP_PROBE_AMOUNT=0.01 \\
  ZCASH_SWAP_PROBE_DESTINATION=0xRecipientAddress \\
  ZCASH_SWAP_PROBE_REFUND=t1RefundAddress \\
    scripts/e2e/swap-one-click-live-validation.sh

  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  fvm dart run tool/swap_one_click_probe.dart \\
    --direction zec-to-external \\
    --asset USDC \\
    --amount 0.01 \\
    --destination 0xRecipientAddress \\
    --refund t1RefundAddress

  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  fvm dart run tool/swap_one_click_probe.dart \\
    --direction external-to-zec \\
    --asset USDC \\
    --amount 10 \\
    --destination t1WalletStagingAddress \\
    --refund 0xRefundAddress

  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  fvm dart run tool/swap_one_click_probe.dart \\
    --status-deposit 0xDepositAddress \\
    --status-memo memo-if-required

Options:
  --tokens-only                 Only call /v0/tokens.
  --base-url <url>              Defaults to ZCASH_SWAP_1CLICK_BASE_URL or production.
  --jwt <token>                 Defaults to ZCASH_SWAP_1CLICK_JWT.
                                Required for quote/status validation.
  --referral <value>            Defaults to ZCASH_SWAP_1CLICK_REFERRAL.
  --dry-run <true|false>        Defaults to true. Set false only to inspect a
                                real quote/deposit instruction without sending funds.
  --direction <value>           zec-to-external or external-to-zec.
  --asset <symbol>              USDC, ETH, BTC, SOL, USDT, DAI, WBTC, NEAR, or DOGE.
  --asset-id <assetId>          Exact 1Click assetId from --tokens-only output.
                                Mutually exclusive with USDC-specific overrides.
  --usdc-chain <chain>          eth, base, arb, or near. Defaults to Ethereum
                                USDC when no explicit asset ID is supplied.
  --usdc-asset-id <assetId>     Exact 1Click assetId for USDC.
  --amount <number>             Exact input amount.
  --destination <address>       Destination recipient for the dry quote.
  --refund <address>            Origin-chain refund address for the dry quote.
  --status-deposit <address>    Also call /v0/status for this deposit address.
                                Without quote inputs, runs status-only after tokens.
  --status-memo <memo>          Optional status deposit memo.
''';
