import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_card_tracking_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';

final _txid = 'aa' * 32;
final _spent = 'bb' * 32;

class MemoryStorage implements PaymentLinkRecoveryStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    if (fail) throw StateError('disk full');
    value = text;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class Backend implements GiftCardTrackingBackend {
  final events = <String>[];
  final ids = <String>{};
  Completer<void>? scan;
  bool used = false;
  GiftCardUsageReason? reason;
  bool remaining = false;
  bool failRemove = false;
  bool failSync = false;
  final failRegister = <String>{};
  final failAfterRegister = <String>{};
  final failInspect = <String>{};
  final failRemoves = <String>{};
  final inspected = <String>[];
  void Function()? afterRegister;
  void Function()? onInspectFailure;
  void Function()? beforeInspect;
  @override
  Future<String> register(PaymentLinkRecoveryRecord card) async {
    events.add('register');
    if (failRegister.contains(card.link.address)) throw StateError('bad card');
    ids.add(card.link.address);
    afterRegister?.call();
    if (failAfterRegister.contains(card.link.address)) {
      throw StateError('response lost');
    }
    return card.link.address;
  }

  @override
  Future<List<String>> accounts(String network) async => ids.toList();
  @override
  Future<void> sync(String network) async {
    events.add('sync');
    if (failSync) throw StateError('offline');
    await scan?.future;
  }

  @override
  Future<GiftCardUsage> inspect(PaymentLinkRecoveryRecord card) async {
    inspected.add(card.link.address);
    if (failInspect.contains(card.link.address)) {
      onInspectFailure?.call();
      throw StateError('bad observation');
    }
    beforeInspect?.call();
    return GiftCardUsage(
      status: reason != null
          ? GiftCardUsageStatus.unknown
          : used
          ? GiftCardUsageStatus.used
          : GiftCardUsageStatus.unused,
      reason: reason,
      accountUuid: card.usage.accountUuid,
      checkedAt: DateTime.utc(2026),
      verifiedHeight: 106,
      spentHeight: used ? 101 : 0,
      spendingTxids: used ? [_spent] : [],
      cleanupPending: used && !remaining,
    );
  }

  @override
  Future<void> remove(String network, String uuid) async {
    events.add('remove');
    if (failRemove || failRemoves.contains(uuid)) throw StateError('busy');
    ids.remove(uuid);
  }

  @override
  void cancel() {
    events.add('cancel');
    if (scan != null && !scan!.isCompleted) scan!.complete();
  }
}

Future<PaymentLinkRecoveryRecord> seed(
  PaymentLinkRecoveryStore store, {
  String address = 'card',
}) async {
  await store.saveDraft(
    link: VizorPaymentLink(
      network: 'main',
      address: address,
      amountZatoshi: BigInt.from(10000000),
      mnemonic: List.filled(24, 'word').join(' '),
      birthdayHeight: 90,
      label: 'Gift Card',
      createdAt: DateTime.utc(2026),
    ),
    sourceAccountUuid: 'source',
    claimFeeReserveZatoshi: BigInt.from(10000),
  );
  return store.markFunded(address: address, fundingTxids: _txid);
}

void main() {
  late MemoryStorage storage;
  late PaymentLinkRecoveryStore store;
  late Backend backend;
  late GiftCardTrackingService service;
  late bool allowed;
  late List<(bool, bool)> states;
  late Set<String> failedAddresses;
  late DateTime clock;
  setUp(() {
    storage = MemoryStorage();
    store = PaymentLinkRecoveryStore(storage);
    backend = Backend();
    allowed = true;
    states = [];
    failedAddresses = {};
    clock = DateTime.utc(2026);
    service = GiftCardTrackingService(
      store: store,
      backend: backend,
      network: () => 'main',
      now: () => clock,
      allowed: () => allowed,
      onState: (checking, failed, addresses) {
        states.add((checking, failed));
        failedAddresses = addresses;
      },
    );
  });
  test(
    'pending reason survives failure and clears after funding is verified',
    () async {
      await seed(store);
      backend.reason = GiftCardUsageReason.awaitingConfirmation;
      await service.refresh();
      expect((await store.load()).single.usage.reason, backend.reason);
      backend.failInspect.add('card');
      await service.refresh(force: true);
      expect((await store.load()).single.usage.reason, backend.reason);
      expect(failedAddresses, {'card'});
      backend.failInspect.clear();
      backend.reason = null;
      await service.refresh(force: true);
      final usage = (await store.load()).single.usage;
      expect(usage.status, GiftCardUsageStatus.unused);
      expect(usage.reason, isNull);
    },
  );
  test(
    'unobserved funding reads as confirming only within the window',
    () async {
      await seed(store);
      await store.markFunded(
        address: 'card',
        fundingTxids: _txid,
        updatedAt: clock,
      );
      backend.reason = GiftCardUsageReason.fundingNotObserved;
      clock = clock.add(giftCardConfirmingWindow - const Duration(seconds: 1));
      await service.refresh();
      var usage = (await store.load()).single.usage;
      expect(usage.status, GiftCardUsageStatus.unknown);
      expect(usage.reason, GiftCardUsageReason.awaitingConfirmation);
      clock = clock.add(const Duration(seconds: 1));
      await service.refresh(force: true);
      usage = (await store.load()).single.usage;
      expect(usage.reason, GiftCardUsageReason.fundingNotObserved);
      backend.reason = null;
      await service.refresh(force: true);
      expect(
        (await store.load()).single.usage.status,
        GiftCardUsageStatus.unused,
      );
    },
  );
  test(
    'legacy cards load unknown and gain a durable observer lazily',
    () async {
      await seed(store);
      final json = jsonDecode(storage.value!);
      json['records'][0].remove('usage');
      storage.value = jsonEncode(json);
      expect(
        (await store.load()).single.usage.status,
        GiftCardUsageStatus.unknown,
      );
      await service.refresh();
      expect(
        (await store.load()).single.usage.status,
        GiftCardUsageStatus.unused,
      );
      expect(backend.events, ['register', 'sync']);
    },
  );
  test(
    'multiple cards share one scan and concurrent refresh joins it',
    () async {
      await seed(store);
      await seed(store, address: 'second');
      backend.scan = Completer();
      final a = service.refresh();
      final b = service.refresh();
      expect(identical(a, b), isTrue);
      await Future<void>.delayed(Duration.zero);
      backend.scan!.complete();
      await a;
      expect(backend.events.where((e) => e == 'sync'), hasLength(1));
      expect(
        (await store.load()).every(
          (c) => c.usage.status == GiftCardUsageStatus.unused,
        ),
        isTrue,
      );
    },
  );
  test(
    'used is durable before deletion; restart retries cleanup only',
    () async {
      await seed(store);
      backend.used = true;
      backend.failRemove = true;
      await service.refresh();
      final usage = (await store.load()).single.usage;
      expect(usage.status, GiftCardUsageStatus.used);
      expect(usage.cleanupPending, isTrue);
      expect(states.last, (false, false));
      expect(failedAddresses, {'card'});
      backend.failRemove = false;
      backend.events.clear();
      await service.refresh(force: true);
      expect(backend.events, ['remove']);
      expect((await store.load()).single.usage.cleaned, isTrue);
      backend.events.clear();
      await service.refresh(force: true);
      expect(backend.events, isEmpty);
    },
  );
  test('storage failure never deletes the observer', () async {
    await seed(store);
    backend.used = true;
    backend.beforeInspect = () => storage.fail = true;
    await expectLater(service.refresh(), throwsStateError);
    expect(backend.events, isNot(contains('remove')));
  });
  test('positive topups retain an observer after used is recorded', () async {
    await seed(store);
    backend.used = true;
    backend.remaining = true;
    await service.refresh();
    expect((await store.load()).single.usage.status, GiftCardUsageStatus.used);
    expect((await store.load()).single.usage.cleaned, isFalse);
    expect(backend.events, isNot(contains('remove')));
  });
  test(
    'lock during scan discards late observations and drains cancellation',
    () async {
      await seed(store);
      backend.scan = Completer();
      final task = service.refresh();
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      await service.quiesceAndDrain();
      await task;
      expect((await store.load()).single.usage.checkedAt, isNull);
      expect(backend.events, isNot(contains('remove')));
    },
  );
  test('queued registration cannot resurrect a reset wallet', () async {
    final card = await seed(store);
    await service.quiesceAndDrain();
    await service.register(card);
    expect(backend.ids, isEmpty);
  });
  test('removed inert drafts retire their observer on next refresh', () async {
    backend.ids.add('orphan');
    await service.refresh();
    expect(backend.ids, isEmpty);
  });
  test(
    'funding/share changes preserve usage and stale funding cannot write',
    () async {
      final card = await seed(store);
      await service.refresh();
      expect(
        await store.updateUsage(expected: card, usage: const GiftCardUsage()),
        isFalse,
      );
      final fresh = (await store.load()).single;
      await store.markShared(address: card.link.address);
      expect(
        (await store.load()).single.usage.accountUuid,
        fresh.usage.accountUuid,
      );
    },
  );
  test(
    'late registration cannot recreate a removed draft after reset',
    () async {
      final old = await seed(store);
      await service.quiesceAndDrain();
      await storage.delete();
      service.resume();
      await service.register(old);
      expect(backend.ids, isEmpty);
    },
  );
  test(
    'new wallet cards can be observed after reset releases its fence',
    () async {
      await seed(store);
      await service.refresh();
      await service.quiesceAndDrain();
      await storage.delete();
      backend.ids.clear();
      service.resume();
      await seed(store, address: 'new-wallet-card');
      await service.refresh();
      expect(backend.ids, {'new-wallet-card'});
      expect(
        (await store.load()).single.usage.status,
        GiftCardUsageStatus.unused,
      );
    },
  );
  test(
    'refresh reuses registered accounts without deriving secrets again',
    () async {
      await seed(store);
      await service.refresh();
      backend.events.clear();
      await service.refresh(force: true);
      expect(backend.events, ['sync']);
    },
  );
  test(
    'registration failure preserves the card and allows later cards to sync',
    () async {
      await seed(store, address: 'bad');
      await seed(store, address: 'good');
      backend.failRegister.add('bad');
      await service.refresh();
      final cards = await store.load();
      expect(cards.first.usage.accountUuid, isNull);
      expect(cards.last.usage.status, GiftCardUsageStatus.unused);
      expect(backend.inspected, ['good']);
      expect(failedAddresses, {'bad'});
      expect(states.last, (false, false));
      backend.failRegister.clear();
      await service.refresh();
      expect(failedAddresses, {'bad'}); // Cooldown preserves the last result.
      clock = clock.add(const Duration(seconds: 30));
      await service.refresh();
      expect(failedAddresses, isEmpty);
      expect(
        (await store.load()).every(
          (c) => c.usage.status == GiftCardUsageStatus.unused,
        ),
        isTrue,
      );
    },
  );
  test('lost registration response never triggers orphan deletion', () async {
    await seed(store, address: 'bad');
    await seed(store, address: 'good');
    backend.failAfterRegister.add('bad');
    await service.refresh();
    expect(backend.ids, {'bad', 'good'});
    expect(backend.events, isNot(contains('remove')));
    expect(backend.inspected, ['good']);
    backend.failAfterRegister.clear();
    await service.refresh(force: true);
    expect((await store.load()).first.usage.accountUuid, 'bad');
    expect(failedAddresses, isEmpty);
  });
  test(
    'registration metadata storage failure aborts before cleanup or sync',
    () async {
      await seed(store);
      backend.afterRegister = () => storage.fail = true;
      await expectLater(service.refresh(), throwsStateError);
      expect(backend.ids, {'card'});
      expect(backend.events, ['register']);
      expect(states.last, (false, true));
    },
  );
  test(
    'stale registration receipt defers orphan cleanup until retry',
    () async {
      await seed(store);
      backend.afterRegister = () {
        unawaited(
          store.markFunded(address: 'card', fundingTxids: _spent).then((_) {}),
        );
      };
      await service.refresh();
      expect((await store.load()).single.usage.accountUuid, isNull);
      expect(backend.ids, {'card'});
      expect(backend.events, ['register']);
      backend.afterRegister = null;
      await service.refresh(force: true);
      expect(
        (await store.load()).single.usage.status,
        GiftCardUsageStatus.unused,
      );
      expect(failedAddresses, isEmpty);
    },
  );
  test(
    'inspection failure preserves its snapshot and updates later cards',
    () async {
      await seed(store, address: 'bad');
      await seed(store, address: 'good');
      await service.refresh();
      final snapshot = (await store.load()).first.usage.toJson();
      backend.failInspect.add('bad');
      backend.used = true;
      await service.refresh(force: true);
      final cards = await store.load();
      expect(cards.first.usage.toJson(), snapshot);
      expect(cards.last.usage.cleaned, isTrue);
      expect(failedAddresses, {'bad'});
      backend.failInspect.clear();
      await service.refresh(force: true);
      expect((await store.load()).first.usage.cleaned, isTrue);
      expect(failedAddresses, isEmpty);
    },
  );
  test('cleanup failure and its retry never block another card', () async {
    await seed(store, address: 'bad');
    await seed(store, address: 'good');
    backend.used = true;
    backend.failRemoves.add('bad');
    await service.refresh();
    expect((await store.load()).first.usage.cleanupPending, isTrue);
    expect((await store.load()).last.usage.cleaned, isTrue);
    await seed(store, address: 'new');
    await service.refresh(force: true);
    expect((await store.load()).last.usage.cleaned, isTrue);
    expect(failedAddresses, {'bad'});
    backend.failRemoves.clear();
    await service.refresh(force: true);
    expect((await store.load()).every((c) => c.usage.cleaned), isTrue);
    expect(failedAddresses, isEmpty);
  });
  test('orphan cleanup failure does not mark or block a live card', () async {
    backend.ids.add('orphan');
    backend.failRemoves.add('orphan');
    await seed(store);
    await service.refresh();
    expect(
      (await store.load()).single.usage.status,
      GiftCardUsageStatus.unused,
    );
    expect(failedAddresses, isEmpty);
    backend.failRemoves.clear();
    await service.refresh(force: true);
    expect(backend.ids, {'card'});
  });
  test(
    'shared scan failure aborts all inspections and retains observers',
    () async {
      await seed(store, address: 'a');
      await seed(store, address: 'b');
      backend.failSync = true;
      await expectLater(service.refresh(), throwsStateError);
      expect(backend.inspected, isEmpty);
      expect(backend.ids, {'a', 'b'});
      expect(states.last, (false, true));
    },
  );
  test(
    'pause during failed inspection still stops the remaining cards',
    () async {
      await seed(store, address: 'bad');
      await seed(store, address: 'good');
      backend.failInspect.add('bad');
      backend.onInspectFailure = service.pause;
      await service.refresh();
      expect(backend.inspected, ['bad']);
      expect(failedAddresses, isEmpty);
      expect(states.last, (false, false));
    },
  );
  test('corrupt terminal observations are rejected', () {
    expect(
      () => GiftCardUsage.fromJson(
        const GiftCardUsage(
          status: GiftCardUsageStatus.used,
          cleaned: true,
        ).toJson(),
      ),
      throwsFormatException,
    );
  });
}
