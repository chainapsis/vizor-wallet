import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/png_save_location.dart';

final paymentLinkQrImageSaverProvider = Provider<PaymentLinkQrImageSaver>((
  ref,
) {
  return const FileSelectorPaymentLinkQrImageSaver();
});

abstract interface class PaymentLinkQrImageSaver {
  /// Opens a native save dialog and writes [pngBytes] to the chosen path.
  ///
  /// Returns `false` when the dialog is dismissed without choosing a path.
  Future<bool> savePng(Uint8List pngBytes);
}

class FileSelectorPaymentLinkQrImageSaver implements PaymentLinkQrImageSaver {
  const FileSelectorPaymentLinkQrImageSaver();

  static const _suggestedName = 'vizor-gift-card.png';

  @override
  Future<bool> savePng(Uint8List pngBytes) async {
    final path = await pickPngSaveLocation(suggestedName: _suggestedName);
    if (path == null) return false;

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes, flush: true);
    return true;
  }
}
