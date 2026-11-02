import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/wallet_pir/wallet_pir_latency.dart';

void main() {
  test('a successful HTTPS response produces a latency sample', () async {
    final sample = await measureWalletPirPing(() async => 200);
    expect(sample.status, WalletPirPingStatus.available);
    expect(sample.label, endsWith('ms'));
  });

  test('error statuses and transport failures are unavailable', () async {
    for (final status in [301, 404, 503]) {
      expect(
        (await measureWalletPirPing(() async => status)).status,
        WalletPirPingStatus.unavailable,
      );
    }
    expect(
      (await measureWalletPirPing(
        () async => throw TimeoutException('offline'),
      )).status,
      WalletPirPingStatus.unavailable,
    );
  });

  testWidgets('pings repeat every ten seconds and stop when hidden', (
    tester,
  ) async {
    var calls = 0;
    final monitor = WalletPirLatencyMonitor(
      probe: (_, _) async {
        calls++;
        return const WalletPirPingSample.available(Duration(milliseconds: 42));
      },
      onChanged: () {},
    );
    monitor.updateTargets(['https://a.example']);
    monitor.resume();
    await tester.pump();
    expect(calls, 1);
    expect(monitor.samples['https://a.example']?.label, '42ms');
    await tester.pump(const Duration(seconds: 9));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    monitor.pause();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    monitor.resume();
    await tester.pump();
    expect(calls, 3);
    monitor.dispose();
  });

  testWidgets('a slow round is not overlapped by the next timer tick', (
    tester,
  ) async {
    var calls = 0;
    final reply = Completer<WalletPirPingSample>();
    final monitor = WalletPirLatencyMonitor(
      probe: (_, _) {
        calls++;
        return reply.future;
      },
      onChanged: () {},
    );
    monitor.updateTargets(['https://a.example']);
    monitor.resume();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 1);
    reply.complete(const WalletPirPingSample.unavailable());
    await tester.pump();
    monitor.dispose();
  });

  testWidgets(
    'removing a target cancels its request and ignores its late reply',
    (tester) async {
      final oldReply = Completer<WalletPirPingSample>();
      Future<void>? oldCancellation;
      final monitor = WalletPirLatencyMonitor(
        probe: (url, cancelled) async {
          if (url == 'https://a.example') {
            oldCancellation = cancelled;
            return oldReply.future;
          }
          return const WalletPirPingSample.available(Duration(milliseconds: 9));
        },
        onChanged: () {},
      );
      monitor.updateTargets(['https://a.example']);
      monitor.resume();
      var cancelled = false;
      oldCancellation!.then((_) => cancelled = true);
      monitor.updateTargets(['https://b.example']);
      await tester.pump();
      expect(cancelled, isTrue);
      oldReply.complete(
        const WalletPirPingSample.available(Duration(milliseconds: 1)),
      );
      await tester.pump();
      expect(monitor.samples.keys, ['https://b.example']);
      expect(monitor.samples['https://b.example']?.label, '9ms');
      monitor.dispose();
    },
  );

  testWidgets(
    'closing cancels pending pings without publishing another update',
    (tester) async {
      final reply = Completer<WalletPirPingSample>();
      var updates = 0;
      var cancelled = false;
      final monitor = WalletPirLatencyMonitor(
        probe: (_, signal) {
          signal.then((_) => cancelled = true);
          return reply.future;
        },
        onChanged: () => updates++,
      );
      monitor.updateTargets(['https://a.example']);
      monitor.resume();
      final beforeClose = updates;
      monitor.dispose();
      reply.complete(
        const WalletPirPingSample.available(Duration(milliseconds: 1)),
      );
      await tester.pump();
      expect(cancelled, isTrue);
      expect(updates, beforeClose);
    },
  );
}
