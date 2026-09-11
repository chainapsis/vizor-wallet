import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/voting/voting_poll_ordering.dart';

import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_models.dart';
import '../../services/voting/voting_config_loader.dart';
import '../../services/voting/voting_discovery_client.dart';
import '../../services/voting/voting_http.dart';
import '../account_provider.dart';
import '../app_security_provider.dart';
import '../rpc_endpoint_provider.dart';
import 'voting_config_provider.dart';
import 'voting_config_source_provider.dart';
import 'voting_home_cache_provider.dart';
import 'voting_round_visibility_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_registry_provider.dart';

/// Only cached data is observed here. In particular, never watch the poll-list,
/// eligibility, session, PIR, or recovery providers from Home.
final votingHomeEntryVisibleProvider = Provider<bool>((ref) {
  ref.watch(votingHomeCacheProvider);
  final account = ref.watch(
    accountProvider.select((s) => s.value?.activeAccountUuid),
  );
  final source = ref.watch(
    votingConfigSourceProvider.select((s) => s.value?.sourceUrl),
  );
  final network = ref.watch(rpcEndpointProvider.select((s) => s.networkName));
  final showTest = ref.watch(showTestVotingRoundsProvider).value ?? false;
  if (account == null || source == null) return false;
  final visible = ref
      .read(votingHomeCacheProvider.notifier)
      .shouldShow(
        listKey: votingHomeListKey(network, source),
        network: network,
        accountUuid: account,
        showTestRounds: showTest,
        now: ref.read(votingHomeClockProvider)(),
      );
  votingHomeTrace('visibility=$visible');
  return visible;
});

final votingDiscoveryEndpointProvider = Provider<String>(
  (ref) => votingDiscoveryUrl,
);
final votingDiscoveryStageEndpointProvider = Provider<String>(
  (ref) => votingDiscoveryStageUrl,
);

VotingDiscoveryScope? votingDiscoveryScopeForSource(
  String network,
  String source,
) {
  if (network == 'main' &&
      kProductionStaticVotingConfigMirrors.contains(source)) {
    return VotingDiscoveryScope.prod;
  }
  if (network == 'test' && kStageStaticVotingConfigMirrors.contains(source)) {
    return VotingDiscoveryScope.stage;
  }
  return null;
}

final votingDiscoveryClientProvider = Provider<VotingDiscoveryClient>((ref) {
  final http = DartIoVotingHttpClient();
  ref.onDispose(http.close);
  return VotingDiscoveryClient(http);
});

final votingHomeRefreshProvider = Provider((ref) => VotingHomeRefresh(ref));

class VotingHomeRefresh {
  VotingHomeRefresh(this.ref);
  final Ref ref;
  Future<void>? _inFlight;
  (String?, String, String)? _runningContext;
  bool _rerun = false;
  // Failed requests do not advance the durable six-hour success timestamp.
  // A short process-local cooldown prevents rebuild/reentry retry storms.
  final Map<String, DateTime> _failures = {};
  final Map<String, DateTime> _probeFailures = {};

  String _endpoint() => ref.read(rpcEndpointProvider).networkName == 'test'
      ? ref.read(votingDiscoveryStageEndpointProvider)
      : ref.read(votingDiscoveryEndpointProvider);

  (String?, String, String) _context() => (
    ref.read(votingConfigSourceProvider).value?.sourceUrl,
    ref.read(rpcEndpointProvider).networkName,
    _endpoint(),
  );

  Future<void> refresh() {
    if (!ref.mounted) return Future.value();
    if (_inFlight != null) {
      if (_context() != _runningContext) _rerun = true;
      return _inFlight!;
    }
    return _inFlight = _refresh().whenComplete(() {
      _inFlight = null;
      if (_rerun && ref.mounted) {
        _rerun = false;
        return refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final release = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork();
    if (release == null) return;
    String? key;
    try {
      if (ref.read(appSecurityProvider).requiresUnlock) return;
      _runningContext = _context();
      final source = (await ref.read(
        votingConfigSourceProvider.future,
      )).sourceUrl;
      if (!ref.mounted) return;
      final network = ref.read(rpcEndpointProvider).networkName;
      _runningContext = (source, network, _endpoint());
      key = votingHomeListKey(network, source);
      final cache = ref.read(votingHomeCacheProvider.notifier);
      await cache.ensureLoaded();
      if (!ref.mounted) return;
      final now = ref.read(votingHomeClockProvider)();
      final endpoint = _endpoint();
      final cached = cache.list(key);
      final fresh = cached?.isFresh(now) ?? false;
      VotingDiscoverySnapshot? discovery;
      final scope = votingDiscoveryScopeForSource(network, source);
      if (scope != null) {
        final probeKey = '$key/$endpoint';
        final failed = _probeFailures[probeKey];
        if (failed == null ||
            now.difference(failed).isNegative ||
            now.difference(failed) >= const Duration(minutes: 1)) {
          try {
            discovery = await ref
                .read(votingDiscoveryClientProvider)
                .fetch(
                  Uri.parse(endpoint),
                  ref.read(votingHomeClockProvider),
                  scope: scope,
                );
            _probeFailures.remove(probeKey);
          } catch (error) {
            if (!ref.mounted) return;
            _probeFailures[probeKey] = ref.read(votingHomeClockProvider)();
            debugPrint('Voting change check failed: $error');
          }
        }
      }
      if (!ref.mounted ||
          ref.read(appSecurityProvider).requiresUnlock ||
          ref.read(votingConfigSourceProvider).value?.sourceUrl != source ||
          ref.read(rpcEndpointProvider).networkName != network ||
          _endpoint() != endpoint) {
        return;
      }
      if (fresh &&
          (discovery == null ||
              (cached?.discoveryRevision == discovery.revision &&
                  cached?.discoveryEndpoint == endpoint))) {
        return;
      }
      final failedAt = _failures[key];
      if (failedAt != null &&
          now.difference(failedAt) < const Duration(minutes: 5)) {
        return;
      }

      if (ref.exists(votingConfigProvider) &&
          !ref.read(votingConfigProvider).isLoading) {
        await ref.read(votingConfigProvider.notifier).refresh();
      }
      final config = await ref.read(votingConfigProvider.future);
      // Last-good config on a transport failure is useful to voting flows, but
      // must not count as a successful Home refresh for another six hours.
      if (ref.read(votingConfigRefreshFailureProvider) != null) {
        throw StateError('Voting config refresh failed');
      }
      if (ref.read(votingConfigSourceProvider).value?.sourceUrl != source ||
          ref.read(rpcEndpointProvider).networkName != network) {
        return;
      }
      final rounds = config.authenticatedRounds.isEmpty
          ? <VotingRoundSummary>[]
          : (await ref
                    .read(votingApiClientProvider(config.apiServers))
                    .listRounds())
                .where((round) => config.isRoundAuthenticated(round.roundId))
                .toList(growable: false);
      if (!ref.mounted || ref.read(appSecurityProvider).requiresUnlock) return;
      if (ref.read(votingConfigSourceProvider).value?.sourceUrl != source ||
          ref.read(rpcEndpointProvider).networkName != network ||
          _endpoint() != endpoint ||
          !identical(ref.read(votingConfigProvider).value, config)) {
        return;
      }
      await cache.recordList(
        key,
        VotingHomeRoundList(
          checkedAt: now,
          fingerprint: config.sourceFingerprint,
          rounds: rounds,
          discoveryRevision: discovery?.revision,
          discoveryEndpoint: discovery == null ? null : endpoint,
        ),
      );
      for (final round in rounds) {
        if (votingPollListStatus(round.status) != VotingPollListStatus.active) {
          try {
            await ref
                .read(votingFileCacheProvider)
                .removeRound(network, round.roundId);
          } catch (_) {
            // Best-effort disposal must not turn successful discovery into a failure.
            debugPrint('Voting ended-round cache cleanup deferred');
          }
        }
      }
      _failures.remove(key);
    } catch (error) {
      if (key != null && ref.mounted) {
        _failures[key] = ref.read(votingHomeClockProvider)();
      }
      debugPrint('Voting Home discovery failed: $error');
    } finally {
      release();
    }
  }
}

final votingHomeRefreshActionProvider = Provider<Future<void> Function()>((
  ref,
) {
  return ref.watch(votingHomeRefreshProvider).refresh;
});
