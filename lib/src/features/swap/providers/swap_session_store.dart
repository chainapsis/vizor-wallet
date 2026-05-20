import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_prototype_models.dart';

const _swapSessionsKey = 'zcash_swap_sessions_v1';
const _swapDraftKey = 'zcash_swap_draft_v1';

String _swapSessionsKeyFor(String accountUuid) =>
    '$_swapSessionsKey:$accountUuid';

final swapSessionStoreProvider = Provider<SwapSessionStore>((ref) {
  return AppSecureStoreSwapSessionStore(AppSecureStore.instance);
});

final swapPendingIntentCountProvider = FutureProvider.family<int, String>((
  ref,
  accountUuid,
) async {
  final intents = await ref
      .read(swapSessionStoreProvider)
      .loadIntents(accountUuid: accountUuid);
  return intents.where((intent) => !intent.status.isTerminal).length;
});

abstract interface class SwapSessionStore {
  Future<List<SwapPrototypeIntent>> loadIntents({required String accountUuid});

  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  });

  Future<SwapDraftSnapshot?> loadDraft();

  Future<void> saveDraft(SwapDraftSnapshot draft);
}

class AppSecureStoreSwapSessionStore implements SwapSessionStore {
  const AppSecureStoreSwapSessionStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<List<SwapPrototypeIntent>> loadIntents({
    required String accountUuid,
  }) async {
    final raw = await _storage.readString(_swapSessionsKeyFor(accountUuid));
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>)
          _intentFromJson(item).copyWith(accountUuid: accountUuid),
    ];
  }

  @override
  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  }) async {
    await _storage.writeString(
      _swapSessionsKeyFor(accountUuid),
      jsonEncode([
        for (final intent in intents)
          _intentToJson(intent.copyWith(accountUuid: accountUuid)),
      ]),
    );
  }

  @override
  Future<SwapDraftSnapshot?> loadDraft() async {
    final raw = await _storage.readString(_swapDraftKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return _draftFromJson(decoded);
  }

  @override
  Future<void> saveDraft(SwapDraftSnapshot draft) async {
    await _storage.writeString(_swapDraftKey, jsonEncode(_draftToJson(draft)));
  }
}

Map<String, Object?> _draftToJson(SwapDraftSnapshot draft) {
  return {
    'direction': draft.direction.name,
    'externalAsset': draft.externalAsset.toPersistedJson(),
    'slippageBps': draft.slippageBps,
  };
}

SwapDraftSnapshot? _draftFromJson(Map<String, dynamic> json) {
  final direction = _optionalEnumByName(
    SwapDirection.values,
    json['direction'],
  );
  final externalAsset = SwapAsset.fromPersistedJson(json['externalAsset']);
  if (direction == null || externalAsset == null) return null;
  if (externalAsset == SwapAsset.zec) return null;
  final slippageBps = _optionalInt(json['slippageBps'])?.clamp(10, 500).toInt();
  return SwapDraftSnapshot(
    direction: direction,
    externalAsset: externalAsset,
    slippageBps: slippageBps ?? defaultSwapSlippageBps,
  );
}

Map<String, Object?> _intentToJson(SwapPrototypeIntent intent) {
  return {
    'id': intent.id,
    'title': intent.title,
    'pair': intent.pair,
    'sellAmount': intent.sellAmount,
    'receiveEstimate': intent.receiveEstimate,
    'provider': intent.provider,
    'status': intent.status.name,
    'nextAction': intent.nextAction,
    'steps': [for (final step in intent.steps) _stepToJson(step)],
    'exposure': [for (final field in intent.exposure) _fieldToJson(field)],
    'receipt': [for (final field in intent.receipt) _fieldToJson(field)],
    'direction': intent.direction?.name,
    'externalAsset': intent.externalAsset?.toPersistedJson(),
    'depositAddress': intent.depositAddress,
    'depositMemo': intent.depositMemo,
    'depositTxHash': intent.depositTxHash,
    'providerQuoteId': intent.providerQuoteId,
    'providerSignature': intent.providerSignature,
    'providerStatusRaw': intent.providerStatusRaw,
    'nearIntentHash': intent.nearIntentHash,
    'nearTransactionHash': intent.nearTransactionHash,
    'originChainTxHash': intent.originChainTxHash,
    'destinationChainTxHash': intent.destinationChainTxHash,
    'providerRefundInfo': _providerRefundInfoToJson(intent.providerRefundInfo),
    'lastStatusCheckedAt': intent.lastStatusCheckedAt
        ?.toUtc()
        .toIso8601String(),
    'statusError': intent.statusError,
    'oneClickRecipient': intent.oneClickRecipient,
    'oneClickRefundTo': intent.oneClickRefundTo,
    'depositDeadline': intent.depositDeadline?.toUtc().toIso8601String(),
    'accountUuid': intent.accountUuid,
  };
}

SwapPrototypeIntent _intentFromJson(Map<String, dynamic> json) {
  return SwapPrototypeIntent(
    id: _string(json['id']),
    title: _string(json['title']),
    pair: _string(json['pair']),
    sellAmount: _string(json['sellAmount']),
    receiveEstimate: _string(json['receiveEstimate']),
    provider: _string(json['provider']),
    status: _enumByName(
      SwapIntentStatus.values,
      json['status'],
      SwapIntentStatus.processing,
    ),
    nextAction: _string(json['nextAction']),
    steps: _stepsFromJson(json['steps']),
    exposure: _fieldsFromJson(json['exposure']),
    receipt: _fieldsFromJson(json['receipt']),
    direction: _optionalEnumByName(SwapDirection.values, json['direction']),
    externalAsset: SwapAsset.fromPersistedJson(json['externalAsset']),
    depositAddress: _optionalString(json['depositAddress']),
    depositMemo: _optionalString(json['depositMemo']),
    depositTxHash: _optionalString(json['depositTxHash']),
    providerQuoteId: _optionalString(json['providerQuoteId']),
    providerSignature: _optionalString(json['providerSignature']),
    providerStatusRaw: _optionalString(json['providerStatusRaw']),
    nearIntentHash: _optionalString(json['nearIntentHash']),
    nearTransactionHash: _optionalString(json['nearTransactionHash']),
    originChainTxHash: _optionalString(json['originChainTxHash']),
    destinationChainTxHash: _optionalString(json['destinationChainTxHash']),
    providerRefundInfo: _providerRefundInfoFromJson(json['providerRefundInfo']),
    lastStatusCheckedAt: _optionalDateTime(json['lastStatusCheckedAt']),
    statusError: _optionalString(json['statusError']),
    oneClickRecipient: _optionalString(json['oneClickRecipient']),
    oneClickRefundTo: _optionalString(json['oneClickRefundTo']),
    depositDeadline: _optionalDateTime(json['depositDeadline']),
    accountUuid: _optionalString(json['accountUuid']),
  );
}

Map<String, Object?>? _providerRefundInfoToJson(SwapProviderRefundInfo? info) {
  if (info == null || !info.hasAny) return null;
  return {
    'minimumDepositText': info.minimumDepositText,
    'refundFeeText': info.refundFeeText,
    'depositedAmountText': info.depositedAmountText,
    'refundedAmountText': info.refundedAmountText,
    'refundReason': info.refundReason,
  };
}

SwapProviderRefundInfo? _providerRefundInfoFromJson(Object? value) {
  if (value is! Map) return null;
  final info = SwapProviderRefundInfo(
    minimumDepositText: _optionalString(value['minimumDepositText']),
    refundFeeText: _optionalString(value['refundFeeText']),
    depositedAmountText: _optionalString(value['depositedAmountText']),
    refundedAmountText: _optionalString(value['refundedAmountText']),
    refundReason: _optionalString(value['refundReason']),
  );
  return info.hasAny ? info : null;
}

Map<String, Object?> _stepToJson(SwapPrototypeStep step) {
  return {
    'label': step.label,
    'state': step.state.name,
    'evidence': step.evidence,
  };
}

List<SwapPrototypeStep> _stepsFromJson(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        SwapPrototypeStep(
          label: _string(item['label']),
          state: _enumByName(
            SwapPrototypeStepState.values,
            item['state'],
            SwapPrototypeStepState.pending,
          ),
          evidence: _string(item['evidence']),
        ),
  ];
}

Map<String, Object?> _fieldToJson(SwapPrototypeField field) {
  return {'label': field.label, 'value': field.value};
}

List<SwapPrototypeField> _fieldsFromJson(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        SwapPrototypeField(
          label: _string(item['label']),
          value: _string(item['value']),
        ),
  ];
}

String _string(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) => value is String ? value : null;

DateTime? _optionalDateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  final parsed = _optionalEnumByName(values, name);
  return parsed ?? fallback;
}

T? _optionalEnumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
