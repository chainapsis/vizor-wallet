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
      final config = await _loadAndCommit(generation);
      if (config != null) return config;
      return _staleLoadResult();
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
      final config = await _loadAndCommit(generation);
      if (config == null) return;
      state = AsyncData(config);
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation)) return;
      state = AsyncError(error, stackTrace);
    }
  }

  /// Commits a preloaded resolution through the normal switch path.
  void setLoadedConfig(VotingConfigResolution resolution) {
    _loadGeneration++;
    state = AsyncData(_commitResolution(resolution));
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

  /// Resolves config and commits cache mutations only for active loads.
  ///
  /// Returning `null` signals this generation became stale while resolving.
  Future<ResolvedVotingConfig?> _loadAndCommit(int generation) async {
    await ref.read(votingConfigSourceProvider.future);
    final resolution = await ref
        .read(votingConfigLoaderProvider)
        .load(previous: _previousResolvedConfig);
    if (!_isCurrentLoad(generation)) return null;
    return _commitResolution(resolution);
  }

  ResolvedVotingConfig _commitResolution(VotingConfigResolution resolution) {
    _applySwitch(resolution.switchKind);
    _previousResolvedConfig = resolution.config;
    return resolution.config;
  }

  /// Applies the Rust-computed switch plan to dependent voting state.
  ///
  /// `unchanged`/`initialLoad` keep all caches. The remaining kinds all imply
  /// the vote/PIR endpoints, signing keys, rounds, or protocol moved, so every
  /// endpoint-dependent cache is rebuilt to force re-resolution against the new
  /// config:
  ///
  /// - shared transport/client + PIR resolver caches via [_invalidateEndpointState];
  /// - the poll list ([votingRoundsProvider]) and the interactive session
  ///   ([votingSessionProvider]) so status polls and session setup rerun;
  /// - the submission-session family ([votingSubmissionSessionProvider]) so a
  ///   subsequent submission re-resolves its endpoints (including the PIR
  ///   endpoint, which `_resolvePirEndpoint` otherwise caches in session state).
  void _applySwitch(ConfigSwitchKind kind) {
    switch (kind) {
      case ConfigSwitchKind.unchanged:
      case ConfigSwitchKind.initialLoad:
        return;
      case ConfigSwitchKind.sameChainServiceUpdate:
      case ConfigSwitchKind.newChainOrRound:
      case ConfigSwitchKind.protocolChanged:
        _invalidateEndpointState();
        ref.invalidate(votingRoundsProvider);
        ref.invalidate(votingSessionProvider);
        ref.invalidate(votingSubmissionSessionProvider);
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
