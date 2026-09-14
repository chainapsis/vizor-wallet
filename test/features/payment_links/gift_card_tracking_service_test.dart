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
  bool remaining = false;
  bool failRemove = false;
  void Function()? beforeInspect;
  @override
  Future<String> register(PaymentLinkRecoveryRecord card) async {
    events.add('register');
    ids.add(card.link.address);
    return card.link.address;
  }

  @override
  Future<List<String>> accounts(String network) async => ids.toList();
  @override
  Future<void> sync(String network) async {
    events.add('sync');
    await scan?.future;
  }

  @override
  Future<GiftCardUsage> inspect(PaymentLinkRecoveryRecord card) async {
    beforeInspect?.call();
    return GiftCardUsage(
      status: used ? GiftCardUsageStatus.used : GiftCardUsageStatus.unused,
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
    if (failRemove) throw StateError('busy');
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
  setUp(() {
    storage = MemoryStorage();
    store = PaymentLinkRecoveryStore(storage);
    backend = Backend();
    allowed = true;
    states = [];
    service = GiftCardTrackingService(
      store: store,
      backend: backend,
      network: () => 'main',
      allowed: () => allowed,
      onState: (checking, failed) => states.add((checking, failed)),
    );
  });
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
      await expectLater(service.refresh(), throwsStateError);
      final usage = (await store.load()).single.usage;
      expect(usage.status, GiftCardUsageStatus.used);
      expect(usage.cleanupPending, isTrue);
      expect(states.last, (false, true));
      backend.failRemove = false;
      backend.events.clear();
      await service.refresh();
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
