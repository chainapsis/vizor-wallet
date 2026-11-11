// l10n-ignore-file: identifier, not copy
/// Advisory status only. These records must never gate quote or payment work.
class NearIntentsServiceIssue {
  const NearIntentsServiceIssue({
    required this.chains,
    this.id,
    this.direction = '*',
    this.startsAt,
    this.finishesAt,
    this.active = true,
  });

  final Set<String> chains;
  final String? id;
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

  /// Stable across polling, ETA edits, failures and recovery. Incident IDs
  /// distinguish separate outages on the same chain; schedules without IDs
  /// use their start, scope and direction rather than their mutable end time.
  String get noticeKey {
    final scope = (chains.toList()..sort()).join(',');
    return '${isMaintenance ? 'maintenance' : 'incident'}:'
        '${id ?? startsAt?.toUtc().toIso8601String() ?? 'scope'}:$scope:$direction';
  }

  bool visibleAt(DateTime now) {
    if (!isMaintenance) return true;
    return active && !now.isBefore(startsAt!) && now.isBefore(finishesAt!);
  }
}

const nearIntentsStatusFreshness = Duration(seconds: 60);

class NearIntentsServiceNoticeData {
  const NearIntentsServiceNoticeData({required this.issues});

  final List<NearIntentsServiceIssue> issues;

  bool get maintenanceOnly => issues.every((issue) => issue.isMaintenance);
}

/// One independently validated response, with time supplied by the Vizor proxy.
class NearIntentsServiceFeed {
  const NearIntentsServiceFeed({
    required this.issues,
    required this.serverTime,
  });
  final List<NearIntentsServiceIssue> issues;
  final DateTime serverTime;
}

/// Anchors a feed to the local monotonic clock at receipt. Device wall time and
/// network round-trip estimates are deliberately absent from this calculation.
class NearIntentsServiceObservation {
  const NearIntentsServiceObservation({
    required this.feed,
    required this.receivedAt,
  });
  final NearIntentsServiceFeed feed;
  final Duration receivedAt;

  Duration ageAt(Duration elapsed) => elapsed - receivedAt;
  bool freshAt(Duration elapsed) {
    final age = ageAt(elapsed);
    return !age.isNegative && age < nearIntentsStatusFreshness;
  }

  DateTime serverTimeAt(Duration elapsed) =>
      feed.serverTime.add(ageAt(elapsed));
}

class NearIntentsServiceStatus {
  const NearIntentsServiceStatus({
    this.elapsed = Duration.zero,
    this.incidentFeed,
    this.maintenanceFeed,
  });

  final Duration elapsed;
  final NearIntentsServiceObservation? incidentFeed;
  final NearIntentsServiceObservation? maintenanceFeed;
  List<NearIntentsServiceIssue> get incidents =>
      incidentFeed?.feed.issues ?? const [];
  List<NearIntentsServiceIssue> get maintenance =>
      maintenanceFeed?.feed.issues ?? const [];

  NearIntentsServiceNoticeData? noticeFor({
    required String inputChain,
    required String outputChain,
  }) {
    final matching = <NearIntentsServiceIssue>[
      for (final observation in [incidentFeed, maintenanceFeed])
        if (observation != null && observation.freshAt(elapsed))
          for (final issue in observation.feed.issues)
            if (issue.affects(inputChain, outputChain) &&
                issue.visibleAt(observation.serverTimeAt(elapsed)))
              issue,
    ];
    if (matching.isEmpty) return null;
    matching.sort((a, b) {
      final global = (b.chains.contains('*') ? 1 : 0).compareTo(
        a.chains.contains('*') ? 1 : 0,
      );
      if (global != 0) return global;
      if (a.startsAt == null) return b.startsAt == null ? 0 : 1;
      if (b.startsAt == null) return -1;
      return a.startsAt!.compareTo(b.startsAt!);
    });
    return NearIntentsServiceNoticeData(issues: matching);
  }

  /// Re-evaluate at expiry or a maintenance boundary, without another HTTP call.
  Duration? get nextUpdateIn {
    final delays = <Duration>[
      for (final observation in [incidentFeed, maintenanceFeed])
        if (observation != null && observation.freshAt(elapsed)) ...[
          nearIntentsStatusFreshness - observation.ageAt(elapsed),
          for (final issue in observation.feed.issues)
            if (issue.isMaintenance && issue.active) ...[
              issue.startsAt!.difference(observation.serverTimeAt(elapsed)),
              issue.finishesAt!.difference(observation.serverTimeAt(elapsed)),
            ],
        ],
    ].where((delay) => delay > Duration.zero).toList()..sort();
    return delays.isEmpty ? null : delays.first;
  }
}

DateTime parseNearIntentsServerTime(String value) {
  if (!value.endsWith('Z')) {
    throw const FormatException('Expected UTC service server time');
  }
  return _timestamp(value);
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
    result.add(
      NearIntentsServiceIssue(
        chains: Set.unmodifiable({scope}),
        id: _optionalId(item['id']),
      ),
    );
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
        id: _optionalId(item['id']),
        direction: direction,
        startsAt: start,
        finishesAt: finish,
        active: status == 'active',
      ),
    );
  }
  return List.unmodifiable(result);
}

String? _optionalId(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid service issue ID');
  }
  return value.trim();
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
