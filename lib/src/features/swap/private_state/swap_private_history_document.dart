import 'dart:convert';
import 'dart:typed_data';

import '../../../core/private_state_sync/private_state_models.dart';
import '../models/swap_models.dart';

const maxSwapPrivateHistoryPlaintextBytes = 192 * 1024;
const _maxHistoryRecords = 512;
const _maxShortTextBytes = 512;
const _maxLongTextBytes = 4096;

enum SwapPrivateHistoryKind {
  swap('swap', false),
  pay('pay', true);

  const SwapPrivateHistoryKind(this.wireName, this.payMode);

  final String wireName;
  final bool payMode;
}

class SwapPrivateHistoryDocument {
  SwapPrivateHistoryDocument({
    required this.kind,
    required Iterable<SwapIntentRecord> records,
  }) : records = List.unmodifiable(records),
       super() {
    _validateRecords();
  }

  final SwapPrivateHistoryKind kind;
  final List<SwapIntentRecord> records;

  Uint8List encode() {
    final sorted = List<SwapIntentRecord>.of(records)
      ..sort(_compareCanonicalRecords);
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode([for (final record in sorted) _recordToJson(record)]),
      ),
    );
    if (bytes.length > maxSwapPrivateHistoryPlaintextBytes) {
      throw const PrivateStateProtocolException(
        'Swap history plaintext exceeds the recovery object limit.',
      );
    }
    return bytes;
  }

  /// Builds a deterministic bounded document containing only finalized
  /// activities. The newest records are retained when a candidate delta
  /// reaches its count or byte budget.
  static SwapPrivateHistoryDocument compact({
    required SwapPrivateHistoryKind kind,
    required Iterable<SwapIntentRecord> records,
  }) {
    final scoped = [
      for (final record in records)
        if (record.payMode == kind.payMode &&
            (record.status == SwapIntentStatus.complete ||
                record.status == SwapIntentStatus.refunded))
          record,
    ];
    final identities = <String>{};
    for (final record in scoped) {
      if (!identities.add(_recordIdentity(record))) {
        throw const PrivateStateProtocolException(
          'Swap history contains a duplicate record identity.',
        );
      }
      _recordToJson(record);
    }
    if (scoped.length <= _maxHistoryRecords) {
      final full = SwapPrivateHistoryDocument(kind: kind, records: scoped);
      try {
        full.encode();
        return full;
      } on PrivateStateProtocolException {
        // Continue with deterministic compaction below.
      }
    }

    final optional = List<SwapIntentRecord>.of(scoped);
    optional.sort((left, right) {
      final byTime = _recordTimestamp(right).compareTo(_recordTimestamp(left));
      return byTime != 0 ? byTime : _compareCanonicalRecords(left, right);
    });

    final selected = <SwapIntentRecord>[];
    for (final candidate in optional) {
      final next = [...selected, candidate];
      try {
        SwapPrivateHistoryDocument(kind: kind, records: next).encode();
        selected.add(candidate);
      } on PrivateStateProtocolException {
        break;
      }
    }
    return SwapPrivateHistoryDocument(kind: kind, records: selected);
  }

  static SwapPrivateHistoryDocument decode(
    Uint8List bytes, {
    required SwapPrivateHistoryKind expectedKind,
  }) {
    if (bytes.isEmpty || bytes.length > maxSwapPrivateHistoryPlaintextBytes) {
      throw const PrivateStateProtocolException(
        'Swap history plaintext size is invalid.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object catch (error) {
      throw PrivateStateProtocolException(
        'Swap history plaintext is not valid UTF-8 JSON: $error',
      );
    }
    if (decoded is! List || decoded.length > _maxHistoryRecords) {
      throw const PrivateStateProtocolException(
        'Swap history document has an invalid shape or record count.',
      );
    }
    final records = <SwapIntentRecord>[];
    final identities = <String>{};
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) {
        throw const PrivateStateProtocolException(
          'Swap history record has an invalid shape.',
        );
      }
      final record = _recordFromJson(raw, expectedKind: expectedKind);
      final identity = _recordIdentity(record);
      if (!identities.add(identity)) {
        throw const PrivateStateProtocolException(
          'Swap history contains a duplicate record identity.',
        );
      }
      records.add(record);
    }
    return SwapPrivateHistoryDocument(kind: expectedKind, records: records);
  }

  void _validateRecords() {
    if (records.length > _maxHistoryRecords) {
      throw const PrivateStateProtocolException(
        'Swap history record count exceeds the limit.',
      );
    }
    final identities = <String>{};
    for (final record in records) {
      if (record.payMode != kind.payMode ||
          (record.status != SwapIntentStatus.complete &&
              record.status != SwapIntentStatus.refunded) ||
          !identities.add(_recordIdentity(record))) {
        throw const PrivateStateProtocolException(
          'Swap history record namespace or identity is invalid.',
        );
      }
      // Run through the encoder's length checks before encryption.
      _recordToJson(record);
    }
  }
}

Map<String, Object?> _recordToJson(SwapIntentRecord record) {
  String requiredText(
    String name,
    String value, {
    int max = _maxShortTextBytes,
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty || utf8.encode(normalized).length > max) {
      throw PrivateStateProtocolException(
        'Swap history $name is empty or exceeds the limit.',
      );
    }
    return normalized;
  }

  String? optionalText(
    String name,
    String? value, {
    int max = _maxLongTextBytes,
  }) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (utf8.encode(normalized).length > max) {
      throw PrivateStateProtocolException(
        'Swap history $name exceeds the limit.',
      );
    }
    return normalized;
  }

  return {
    'id': requiredText('ID', record.id),
    'provider': requiredText('provider', record.providerLabel),
    'pair': requiredText('pair', record.pairText),
    'sell_amount': requiredText('sell amount', record.sellAmountText),
    'receive_estimate': requiredText(
      'receive estimate',
      record.receiveEstimateText,
    ),
    'status': record.status.name,
    'next_action': requiredText('next action', record.nextAction),
    'sell_amount_base_units': record.sellAmountBaseUnits?.toString(),
    'direction': record.direction?.name,
    'external_asset': record.externalAsset?.toPersistedJson(),
    'deposit_address': optionalText('deposit address', record.depositAddress),
    'deposit_memo': optionalText('deposit memo', record.depositMemo),
    'deposit_tx_hash': optionalText('deposit tx hash', record.depositTxHash),
    'provider_quote_id': optionalText(
      'provider quote ID',
      record.providerQuoteId,
    ),
    'swap_fee': optionalText('swap fee', record.swapFeeText),
    'total_fees': optionalText('total fees', record.totalFeesText),
    'realised_slippage': optionalText(
      'realised slippage',
      record.realisedSlippageText,
    ),
    'slippage_tolerance': optionalText(
      'slippage tolerance',
      record.slippageToleranceText,
    ),
    'minimum_receive': optionalText(
      'minimum receive',
      record.minimumReceiveText,
    ),
    'provider_status_raw': optionalText(
      'provider status',
      record.providerStatusRaw,
    ),
    'near_intent_hash': optionalText('NEAR intent hash', record.nearIntentHash),
    'origin_chain_tx_hash': optionalText(
      'origin transaction hash',
      record.originChainTxHash,
    ),
    'destination_chain_tx_hash': optionalText(
      'destination transaction hash',
      record.destinationChainTxHash,
    ),
    'provider_refund': _refundToJson(record.providerRefundInfo, optionalText),
    'fiat_basis': _fiatToJson(record.fiatValueBasis),
    'last_status_checked_at': _date(record.lastStatusCheckedAt),
    'broadcast_status': optionalText(
      'broadcast status',
      record.broadcastStatus,
    ),
    'recipient': optionalText('recipient', record.oneClickRecipient),
    'refund_to': optionalText('refund address', record.oneClickRefundTo),
    'deposit_deadline': _date(record.depositDeadline),
    'created_at': _date(record.createdAt),
    'updated_at': _date(record.updatedAt),
    'completed_at': _date(record.completedAt),
    'deposit_claimed_at': _date(record.depositClaimedAt),
  };
}

SwapIntentRecord _recordFromJson(
  Map<String, dynamic> json, {
  required SwapPrivateHistoryKind expectedKind,
}) {
  final status = _enumValue(SwapIntentStatus.values, json['status']);
  final direction = _optionalEnumValue(SwapDirection.values, json['direction']);
  final asset = SwapAsset.fromPersistedJson(json['external_asset']);
  if (status == null ||
      (json['direction'] != null && direction == null) ||
      (json['external_asset'] != null && asset == null)) {
    throw const PrivateStateProtocolException(
      'Swap history record has invalid enum or asset fields.',
    );
  }
  return SwapIntentRecord(
    id: _requiredText(json['id'], 'ID'),
    providerLabel: _requiredText(json['provider'], 'provider'),
    pairText: _requiredText(json['pair'], 'pair'),
    sellAmountText: _requiredText(json['sell_amount'], 'sell amount'),
    receiveEstimateText: _requiredText(
      json['receive_estimate'],
      'receive estimate',
    ),
    status: status,
    nextAction: _requiredText(json['next_action'], 'next action'),
    sellAmountBaseUnits: _optionalBigInt(json['sell_amount_base_units']),
    direction: direction,
    externalAsset: asset,
    depositAddress: _optionalText(json['deposit_address'], 'deposit address'),
    depositMemo: _optionalText(json['deposit_memo'], 'deposit memo'),
    depositTxHash: _optionalText(json['deposit_tx_hash'], 'deposit tx hash'),
    providerQuoteId: _optionalText(
      json['provider_quote_id'],
      'provider quote ID',
    ),
    swapFeeText: _optionalText(json['swap_fee'], 'swap fee'),
    totalFeesText: _optionalText(json['total_fees'], 'total fees'),
    realisedSlippageText: _optionalText(
      json['realised_slippage'],
      'realised slippage',
    ),
    slippageToleranceText: _optionalText(
      json['slippage_tolerance'],
      'slippage tolerance',
    ),
    minimumReceiveText: _optionalText(
      json['minimum_receive'],
      'minimum receive',
    ),
    providerStatusRaw: _optionalText(
      json['provider_status_raw'],
      'provider status',
    ),
    nearIntentHash: _optionalText(json['near_intent_hash'], 'NEAR intent hash'),
    originChainTxHash: _optionalText(
      json['origin_chain_tx_hash'],
      'origin transaction hash',
    ),
    destinationChainTxHash: _optionalText(
      json['destination_chain_tx_hash'],
      'destination transaction hash',
    ),
    providerRefundInfo: _refundFromJson(json['provider_refund']),
    fiatValueBasis: _fiatFromJson(json['fiat_basis']),
    lastStatusCheckedAt: _optionalDate(json['last_status_checked_at']),
    broadcastStatus: _optionalText(
      json['broadcast_status'],
      'broadcast status',
    ),
    oneClickRecipient: _optionalText(json['recipient'], 'recipient'),
    oneClickRefundTo: _optionalText(json['refund_to'], 'refund address'),
    depositDeadline: _optionalDate(json['deposit_deadline']),
    payMode: expectedKind.payMode,
    createdAt: _optionalDate(json['created_at']),
    updatedAt: _optionalDate(json['updated_at']),
    completedAt: _optionalDate(json['completed_at']),
    depositClaimedAt: _optionalDate(json['deposit_claimed_at']),
  );
}

Map<String, Object?>? _refundToJson(
  SwapProviderRefundInfo? info,
  String? Function(String name, String? value, {int max}) optionalText,
) {
  if (info == null || !info.hasAny) return null;
  return {
    'minimum_deposit': optionalText('minimum deposit', info.minimumDepositText),
    'refund_fee': optionalText('refund fee', info.refundFeeText),
    'deposited_amount': optionalText(
      'deposited amount',
      info.depositedAmountText,
    ),
    'refunded_amount': optionalText('refunded amount', info.refundedAmountText),
    'refund_reason': optionalText('refund reason', info.refundReason),
  };
}

SwapProviderRefundInfo? _refundFromJson(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map<String, dynamic>) {
    throw const PrivateStateProtocolException('Invalid provider refund data.');
  }
  final info = SwapProviderRefundInfo(
    minimumDepositText: _optionalText(
      raw['minimum_deposit'],
      'minimum deposit',
    ),
    refundFeeText: _optionalText(raw['refund_fee'], 'refund fee'),
    depositedAmountText: _optionalText(
      raw['deposited_amount'],
      'deposited amount',
    ),
    refundedAmountText: _optionalText(
      raw['refunded_amount'],
      'refunded amount',
    ),
    refundReason: _optionalText(raw['refund_reason'], 'refund reason'),
  );
  return info.hasAny ? info : null;
}

Map<String, Object?>? _fiatToJson(SwapFiatValueBasis? basis) {
  if (basis == null || !basis.isUsable) return null;
  for (final price in [basis.sellUsdUnitPrice, basis.receiveUsdUnitPrice]) {
    if (price != null && (!price.isFinite || price <= 0)) {
      throw const PrivateStateProtocolException(
        'Swap history fiat basis contains an invalid price.',
      );
    }
  }
  return {
    'sell_usd_unit_price': basis.sellUsdUnitPrice,
    'receive_usd_unit_price': basis.receiveUsdUnitPrice,
    'captured_at': _date(basis.capturedAt),
  };
}

SwapFiatValueBasis? _fiatFromJson(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map<String, dynamic>) {
    throw const PrivateStateProtocolException('Invalid fiat basis data.');
  }
  final basis = SwapFiatValueBasis(
    sellUsdUnitPrice: _optionalPositiveDouble(raw['sell_usd_unit_price']),
    receiveUsdUnitPrice: _optionalPositiveDouble(raw['receive_usd_unit_price']),
    capturedAt: _requiredDate(raw['captured_at']),
  );
  if (!basis.isUsable) {
    throw const PrivateStateProtocolException('Invalid fiat basis prices.');
  }
  return basis;
}

String _recordIdentity(SwapIntentRecord record) => record.id.trim();

int _compareCanonicalRecords(SwapIntentRecord left, SwapIntentRecord right) =>
    _recordIdentity(left).compareTo(_recordIdentity(right));

DateTime _recordTimestamp(SwapIntentRecord record) =>
    record.updatedAt ??
    record.createdAt ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

String? _date(DateTime? value) {
  if (value == null) return null;
  final utc = value.toUtc();
  if (utc.year < 2000 || utc.year > 2200) {
    throw const PrivateStateProtocolException('Invalid swap history date.');
  }
  return utc.toIso8601String();
}

String _requiredText(Object? raw, String field) {
  final value = _optionalText(raw, field, max: _maxShortTextBytes);
  if (value == null) {
    throw PrivateStateProtocolException('Swap history $field is required.');
  }
  return value;
}

String? _optionalText(
  Object? raw,
  String field, {
  int max = _maxLongTextBytes,
}) {
  if (raw == null) return null;
  if (raw is! String) {
    throw PrivateStateProtocolException('Swap history $field is invalid.');
  }
  final value = raw.trim();
  if (value.isEmpty || utf8.encode(value).length > max) {
    throw PrivateStateProtocolException(
      'Swap history $field is empty or exceeds the limit.',
    );
  }
  return value;
}

BigInt? _optionalBigInt(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || raw.length > 100) {
    throw const PrivateStateProtocolException('Invalid swap base-unit amount.');
  }
  final value = BigInt.tryParse(raw);
  if (value == null || value.isNegative) {
    throw const PrivateStateProtocolException('Invalid swap base-unit amount.');
  }
  return value;
}

double? _optionalPositiveDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is! num) {
    throw const PrivateStateProtocolException('Invalid fiat unit price.');
  }
  final value = raw.toDouble();
  if (!value.isFinite || value <= 0) {
    throw const PrivateStateProtocolException('Invalid fiat unit price.');
  }
  return value;
}

DateTime _requiredDate(Object? raw) {
  final value = _optionalDate(raw);
  if (value == null) {
    throw const PrivateStateProtocolException(
      'Required history date is missing.',
    );
  }
  return value;
}

DateTime? _optionalDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! String ||
      raw.length > 64 ||
      !RegExp(r'(?:[zZ]|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
    throw const PrivateStateProtocolException('Invalid swap history date.');
  }
  final value = DateTime.tryParse(raw)?.toUtc();
  if (value == null || value.year < 2000 || value.year > 2200) {
    throw const PrivateStateProtocolException('Invalid swap history date.');
  }
  return value;
}

T? _enumValue<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

T? _optionalEnumValue<T extends Enum>(List<T> values, Object? raw) {
  if (raw == null) return null;
  return _enumValue(values, raw);
}
