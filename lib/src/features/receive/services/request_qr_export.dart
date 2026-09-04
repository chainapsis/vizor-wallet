/// Where a request QR goes once it has been rendered: a file the user picks
/// on desktop, a share sheet on mobile.
///
/// Both sides are injected rather than called directly so a widget test can
/// answer with a temporary path and record a share instead of talking to the
/// operating system.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/png_save_location.dart';

/// Base name of an exported request QR, before the amount and the extension.
const _requestQrFileStem = 'vizor-request';

/// File name the mobile share attaches. Mobile shares one request at a time
/// into another app's inbox, so it does not carry the amount the desktop
/// file name uses to keep several saved requests apart.
const kRequestQrShareFileName = '$_requestQrFileStem.png';

/// Asks the user where a saved request QR should go. Returns the chosen
/// absolute path, or null when the dialog was cancelled.
typedef RequestQrSaveLocationPicker =
    Future<String?> Function({required String suggestedName});

/// Hands [png] to the platform share sheet alongside [text].
typedef RequestShareHandler =
    Future<void> Function({
      required String text,
      required Uint8List png,
      required String fileName,
    });

/// The platform's own save panel, shared with the Gift Card QR export.
Future<String?> defaultRequestQrSaveLocation({required String suggestedName}) =>
    pickPngSaveLocation(suggestedName: suggestedName);

Future<void> defaultRequestShare({
  required String text,
  required Uint8List png,
  required String fileName,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: [fileName],
    ),
  );
}

final requestQrSaveLocationPickerProvider =
    Provider<RequestQrSaveLocationPicker>(
      (ref) => defaultRequestQrSaveLocation,
    );

final requestShareHandlerProvider = Provider<RequestShareHandler>(
  (ref) => defaultRequestShare,
);

/// A request QR that reached disk.
class SavedRequestQr {
  const SavedRequestQr({required this.path, required this.folderName});

  /// Absolute path of the written PNG.
  final String path;

  /// Name of the folder the user picked, for the confirmation toast.
  final String folderName;
}

/// Asks [pickSaveLocation] where the QR should go and writes [png] there.
///
/// Returns null when the user cancelled the dialog. An existing file at the
/// chosen path is replaced: the save panel already asked the user about that.
Future<SavedRequestQr?> saveRequestQrPng({
  required Uint8List png,
  required String amountZec,
  required RequestQrSaveLocationPicker pickSaveLocation,
}) async {
  final path = await pickSaveLocation(
    suggestedName: requestQrFileName(amountZec),
  );
  if (path == null) return null;

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(png, flush: true);
  return SavedRequestQr(
    path: file.path,
    folderName: _folderNameOf(file.parent.path),
  );
}

/// `vizor-request-0.5.png`, or `vizor-request.png` when there is no amount.
///
/// Anything outside digits and a decimal point is dropped rather than escaped:
/// the amount is only in the name so a person can tell two saved requests
/// apart, and it is not worth a file name a shell has to quote.
String requestQrFileName(String amountZec) {
  final sanitized = amountZec.trim().replaceAll(RegExp(r'[^0-9.]'), '');
  if (sanitized.isEmpty) return '$_requestQrFileStem.png';
  return '$_requestQrFileStem-$sanitized.png';
}

String _folderNameOf(String directoryPath) {
  final segments = directoryPath
      .split(RegExp(r'[/\\]'))
      .where((segment) => segment.isNotEmpty)
      .toList();
  return segments.isEmpty ? directoryPath : segments.last;
}
