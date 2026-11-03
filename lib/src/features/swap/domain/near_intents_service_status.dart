/// Advisory status only. These records must never gate quote or payment work.
class NearIntentsServiceIssue {
  const NearIntentsServiceIssue({
    required this.chains,
    this.direction = '*',
    this.startsAt,
    this.finishesAt,
    this.active = true,
  });

  final Set<String> chains;
  final String direction;
  final DateTime? startsAt;
  final DateTime? finishesAt;
  final bool active;

  bool get isMaintenance => startsAt != null && finishesAt != null;

  bool affects(String inputChain, String outputChain) =>
      (direction != 'withdraw' &&
          (chains.contains('*') || chains.contains(inputChain))) ||
      (direction != 'deposit' &&
          (chains.contains('*') || chains.contains(outputChain)));

  bool upcomingAt(DateTime now) =>
      isMaintenance && !active && now.isBefore(startsAt!);

  bool visibleAt(DateTime now) {
    if (!isMaintenance) return true;
    if (!now.isBefore(finishesAt!)) return false;
    return !upcomingAt(now) ||
        !startsAt!.isAfter(now.add(nearIntentsMaintenanceLeadTime));
  }
}

const nearIntentsMaintenanceLeadTime = Duration(hours: 3);
const nearIntentsStatusFreshness = Duration(seconds: 60);

class NearIntentsServiceNoticeData {
  const NearIntentsServiceNoticeData({
    required this.upcoming,
    required this.issues,
  });

  final bool upcoming;
  final List<NearIntentsServiceIssue> issues;
}

class NearIntentsServiceStatus {
  const NearIntentsServiceStatus({
    required this.now,
    this.incidents = const [],
    this.maintenance = const [],
    this.incidentsFetchedAt,
    this.maintenanceFetchedAt,
  });

  final DateTime now;
  final List<NearIntentsServiceIssue> incidents;
  final List<NearIntentsServiceIssue> maintenance;
  final DateTime? incidentsFetchedAt;
  final DateTime? maintenanceFetchedAt;

  NearIntentsServiceNoticeData? noticeFor({
    required String inputChain,
    required String outputChain,
  }) {
    bool fresh(DateTime? fetchedAt) =>
        fetchedAt != null &&
        !now.isBefore(fetchedAt) &&
        now.difference(fetchedAt) < nearIntentsStatusFreshness;
    final matching =
        [
              if (fresh(incidentsFetchedAt)) ...incidents,
              if (fresh(maintenanceFetchedAt)) ...maintenance,
            ]
            .where(
              (issue) =>
                  issue.affects(inputChain, outputChain) &&
                  issue.visibleAt(now),
            )
            .toList();
    if (matching.isEmpty) return null;
    final ongoing = matching.where((issue) => !issue.upcomingAt(now)).toList();
    final selected = ongoing.isEmpty ? matching : ongoing;
    selected.sort((a, b) {
      final global = (b.chains.contains('*') ? 1 : 0).compareTo(
        a.chains.contains('*') ? 1 : 0,
      );
      if (global != 0) return global;
      return (a.startsAt ?? now).compareTo(b.startsAt ?? now);
    });
    return NearIntentsServiceNoticeData(
      upcoming: ongoing.isEmpty,
      issues: selected,
    );
  }
}

/// The public feed is not the authenticated /incident API. Ignore history and
/// counts as an alert source; only explicitly active, recognizable scopes count.
List<NearIntentsServiceIssue> parseNearIntentsIncidents(Object? json) {
  final root = _object(json);
  final count = root['activeIncidentCount'];
  final records = root['activeIncidents'];
  if (count is! int ||
      count < 0 ||
      records is! List ||
      count != records.length) {
    throw const FormatException('Invalid active incident list');
  }
  final result = <NearIntentsServiceIssue>[];
  for (final record in records) {
    final item = _object(record);
    final status = _string(item['status']);
    final type = _string(item['scopeType']);
    final scope = _string(item['scopeValue']);
    if (status != 'active' || type != 'chain') continue;
    result.add(NearIntentsServiceIssue(chains: Set.unmodifiable({scope})));
  }
  return List.unmodifiable(result);
}

List<NearIntentsServiceIssue> parseNearIntentsMaintenance(Object? json) {
  if (json is! List) throw const FormatException('Invalid maintenance list');
  final result = <NearIntentsServiceIssue>[];
  for (final record in json) {
    final item = _object(record);
    final status = _string(item['status']);
    if (status != 'active' && status != 'scheduled') continue;
    final direction = _string(item['direction']);
    if (!const {'*', 'deposit', 'withdraw'}.contains(direction)) continue;
    final scopes = item['scopes'];
    if (scopes is! List || scopes.isEmpty) {
      throw const FormatException('Invalid maintenance scopes');
    }
    final chains = <String>{};
    for (final raw in scopes) {
      final scope = _object(raw);
      final type = _string(scope['scopeType']);
      final value = _string(scope['scopeValue']);
      if (type == 'chain') chains.add(value);
    }
    final start = _timestamp(item['startsAt']);
    final finish = _timestamp(item['finishesAt']);
    if (!finish.isAfter(start)) {
      throw const FormatException('Invalid maintenance interval');
    }
    if (chains.isEmpty) continue;
    result.add(
      NearIntentsServiceIssue(
        chains: Set.unmodifiable(chains),
        direction: direction,
        startsAt: start,
        finishesAt: finish,
        active: status == 'active',
      ),
    );
  }
  return List.unmodifiable(result);
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected status object');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected non-empty status field');
  }
  return value.trim().toLowerCase();
}

DateTime _timestamp(Object? value) {
  // Require an explicit zone and reject DateTime.parse's overflowing dates.
  if (value is! String) throw const FormatException('Expected timestamp');
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null) throw const FormatException('Expected zoned timestamp');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      parts[3] > 23 ||
      parts[4] > 59 ||
      parts[5] > 59 ||
      (match.group(8) != null && int.parse(match.group(8)!) > 23) ||
      (match.group(9) != null && int.parse(match.group(9)!) > 59)) {
    throw const FormatException('Invalid timestamp');
  }
  return DateTime.parse(value).toUtc();
}
