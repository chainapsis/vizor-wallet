import 'dart:convert';

/// Shared test-only helpers for extracting fields from tx-event JSON payloads.
///
/// The production voting flow now forwards tx events as raw JSON into Rust for
/// confirmation parsing. Multiple test suites still need to assert on specific
/// event attributes (for example `leaf_index`) before/after fake Rust calls.
/// Keeping this logic in one place avoids copy/paste parsers that can drift.
int eventIntFromTxEventsJson(
  String eventsJson,
  String eventType,
  String roundId,
  String key,
) {
  final value = eventAttributeFromTxEventsJson(eventsJson, eventType, roundId, key);
  final parsed = int.tryParse(value ?? '');
  if (parsed == null) {
    throw StateError('Missing $eventType $key.');
  }
  return parsed;
}

/// Parses `cast_vote` leaf-index payloads encoded as `"van,vc_tree_position"`.
({int vanPosition, BigInt vcTreePosition}) castVoteLeafPositionsFromTxEventsJson(
  String eventsJson,
  String roundId,
) {
  final raw = eventAttributeFromTxEventsJson(
    eventsJson,
    'cast_vote',
    roundId,
    'leaf_index',
  );
  if (raw == null) {
    throw StateError('Missing cast_vote leaf_index.');
  }
  final parts = raw.split(',');
  if (parts.length != 2) {
    throw StateError('Malformed cast_vote leaf_index: $raw');
  }
  final vanPosition = int.tryParse(parts[0].trim());
  final vcTreePosition = BigInt.tryParse(parts[1].trim());
  if (vanPosition == null || vcTreePosition == null) {
    throw StateError('Malformed cast_vote leaf_index: $raw');
  }
  return (vanPosition: vanPosition, vcTreePosition: vcTreePosition);
}

/// Finds one event attribute by `(eventType, roundId, key)` in tx-event JSON.
///
/// `roundId` filtering mirrors confirmation behavior where multiple event kinds
/// can appear and only the target round's attributes are meaningful.
String? eventAttributeFromTxEventsJson(
  String eventsJson,
  String eventType,
  String roundId,
  String key,
) {
  final decoded = jsonDecode(eventsJson);
  if (decoded is! List<dynamic>) return null;
  for (final event in decoded) {
    if (event is! Map<String, dynamic>) continue;
    if (event['type'] != eventType) continue;
    final eventRoundId = _eventRoundId(event);
    if (eventRoundId != roundId) continue;
    final attributes = event['attributes'];
    if (attributes is! List<dynamic>) continue;
    for (final attribute in attributes) {
      if (attribute is! Map<String, dynamic>) continue;
      if (attribute['key'] == key) return attribute['value'] as String?;
    }
  }
  return null;
}

String? _eventRoundId(Map<String, dynamic> event) {
  final attributes = event['attributes'];
  if (attributes is! List<dynamic>) return null;
  for (final attribute in attributes) {
    if (attribute is! Map<String, dynamic>) continue;
    final key = attribute['key'];
    if (key == 'vote_round_id' || key == 'round_id') {
      return attribute['value'] as String?;
    }
  }
  return null;
}
