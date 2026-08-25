import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';

void main() {
  test('round-trips recovery fields without device-local metadata', () {
    final source = _record('swap-a', status: SwapIntentStatus.processing)
        .copyWith(
          accountUuid: 'local-account',
          userExternalContactId: 'local-contact',
          statusError: 'local network failed',
          broadcastNotice: 'local notice',
        );

    final encoded = SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.swap,
      records: [source],
    ).encode();
    final raw = utf8.decode(encoded);
    final decoded = SwapPrivateHistoryDocument.decode(
      encoded,
      expectedKind: SwapPrivateHistoryKind.swap,
    ).records.single;

    expect(raw, isNot(contains('local-account')));
    expect(raw, isNot(contains('local-contact')));
    expect(raw, isNot(contains('local network failed')));
    expect(raw, isNot(contains('local notice')));
    expect(decoded.id, source.id);
    expect(decoded.status, SwapIntentStatus.processing);
    expect(decoded.depositTxHash, source.depositTxHash);
    expect(decoded.accountUuid, isNull);
    expect(decoded.userExternalContactId, isNull);
    expect(decoded.statusError, isNull);
  });

  test('rejects namespace confusion and duplicate identities', () {
    final swapBytes = SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.swap,
      records: [_record('swap-a')],
    ).encode();

    expect(
      () => SwapPrivateHistoryDocument.decode(
        swapBytes,
        expectedKind: SwapPrivateHistoryKind.pay,
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(
      () => SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [_record('swap-a'), _record('swap-a')],
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('evidence-bearing progress defeats local deadline expiry', () {
    final local = _record('swap-a', status: SwapIntentStatus.expired).copyWith(
      accountUuid: 'account-1',
      userExternalContactId: 'contact-1',
      updatedAt: DateTime.utc(2026, 8, 25, 12),
    );
    final remote = _record('swap-a', status: SwapIntentStatus.processing)
        .copyWith(
          originChainTxHash: 'origin-tx',
          updatedAt: DateTime.utc(2026, 8, 25, 11),
        );

    final merged = mergeSwapPrivateHistoryRecord(local, remote);

    expect(merged.status, SwapIntentStatus.processing);
    expect(merged.originChainTxHash, 'origin-tx');
    expect(merged.userExternalContactId, 'contact-1');
    expect(merged.accountUuid, 'account-1');
  });

  test('rejects contradictory immutable or terminal evidence', () {
    final local = _record('swap-a', status: SwapIntentStatus.complete);

    expect(
      () => mergeSwapPrivateHistoryRecord(
        local,
        _record(
          'swap-a',
          status: SwapIntentStatus.complete,
        ).copyWith(depositTxHash: 'different-deposit-tx'),
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(
      () => mergeSwapPrivateHistoryRecord(
        local,
        _record('swap-a', status: SwapIntentStatus.refunded),
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(
      () => mergeSwapPrivateHistoryRecord(
        local,
        _record(
          'swap-a',
          status: SwapIntentStatus.complete,
        ).copyWith(sellAmountBaseUnits: BigInt.two),
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('evidence winner also owns conflicting mutable evidence metadata', () {
    final local = _record('swap-a', status: SwapIntentStatus.awaitingDeposit)
        .copyWith(
          broadcastStatus: 'pending_broadcast',
          providerRefundInfo: const SwapProviderRefundInfo(
            depositedAmountText: '0.5 ZEC',
          ),
          updatedAt: DateTime.utc(2026, 8, 25, 12),
        );
    final remote = _record('swap-a', status: SwapIntentStatus.processing)
        .copyWith(
          broadcastStatus: 'broadcasted',
          providerRefundInfo: const SwapProviderRefundInfo(
            depositedAmountText: '1 ZEC',
          ),
          updatedAt: DateTime.utc(2026, 8, 25, 11),
        );

    final merged = mergeSwapPrivateHistoryRecord(local, remote);

    expect(merged.broadcastStatus, 'broadcasted');
    expect(merged.providerRefundInfo?.depositedAmountText, '1 ZEC');
  });

  test('rejects timezone-less or out-of-range dates', () {
    final encoded = SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.swap,
      records: [_record('swap-a')],
    ).encode();
    final raw = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final records = raw['records'] as List<dynamic>;
    final record = records.single as Map<String, dynamic>;
    record['updated_at'] = '2026-08-25T12:00:00';

    expect(
      () => SwapPrivateHistoryDocument.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(raw))),
        expectedKind: SwapPrivateHistoryKind.swap,
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
    expect(
      () => SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [_record('future').copyWith(updatedAt: DateTime.utc(2300))],
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('rejects an invalid secondary fiat price before JSON encoding', () {
    expect(
      () => SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [
          _record('swap-a').copyWith(
            fiatValueBasis: SwapFiatValueBasis(
              capturedAt: DateTime.utc(2026, 8, 25),
              sellUsdUnitPrice: 70,
              receiveUsdUnitPrice: double.nan,
            ),
          ),
        ],
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('compaction keeps mandatory records and newest terminal history', () {
    final records = [
      _record(
        'open',
        status: SwapIntentStatus.processing,
      ).copyWith(providerStatusRaw: 'open-status'),
      for (var index = 0; index < 100; index++)
        _record(
          'terminal-$index',
          status: SwapIntentStatus.expired,
          includeEvidence: false,
        ).copyWith(
          providerStatusRaw: '${List.filled(3000, 'x').join()}-$index',
          updatedAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
        ),
    ];

    final compacted = SwapPrivateHistoryDocument.compact(
      kind: SwapPrivateHistoryKind.swap,
      records: records,
    );
    final decoded = SwapPrivateHistoryDocument.decode(
      compacted.encode(),
      expectedKind: SwapPrivateHistoryKind.swap,
    );

    expect(compacted.truncated, isTrue);
    expect(decoded.records.any((record) => record.id == 'open'), isTrue);
    expect(decoded.records.any((record) => record.id == 'terminal-99'), isTrue);
    expect(decoded.records.any((record) => record.id == 'terminal-0'), isFalse);
    expect(compacted.encode().length, lessThanOrEqualTo(192 * 1024));
  });

  test('compaction prunes a valid legacy history over the record cap', () {
    final compacted = SwapPrivateHistoryDocument.compact(
      kind: SwapPrivateHistoryKind.swap,
      records: [
        for (var index = 0; index < 600; index++)
          _record(
            'terminal-$index',
            status: SwapIntentStatus.expired,
            includeEvidence: false,
          ).copyWith(updatedAt: DateTime.utc(2025).add(Duration(days: index))),
      ],
    );

    expect(compacted.truncated, isTrue);
    expect(compacted.records.length, lessThanOrEqualTo(512));
    expect(
      compacted.records.any((record) => record.id == 'terminal-599'),
      isTrue,
    );
    expect(
      compacted.records.any((record) => record.id == 'terminal-0'),
      isFalse,
    );
  });
}

SwapIntentRecord _record(
  String id, {
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
  bool includeEvidence = true,
}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1 ZEC',
    receiveEstimateText: '70 USDC',
    status: status,
    nextAction: 'Checking status',
    sellAmountBaseUnits: BigInt.one,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 'deposit-$id',
    depositTxHash: includeEvidence ? 'deposit-tx-$id' : null,
    providerQuoteId: 'quote-$id',
    broadcastStatus: includeEvidence ? 'broadcasted' : null,
    payMode: false,
    createdAt: DateTime.utc(2026, 8, 25, 10),
    updatedAt: DateTime.utc(2026, 8, 25, 10),
  );
}
