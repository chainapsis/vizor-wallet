import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/sharing/share_png.dart';

/// Captures the same artwork and QR composite on either form factor.
Future<Uint8List> capturePaymentLinkQr(
  GlobalKey cardKey, {
  required double pixelRatio,
}) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary = cardKey.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
    throw StateError('Gift Card QR image is not ready.');
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Gift Card QR image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

typedef PaymentLinkQrShareHandler =
    Future<bool> Function({
      required Uint8List png,
      required Rect sharePositionOrigin,
    });

final paymentLinkQrShareHandlerProvider = Provider<PaymentLinkQrShareHandler>(
  (ref) => sharePaymentLinkQr,
);

/// Returns true only when the user selected a native sharing action.
Future<bool> sharePaymentLinkQr({
  required Uint8List png,
  required Rect sharePositionOrigin,
}) async {
  final result = await sharePng(
    png: png,
    fileName: 'vizor-gift-card.png',
    sharePositionOrigin: sharePositionOrigin,
  );
  return result.status == ShareResultStatus.success;
}
