import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/voting_config.dart';
import '../../rust/third_party/zcash_voting/config.dart';
import '../../services/voting/voting_retry.dart';
import 'voting_config_source_provider.dart';
import 'voting_rounds_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_submission_guard_provider.dart';
import 'voting_tree_sync_provider.dart';

/// Resolves the active dynamic voting configuration for the current source.
///
/// Errors remain explicit `AsyncError`s because voting must fail closed when
/// service discovery is unavailable or malformed.
class VotingConfigNotifier extends AsyncNotifier<ResolvedVotingConfig> {
  static const _configRetryDelays = <Duration>[
    Duration(milliseconds: 300),
    Duration(seconds: 1),
  ];
  int _loadGeneration = 0;
  ResolvedVotingConfig? _previousResolvedConfig;

  @override
  Future<ResolvedVotingConfig> build() async {
    final generation = ++_loadGeneration;
    ref.onDispose(() {
      _loadGeneration++;
    });
    try {
      final config = await _loadAndCommit(generation);
      if (config != null) return config;
      final latest = state.value;
      if (latest != null) return latest;
      final error = state.error;
      if (error != null) {
        Error.throwWithStackTrace(
          error,
          state.stackTrace ?? StackTrace.current,
        );
      }
      throw StateError('Ignored stale voting config load.');
    } catch (_) {
      if (!_isCurrentLoad(generation)) {
        final latest = state.value;
        if (latest != null) return latest;
        final error = state.error;
        if (error != null) {
          Error.throwWithStackTrace(
            error,
            state.stackTrace ?? StackTrace.current,
          );
        }
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

  bool _isCurrentLoad(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  /// Resolves config and commits cache mutations only for active loads.
  ///
  /// Returning `null` signals this generation became stale while resolving.
  Future<ResolvedVotingConfig?> _loadAndCommit(int generation) async {
    await ref.read(votingConfigSourceProvider.future);
    final resolution = await _withConfigRetry(
      () => ref
          .read(votingConfigLoaderProvider)
          .load(previous: _previousResolvedConfig),
    );
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
  /// the vote/PIR endpoints, signing keys, rounds, or protocol moved, so
  /// endpoint-dependent caches are rebuilt to force re-resolution against the new
  /// config:
  ///
  /// - shared transport/client + PIR resolver caches via [_invalidateEndpointState];
  /// - the poll list ([votingRoundsProvider]) and the interactive session
  ///   ([votingSessionProvider]) so status polls and session setup rerun;
  /// - the submission-session family ([votingSubmissionSessionProvider]) so a
  ///   subsequent submission re-resolves its endpoints. Active submission guards
  ///   keep existing sessions alive until their jobs release process-local state.
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
        if (ref.read(votingSubmissionGuardProvider).isEmpty) {
          ref.invalidate(votingSessionProvider);
          ref.invalidate(votingSubmissionSessionProvider);
        }
        return;
    }
  }

  void _invalidateEndpointState() {
    ref.invalidate(votingApiClientProvider);
    ref.invalidate(votingHelperHealthTrackerProvider);
    ref.invalidate(votingPirResolverProvider);
    ref.invalidate(votingTreePreSyncProvider);
  }

  Future<T> _withConfigRetry<T>(Future<T> Function() operation) async {
    return retryVotingOperation(
      operation: operation,
      delays: _configRetryDelays,
      label: 'config load',
    );
  }
}

final votingConfigProvider =
    AsyncNotifierProvider<VotingConfigNotifier, ResolvedVotingConfig>(
      VotingConfigNotifier.new,
    );
