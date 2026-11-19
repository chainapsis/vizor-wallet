import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/shared_payment_inbox.dart';
import 'package:zcash_wallet/src/core/navigation/shared_payment_intake.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';
import 'package:zcash_wallet/src/services/shared_payment_service.dart';

// What reaches the host from the share sheet, in what order, and what is
// dropped on the way: the inbox is the whole policy between the runner's
// queue and the link lanes. The QR reader is a fake that answers when the
// test says so, standing in for an analysis that takes its time, and the
// capture numbers are the test's, standing in for the runner's intake
// sequence that links and shares share.
void main() {
  const transparent = 'tmEjY6KfCryQhJ1hKSGiA7p8EeVggpvN78r';
  const request = 'zcash:$transparent?amount=1';
  final giftLink = 'https://${VizorDeepLink.host}/payment-links/open#v1=abcdef';

  late Directory tempDir;
  late StreamController<List<SharedIntakeEvent>> events;
  late List<Completer<List<String>>> readings;
  late List<SharedPaymentOutcome> outcomes;
  late SharedPaymentInbox inbox;
  late int seq;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shared_payment_inbox');
    events = StreamController<List<SharedIntakeEvent>>();
    readings = [];
    outcomes = [];
    seq = 0;
    inbox = SharedPaymentInbox(
      intake: SharedPaymentIntake(
        readQrCodes: (_) {
          final reading = Completer<List<String>>();
          readings.add(reading);
          return reading.future;
        },
      ),
      events: events.stream,
    );
    inbox.outcomes.listen(outcomes.add);
  });

  tearDown(() async {
    await inbox.dispose();
    await events.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  var copies = 0;
  Future<File> copy() =>
      File('${tempDir.path}/${copies++}.png').writeAsBytes([0]);

  // Nothing waits on a delete, so the check gives it a moment.
  Future<bool> isGone(File file) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (!await file.exists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  /// One push from the runner: what it had queued, in capture order.
  Future<void> emitBatch(List<SharedIntakeEvent> batch) async {
    events.add(batch);
    await pumpEventQueue();
  }

  Future<void> emit(SharedIntakeEvent event) => emitBatch([event]);

  /// The runner took a link: announced on this channel with the next number.
  Future<void> linkCaptured() => emit(SharedCaptured(seq: ++seq));

  /// Text as the runner delivers it: at once, with its number, ahead of any
  /// image still being copied.
  Future<void> shareText(String text) => emit(SharedText(text, seq: ++seq));

  /// An image share as the runner delivers it: announced at capture, the
  /// payload once the copy is written. [duringCopy] runs in between.
  Future<File> shareImage({Future<void> Function()? duringCopy}) async {
    final file = await copy();
    final number = ++seq;
    await emit(SharedCaptured(seq: number));
    await duringCopy?.call();
    await emit(SharedImage(file.path, seq: number));
    return file;
  }

  Future<void> finishReading(List<String> codes) async {
    readings.last.complete(codes);
    await pumpEventQueue();
  }

  test('shared text resolves at once', () async {
    await shareText('pay $request');

    expect(outcomes, [
      isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', request),
    ]);
  });

  test('images are read one at a time, and a share overtaken by a later one '
      'is resolved but not delivered', () async {
    final first = await shareImage();
    final second = await shareImage();
    expect(readings, hasLength(1), reason: 'the plugin has one analysis slot');

    await finishReading([request]);
    expect(outcomes, isEmpty, reason: 'the second share came after it');
    expect(await isGone(first), isTrue);

    await finishReading([request]);
    expect(outcomes, hasLength(1));
    expect(await isGone(second), isTrue);
  });

  test(
    'a link overtakes a share still resolving, except a Gift Card',
    () async {
      await shareImage();
      await linkCaptured();
      await finishReading([request]);
      expect(outcomes, isEmpty);

      await shareImage();
      await linkCaptured();
      await finishReading([giftLink]);
      expect(outcomes, [
        isA<SharedGiftCard>().having((g) => g.link, 'link', giftLink),
      ]);
    },
  );

  test('a link tapped while an image was still being copied overtakes it, '
      'whichever channel reached Dart first', () async {
    // The image is announced at capture, the link is captured and announced
    // while the copy is still being written, and the payload lands last.
    await shareImage(duringCopy: linkCaptured);
    await finishReading([request]);
    expect(outcomes, isEmpty, reason: 'the link has the higher number');

    await shareImage();
    await finishReading([request]);
    expect(outcomes, hasLength(1), reason: 'captured after the link');
  });

  test(
    'every number in a batch counts before any payload in it resolves',
    () async {
      // A cold start drains the runner's queue in one push: an older text
      // share and the number of a link tapped after it, in that order.
      await emitBatch([
        SharedText('pay $request', seq: ++seq),
        SharedCaptured(seq: ++seq),
      ]);
      expect(outcomes, isEmpty, reason: 'the link in the same batch is newer');

      await emitBatch([SharedText('pay $request', seq: ++seq)]);
      expect(outcomes, hasLength(1));
    },
  );

  test(
    'a reset overtakes everything captured so far, except a Gift Card',
    () async {
      await shareImage();
      inbox.supersede();
      await finishReading([request]);
      expect(outcomes, isEmpty);

      // An image whose copy was still being written when the reset came is
      // counted too, because its number was announced at capture.
      final file = await copy();
      final image = ++seq;
      await emit(SharedCaptured(seq: image));
      inbox.supersede();
      await emit(SharedImage(file.path, seq: image));
      await finishReading([request]);
      expect(outcomes, isEmpty, reason: 'captured before the reset');

      // Text shared after the reset, while that image was still being
      // copied, is delivered at once and is not overtaken by anything.
      await shareText('pay $request');
      expect(outcomes, hasLength(1));
      outcomes.clear();

      await shareImage();
      inbox.supersede();
      await finishReading([giftLink]);
      expect(outcomes, [
        isA<SharedGiftCard>().having((g) => g.link, 'link', giftLink),
      ]);
    },
  );

  test('a share that cannot be read is answered, and does not hold up the '
      'next one', () async {
    await shareImage();
    readings.last.completeError(StateError('plugin missing'));
    await pumpEventQueue();
    expect(outcomes, [SharedPaymentNotice.imageUnreadable]);

    await shareImage();
    await finishReading([request]);
    expect(outcomes, hasLength(2));
    expect(outcomes.last, isA<SharedPaymentRequest>());
  });

  test('a burst keeps the newest kMaxQueuedShares waiting and deletes the '
      'copies it drops unread', () async {
    final files = [
      for (var i = 0; i < kMaxQueuedShares + 3; i++) await shareImage(),
    ];
    expect(readings, hasLength(1), reason: 'the first is being read');
    // The two oldest waiting shares made room for the newest.
    expect(await isGone(files[1]), isTrue);
    expect(await isGone(files[2]), isTrue);
    expect(await files[3].exists(), isTrue);

    while (!readings.last.isCompleted) {
      await finishReading(const []);
    }
    expect(readings, hasLength(1 + kMaxQueuedShares));
    for (final file in files) {
      expect(await isGone(file), isTrue);
    }
  });

  test('once disposed, what was queued is still resolved for its copy, but '
      'nothing is delivered', () async {
    final file = await shareImage();
    await inbox.dispose();

    await finishReading([request]);

    expect(outcomes, isEmpty);
    expect(await isGone(file), isTrue);
  });
}
