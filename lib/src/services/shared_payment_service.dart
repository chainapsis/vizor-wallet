import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'native_intake_service.dart';

const kSharedPaymentChannelName = 'com.zcash.wallet/shared_payment';

final sharedPaymentServiceProvider = Provider<SharedPaymentService>((ref) {
  final service = SharedPaymentService();
  ref.onDispose(service.dispose);
  return service;
});

/// What the share channel delivers, numbered by the runner's intake sequence.
///
/// The runner numbers everything it takes in, links on the other channel as
/// well as shares, so [seq] orders a share against a link without a clock:
/// a link tapped while an image was still being copied has the higher
/// number, whichever channel reached Dart first.
sealed class SharedIntakeEvent {
  const SharedIntakeEvent({required this.seq});

  final int seq;
}

/// Something reached the runner whose payload is not here yet: a link on the
/// other channel, or an image whose payload follows once its copy is
/// written. Sent at once, so the number is known before the payload is. Text
/// needs no announcement: it is delivered at once, with its number.
final class SharedCaptured extends SharedIntakeEvent {
  const SharedCaptured({required super.seq});
}

/// Content another app handed to Vizor through the system share sheet.
sealed class SharedPayload extends SharedIntakeEvent {
  const SharedPayload({required super.seq});
}

/// Shared text: a bare address, a link, or a whole message with one inside.
final class SharedText extends SharedPayload {
  const SharedText(this.text, {required super.seq});

  final String text;
}

/// A shared image, which the native side wrote to the app's cache scaled
/// down. The file is the receiver's to delete once it has looked for a QR
/// code in it.
final class SharedImage extends SharedPayload {
  const SharedImage(this.path, {required super.seq});

  final String path;
}

/// A shared image the native side could not read at all: not an image, or a
/// provider that never answered. It arrives as an image item without a path,
/// and keeps its place in the order so the user is told about it in turn.
final class SharedUnreadableImage extends SharedPayload {
  const SharedUnreadableImage({required super.seq});
}

/// The native-to-Dart intake for the system share sheet, on a channel of its
/// own beside `IncomingUriService`'s. Only the Android runner installs it so
/// far; iOS joins once its share extension does.
///
/// Delivered in the batches the runner sends, not one event at a time: a
/// batch can hold a text payload and, after it, the number of a link tapped
/// later, and the receiver must know that number before it resolves the
/// text. One batch at a time keeps the two together.
class SharedPaymentService
    extends NativeIntakeService<List<SharedIntakeEvent>> {
  SharedPaymentService({MethodChannel? channel})
    : super(
        channel ?? const MethodChannel(kSharedPaymentChannelName),
        takePendingMethod: 'takePending',
        pushMethod: 'onShared',
      );

  @override
  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Iterable<List<SharedIntakeEvent>> parse(Object? arguments) {
    if (arguments is! Iterable) return const [];
    final batch = arguments.map(_eventFrom).nonNulls.toList();
    return batch.isEmpty ? const [] : [batch];
  }

  static SharedIntakeEvent? _eventFrom(Object? item) {
    if (item is! Map) return null;
    final seq = item['seq'];
    if (seq is! int) return null;
    return switch (item['type']) {
      'captured' => SharedCaptured(seq: seq),
      'text' => switch (item['text']) {
        final String text => SharedText(text, seq: seq),
        _ => null,
      },
      'image' => switch (item['path']) {
        final String path => SharedImage(path, seq: seq),
        _ => SharedUnreadableImage(seq: seq),
      },
      _ => null,
    };
  }
}
