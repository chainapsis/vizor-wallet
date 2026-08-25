import 'dart:convert';
import 'dart:typed_data';

import '../../../core/private_state_sync/private_state_models.dart';
import '../models/swap_models.dart';

const swapPrivateHistorySchemaVersion = 1;
const maxSwapPrivateHistoryPlaintextBytes = 192 * 1024;
const _maxHistoryRecords = 512;
const _maxHistoryTombstones = 2048;
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
    Map<String, DateTime> tombstones = const {},
    this.truncated = false,
  }) : records = List.unmodifiable(records),
       tombstones = Map.unmodifiable(tombstones) {
    _validateRecords();
  }

  final SwapPrivateHistoryKind kind;
  final List<SwapIntentRecord> records;
  final Map<String, DateTime> tombstones;
  final bool truncated;

  Uint8List encode() {
    final sorted = List<SwapIntentRecord>.of(records)
      ..sort(_compareCanonicalRecords);
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': swapPrivateHistorySchemaVersion,
          'kind': kind.wireName,
          'truncated': truncated,
          'records': [for (final record in sorted) _recordToJson(record)],
          'tombstones': [
            for (final entry
                in tombstones.entries.toList()
                  ..sort((left, right) => left.key.compareTo(right.key)))
              {'id': entry.key, 'deleted_at': _date(entry.value)},
          ],
        }),
      ),
    );
    if (bytes.length > maxSwapPrivateHistoryPlaintextBytes) {
      throw const PrivateStateProtocolException(
        'Swap history plaintext exceeds the recovery object limit.',
      );
    }
    return bytes;
  }

  /// Builds a deterministic recovery snapshot. Open records and records with
  /// deposit evidence are never compacted; oldest evidence-free terminal
  /// records are omitted first when the object reaches its byte budget.
  static SwapPrivateHistoryDocument compact({
    required SwapPrivateHistoryKind kind,
    required Iterable<SwapIntentRecord> records,
    Map<String, DateTime> tombstones = const {},
  }) {
    final scoped = [
      for (final record in records)
        if (record.payMode == kind.payMode) record,
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
      final full = SwapPrivateHistoryDocument(
        kind: kind,
        records: scoped,
        tombstones: tombstones,
      );
      try {
        full.encode();
        return full;
      } on PrivateStateProtocolException {
        // Continue with deterministic compaction below.
      }
    }

    final mandatory = <SwapIntentRecord>[];
    final optional = <SwapIntentRecord>[];
    for (final record in scoped) {
      if (!record.status.isTerminal || _hasDepositEvidence(record)) {
        mandatory.add(record);
      } else {
        optional.add(record);
      }
    }
    optional.sort((left, right) {
      final byTime = _recordTimestamp(right).compareTo(_recordTimestamp(left));
      return byTime != 0 ? byTime : _compareCanonicalRecords(left, right);
    });

    final selected = List<SwapIntentRecord>.of(mandatory);
    final requiredOnly = SwapPrivateHistoryDocument(
      kind: kind,
      records: selected,
      tombstones: tombstones,
      truncated: true,
    );
    requiredOnly.encode();
    for (final candidate in optional) {
      final next = [...selected, candidate];
      try {
        SwapPrivateHistoryDocument(
          kind: kind,
          records: next,
          tombstones: tombstones,
          truncated: true,
        ).encode();
        selected.add(candidate);
      } on PrivateStateProtocolException {
        break;
      }
    }
    return SwapPrivateHistoryDocument(
      kind: kind,
      records: selected,
      tombstones: tombstones,
      truncated: selected.length != scoped.length,
    );
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
    if (decoded is! Map<String, dynamic> ||
        (decoded.length != 4 && decoded.length != 5) ||
        decoded.keys.any(
          (key) => !const {
            'schema',
            'kind',
            'truncated',
            'records',
            'tombstones',
          }.contains(key),
        ) ||
        decoded['schema'] != swapPrivateHistorySchemaVersion ||
        decoded['kind'] != expectedKind.wireName ||
        decoded['truncated'] is! bool) {
      throw const PrivateStateProtocolException(
        'Swap history document has an invalid schema.',
      );
    }
    final rawRecords = decoded['records'];
    if (rawRecords is! List || rawRecords.length > _maxHistoryRecords) {
      throw const PrivateStateProtocolException(
        'Swap history record count is invalid.',
      );
    }
    final records = <SwapIntentRecord>[];
    final identities = <String>{};
    for (final raw in rawRecords) {
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
    final tombstones = <String, DateTime>{};
    final rawTombstones = decoded['tombstones'];
    if (rawTombstones != null) {
      if (rawTombstones is! List ||
          rawTombstones.length > _maxHistoryTombstones) {
        throw const PrivateStateProtocolException(
          'Swap history tombstone count is invalid.',
        );
      }
      for (final raw in rawTombstones) {
        if (raw is! Map<String, dynamic> ||
            raw.length != 2 ||
            !raw.containsKey('id') ||
            !raw.containsKey('deleted_at')) {
          throw const PrivateStateProtocolException(
            'Swap history tombstone has an invalid shape.',
          );
        }
        final id = _requiredText(raw['id'], 'tombstone ID');
        if (tombstones.containsKey(id) || identities.contains(id)) {
          throw const PrivateStateProtocolException(
            'Swap history tombstone identity is duplicated or still live.',
          );
        }
        tombstones[id] = _requiredDate(raw['deleted_at']);
      }
    }
    return SwapPrivateHistoryDocument(
      kind: expectedKind,
      records: records,
      tombstones: tombstones,
      truncated: decoded['truncated'] as bool,
    );
  }

  void _validateRecords() {
    if (records.length > _maxHistoryRecords) {
      throw const PrivateStateProtocolException(
        'Swap history record count exceeds the limit.',
      );
    }
    if (tombstones.length > _maxHistoryTombstones) {
      throw const PrivateStateProtocolException(
        'Swap history tombstone count exceeds the limit.',
      );
    }
    final identities = <String>{};
    for (final record in records) {
      if (record.payMode != kind.payMode ||
          !identities.add(_recordIdentity(record))) {
        throw const PrivateStateProtocolException(
          'Swap history record namespace or identity is invalid.',
        );
      }
      // Run through the encoder's length checks before encryption.
      _recordToJson(record);
    }
    for (final entry in tombstones.entries) {
      final id = entry.key.trim();
      if (id.isEmpty ||
          utf8.encode(id).length > _maxShortTextBytes ||
          identities.contains(id) ||
          id != entry.key) {
        throw const PrivateStateProtocolException(
          'Swap history tombstone identity is invalid or still live.',
        );
      }
      _date(entry.value);
    }
  }
}

SwapIntentRecord mergeSwapPrivateHistoryRecord(
  SwapIntentRecord local,
  SwapIntentRecord remote,
) {
  if (_recordIdentity(local) != _recordIdentity(remote) ||
      local.payMode != remote.payMode) {
    throw const PrivateStateProtocolException(
      'Cannot merge different swap history identities.',
    );
  }
  _requireCompatible('provider', local.providerLabel, remote.providerLabel);
  _requireCompatible(
    'direction',
    local.direction?.name,
    remote.direction?.name,
  );
  _requireCompatible(
    'external asset',
    _assetIdentity(local.externalAsset),
    _assetIdentity(remote.externalAsset),
  );
  _requireCompatible('pair', local.pairText, remote.pairText);
  _requireCompatible(
    'sell amount',
    local.sellAmountBaseUnits?.toString() ?? local.sellAmountText,
    remote.sellAmountBaseUnits?.toString() ?? remote.sellAmountText,
  );
  _requireCompatible(
    'deposit address',
    local.depositAddress,
    remote.depositAddress,
  );
  _requireCompatible('deposit memo', local.depositMemo, remote.depositMemo);
  _requireCompatible(
    'provider quote',
    local.providerQuoteId,
    remote.providerQuoteId,
  );
  _requireCompatible(
    'deposit transaction',
    local.depositTxHash,
    remote.depositTxHash,
  );
  _requireCompatible(
    'origin transaction',
    local.originChainTxHash,
    remote.originChainTxHash,
  );
  _requireCompatible(
    'destination transaction',
    local.destinationChainTxHash,
    remote.destinationChainTxHash,
  );
  _requireCompatible(
    'NEAR intent',
    local.nearIntentHash,
    remote.nearIntentHash,
  );
  _requireCompatible(
    'recipient',
    local.oneClickRecipient,
    remote.oneClickRecipient,
  );
  _requireCompatible(
    'refund address',
    local.oneClickRefundTo,
    remote.oneClickRefundTo,
  );
  _requireCompatible(
    'deposit deadline',
    _date(local.depositDeadline),
    _date(remote.depositDeadline),
  );

  if (local.status != remote.status &&
      _isStrongTerminal(local.status) &&
      _isStrongTerminal(remote.status)) {
    throw const PrivateStateProtocolException(
      'Swap history has contradictory terminal provider states.',
    );
  }
  final preferred = _compareRecordEvidence(local, remote) >= 0 ? local : remote;
  final other = identical(preferred, local) ? remote : local;
  final mergedRefund =
      other.providerRefundInfo?.merge(preferred.providerRefundInfo) ??
      preferred.providerRefundInfo;
  final mergedFiat = _newerFiat(local.fiatValueBasis, remote.fiatValueBasis);

  return preferred.copyWith(
    pairText: _preferText(preferred.pairText, other.pairText),
    sellAmountText: _preferText(preferred.sellAmountText, other.sellAmountText),
    receiveEstimateText: _preferText(
      preferred.receiveEstimateText,
      other.receiveEstimateText,
    ),
    sellAmountBaseUnits:
        preferred.sellAmountBaseUnits ?? other.sellAmountBaseUnits,
    direction: preferred.direction ?? other.direction,
    externalAsset: preferred.externalAsset ?? other.externalAsset,
    depositAddress: preferred.depositAddress ?? other.depositAddress,
    depositMemo: preferred.depositMemo ?? other.depositMemo,
    depositTxHash: preferred.depositTxHash ?? other.depositTxHash,
    providerQuoteId: preferred.providerQuoteId ?? other.providerQuoteId,
    swapFeeText: preferred.swapFeeText ?? other.swapFeeText,
    totalFeesText: preferred.totalFeesText ?? other.totalFeesText,
    realisedSlippageText:
        preferred.realisedSlippageText ?? other.realisedSlippageText,
    slippageToleranceText:
        preferred.slippageToleranceText ?? other.slippageToleranceText,
    minimumReceiveText:
        preferred.minimumReceiveText ?? other.minimumReceiveText,
    providerStatusRaw: preferred.providerStatusRaw ?? other.providerStatusRaw,
    nearIntentHash: preferred.nearIntentHash ?? other.nearIntentHash,
    originChainTxHash: preferred.originChainTxHash ?? other.originChainTxHash,
    destinationChainTxHash:
        preferred.destinationChainTxHash ?? other.destinationChainTxHash,
    providerRefundInfo: mergedRefund,
    fiatValueBasis: mergedFiat,
    lastStatusCheckedAt: _later(
      local.lastStatusCheckedAt,
      remote.lastStatusCheckedAt,
    ),
    statusError: local.statusError,
    broadcastNotice: local.broadcastNotice,
    broadcastStatus: preferred.broadcastStatus ?? other.broadcastStatus,
    oneClickRecipient: preferred.oneClickRecipient ?? other.oneClickRecipient,
    oneClickRefundTo: preferred.oneClickRefundTo ?? other.oneClickRefundTo,
    userExternalContactId: local.userExternalContactId,
    depositDeadline: _later(local.depositDeadline, remote.depositDeadline),
    accountUuid: local.accountUuid,
    createdAt: _earlier(local.createdAt, remote.createdAt),
    updatedAt: _later(local.updatedAt, remote.updatedAt),
    completedAt: _later(local.completedAt, remote.completedAt),
    depositClaimedAt: _later(local.depositClaimedAt, remote.depositClaimedAt),
  );
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
  const allowed = {
    'id',
    'provider',
    'pair',
    'sell_amount',
    'receive_estimate',
    'status',
    'next_action',
    'sell_amount_base_units',
    'direction',
    'external_asset',
    'deposit_address',
    'deposit_memo',
    'deposit_tx_hash',
    'provider_quote_id',
    'swap_fee',
    'total_fees',
    'realised_slippage',
    'slippage_tolerance',
    'minimum_receive',
    'provider_status_raw',
    'near_intent_hash',
    'origin_chain_tx_hash',
    'destination_chain_tx_hash',
    'provider_refund',
    'fiat_basis',
    'last_status_checked_at',
    'broadcast_status',
    'recipient',
    'refund_to',
    'deposit_deadline',
    'created_at',
    'updated_at',
    'completed_at',
    'deposit_claimed_at',
  };
  if (json.length != allowed.length ||
      json.keys.any((key) => !allowed.contains(key))) {
    throw const PrivateStateProtocolException(
      'Swap history record has unknown or missing fields.',
    );
  }
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
  if (raw is! Map<String, dynamic> || raw.length != 5) {
    throw const PrivateStateProtocolException('Invalid provider refund data.');
  }
  const keys = {
    'minimum_deposit',
    'refund_fee',
    'deposited_amount',
    'refunded_amount',
    'refund_reason',
  };
  if (raw.keys.any((key) => !keys.contains(key))) {
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
  if (raw is! Map<String, dynamic> || raw.length != 3) {
    throw const PrivateStateProtocolException('Invalid fiat basis data.');
  }
  const keys = {'sell_usd_unit_price', 'receive_usd_unit_price', 'captured_at'};
  if (raw.keys.any((key) => !keys.contains(key))) {
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

bool _hasDepositEvidence(SwapIntentRecord record) =>
    swapHasProviderObservedDepositEvidence(
      status: record.status,
      originChainTxHash: record.originChainTxHash,
      depositedAmountText: record.providerRefundInfo?.depositedAmountText,
    ) ||
    swapHasConfirmedDepositEvidence(
      originChainTxHash: record.originChainTxHash,
      depositTxHash: record.depositTxHash,
      broadcastStatus: record.broadcastStatus,
    );

int _compareRecordEvidence(SwapIntentRecord left, SwapIntentRecord right) {
  final score = _statusScore(left).compareTo(_statusScore(right));
  if (score != 0) return score;
  return _recordTimestamp(left).compareTo(_recordTimestamp(right));
}

int _statusScore(SwapIntentRecord record) {
  final evidenceBonus = _hasDepositEvidence(record) ? 40 : 0;
  return evidenceBonus +
      switch (record.status) {
        SwapIntentStatus.complete => 100,
        SwapIntentStatus.refunded => 95,
        SwapIntentStatus.processing => 80,
        SwapIntentStatus.incompleteDeposit => 75,
        SwapIntentStatus.depositObserved => 70,
        SwapIntentStatus.providerStatusUnknown => 50,
        SwapIntentStatus.awaitingDeposit ||
        SwapIntentStatus.awaitingExternalDeposit => 20,
        SwapIntentStatus.expired || SwapIntentStatus.failed => 10,
      };
}

bool _isStrongTerminal(SwapIntentStatus status) =>
    status == SwapIntentStatus.complete || status == SwapIntentStatus.refunded;

void _requireCompatible(String field, String? left, String? right) {
  final a = left?.trim();
  final b = right?.trim();
  if (a != null && a.isNotEmpty && b != null && b.isNotEmpty && a != b) {
    throw PrivateStateProtocolException(
      'Swap history has contradictory $field evidence.',
    );
  }
}

String? _assetIdentity(SwapAsset? asset) =>
    asset == null ? null : jsonEncode(asset.toPersistedJson());

String _preferText(String preferred, String other) =>
    preferred.trim().isNotEmpty ? preferred : other;

SwapFiatValueBasis? _newerFiat(
  SwapFiatValueBasis? left,
  SwapFiatValueBasis? right,
) {
  if (left == null) return right;
  if (right == null) return left;
  return left.capturedAt.isAfter(right.capturedAt) ? left : right;
}

DateTime? _later(DateTime? left, DateTime? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left.isAfter(right) ? left : right;
}

DateTime? _earlier(DateTime? left, DateTime? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left.isBefore(right) ? left : right;
}

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
