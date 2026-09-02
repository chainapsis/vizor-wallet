import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  static const _pngType = XTypeGroup(
    label: 'PNG image',
    extensions: ['png'],
    mimeTypes: ['image/png'],
    uniformTypeIdentifiers: ['public.png'],
  );

  @override
  Future<bool> savePng(Uint8List pngBytes) async {
    final location = await getSaveLocation(
      suggestedName: _suggestedName,
      acceptedTypeGroups: const [_pngType],
      canCreateDirectories: true,
    );
    if (location == null) return false;

    final image = XFile.fromData(
      pngBytes,
      mimeType: 'image/png',
      name: _suggestedName,
    );
    await image.saveTo(location.path);
    return true;
  }
}
