import 'dart:async';

import 'package:flutter/foundation.dart';

// Avoid spawning an isolate for the usual handful of saved cards. Larger
// stores include nested link JSON/base64 and benefit from offloading the full
// conversion, not just the outer jsonDecode call.
const paymentLinkCodecBackgroundBytes = 16 * 1024;
const paymentLinkCodecBackgroundRecords = 16;

Future<R> runPaymentLinkStoreCodec<M, R>(
  ComputeCallback<M, R> convert,
  M value, {
  required bool inBackground,
}) async {
  if (!inBackground) return convert(value);
  return compute(convert, value, debugLabel: 'Gift Card storage codec');
}

/// Durable writers use v2. Preserve compatibility with a compact link in an
/// older/imported payload: its mnemonic decoder needs the initialized Rust
/// bridge in the owning isolate. Only that record is completed there.
bool paymentLinkRecordNeedsNativeCodec(Object? item, String linkKey) {
  if (item is! Map) return false;
  final link = item[linkKey];
  return link is String &&
      (Uri.tryParse(link)?.fragment.startsWith('v3=') ?? false);
}

/// Ordinary records arrive fully decoded from the worker. Compact legacy
/// records need the owning Rust bridge; yield between small groups rather
/// than completing an arbitrarily large fallback in a single UI event.
Future<List<R>> finishPaymentLinkStoreDecode<R>(
  List<Object?> items,
  R Function(Object?) decodeNativeRecord,
) async {
  final result = <R>[];
  var nativeRecords = 0;
  for (final item in items) {
    if (item is R) {
      result.add(item);
    } else {
      if (nativeRecords > 0 && nativeRecords % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      result.add(decodeNativeRecord(item));
      nativeRecords++;
    }
  }
  return result;
}
