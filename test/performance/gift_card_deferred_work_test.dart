import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_store_codec.dart';

int _isolateId(int _) => Isolate.current.hashCode;

void main() {
  test(
    'large codec runs off the caller isolate; small codec stays local',
    () async {
      final caller = Isolate.current.hashCode;
      expect(
        await runPaymentLinkStoreCodec(_isolateId, 0, inBackground: false),
        caller,
      );
      expect(
        await runPaymentLinkStoreCodec(_isolateId, 0, inBackground: true),
        isNot(caller),
      );
    },
  );

  test(
    'native compatibility decoding yields between groups and retains order',
    () async {
      var eventRan = false;
      Timer.run(() => eventRan = true);
      final decoded = await finishPaymentLinkStoreDecode<int>([
        0,
        for (var i = 1; i < 30; i++) '$i',
      ], (item) => int.parse(item as String));
      expect(eventRan, isTrue);
      expect(decoded, List.generate(30, (i) => i));
      await expectLater(
        finishPaymentLinkStoreDecode<int>([
          'invalid',
        ], (_) => throw const FormatException()),
        throwsFormatException,
      );
    },
  );

  test(
    'background decode preserves typed errors and does not poison store queues',
    () async {
      final invalid = jsonEncode({
        'version': 1,
        'records': [{}],
        'padding': 'x' * 20000,
      });
      final createdStorage = _CreatedStorage()..value = invalid;
      final receivedStorage = _ReceivedStorage()..value = invalid;
      final created = PaymentLinkRecoveryStore(createdStorage);
      final received = PaymentLinkReceivedStore(receivedStorage);
      await expectLater(
        created.load(),
        throwsA(isA<PaymentLinkRecoveryStoreFormatException>()),
      );
      await expectLater(
        received.load(),
        throwsA(isA<PaymentLinkReceivedStoreFormatException>()),
      );
      expect(createdStorage.value, invalid);
      expect(receivedStorage.value, invalid);
      final empty = jsonEncode({'version': 1, 'records': []});
      createdStorage.value = empty;
      receivedStorage.value = empty;
      expect(await created.load(), isEmpty);
      expect(await received.load(), isEmpty);
    },
  );

  for (final count in [30, 300, 1000]) {
    test(
      '$count saved cards preserve data while deferred work yields to UI events',
      () async {
        final createdStorage = _CreatedStorage();
        final created = PaymentLinkRecoveryStore(createdStorage);
        final receivedStorage = _ReceivedStorage();
        final received = PaymentLinkReceivedStore(receivedStorage);
        final link = VizorPaymentLink(
          network: 'main',
          address: 'u1card-0',
          amountZatoshi: BigInt.from(100000),
          mnemonic:
              'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
          birthdayHeight: 100,
          label: 'Payment link',
          createdAt: DateTime.utc(2026, 9, 1),
        );
        await created.saveDraft(
          link: link,
          sourceAccountUuid: 'source-account',
          claimFeeReserveZatoshi: BigInt.from(10000),
        );
        await created.markFunded(
          address: link.address,
          fundingTxids: 'ab' * 32,
        );
        await received.saveReady(link);
        String multiply(String raw) {
          final envelope = jsonDecode(raw) as Map<String, dynamic>;
          final row =
              (envelope['records'] as List).single as Map<String, dynamic>;
          envelope['records'] = [
            for (var i = 0; i < count; i++) {...row, 'address': 'u1card-$i'},
          ];
          return jsonEncode(envelope);
        }

        createdStorage.value = multiply(createdStorage.value!);
        receivedStorage.value = multiply(receivedStorage.value!);
        final watch = Stopwatch()..start();
        var ticks = 0;
        var lastTick = 0;
        var maxGapUs = 0;
        final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
          ticks++;
          final now = watch.elapsedMicroseconds;
          if (now - lastTick > maxGapUs) maxGapUs = now - lastTick;
          lastTick = now;
        });
        try {
          final records = await created.load();
          final createdLoadUs = watch.elapsedMicroseconds;
          expect(records.length, count);
          expect(records.last.link.address, 'u1card-${count - 1}');
          final receiptStart = watch.elapsedMicroseconds;
          final receipts = await received.load();
          final receivedLoadUs = watch.elapsedMicroseconds - receiptStart;
          expect(receipts.length, count);
          expect(receipts.last.claimLink!.mnemonic, link.mnemonic);
          final updateStart = watch.elapsedMicroseconds;
          final saved = await created.updateUsages([
            for (final record in records)
              (
                expected: record,
                usage: const GiftCardUsage(status: GiftCardUsageStatus.unused),
              ),
          ]);
          final updateUs = watch.elapsedMicroseconds - updateStart;
          expect(saved.length, count);
          expect(
            (await created.load()).every(
              (row) => row.usage.status == GiftCardUsageStatus.unused,
            ),
            isTrue,
          );
          await received.setAvailability(
            link.address,
            PaymentLinkAvailability.available,
          );
          expect(
            (await received.load()).first.availability,
            PaymentLinkAvailability.available,
          );
          // Diagnostics, not a machine-dependent frame-duration assertion. The
          // heartbeat catches event starvation; native device profiling is separate.
          final lastGap = watch.elapsedMicroseconds - lastTick;
          if (lastGap > maxGapUs) maxGapUs = lastGap;
          debugPrintSynchronously(
            'cards=$count createdLoadUs=$createdLoadUs receivedLoadUs=$receivedLoadUs updateUs=$updateUs heartbeatTicks=$ticks maxEventGapUs=$maxGapUs',
          );
          expect(ticks, greaterThan(0));
        } finally {
          heartbeat.cancel();
          watch.stop();
        }
      },
    );
  }
}

class _CreatedStorage implements PaymentLinkRecoveryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _ReceivedStorage implements PaymentLinkReceivedStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
