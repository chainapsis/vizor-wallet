import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/private_state_sync_config.dart';
import '../core/private_state_sync/private_state_http_remote_store.dart';
import '../core/private_state_sync/private_state_remote_store.dart';
import '../core/storage/app_secure_store.dart';

abstract interface class PrivateStateSyncSettingsStore {
  Future<void> writeEnabled(bool enabled);
}

class AppSecureStorePrivateStateSyncSettingsStore
    implements PrivateStateSyncSettingsStore {
  const AppSecureStorePrivateStateSyncSettingsStore(this._store);

  final AppSecureStore _store;

  @override
  Future<void> writeEnabled(bool enabled) {
    return _store.writePlain(
      kPrivateStateSyncEnabledKey,
      enabled ? 'true' : 'false',
    );
  }
}

class PrivateStateSyncSettings {
  const PrivateStateSyncSettings({
    required this.enabled,
    this.isSaving = false,
    this.targetEnabled,
    this.error,
  });

  final bool enabled;
  final bool isSaving;
  final bool? targetEnabled;
  final Object? error;

  /// New private-state requests stop as soon as an off request is made. An on
  /// request becomes effective only after its preference has been persisted.
  bool get requestsAllowed => enabled && targetEnabled != false;

  bool get displayedEnabled => targetEnabled ?? enabled;

  PrivateStateSyncSettings copyWith({
    bool? enabled,
    bool? isSaving,
    bool? targetEnabled,
    bool clearTargetEnabled = false,
    Object? error,
    bool clearError = false,
  }) {
    return PrivateStateSyncSettings(
      enabled: enabled ?? this.enabled,
      isSaving: isSaving ?? this.isSaving,
      targetEnabled: clearTargetEnabled
          ? null
          : targetEnabled ?? this.targetEnabled,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final privateStateSyncSettingsStoreProvider =
    Provider<PrivateStateSyncSettingsStore>(
      (_) =>
          AppSecureStorePrivateStateSyncSettingsStore(AppSecureStore.instance),
    );

class PrivateStateSyncSettingsNotifier
    extends Notifier<PrivateStateSyncSettings> {
  Future<void> _mutationTail = Future.value();
  var _latestMutation = 0;
  late bool _persistedEnabled;

  @override
  PrivateStateSyncSettings build() {
    _persistedEnabled = ref.watch(appBootstrapProvider).privateStateSyncEnabled;
    return PrivateStateSyncSettings(enabled: _persistedEnabled);
  }

  Future<void> setEnabled(bool enabled) {
    if (!state.isSaving && state.enabled == enabled) return Future.value();
    final mutation = ++_latestMutation;
    state = state.copyWith(
      isSaving: true,
      targetEnabled: enabled,
      clearError: true,
    );

    final completer = Completer<void>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        await ref
            .read(privateStateSyncSettingsStoreProvider)
            .writeEnabled(enabled);
        _persistedEnabled = enabled;
        if (mutation == _latestMutation) {
          state = PrivateStateSyncSettings(enabled: enabled);
        } else {
          state = state.copyWith(enabled: enabled);
        }
        completer.complete();
      } catch (error, stackTrace) {
        if (mutation == _latestMutation) {
          state = PrivateStateSyncSettings(
            enabled: _persistedEnabled,
            // An off action remains fail-closed for this app session even if
            // storage is temporarily unavailable. On failures may safely roll
            // back because they never became request-authorizing state.
            targetEnabled: enabled ? null : false,
            error: error,
          );
        }
        completer.completeError(error, stackTrace);
      }
    });
    // A failed mutation must not prevent a later request from being persisted.
    _mutationTail = _mutationTail.catchError((_) {});
    return completer.future;
  }
}

final privateStateSyncSettingsProvider =
    NotifierProvider<
      PrivateStateSyncSettingsNotifier,
      PrivateStateSyncSettings
    >(PrivateStateSyncSettingsNotifier.new);

final privateStateSyncRequestsAllowedProvider = Provider<bool>((ref) {
  return ref.watch(
    privateStateSyncSettingsProvider.select(
      (settings) => settings.requestsAllowed,
    ),
  );
});

/// Stable gate shared with transports that may outlive the provider instance
/// that created them while their final in-flight request is unwinding.
class PrivateStateSyncRequestGate {
  PrivateStateSyncRequestGate(bool allowed) : _allowed = allowed;

  bool _allowed;

  bool get allowed => _allowed;

  void update(bool allowed) => _allowed = allowed;
}

final privateStateSyncRequestGateProvider =
    Provider<PrivateStateSyncRequestGate>((ref) {
      final gate = PrivateStateSyncRequestGate(
        ref.read(privateStateSyncRequestsAllowedProvider),
      );
      ref.listen<bool>(privateStateSyncRequestsAllowedProvider, (_, next) {
        gate.update(next);
      });
      return gate;
    });

final privateStateBaseUriProvider = Provider<Uri>((_) {
  return privateStateBaseUriForBuild();
});

final privateStateAudienceProvider = Provider<String>((ref) {
  return privateStateAudienceForBuild(ref.watch(privateStateBaseUriProvider));
});

/// The central opt-in boundary for every private-state feature. When disabled,
/// neither a transport nor a remote store exists and private sync cannot cause
/// Tor bootstrap or HTTP traffic.
final privateStateRemoteStoreProvider = Provider<PrivateStateRemoteStore?>((
  ref,
) {
  if (!ref.watch(privateStateSyncRequestsAllowedProvider)) return null;
  final transport = privateStateHttpTransportForBuild();
  final gate = ref.read(privateStateSyncRequestGateProvider);
  // Graceful close lets a request already handed to the HTTP client finish.
  // The shared gate still rejects every subsequent challenge/GET/upload step.
  ref.onDispose(transport.close);
  return HttpPrivateStateRemoteStore(
    baseUri: ref.watch(privateStateBaseUriProvider),
    signingAudience: ref.watch(privateStateAudienceProvider),
    transport: GatedPrivateStateHttpTransport(
      delegate: transport,
      canStartRequest: () => gate.allowed,
    ),
  );
});
