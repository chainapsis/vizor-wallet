import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../rust/api/multisig.dart' as rust_multisig;
import 'app_security_provider.dart';
import 'multisig_account_material_provider.dart';
import 'multisig_coordinator_service.dart';
import 'multisig_pending_session_provider.dart';
import 'multisig_signing_request_provider.dart';

const _realtimeAccessRefreshSkewSeconds = 30;

final multisigRealtimeProvider =
    NotifierProvider<MultisigRealtimeNotifier, MultisigRealtimeState>(
      MultisigRealtimeNotifier.new,
    );

enum MultisigRealtimeSignalType {
  sessionChanged,
  eventsAvailable,
  inboxAvailable,
  signingRequestChanged,
  repairSessionChanged,
}

class MultisigRealtimeSignal {
  const MultisigRealtimeSignal({
    required this.type,
    required this.sessionId,
    this.cursor,
    this.signingRequestId,
    this.repairSessionId,
  });

  final MultisigRealtimeSignalType type;
  final String sessionId;
  final int? cursor;
  final String? signingRequestId;
  final String? repairSessionId;

  static MultisigRealtimeSignal? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = value.cast<String, Object?>();
    final rawType = json['type'];
    final rawSessionId = json['session_id'];
    if (rawType is! String || rawSessionId is! String) return null;

    final type = switch (rawType) {
      'session_changed' => MultisigRealtimeSignalType.sessionChanged,
      'events_available' => MultisigRealtimeSignalType.eventsAvailable,
      'inbox_available' => MultisigRealtimeSignalType.inboxAvailable,
      'signing_request_changed' =>
        MultisigRealtimeSignalType.signingRequestChanged,
      'repair_session_changed' =>
        MultisigRealtimeSignalType.repairSessionChanged,
      _ => null,
    };
    if (type == null) return null;

    return MultisigRealtimeSignal(
      type: type,
      sessionId: rawSessionId,
      cursor: _readOptionalInt(json['cursor']),
      signingRequestId: json['signing_request_id'] as String?,
      repairSessionId: json['repair_session_id'] as String?,
    );
  }
}

class MultisigRealtimeTarget {
  const MultisigRealtimeTarget({
    required this.coordinatorUrl,
    required this.sessionId,
    required this.participantId,
    required this.accessToken,
    required this.refreshToken,
    required this.identity,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    this.accountUuid,
  });

  factory MultisigRealtimeTarget.fromPendingSession(
    MultisigPendingSession session,
  ) {
    return MultisigRealtimeTarget(
      coordinatorUrl: session.coordinatorUrl,
      sessionId: session.sessionId,
      participantId: session.participantId,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      identity: session.identity,
      accessTokenExpiresAt: session.accessTokenExpiresAt,
      refreshTokenExpiresAt: session.refreshTokenExpiresAt,
    );
  }

  factory MultisigRealtimeTarget.fromAccountMaterial(
    MultisigAccountMaterial material,
  ) {
    return MultisigRealtimeTarget(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: material.sessionId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      refreshToken: material.refreshToken,
      identity: material.identity,
      accessTokenExpiresAt: material.accessTokenExpiresAt,
      refreshTokenExpiresAt: material.refreshTokenExpiresAt,
      accountUuid: material.accountUuid,
    );
  }

  final String coordinatorUrl;
  final String sessionId;
  final String participantId;
  final String accessToken;
  final String refreshToken;
  final MultisigParticipantIdentity identity;
  final int accessTokenExpiresAt;
  final int refreshTokenExpiresAt;
  final String? accountUuid;

  String get storageId => '$sessionId:$participantId';

  String get connectionKey => '$coordinatorUrl|$sessionId|$participantId';

  MultisigRealtimeTarget applyAuthUpdate(
    rust_multisig.ApiMultisigAuthUpdate update,
  ) {
    if (update.sessionId != sessionId ||
        update.participantId != participantId) {
      throw StateError('Multisig auth refresh returned a different session.');
    }
    return MultisigRealtimeTarget(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      accessToken: update.accessToken,
      refreshToken: update.refreshToken,
      identity: MultisigParticipantIdentity(
        admissionSecretKey: identity.admissionSecretKey,
        admissionPublicKey: update.admissionPublicKey,
        deliverySecretKey: update.deliverySecretKey,
        deliveryPublicKey: update.deliveryPublicKey,
      ),
      accessTokenExpiresAt: update.accessTokenExpiresAt.toInt(),
      refreshTokenExpiresAt: update.refreshTokenExpiresAt.toInt(),
      accountUuid: accountUuid,
    );
  }

  MultisigRealtimeTarget withAuthFrom(
    MultisigRealtimeTarget freshTarget, {
    String? accountUuid,
  }) {
    return MultisigRealtimeTarget(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      accessToken: freshTarget.accessToken,
      refreshToken: freshTarget.refreshToken,
      identity: freshTarget.identity,
      accessTokenExpiresAt: freshTarget.accessTokenExpiresAt,
      refreshTokenExpiresAt: freshTarget.refreshTokenExpiresAt,
      accountUuid: accountUuid ?? this.accountUuid,
    );
  }
}

class MultisigRealtimeConnectionSnapshot {
  const MultisigRealtimeConnectionSnapshot({
    required this.connectionKey,
    required this.sessionId,
    required this.participantId,
    required this.leaseCount,
    required this.connected,
    required this.connecting,
    required this.reconnecting,
    this.lastError,
  });

  final String connectionKey;
  final String sessionId;
  final String participantId;
  final int leaseCount;
  final bool connected;
  final bool connecting;
  final bool reconnecting;
  final String? lastError;
}

class MultisigRealtimeState {
  const MultisigRealtimeState({
    this.isForeground = true,
    this.connections = const <String, MultisigRealtimeConnectionSnapshot>{},
  });

  final bool isForeground;
  final Map<String, MultisigRealtimeConnectionSnapshot> connections;
}

class MultisigRealtimeLease {
  MultisigRealtimeLease._(this._release);
  MultisigRealtimeLease.noop() : _release = (() {});

  final VoidCallback _release;
  bool _released = false;

  void dispose() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class MultisigRealtimeNotifier extends Notifier<MultisigRealtimeState> {
  final _connections = <String, _MultisigRealtimeConnection>{};
  final _sessionRefreshes = <String, Future<void>>{};
  final _accountRefreshes = <String, Future<void>>{};

  AppLifecycleListener? _lifecycleListener;
  bool _isForeground = true;
  bool _disposed = false;

  @override
  MultisigRealtimeState build() {
    _disposed = false;
    _isForeground = true;
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _isForeground = true;
        for (final connection in _connections.values) {
          connection.resumeIfLeased();
        }
        _publish();
      },
      onHide: () {
        _isForeground = false;
        for (final connection in _connections.values) {
          connection.suspend();
        }
        _publish();
      },
    );

    ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
      if (next.requiresUnlock) {
        _stopAll();
      } else if (previous?.requiresUnlock == true && _isForeground) {
        for (final connection in _connections.values) {
          connection.resumeIfLeased();
        }
      }
    });

    ref.onDispose(() {
      _disposed = true;
      _lifecycleListener?.dispose();
      for (final connection in _connections.values.toList(growable: false)) {
        connection.dispose();
      }
      _connections.clear();
      _sessionRefreshes.clear();
      _accountRefreshes.clear();
    });

    return const MultisigRealtimeState();
  }

  MultisigRealtimeLease acquire(
    MultisigRealtimeTarget target, {
    required String reason,
  }) {
    final key = target.connectionKey;
    final connection = _connections.putIfAbsent(
      key,
      () => _MultisigRealtimeConnection(owner: this, target: target),
    );
    connection.updateTarget(target);
    connection.addLease(reason);
    if (_canConnect) {
      connection.resumeIfLeased();
    }
    _publish();

    return MultisigRealtimeLease._(() {
      final existing = _connections[key];
      if (existing == null) return;
      existing.releaseLease(reason);
      if (!existing.hasLeases) {
        existing.dispose();
        _connections.remove(key);
      }
      _publish();
    });
  }

  void updateTarget(MultisigRealtimeTarget target) {
    final connection = _connections[target.connectionKey];
    if (connection == null) return;
    connection.updateTarget(target);
    if (_canConnect) connection.resumeIfLeased();
    _publish();
  }

  bool get _canConnect =>
      _isForeground && !ref.read(appSecurityProvider).requiresUnlock;

  Future<MultisigRealtimeTarget> _targetWithFreshAccess(
    MultisigRealtimeTarget target, {
    bool force = false,
  }) async {
    if (!force && _hasFreshAccess(target)) return target;

    final update = await ref
        .read(multisigCoordinatorServiceProvider)
        .refreshOrResumeAuth(
          coordinatorUrl: target.coordinatorUrl,
          sessionId: target.sessionId,
          participantId: target.participantId,
          refreshToken: target.refreshToken,
          admissionSecretKey: target.identity.admissionSecretKey,
          deliverySecretKey: target.identity.deliverySecretKey,
        );
    await ref
        .read(multisigPendingSessionsProvider.notifier)
        .applyAuthUpdate(update);
    return target.applyAuthUpdate(update);
  }

  bool _hasFreshAccess(MultisigRealtimeTarget target) {
    final nowSeconds =
        ref.read(multisigNowProvider)().millisecondsSinceEpoch ~/ 1000;
    return target.accessTokenExpiresAt >
        nowSeconds + _realtimeAccessRefreshSkewSeconds;
  }

  Future<void> _catchUp(_MultisigRealtimeConnection connection) async {
    final target = connection.target;
    final accountUuid = target.accountUuid;
    if (accountUuid != null) {
      _refreshAccount(accountUuid);
    } else {
      _refreshSessionFromEvents(target.storageId);
    }
  }

  Future<void> _handleSignal(
    _MultisigRealtimeConnection connection,
    MultisigRealtimeSignal signal,
  ) async {
    final target = connection.target;
    if (signal.sessionId != target.sessionId) return;

    switch (signal.type) {
      case MultisigRealtimeSignalType.sessionChanged:
      case MultisigRealtimeSignalType.repairSessionChanged:
      case MultisigRealtimeSignalType.eventsAvailable:
        if (target.accountUuid == null) {
          _refreshSessionFromEvents(target.storageId);
        }
      case MultisigRealtimeSignalType.inboxAvailable:
      case MultisigRealtimeSignalType.signingRequestChanged:
        final accountUuid = target.accountUuid;
        if (accountUuid != null) {
          _refreshAccount(accountUuid);
        }
    }
  }

  void _refreshSessionFromEvents(String storageId) {
    final existing = _sessionRefreshes[storageId];
    if (existing != null) return;

    late final Future<void> refresh;
    refresh =
        (() async {
          try {
            await ref
                .read(multisigPendingSessionsProvider.notifier)
                .refreshSessionFromEvents(storageId);
          } catch (e, st) {
            log('MultisigRealtime: session events refresh failed: $e\n$st');
          }
        })().whenComplete(() {
          if (identical(_sessionRefreshes[storageId], refresh)) {
            _sessionRefreshes.remove(storageId);
          }
        });
    _sessionRefreshes[storageId] = refresh;
  }

  void _refreshAccount(String accountUuid) {
    final existing = _accountRefreshes[accountUuid];
    if (existing != null) return;

    late final Future<void> refresh;
    refresh =
        (() async {
          try {
            await ref
                .read(multisigSigningRequestsProvider.notifier)
                .refreshForAccount(accountUuid);
          } catch (e, st) {
            log('MultisigRealtime: signing inbox refresh failed: $e\n$st');
          }
        })().whenComplete(() {
          if (identical(_accountRefreshes[accountUuid], refresh)) {
            _accountRefreshes.remove(accountUuid);
          }
        });
    _accountRefreshes[accountUuid] = refresh;
  }

  void _stopAll() {
    for (final connection in _connections.values.toList(growable: false)) {
      connection.dispose();
    }
    _connections.clear();
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    state = MultisigRealtimeState(
      isForeground: _isForeground,
      connections: {
        for (final entry in _connections.entries)
          entry.key: entry.value.snapshot(entry.key),
      },
    );
  }
}

class _MultisigRealtimeConnection {
  _MultisigRealtimeConnection({
    required this.owner,
    required MultisigRealtimeTarget target,
  }) : _target = target;

  final MultisigRealtimeNotifier owner;

  MultisigRealtimeTarget _target;
  WebSocket? _socket;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _retryAttempt = 0;
  int _leaseCount = 0;
  bool _desired = false;
  bool _connecting = false;
  bool _connected = false;
  bool _reconnecting = false;
  String? _lastError;

  MultisigRealtimeTarget get target => _target;

  bool get hasLeases => _leaseCount > 0;

  void updateTarget(MultisigRealtimeTarget target) {
    if (target.accessTokenExpiresAt < _target.accessTokenExpiresAt) {
      _target = target.withAuthFrom(
        _target,
        accountUuid: target.accountUuid ?? _target.accountUuid,
      );
      return;
    }
    _target = target;
  }

  void addLease(String reason) {
    _leaseCount += 1;
    log('MultisigRealtime: acquired $reason lease for ${_target.storageId}');
  }

  void releaseLease(String reason) {
    if (_leaseCount <= 0) return;
    _leaseCount -= 1;
    log('MultisigRealtime: released $reason lease for ${_target.storageId}');
  }

  void resumeIfLeased() {
    if (!hasLeases || _desired || _connecting || _connected) return;
    _desired = true;
    _generation += 1;
    final generation = _generation;
    unawaited(_connect(generation));
  }

  void suspend() {
    _desired = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _connecting = false;
    unawaited(_socket?.close(WebSocketStatus.normalClosure, 'suspended'));
    _socket = null;
    _connected = false;
  }

  void dispose() {
    _desired = false;
    _generation += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _connecting = false;
    unawaited(_socket?.close(WebSocketStatus.normalClosure, 'released'));
    _socket = null;
    _connected = false;
  }

  MultisigRealtimeConnectionSnapshot snapshot(String key) {
    return MultisigRealtimeConnectionSnapshot(
      connectionKey: key,
      sessionId: _target.sessionId,
      participantId: _target.participantId,
      leaseCount: _leaseCount,
      connected: _connected,
      connecting: _connecting,
      reconnecting: _reconnecting,
      lastError: _lastError,
    );
  }

  Future<void> _connect(int generation) async {
    if (!_desired || !owner._canConnect || generation != _generation) return;
    _connecting = true;
    _reconnecting = _retryAttempt > 0;
    _lastError = null;
    owner._publish();

    try {
      _target = await owner._targetWithFreshAccess(
        _target,
        force: _retryAttempt > 0,
      );
      if (!_shouldContinue(generation)) return;

      final socket = await WebSocket.connect(
        _webSocketUrl(_target.coordinatorUrl).toString(),
        headers: {'Authorization': 'Bearer ${_target.accessToken}'},
      );
      if (!_shouldContinue(generation)) {
        unawaited(socket.close(WebSocketStatus.normalClosure, 'stale'));
        return;
      }

      _socket = socket;
      _connected = true;
      _connecting = false;
      _reconnecting = false;
      _retryAttempt = 0;
      owner._publish();
      unawaited(owner._catchUp(this));

      await for (final raw in socket) {
        if (!_shouldContinue(generation)) break;
        final signal = _decodeSignal(raw);
        if (signal == null) continue;
        unawaited(owner._handleSignal(this, signal));
      }
    } catch (e, st) {
      _lastError = e.toString();
      log(
        'MultisigRealtime: websocket failed for ${_target.storageId}: $e\n$st',
      );
    } finally {
      if (generation == _generation) {
        _socket = null;
        _connected = false;
        _connecting = false;
        owner._publish();
        if (_desired && owner._canConnect) {
          _scheduleReconnect();
        }
      }
    }
  }

  bool _shouldContinue(int generation) {
    return _desired && owner._canConnect && generation == _generation;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _retryAttempt += 1;
    _reconnecting = true;
    owner._publish();

    final cappedAttempt = math.min(_retryAttempt, 6);
    final seconds = math.min(30, 1 << cappedAttempt);
    final jitterMs = math.Random().nextInt(500);
    _reconnectTimer = Timer(
      Duration(seconds: seconds, milliseconds: jitterMs),
      () {
        _reconnectTimer = null;
        if (!_desired || !owner._canConnect) return;
        _generation += 1;
        unawaited(_connect(_generation));
      },
    );
  }

  MultisigRealtimeSignal? _decodeSignal(Object? raw) {
    try {
      Object? decoded;
      if (raw is String) {
        decoded = jsonDecode(raw);
      } else if (raw is List<int>) {
        decoded = jsonDecode(utf8.decode(raw));
      } else {
        return null;
      }
      return MultisigRealtimeSignal.tryParse(decoded);
    } catch (e, st) {
      log('MultisigRealtime: failed to decode signal: $e\n$st');
      return null;
    }
  }
}

Uri _webSocketUrl(String coordinatorUrl) {
  final base = Uri.parse(coordinatorUrl);
  final scheme = switch (base.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    'ws' => 'ws',
    'wss' => 'wss',
    _ => throw StateError('Unsupported multisig websocket URL.'),
  };
  final basePath = base.path.isEmpty || base.path == '/'
      ? ''
      : base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(
    scheme: scheme,
    path: '$basePath/v2/ws',
    query: null,
    fragment: null,
  );
}

int? _readOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is BigInt) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
