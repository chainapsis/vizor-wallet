import 'dart:async';

import '../models/gift_card_usage.dart';
import 'payment_link_recovery_store.dart';

/// A narrow observer-only boundary, independently replaceable in tests.
abstract interface class GiftCardTrackingBackend {
  Future<String> register(PaymentLinkRecoveryRecord card);
  Future<void> sync(String network);
  Future<List<String>> accounts(String network);
  Future<GiftCardUsage> inspect(PaymentLinkRecoveryRecord card);
  Future<void> remove(String network, String accountUuid);
  void cancel();
}

/// How long after funding submission an unobserved card reads as confirming.
///
/// Funding is observed only through the observer's own block scan, never by
/// querying lightwalletd for the funding txid, so a card cannot see its funding
/// transaction until it is mined and scanned. About eight target block times.
const giftCardConfirmingWindow = Duration(minutes: 10);

/// One owner serializes registration, scans and deletion. Durable card records
/// are the registration intents; an interrupted import is repaired idempotently.
class GiftCardTrackingService {
  GiftCardTrackingService({
    required this.store,
    required this.backend,
    required this.network,
    required this.allowed,
    required this.onState,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final PaymentLinkRecoveryStore store;
  final GiftCardTrackingBackend backend;
  final String Function() network;
  final bool Function() allowed;
  final void Function(bool checking, bool failed, Set<String> failedAddresses)
  onState;
  final DateTime Function() now;
  Future<void> _tail = Future.value();
  Future<void>? _refresh;
  int _epoch = 0;
  bool _quiesced = false;
  DateTime? _lastSync;
  String? _lastNetwork;

  bool _valid(int epoch) => epoch == _epoch && !_quiesced && allowed();

  Future<void> _enqueue(Future<void> Function(int epoch) work) {
    final epoch = _epoch;
    final result = _tail.then((_) async {
      if (_valid(epoch)) await work(epoch);
    });
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  /// Presents a recently funded card whose funding is not yet scanned as
  /// confirming. After the window it stays unverified, which then signals a
  /// funding transaction that did not confirm.
  GiftCardUsage _confirmingWithinWindow(
    PaymentLinkRecoveryRecord card,
    GiftCardUsage usage,
  ) {
    final elapsed = now().difference(card.updatedAt);
    if (usage.reason != GiftCardUsageReason.fundingNotObserved ||
        card.state == PaymentLinkRecoveryState.draft ||
        elapsed.isNegative ||
        elapsed >= giftCardConfirmingWindow) {
      return usage;
    }
    return GiftCardUsage(
      status: usage.status,
      reason: GiftCardUsageReason.awaitingConfirmation,
      accountUuid: usage.accountUuid,
      checkedAt: usage.checkedAt,
      verifiedHeight: usage.verifiedHeight,
      spentHeight: usage.spentHeight,
      spendingTxids: usage.spendingTxids,
      cleanupPending: usage.cleanupPending,
    );
  }

  Future<void> register(PaymentLinkRecoveryRecord card) =>
      _enqueue((epoch) async {
        final records = await store.load();
        if (!_valid(epoch)) return;
        final current = records
            .where((c) => c.link.hasSameCanonicalPayload(card.link))
            .firstOrNull;
        if (current == null ||
            current.link.network != network() ||
            current.usage.cleaned ||
            current.usage.cleanupPending) {
          return;
        }
        final uuid = await backend.register(current);
        if (!_valid(epoch)) return;
        await store.updateUsage(
          expected: current,
          usage: current.usage.withAccount(uuid),
        );
        _lastSync = null;
      });

  Future<void> refresh({bool force = false}) {
    final existing = _refresh;
    if (existing != null) return existing;
    late final Future<void> result;
    result =
        _enqueue((epoch) async {
          final currentNetwork = network();
          if (!force &&
              _lastNetwork == currentNetwork &&
              _lastSync != null &&
              now().difference(_lastSync!) < const Duration(seconds: 30)) {
            return;
          }
          onState(true, false, const {});
          var failed = false;
          final failedAddresses = <String>{};
          var canCleanOrphans = true;
          try {
            var cards = (await store.load())
                .where(
                  (c) => c.link.network == currentNetwork && !c.usage.cleaned,
                )
                .toList();
            if (!_valid(epoch)) return;
            final knownAccounts = (await backend.accounts(
              currentNetwork,
            )).toSet();
            for (final card in cards) {
              if (!_valid(epoch) || network() != currentNetwork) return;
              // Recover deletion after a crash without recreating the removed account.
              if (card.usage.cleanupPending) {
                try {
                  await backend.remove(currentNetwork, card.usage.accountUuid!);
                } catch (_) {
                  failedAddresses.add(card.link.address);
                  continue;
                }
                if (!_valid(epoch)) return;
                await store.updateUsage(
                  expected: card,
                  usage: card.usage.afterCleanup(),
                );
                continue;
              }
              if (knownAccounts.contains(card.usage.accountUuid)) continue;
              late final String uuid;
              try {
                uuid = await backend.register(card);
              } catch (_) {
                failedAddresses.add(card.link.address);
                // A failed response may follow a committed native import.
                // Do not mistake its not-yet-recorded UUID for an orphan.
                canCleanOrphans = false;
                continue;
              }
              if (!_valid(epoch)) return;
              if (card.usage.accountUuid != uuid) {
                final saved = await store.updateUsage(
                  expected: card,
                  usage: card.usage.withAccount(uuid),
                );
                if (!saved) canCleanOrphans = false;
              }
            }
            if (!_valid(epoch)) return;
            final retained = (await store.load())
                .where(
                  (c) => c.link.network == currentNetwork && !c.usage.cleaned,
                )
                .map((c) => c.usage.accountUuid)
                .whereType<String>()
                .toSet();
            final registered = await backend.accounts(currentNetwork);
            for (final uuid in registered) {
              if (!_valid(epoch)) return;
              if (canCleanOrphans && !retained.contains(uuid)) {
                try {
                  await backend.remove(currentNetwork, uuid);
                } catch (_) {
                  // No card owns this account. Retry housekeeping on the next
                  // refresh without blocking live cards or marking them failed.
                }
              }
            }
            if (!_valid(epoch)) return;
            cards = (await store.load())
                .where(
                  (c) =>
                      c.link.network == currentNetwork &&
                      !c.usage.cleaned &&
                      !failedAddresses.contains(c.link.address) &&
                      !c.usage.cleanupPending &&
                      c.usage.accountUuid != null,
                )
                .toList();
            if (cards.any((c) => c.fundingTxids?.trim().isNotEmpty ?? false)) {
              await backend.sync(currentNetwork);
            }
            if (!_valid(epoch) || network() != currentNetwork) return;
            for (final card in cards) {
              if (!_valid(epoch) || network() != currentNetwork) return;
              late final GiftCardUsage observation;
              try {
                observation = _confirmingWithinWindow(
                  card,
                  await backend.inspect(card),
                );
                GiftCardUsage.fromJson(observation.toJson());
              } catch (_) {
                failedAddresses.add(card.link.address);
                continue;
              }
              if (!_valid(epoch)) return;
              // No history is not proof of a reorg or a failed broadcast. Preserve
              // the prior snapshot but do not claim it was freshly verified.
              if (observation.status == GiftCardUsageStatus.unknown &&
                  card.usage.status != GiftCardUsageStatus.unknown) {
                continue;
              }
              final saved = await store.updateUsage(
                expected: card,
                usage: observation,
              );
              if (!_valid(epoch)) return;
              if (saved && observation.cleanupPending) {
                try {
                  await backend.remove(
                    currentNetwork,
                    observation.accountUuid!,
                  );
                } catch (_) {
                  failedAddresses.add(card.link.address);
                  continue;
                }
                if (!_valid(epoch)) return;
                await store.updateUsage(
                  expected: card.copyWith(
                    state: card.state,
                    updatedAt: card.updatedAt,
                    usage: observation,
                  ),
                  usage: observation.afterCleanup(),
                );
              }
            }
            _lastNetwork = currentNetwork;
            _lastSync = now();
          } catch (_) {
            failed = true;
            rethrow;
          } finally {
            if (_valid(epoch)) {
              onState(false, failed, Set.unmodifiable(failedAddresses));
            }
          }
        }).whenComplete(() {
          if (identical(_refresh, result)) _refresh = null;
        });
    _refresh = result;
    return result;
  }

  void pause() {
    _epoch++;
    _lastSync = null;
    backend.cancel();
    onState(false, false, const {});
  }

  Future<void> quiesceAndDrain() async {
    _quiesced = true;
    pause();
    // Also cover cancellation arriving just before the native worker registers
    // its scan token. Never delete a DB until its worker has actually exited.
    final timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => backend.cancel(),
    );
    try {
      await _tail;
    } finally {
      timer.cancel();
    }
  }

  void resume() {
    _quiesced = false;
    _lastSync = null;
  }
}
