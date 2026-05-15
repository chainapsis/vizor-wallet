import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';

import '../../tool/swap_one_click_probe.dart';

void main() {
  test('live validation wrapper help documents required env', () async {
    final result = await Process.run(
      'scripts/e2e/swap-one-click-live-validation.sh',
      const ['--help'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('ZCASH_SWAP_1CLICK_JWT'));
    expect(result.stdout, contains('ZCASH_SWAP_PROBE_AMOUNT'));
    expect(result.stdout, contains('ZCASH_SWAP_PROBE_ASSET_ID'));
    expect(result.stdout, contains('ZCASH_SWAP_PROBE_DRY_RUN'));
    expect(result.stdout, contains('ZCASH_SWAP_PROBE_STATUS_DEPOSIT'));
    expect(result.stdout, contains('--tokens-only'));
    expect(result.stdout, contains("printf 'ZCASH_SWAP_1CLICK_JWT: '"));
    expect(result.stdout, contains('read -r -s ZCASH_SWAP_1CLICK_JWT'));
    expect(result.stdout, isNot(contains('ZCASH_SWAP_1CLICK_JWT=<jwt>')));
  });

  test(
    'live validation wrapper rejects unexpected args before validation',
    () async {
      final result = await Process.run(
        'scripts/e2e/swap-one-click-live-validation.sh',
        const ['unexpected'],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('unexpected arguments: unexpected'));
      expect(result.stderr, contains('ZCASH_SWAP_1CLICK_JWT'));
    },
  );

  test(
    'live validation wrapper reports missing JWT before fvm setup',
    () async {
      final result = await Process.run(
        'scripts/e2e/swap-one-click-live-validation.sh',
        const [],
        environment: const {'PATH': '/usr/bin:/bin'},
        includeParentEnvironment: false,
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Set ZCASH_SWAP_1CLICK_JWT.'));
      expect(result.stderr, contains("printf 'ZCASH_SWAP_1CLICK_JWT: '"));
      expect(result.stderr, contains('read -r -s ZCASH_SWAP_1CLICK_JWT'));
      expect(
        result.stderr,
        contains('Then rerun scripts/e2e/swap-one-click-live-validation.sh.'),
      );
      expect(result.stderr, isNot(contains('missing required command: fvm')));
    },
  );

  test('live validation wrapper token mode skips JWT requirement', () async {
    final result = await Process.run(
      'scripts/e2e/swap-one-click-live-validation.sh',
      const ['--tokens-only'],
      environment: const {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('missing required command: fvm'));
    expect(result.stderr, isNot(contains('Set ZCASH_SWAP_1CLICK_JWT.')));
  });

  test('live app wrapper forwards shell JWT as a dart define', () async {
    final result = await Process.run(
      'scripts/e2e/swap-one-click-live-app.sh',
      const ['--help'],
    );

    expect(result.exitCode, 0);
    expect(result.stdout, contains('fvm flutter run'));
    expect(result.stdout, contains('String.fromEnvironment'));
    expect(result.stdout, contains('ZCASH_SWAP_1CLICK_JWT'));
    expect(result.stdout, contains('ZCASH_SWAP_ENABLE_LIVE_FUNDS=false'));
    expect(result.stdout, contains('swap-one-click-live-app.sh -d macos'));
  });

  test('live app wrapper reports missing JWT before fvm setup', () async {
    final result = await Process.run(
      'scripts/e2e/swap-one-click-live-app.sh',
      const ['-d', 'macos'],
      environment: const {'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Set ZCASH_SWAP_1CLICK_JWT.'));
    expect(result.stderr, contains("printf 'ZCASH_SWAP_1CLICK_JWT: '"));
    expect(result.stderr, contains('read -r -s ZCASH_SWAP_1CLICK_JWT'));
    expect(
      result.stderr,
      contains('Then rerun scripts/e2e/swap-one-click-live-app.sh.'),
    );
    expect(result.stderr, isNot(contains('missing required command: fvm')));
  });

  test('default probe mode still requires dry quote inputs', () {
    expect(
      () => OneClickProbeOptions.parse(const []),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Provide --amount'),
        ),
      ),
    );
  });

  test('status-only mode does not require dry quote inputs', () {
    final options = OneClickProbeOptions.parse(const [
      '--status-deposit',
      'deposit-1',
      '--status-memo',
      'memo-1',
      '--jwt',
      'test-jwt',
    ]);

    expect(options.tokensOnly, isFalse);
    expect(options.quoteRequested, isFalse);
    expect(options.statusDeposit, 'deposit-1');
    expect(options.statusMemo, 'memo-1');
  });

  test('status probe can be combined with a dry quote', () {
    final options = OneClickProbeOptions.parse(const [
      '--status-deposit',
      'deposit-1',
      '--amount',
      '0.25',
      '--destination',
      '0xrecipient',
      '--refund',
      't1refund',
      '--jwt',
      'test-jwt',
    ]);

    expect(options.quoteRequested, isTrue);
    expect(options.dryRun, isTrue);
    expect(options.statusDeposit, 'deposit-1');
    expect(options.amount, 0.25);
  });

  test('quote probe can request a non-dry quote without changing defaults', () {
    final dryOptions = OneClickProbeOptions.parse(const [
      '--direction',
      'external-to-zec',
      '--amount',
      '10',
      '--destination',
      't1recipient',
      '--refund',
      '0xrefund',
      '--jwt',
      'test-jwt',
    ]);
    final liveOptions = OneClickProbeOptions.parse(const [
      '--direction',
      'external-to-zec',
      '--amount',
      '10',
      '--destination',
      't1recipient',
      '--refund',
      '0xrefund',
      '--dry-run',
      'false',
      '--jwt',
      'test-jwt',
    ]);

    expect(dryOptions.dryRun, isTrue);
    expect(liveOptions.dryRun, isFalse);
  });

  test('quote probe rejects unknown dry-run values', () {
    expect(
      () => OneClickProbeOptions.parse(const [
        '--direction',
        'external-to-zec',
        '--amount',
        '10',
        '--destination',
        't1recipient',
        '--refund',
        '0xrefund',
        '--dry-run',
        'maybe',
        '--jwt',
        'test-jwt',
      ]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Unsupported --dry-run'),
        ),
      ),
    );
  });

  test('tokens-only remains tokens-only even with status arguments', () {
    final options = OneClickProbeOptions.parse(const [
      '--tokens-only',
      '--status-deposit',
      'deposit-1',
    ]);

    expect(options.tokensOnly, isTrue);
    expect(options.quoteRequested, isFalse);
    expect(options.statusDeposit, 'deposit-1');
  });

  test('receive-zec alias parses as external-to-zec', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'receive-zec',
      '--amount',
      '140.35',
      '--destination',
      't1staging',
      '--refund',
      '0xrefund',
      '--jwt',
      'test-jwt',
    ]);

    expect(options.direction, SwapDirection.externalToZec);
    expect(options.asset, SwapAsset.usdc);
  });

  test('probe asset parser accepts expanded external symbols', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'zec-to-external',
      '--asset',
      'BTC',
      '--amount',
      '0.25',
      '--destination',
      'bc1recipient',
      '--refund',
      't1refund',
      '--jwt',
      'test-jwt',
    ]);

    expect(options.asset, SwapAsset.btc);
  });

  test('USDC chain override maps to exact 1Click asset id', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'zec-to-external',
      '--amount',
      '0.25',
      '--destination',
      '0xrecipient',
      '--refund',
      't1refund',
      '--usdc-chain',
      'base',
      '--jwt',
      'test-jwt',
    ]);

    expect(
      options.assetIdOverrides[SwapAsset.usdc],
      'nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near',
    );
  });

  test('USDC direct asset id override wins when no chain is provided', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'zec-to-external',
      '--amount',
      '0.25',
      '--destination',
      '0xrecipient',
      '--refund',
      't1refund',
      '--usdc-asset-id',
      'nep141:custom-usdc',
      '--jwt',
      'test-jwt',
    ]);

    expect(options.assetIdOverrides[SwapAsset.usdc], 'nep141:custom-usdc');
  });

  test('exact asset id resolves against the live token list', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'zec-to-external',
      '--asset-id',
      'nep141:base-usdc.example',
      '--amount',
      '0.25',
      '--destination',
      '0xrecipient',
      '--refund',
      't1refund',
      '--jwt',
      'test-jwt',
    ]);
    final baseUsdc = SwapAsset.live(
      assetId: 'nep141:base-usdc.example',
      symbol: 'USDC',
      blockchain: 'base',
      decimals: 6,
    );

    expect(options.assetId, 'nep141:base-usdc.example');
    expect(options.resolveAsset([SwapAsset.usdc, baseUsdc]), baseUsdc);
  });

  test('exact asset id rejects missing token-list entries', () {
    final options = OneClickProbeOptions.parse(const [
      '--direction',
      'zec-to-external',
      '--asset-id',
      'nep141:missing.example',
      '--amount',
      '0.25',
      '--destination',
      '0xrecipient',
      '--refund',
      't1refund',
      '--jwt',
      'test-jwt',
    ]);

    expect(
      () => options.resolveAsset(const [SwapAsset.usdc]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('does not include asset id nep141:missing.example'),
        ),
      ),
    );
  });

  test('USDC chain and direct asset id are mutually exclusive', () {
    expect(
      () => OneClickProbeOptions.parse(const [
        '--direction',
        'zec-to-external',
        '--amount',
        '0.25',
        '--destination',
        '0xrecipient',
        '--refund',
        't1refund',
        '--usdc-chain',
        'base',
        '--usdc-asset-id',
        'nep141:custom-usdc',
        '--jwt',
        'test-jwt',
      ]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Use either --usdc-asset-id or --usdc-chain'),
        ),
      ),
    );
  });

  test('generic exact asset id and USDC overrides are mutually exclusive', () {
    expect(
      () => OneClickProbeOptions.parse(const [
        '--direction',
        'zec-to-external',
        '--amount',
        '0.25',
        '--destination',
        '0xrecipient',
        '--refund',
        't1refund',
        '--asset-id',
        'nep141:base-usdc.example',
        '--usdc-chain',
        'base',
        '--jwt',
        'test-jwt',
      ]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Use either --asset-id or a USDC-specific override'),
        ),
      ),
    );
  });

  test('dry quote validation requires a JWT', () {
    expect(
      () => OneClickProbeOptions.parse(const [
        '--amount',
        '0.25',
        '--destination',
        '0xrecipient',
        '--refund',
        't1refund',
        '--jwt',
        '',
      ]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Provide --jwt or ZCASH_SWAP_1CLICK_JWT'),
        ),
      ),
    );
  });

  test('status validation requires a JWT', () {
    expect(
      () => OneClickProbeOptions.parse(const [
        '--status-deposit',
        'deposit-1',
        '--jwt',
        '',
      ]),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'message',
          contains('Provide --jwt or ZCASH_SWAP_1CLICK_JWT'),
        ),
      ),
    );
  });
}
