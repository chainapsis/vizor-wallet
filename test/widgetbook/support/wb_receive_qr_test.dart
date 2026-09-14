import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';

import 'wb_gallery_harness.dart';
import 'wb_receive_qr.dart';

void main() {
  testWidgets('loaded receive capture waits for the rendered QR bitmap', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: const {
        'Layout': 'Mobile',
        'Pool': 'Shielded',
        'Address': 'Loaded',
      },
      canvasSize: const Size(393, 852),
    );

    expect(await waitForLoadedReceiveQr(tester), isNull);
    expect(
      find.descendant(
        of: find.byType(ReceiveQrSurface),
        matching: find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        ),
      ),
      findsOneWidget,
    );
    await disposeTree(tester);
  });
}
