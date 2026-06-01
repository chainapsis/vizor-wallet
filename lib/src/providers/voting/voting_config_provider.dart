import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voting/voting_models.dart';
import 'voting_config_source_provider.dart';
import 'voting_service_providers.dart';

/// Loads and caches the active dynamic voting configuration.
///
/// The config is refreshed on app resume so endpoint/round changes are picked up
/// without a restart, but errors remain explicit `AsyncError`s because voting
/// must fail closed when service discovery is unavailable or malformed.
class VotingConfigNotifier extends AsyncNotifier<VotingConfig> {
  AppLifecycleListener? _lifecycleListener;
  int _loadGeneration = 0;

  @override
  Future<VotingConfig> build() async {
    final generation = ++_loadGeneration;
    _lifecycleListener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _loadGeneration++;
      _lifecycleListener?.dispose();
    });
    try {
      final config = await _load();
      if (!_isCurrentLoad(generation)) {
        return state.value ?? config;
      }
      return config;
    } catch (_) {
      if (!_isCurrentLoad(generation)) {
        final previous = state.value;
        if (previous != null) return previous;
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    final generation = ++_loadGeneration;
    state = const AsyncLoading<VotingConfig>();
    final config = await AsyncValue.guard(_load);
    if (!_isCurrentLoad(generation)) return;
    state = config;
  }

  bool _isCurrentLoad(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  Future<VotingConfig> _load() async {
    await ref.read(votingConfigSourceProvider.future);
    return ref.read(votingConfigLoaderProvider).load();
  }
}

final votingConfigProvider =
    AsyncNotifierProvider<VotingConfigNotifier, VotingConfig>(
      VotingConfigNotifier.new,
    );
