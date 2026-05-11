import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voting/voting_models.dart';
import 'voting_service_providers.dart';

/// Loads and caches the active dynamic voting configuration.
///
/// The config is refreshed on app resume so endpoint/round changes are picked up
/// without a restart, but errors remain explicit `AsyncError`s because voting
/// must fail closed when service discovery is unavailable or malformed.
class VotingConfigNotifier extends AsyncNotifier<VotingConfig> {
  AppLifecycleListener? _lifecycleListener;

  @override
  Future<VotingConfig> build() async {
    _lifecycleListener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _lifecycleListener?.dispose();
    });
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<VotingConfig>();
    state = await AsyncValue.guard(_load);
  }

  Future<VotingConfig> _load() {
    return ref.read(votingConfigLoaderProvider).load();
  }
}

final votingConfigProvider =
    AsyncNotifierProvider<VotingConfigNotifier, VotingConfig>(
      VotingConfigNotifier.new,
    );
