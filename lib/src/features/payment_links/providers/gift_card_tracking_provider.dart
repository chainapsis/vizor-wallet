import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../rust/api/gift_card_tracking.dart' as rust;
import '../models/gift_card_usage.dart';
import '../services/gift_card_tracking_service.dart';
import '../services/payment_link_lifecycle_revision.dart';
import '../services/payment_link_recovery_store.dart';
import 'gift_card_tracking_lifecycle_provider.dart';

class GiftCardTrackingState {
  const GiftCardTrackingState({
    this.checking = false,
    this.failed = false,
    this.failedAddresses = const {},
  });
  final bool checking;

  /// Shared infrastructure failure; individual card failures live below.
  final bool failed;
  final Set<String> failedAddresses;

  bool failedFor(String address) => failed || failedAddresses.contains(address);
}

class GiftCardTrackingStateNotifier extends Notifier<GiftCardTrackingState> {
  @override
  GiftCardTrackingState build() => const GiftCardTrackingState();
  void update(
    bool checking,
    bool failed, [
    Set<String> failedAddresses = const {},
  ]) => state = GiftCardTrackingState(
    checking: checking,
    failed: failed,
    failedAddresses: Set.unmodifiable(failedAddresses),
  );
}

final giftCardTrackingStateProvider =
    NotifierProvider<GiftCardTrackingStateNotifier, GiftCardTrackingState>(
      GiftCardTrackingStateNotifier.new,
    );

final giftCardUsageProvider = FutureProvider.family<GiftCardUsage, String>((
  ref,
  address,
) async {
  ref.watch(paymentLinkLifecycleRevisionProvider);
  if (ref.watch(appSecurityProvider).requiresUnlock) {
    return const GiftCardUsage();
  }
  final cards = await ref.read(paymentLinkRecoveryStoreProvider).load();
  return cards.where((c) => c.link.address == address).firstOrNull?.usage ??
      const GiftCardUsage();
});

final giftCardTrackingBackendProvider = Provider<GiftCardTrackingBackend>(
  (ref) => RustGiftCardTrackingBackend(ref),
);

final giftCardTrackingServiceProvider = Provider((ref) {
  var foreground = true;
  var disposed = false;
  final service = GiftCardTrackingService(
    store: ref.read(paymentLinkRecoveryStoreProvider),
    backend: ref.read(giftCardTrackingBackendProvider),
    network: () => ref.read(rpcEndpointFailoverProvider).current.networkName,
    allowed: () =>
        !disposed &&
        foreground &&
        !ref.read(appSecurityProvider).requiresUnlock,
    onState: (checking, failed, failedAddresses) {
      if (!disposed) {
        ref
            .read(giftCardTrackingStateProvider.notifier)
            .update(checking, failed, failedAddresses);
      }
    },
  );
  final registry = ref.read(giftCardTrackingLifecycleProvider);
  registry.register(
    owner: service,
    quiesceAndDrain: service.quiesceAndDrain,
    resume: service.resume,
  );
  ref.listen(appSecurityProvider, (previous, next) {
    if (next.requiresUnlock) {
      service.pause();
    }
  });
  ref.listen(rpcEndpointFailoverProvider, (previous, next) {
    if (previous?.current.networkName != next.current.networkName) {
      service.pause();
    }
  });
  final listener = AppLifecycleListener(
    onHide: () {
      foreground = false;
      service.pause();
    },
    onPause: () {
      foreground = false;
      service.pause();
    },
    onResume: () {
      foreground = true;
    },
  );
  ref.onDispose(() {
    disposed = true;
    service.pause();
    registry.unregister(service);
    listener.dispose();
  });
  return service;
});

class RustGiftCardTrackingBackend implements GiftCardTrackingBackend {
  RustGiftCardTrackingBackend(this.ref);
  final Ref ref;
  String? _activePath;
  int _cancelEpoch = 0;
  Timer? _cancelTimer;

  Future<String> _path(String network) => getGiftCardTrackingDbPath(network);

  @override
  Future<String> register(PaymentLinkRecoveryRecord card) async {
    final path = await _path(card.link.network);
    final bytes = Uint8List.fromList(utf8.encode(card.link.mnemonic));
    try {
      return await rust.registerGiftCardObserver(
        dbPath: path,
        network: card.link.network,
        mnemonicBytes: bytes,
        address: card.link.address,
        birthdayHeight: BigInt.from(card.link.birthdayHeight),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<List<String>> accounts(String network) async =>
      rust.listGiftCardObservers(dbPath: await _path(network));

  @override
  Future<void> sync(String network) async {
    final epoch = _cancelEpoch;
    final path = await _path(network);
    if (epoch != _cancelEpoch) throw StateError('Gift Card scan cancelled');
    _activePath = path;
    try {
      await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback<void>(
            operation: 'Gift Card usage sync',
            action: (endpoint) {
              if (epoch != _cancelEpoch) {
                throw StateError('Gift Card scan cancelled');
              }
              if (endpoint.networkName != network) {
                throw StateError('Gift Card network changed');
              }
              return rust.syncGiftCardObservers(
                dbPath: path,
                network: network,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              );
            },
          );
    } finally {
      _activePath = null;
      _cancelTimer?.cancel();
      _cancelTimer = null;
    }
  }

  @override
  Future<GiftCardUsage> inspect(PaymentLinkRecoveryRecord card) async {
    final epoch = _cancelEpoch;
    final path = await _path(card.link.network);
    if (epoch != _cancelEpoch) throw StateError('Gift Card lookup cancelled');
    _activePath = path;
    try {
      final e = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'Gift Card funding status',
            action: (endpoint) {
              if (epoch != _cancelEpoch) {
                throw StateError('Gift Card lookup cancelled');
              }
              if (endpoint.networkName != card.link.network) {
                throw StateError('Gift Card network changed');
              }
              return rust.inspectGiftCardUsage(
                dbPath: path,
                accountUuid: card.usage.accountUuid!,
                fundingTxids: card.fundingTxids ?? '',
                expectedFundingZatoshi:
                    card.link.amountZatoshi + card.claimFeeReserveZatoshi,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              );
            },
          );
      return GiftCardUsage(
        status: GiftCardUsageStatus.values.byName(e.status),
        reason: e.reason == null
            ? null
            : GiftCardUsageReason.values.byName(e.reason!),
        accountUuid: card.usage.accountUuid,
        checkedAt: DateTime.now().toUtc(),
        verifiedHeight: e.verifiedHeight.toInt(),
        spentHeight: e.spentHeight.toInt(),
        spendingTxids: e.spendingTxids,
        cleanupPending: e.canDelete,
      );
    } finally {
      _activePath = null;
      _cancelTimer?.cancel();
      _cancelTimer = null;
    }
  }

  @override
  Future<void> remove(String network, String accountUuid) async =>
      rust.removeGiftCardObserver(
        dbPath: await _path(network),
        network: network,
        accountUuid: accountUuid,
      );

  @override
  void cancel() {
    _cancelEpoch++;
    final path = _activePath;
    if (path == null) return;
    rust.cancelGiftCardObserverSync(dbPath: path);
    _cancelTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_activePath == path) rust.cancelGiftCardObserverSync(dbPath: path);
    });
  }
}
