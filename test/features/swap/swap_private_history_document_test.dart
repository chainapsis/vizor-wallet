import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';

void main() {
  test('round-trips recovery fields without device-local metadata', () {
    final source = _record('swap-a', status: SwapIntentStatus.complete)
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
    expect(jsonDecode(raw), isA<List<dynamic>>());
    expect(decoded.id, source.id);
    expect(decoded.status, SwapIntentStatus.complete);
    expect(decoded.depositTxHash, source.depositTxHash);
    expect(decoded.accountUuid, isNull);
    expect(decoded.userExternalContactId, isNull);
    expect(decoded.statusError, isNull);
  });

  test('rejects namespace confusion and duplicate identities', () {
    expect(
      () => SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.pay,
        records: [_record('swap-a')],
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
    expect(
      () => SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [
          _record('swap-a'),
          _record('swap-a').copyWith(providerLabel: 'Another provider'),
        ],
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('round-trips the minimal record shape', () {
    final source = _record('minimal');
    final minimal = SwapIntentRecord(
      id: source.id,
      providerLabel: source.providerLabel,
      pairText: source.pairText,
      sellAmountText: source.sellAmountText,
      receiveEstimateText: source.receiveEstimateText,
      status: source.status,
      nextAction: source.nextAction,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
    );

    final decoded = SwapPrivateHistoryDocument.decode(
      SwapPrivateHistoryDocument(
        kind: SwapPrivateHistoryKind.swap,
        records: [minimal],
      ).encode(),
      expectedKind: SwapPrivateHistoryKind.swap,
    ).records.single;

    expect(decoded.direction, isNull);
    expect(decoded.externalAsset, isNull);
    expect(decoded.depositAddress, isNull);
    expect(decoded.providerQuoteId, isNull);
  });

  test('ignores fields added by a newer Activity document version', () {
    final encoded = SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.swap,
      records: [_record('swap-a')],
    ).encode();
    final raw = jsonDecode(utf8.decode(encoded)) as List<dynamic>;
    final record = raw.single as Map<String, dynamic>;
    record['future_record_field'] = {'nested': true};
    record['provider_refund'] = {
      'minimum_deposit': null,
      'refund_fee': null,
      'deposited_amount': '1 ZEC',
      'refunded_amount': null,
      'refund_reason': null,
      'future_refund_field': 1,
    };
    record['fiat_basis'] = {
      'sell_usd_unit_price': 70,
      'receive_usd_unit_price': null,
      'captured_at': '2026-08-25T10:00:00.000Z',
      'future_fiat_field': 'ignored',
    };

    final decoded = SwapPrivateHistoryDocument.decode(
      Uint8List.fromList(utf8.encode(jsonEncode(raw))),
      expectedKind: SwapPrivateHistoryKind.swap,
    ).records.single;

    expect(decoded.id, 'swap-a');
    expect(decoded.providerRefundInfo?.depositedAmountText, '1 ZEC');
    expect(decoded.fiatValueBasis?.sellUsdUnitPrice, 70);
  });

  test('rejects timezone-less or out-of-range dates', () {
    final encoded = SwapPrivateHistoryDocument(
      kind: SwapPrivateHistoryKind.swap,
      records: [_record('swap-a')],
    ).encode();
    final raw = jsonDecode(utf8.decode(encoded)) as List<dynamic>;
    final record = raw.single as Map<String, dynamic>;
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

  test('compaction excludes non-final records and keeps newest history', () {
    final records = [
      _record(
        'open',
        status: SwapIntentStatus.processing,
      ).copyWith(providerStatusRaw: 'open-status'),
      for (var index = 0; index < 100; index++)
        _record(
          'terminal-$index',
          status: SwapIntentStatus.complete,
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

    expect(decoded.records.any((record) => record.id == 'open'), isFalse);
    expect(decoded.records.any((record) => record.id == 'terminal-99'), isTrue);
    expect(decoded.records.any((record) => record.id == 'terminal-0'), isFalse);
    expect(compacted.encode().length, lessThanOrEqualTo(192 * 1024));
  });

  test('compaction prunes history over the record cap', () {
    final compacted = SwapPrivateHistoryDocument.compact(
      kind: SwapPrivateHistoryKind.swap,
      records: [
        for (var index = 0; index < 600; index++)
          _record(
            'terminal-$index',
            status: SwapIntentStatus.complete,
            includeEvidence: false,
          ).copyWith(updatedAt: DateTime.utc(2025).add(Duration(days: index))),
      ],
    );

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
  SwapIntentStatus status = SwapIntentStatus.complete,
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
