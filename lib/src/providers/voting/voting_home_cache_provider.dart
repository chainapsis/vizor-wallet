import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voting/voting_file_cache.dart';
import '../../features/voting/voting_poll_ordering.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as wire;
import '../../services/voting/voting_models.dart';
import '../../services/voting/voting_participation_client.dart';
import 'voting_round_visibility_provider.dart';
import 'voting_share_tracking_registry_provider.dart';
import '../../services/voting/voting_storage_keys.dart';

export '../../services/voting/voting_storage_keys.dart' show votingHomeCacheKey;

/// Diagnostic events contain no wallet identifiers or RPC payloads.
void votingHomeTrace(String message) {
  if (kDebugMode) {
    debugPrint(
      '[VotingHomeTrace] ${DateTime.now().toIso8601String()} $message',
    );
  }
}

const votingHomeRefreshInterval = Duration(hours: 6);

/// UI hints only. These never authorize a vote or replace live validation.
enum VotingHomeEligibility { unknown, eligible, ineligible }

enum VotingHomeDecision { unknown, show, hide }

enum VotingHomeProgress { unknown, available, inProgress, completed }

class VotingHomeRoundList {
  const VotingHomeRoundList({
    required this.checkedAt,
    required this.fingerprint,
    required this.rounds,
    this.discoveryRevision,
    this.discoveryEndpoint,
  });

  final DateTime checkedAt;
  final String fingerprint;
  final List<VotingRoundSummary> rounds;
  final String? discoveryRevision;
  final String? discoveryEndpoint;

  bool isFresh(DateTime now) {
    final age = now.difference(checkedAt);
    return !age.isNegative && age < votingHomeRefreshInterval;
  }

  Map<String, Object?> toJson() => {
    'checkedAt': checkedAt.toIso8601String(),
    'fingerprint': fingerprint,
    if (discoveryRevision != null) 'discoveryRevision': discoveryRevision,
    if (discoveryEndpoint != null) 'discoveryEndpoint': discoveryEndpoint,
    // Home only consumes these hints. Keep proposal bodies and other detailed
    // API payloads out of every startup read and participation-state write.
    'rounds': [
      for (final round in rounds)
        {
          'vote_round_id': round.roundId,
          'title': round.title,
          'status': round.status,
          'snapshot_height': int.tryParse(
            '${round.rawJson['snapshot_height']}',
          ),
          'vote_end_time': votingRoundEndDate(
            round.rawJson,
          )?.toUtc().toIso8601String(),
        },
    ],
  };

  factory VotingHomeRoundList.fromJson(Map<String, dynamic> json) =>
      VotingHomeRoundList(
        checkedAt: DateTime.parse(json['checkedAt'] as String),
        fingerprint: json['fingerprint'] as String,
        discoveryRevision: json['discoveryRevision'] as String?,
        discoveryEndpoint: json['discoveryEndpoint'] as String?,
        rounds: [
          for (final round in json['rounds'] as List)
            VotingRoundSummary.fromJson(
              Map<String, dynamic>.from(round as Map),
            ),
        ],
      );
}

class VotingHomeFact {
  const VotingHomeFact({
    this.eligibility = VotingHomeEligibility.unknown,
    this.progress = VotingHomeProgress.unknown,
    this.snapshotHeight,
    this.participation,
    this.decision = VotingHomeDecision.unknown,
    this.needsRecheck = false,
  });

  final VotingHomeEligibility eligibility;
  final VotingHomeProgress progress;
  final int? snapshotHeight;
  final VotingParticipationResult? participation;
  final VotingHomeDecision decision;
  final bool needsRecheck;

  bool get hasCheckedParticipation =>
      participation != null &&
      !needsRecheck &&
      decision != VotingHomeDecision.unknown;

  Map<String, Object?> toJson() => {
    'eligibility': eligibility.name,
    'progress': progress.name,
    'snapshotHeight': snapshotHeight,
    'decision': decision.name,
    'needsRecheck': needsRecheck,
    if (participation != null) 'participation': participation!.toJson(),
  };

  factory VotingHomeFact.fromJson(Map<String, dynamic> json) => VotingHomeFact(
    decision: VotingHomeDecision.values.byName(json['decision'] as String),
    needsRecheck: json['needsRecheck'] as bool,
    eligibility: VotingHomeEligibility.values.byName(
      json['eligibility'] as String,
    ),
    progress: VotingHomeProgress.values.byName(json['progress'] as String),
    snapshotHeight: json['snapshotHeight'] as int?,
    participation: json['participation'] == null
        ? null
        : VotingParticipationResult.fromJson(
            json['participation'] as Map<String, dynamic>,
          ),
  );
}

abstract interface class VotingHomeCacheStore {
  Future<String?> read();
  Future<void> write(String value);
}

class _FileVotingHomeCacheStore implements VotingHomeCacheStore {
  _FileVotingHomeCacheStore(this.cache);
  final VotingFileCache cache;
  @override
  Future<String?> read() => cache.read(votingHomeCacheKey);
  @override
  Future<void> write(String value) => cache.write(votingHomeCacheKey, value);
}

final votingFileCacheProvider = Provider<VotingFileCache>(
  (ref) => VotingFileCache(),
);

final votingHomeCacheStoreProvider = Provider<VotingHomeCacheStore>(
  (ref) => _FileVotingHomeCacheStore(ref.watch(votingFileCacheProvider)),
);
final votingHomeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

String votingHomeListKey(String network, String source) =>
    jsonEncode([network, source]);
String votingHomeFactKey(
  String network,
  String fingerprint,
  String account,
  String round,
) => jsonEncode([network, fingerprint, account, round]);

/// One serialized, durable cache shared by Home and the existing voting flows.
/// Writes register with the account/reset drain before their first await.
class VotingHomeCacheNotifier extends Notifier<int> {
  final Map<String, VotingHomeRoundList> _lists = {};
  final Map<String, VotingHomeFact> _facts = {};
  Future<void>? _load;
  Future<void> _writes = Future.value();

  // Home renders unknown as hidden. Its post-frame refresh calls ensureLoaded;
  // neither provider construction nor app bootstrap waits for voting storage.
  @override
  int build() => 0;

  VotingHomeRoundList? list(String key) => _lists[key];
  VotingHomeFact fact(String key) => _facts[key] ?? const VotingHomeFact();

  Future<void> ensureLoaded() => _load ??= _read();

  Future<void> _read() async {
    try {
      votingHomeTrace('cache.load.start');
      final raw = await ref.read(votingHomeCacheStoreProvider).read();
      if (!ref.mounted) return;
      if (raw == null) {
        votingHomeTrace('cache.load.empty');
        return;
      }
      _decode(raw);
      state++;
    } catch (error) {
      votingHomeTrace('cache.load.failed');
      debugPrint('Voting Home cache read failed: $error');
    }
  }

  void _decode(String? raw) {
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final lists = (json['lists'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        VotingHomeRoundList.fromJson(value as Map<String, dynamic>),
      ),
    );
    final facts = (json['facts'] as Map<String, dynamic>).map(
      (key, value) =>
          MapEntry(key, VotingHomeFact.fromJson(value as Map<String, dynamic>)),
    );
    _lists.addAll(lists);
    _facts.addAll(facts);
    votingHomeTrace(
      'cache.load.done lists=${lists.length} facts=${facts.length} '
      'participation=${facts.values.where((f) => f.participation != null).length}',
    );
  }

  Future<void> recordList(String key, VotingHomeRoundList list) => _update(() {
    if (_lists[key]?.checkedAt.isAfter(list.checkedAt) ?? false) return false;
    final previous = _lists[key];
    final network = (jsonDecode(key) as List)[0];
    for (final round in list.rounds) {
      final snapshot = int.tryParse('${round.rawJson['snapshot_height']}');
      if (snapshot == null) continue;
      for (final entry in _facts.entries.toList()) {
        final scope = jsonDecode(entry.key) as List;
        if (scope[0] == network &&
            scope[1] == list.fingerprint &&
            scope[3] == round.roundId &&
            entry.value.snapshotHeight != null &&
            entry.value.snapshotHeight != snapshot) {
          _facts[entry.key] = const VotingHomeFact();
        }
      }
    }
    // Existing voting screens also refresh this list. Preserve the last applied
    // hint within the same authenticated source, without inventing a new one.
    _lists[key] =
        list.discoveryRevision == null &&
            previous?.fingerprint == list.fingerprint
        ? VotingHomeRoundList(
            checkedAt: list.checkedAt,
            fingerprint: list.fingerprint,
            rounds: list.rounds,
            discoveryRevision: previous?.discoveryRevision,
            discoveryEndpoint: previous?.discoveryEndpoint,
          )
        : list;
    return true;
  });

  Future<void> recordEligibility(
    String key,
    bool eligible,
    int snapshotHeight,
  ) => _update(() {
    final old = fact(key);
    final nextEligibility = eligible
        ? VotingHomeEligibility.eligible
        : VotingHomeEligibility.ineligible;
    if (old.eligibility == nextEligibility &&
        old.snapshotHeight == snapshotHeight) {
      return false;
    }
    final sameSnapshot =
        old.snapshotHeight == null || old.snapshotHeight == snapshotHeight;
    final progress = sameSnapshot ? old.progress : VotingHomeProgress.unknown;
    var decision = sameSnapshot ? old.decision : VotingHomeDecision.unknown;
    if (progress != VotingHomeProgress.inProgress &&
        progress != VotingHomeProgress.completed &&
        !eligible) {
      decision = VotingHomeDecision.hide;
    }
    _facts[key] = VotingHomeFact(
      eligibility: nextEligibility,
      progress: progress,
      decision: decision,
      needsRecheck:
          old.needsRecheck ||
          (eligible && old.eligibility == VotingHomeEligibility.ineligible),
      participation: sameSnapshot ? old.participation : null,
      snapshotHeight: snapshotHeight,
    );
    return true;
  });

  Future<void> recordParticipation(
    String key,
    int snapshotHeight,
    VotingParticipationResult result,
  ) => _update(() {
    final old = fact(key);
    votingHomeTrace(
      'participation.record snapshot=$snapshotHeight '
      'unavailable=${result.unavailable}',
    );
    final sameSnapshot =
        old.snapshotHeight == null || old.snapshotHeight == snapshotHeight;
    final progress = sameSnapshot ? old.progress : VotingHomeProgress.unknown;
    var decision = sameSnapshot ? old.decision : VotingHomeDecision.unknown;
    if (progress != VotingHomeProgress.completed &&
        progress != VotingHomeProgress.inProgress &&
        !result.localState &&
        (result.complete || result.remainingEligible)) {
      decision = result.remainingEligible
          ? VotingHomeDecision.show
          : VotingHomeDecision.hide;
    }
    _facts[key] = VotingHomeFact(
      eligibility: sameSnapshot
          ? old.eligibility
          : VotingHomeEligibility.unknown,
      progress: progress,
      snapshotHeight: snapshotHeight,
      participation: result,
      decision: decision,
      needsRecheck: result.localState || !result.complete,
    );
    return true;
  });

  Future<void> recordPlan(String key, wire.RoundPlanView? plan) => _update(() {
    final old = fact(key);
    // completedForDisplay may cover only some proposals. Open proposals and
    // blocking recovery must remain discoverable from Home.
    final progress = plan == null
        ? VotingHomeProgress.unknown
        : plan.blockingRecovery
        ? VotingHomeProgress.inProgress
        : plan.completedForDisplay && plan.openProposals.isEmpty
        ? VotingHomeProgress.completed
        : plan.pendingRecovery && !plan.completedForDisplay
        ? VotingHomeProgress.inProgress
        : VotingHomeProgress.available;
    final actionable =
        plan != null &&
        (progress == VotingHomeProgress.inProgress ||
            (!plan.needsDraftSetup && plan.openProposals.isNotEmpty));
    final decision = progress == VotingHomeProgress.completed
        ? VotingHomeDecision.hide
        : actionable
        ? VotingHomeDecision.show
        : plan != null && (old.participation?.localState ?? false)
        ? (old.participation!.remainingEligible
              ? VotingHomeDecision.show
              : VotingHomeDecision.hide)
        : old.decision;
    final needsRecheck =
        old.needsRecheck &&
        !actionable &&
        progress != VotingHomeProgress.completed &&
        !(plan != null && (old.participation?.localState ?? false));
    if (old.progress == progress &&
        old.decision == decision &&
        old.needsRecheck == needsRecheck) {
      return false;
    }
    _facts[key] = VotingHomeFact(
      eligibility: old.eligibility,
      progress: progress,
      snapshotHeight: old.snapshotHeight,
      participation: old.participation,
      decision: decision,
      needsRecheck: needsRecheck,
    );
    return true;
  });

  /// Only callers that know an actual wallet rewind occurred may use this.
  /// A sync progress height is not evidence of a rewind.
  Future<void> invalidateEligibilityAfterRewind({
    required String network,
    required String accountUuid,
    required int scannedHeight,
    String trigger = 'unspecified',
  }) => _update(() {
    var changed = false;
    for (final entry in _facts.entries.toList()) {
      final key = jsonDecode(entry.key) as List;
      final fact = entry.value;
      if (key[0] != network ||
          key[2] != accountUuid ||
          (fact.eligibility == VotingHomeEligibility.unknown &&
              fact.participation == null) ||
          fact.snapshotHeight == null ||
          scannedHeight >= fact.snapshotHeight!) {
        continue;
      }
      votingHomeTrace(
        'cache.invalidate trigger=$trigger scanned=$scannedHeight '
        'snapshot=${fact.snapshotHeight} participation=${fact.participation != null} '
        'progress=${fact.progress.name}',
      );
      if (fact.needsRecheck) continue;
      _facts[entry.key] = VotingHomeFact(
        progress: fact.progress,
        eligibility: fact.eligibility,
        snapshotHeight: fact.snapshotHeight,
        participation: fact.participation,
        decision: fact.decision,
        needsRecheck: true,
      );
      changed = true;
    }
    return changed;
  });

  Future<void> _update(bool Function() change) async {
    final release = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork();
    if (release == null) return;
    try {
      await ensureLoaded();
      if (!ref.mounted) return;
      if (!change()) return;
      state++;
      await _persist();
    } catch (error) {
      // Discovery hints must never fail an eligibility check or a submission.
      debugPrint('Voting Home cache write failed: $error');
    } finally {
      release();
    }
  }

  Future<void> _persist() {
    final store = ref.read(votingHomeCacheStoreProvider);
    final value = jsonEncode({
      'lists': _lists.map((key, value) => MapEntry(key, value.toJson())),
      'facts': _facts.map((key, value) => MapEntry(key, value.toJson())),
    });
    final write = _writes.then((_) async {
      await store.write(value);
      votingHomeTrace('cache.persist.done');
    });
    _writes = write.catchError((Object error) {
      votingHomeTrace('cache.persist.failed');
      debugPrint('Voting Home cache persistence failed: $error');
    });
    return write;
  }

  /// Called by account deletion after the voting drain has completed.
  Future<void> removeAccount(String accountUuid) async {
    await ensureLoaded();
    _facts.removeWhere((key, _) => (jsonDecode(key) as List)[2] == accountUuid);
    state++;
    await _persist();
  }

  /// Called during reset while the drain is held, before secure storage wipe.
  void clearForReset() {
    _lists.clear();
    _facts.clear();
    _load = Future.value();
    state++;
  }

  bool shouldShow({
    required String listKey,
    required String network,
    required String accountUuid,
    required bool showTestRounds,
    required DateTime now,
  }) {
    final rounds = list(listKey);
    if (rounds == null) {
      votingHomeTrace('visibility=false reason=no-list');
      return false;
    }
    return rounds.rounds.any((round) {
      if (!showTestRounds && isHiddenTestVotingRoundTitle(round.title)) {
        return false;
      }
      if (votingPollListStatus(round.status) != VotingPollListStatus.active) {
        return false;
      }
      final end = votingRoundEndDate(round.rawJson);
      if (end != null && !now.isBefore(end)) return false;
      final local = fact(
        votingHomeFactKey(
          network,
          rounds.fingerprint,
          accountUuid,
          round.roundId,
        ),
      );
      votingHomeTrace(
        'visibility.candidate decision=${local.decision.name} '
        'recheck=${local.needsRecheck}',
      );
      return local.decision == VotingHomeDecision.show;
    });
  }
}

final votingHomeCacheProvider = NotifierProvider<VotingHomeCacheNotifier, int>(
  VotingHomeCacheNotifier.new,
);

/// Observe an existing check without introducing any Home-side wallet query.
Future<T> observeVotingHomeResult<T>(
  Ref ref, {
  required Future<T> Function() operation,
  required Future<void> Function(VotingHomeCacheNotifier cache, T result)
  record,
}) {
  final release = ref
      .read(votingShareTrackingRegistryProvider)
      .beginBackgroundWork();
  if (release == null) return operation();
  final Future<T> pending;
  try {
    pending = operation();
  } catch (error, stack) {
    release();
    return Future.error(error, stack);
  }
  return pending.then(
    (result) {
      if (!ref.mounted) {
        release();
        return result;
      }
      try {
        // Persistence stays drainable but must not delay session initialization,
        // tracking schedules, or a successful eligibility result.
        unawaited(
          record(ref.read(votingHomeCacheProvider.notifier), result)
              .catchError(
                (Object error) =>
                    debugPrint('Voting Home observation failed: $error'),
              )
              .whenComplete(release),
        );
      } catch (error) {
        release();
        debugPrint('Voting Home observation failed: $error');
      }
      return result;
    },
    onError: (Object error, StackTrace stack) {
      release();
      Error.throwWithStackTrace(error, stack);
    },
  );
}
