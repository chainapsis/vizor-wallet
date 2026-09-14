import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';

/// Lets the engine-backed Pretty QR bitmap complete without settling every
/// spinner in the selected fixture.
Future<String?> waitForLoadedReceiveQr(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final qrImage = find.descendant(
    of: find.byType(ReceiveQrSurface),
    matching: find.byWidgetPredicate(
      (widget) => widget is RawImage && widget.image != null,
      description: 'loaded receive QR RawImage',
    ),
  );
  const step = Duration(milliseconds: 20);
  final attempts = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (qrImage.evaluate().isNotEmpty) return null;
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
  if (qrImage.evaluate().isNotEmpty) return null;
  return 'Loaded receive address did not render its QR bitmap within '
      '${timeout.inMilliseconds}ms.';
}
