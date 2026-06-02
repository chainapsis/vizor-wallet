import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/voting_config.dart';
import '../../rust/third_party/zcash_voting/config.dart';
import 'voting_config_source_provider.dart';
import 'voting_rounds_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_tree_sync_provider.dart';

/// Loads and caches the active dynamic voting configuration.
///
/// The config is refreshed on app resume so endpoint/round changes are picked up
/// without a restart, but errors remain explicit `AsyncError`s because voting
/// must fail closed when service discovery is unavailable or malformed.
class VotingConfigNotifier extends AsyncNotifier<ResolvedVotingConfig> {
  AppLifecycleListener? _lifecycleListener;
  int _loadGeneration = 0;
  ResolvedVotingConfig? _previousResolvedConfig;

  @override
  Future<ResolvedVotingConfig> build() async {
    final generation = ++_loadGeneration;
    _lifecycleListener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _loadGeneration++;
      _lifecycleListener?.dispose();
    });
    try {
      final resolution = await _resolve();
      if (!_isCurrentLoad(generation)) {
        return _staleLoadResult();
      }
      return _commitResolution(resolution);
    } catch (_) {
      if (!_isCurrentLoad(generation)) {
        return _staleLoadResult();
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    final generation = ++_loadGeneration;
    state = const AsyncLoading<ResolvedVotingConfig>();
    try {
      final resolution = await _resolve();
      if (!_isCurrentLoad(generation)) return;
      state = AsyncData(_commitResolution(resolution));
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation)) return;
      state = AsyncError(error, stackTrace);
    }
  }

  /// Replaces state with a config that was already loaded and validated.
  void setLoadedConfig(VotingConfig config) {
    _loadGeneration++;
    state = AsyncData(config);
  }

  bool _isCurrentLoad(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  ResolvedVotingConfig _staleLoadResult() {
    final previous = state.value ?? _previousResolvedConfig;
    if (previous != null) return previous;
    final error = state.error;
    if (error != null) {
      Error.throwWithStackTrace(error, state.stackTrace ?? StackTrace.current);
    }
    throw StateError('Ignored stale voting config load.');
  }

  Future<VotingConfigResolution> _resolve() async {
    await ref.read(votingConfigSourceProvider.future);
    return ref
        .read(votingConfigLoaderProvider)
        .load(previous: _previousResolvedConfig);
  }

  ResolvedVotingConfig _commitResolution(VotingConfigResolution resolution) {
    _applySwitch(resolution.switchKind);
    _previousResolvedConfig = resolution.config;
    return resolution.config;
  }

  void _applySwitch(ConfigSwitchKind kind) {
    switch (kind) {
      case ConfigSwitchKind.unchanged:
      case ConfigSwitchKind.initialLoad:
        return;
      case ConfigSwitchKind.sameChainServiceUpdate:
        _invalidateEndpointState();
        return;
      case ConfigSwitchKind.newChainOrRound:
        _invalidateEndpointState();
        ref.invalidate(votingRoundsProvider);
        ref.invalidate(votingSessionProvider);
        return;
      case ConfigSwitchKind.protocolChanged:
        _invalidateEndpointState();
        ref.invalidate(votingRoundsProvider);
        ref.invalidate(votingSessionProvider);
        return;
    }
  }

  void _invalidateEndpointState() {
    ref.invalidate(votingApiClientProvider);
    ref.invalidate(votingEndorserClientProvider);
    ref.invalidate(votingHelperHealthTrackerProvider);
    ref.invalidate(votingPirResolverProvider);
    ref.invalidate(votingTreePreSyncProvider);
  }
}

final votingConfigProvider =
    AsyncNotifierProvider<VotingConfigNotifier, ResolvedVotingConfig>(
      VotingConfigNotifier.new,
    );
