import 'package:pretty_qr_code/pretty_qr_code.dart';

final _nonAlphanumericQrCharacter = RegExp(r'[^-0-9A-Z $%*+./:]');

bool keystoneQrUsesAlphanumeric(String data) =>
    data.isNotEmpty && !_nonAlphanumericQrCharacter.hasMatch(data);

/// Builds the smallest QR for a Keystone UR without changing its text.
///
/// Production UR frames are uppercase and fit QR's alphanumeric alphabet.
/// Other input keeps byte encoding so previews and callers retain exact text.
QrImage encodeKeystoneQrImage(
  String data, {
  int errorCorrectLevel = QrErrorCorrectLevel.M,
}) {
  if (!keystoneQrUsesAlphanumeric(data)) {
    return QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: errorCorrectLevel),
    );
  }

  // addAlphaNumeric does not select a version automatically. Image creation
  // validates capacity through the public API; only an undersized candidate
  // is retried. Successful images still use the library's best mask pattern.
  for (var version = 1; ; version++) {
    final code = QrCode(version, errorCorrectLevel)..addAlphaNumeric(data);
    try {
      return QrImage(code);
    } on InputTooLongException {
      if (version == 40) rethrow;
    }
  }
}
