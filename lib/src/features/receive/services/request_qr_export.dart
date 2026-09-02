/// Where a request QR goes once it has been rendered: a file on desktop, a
/// share sheet on mobile.
///
/// Both sides are injected rather than called directly so a widget test can
/// write into a temporary directory and record a share instead of talking to
/// the operating system.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Base name of an exported request QR, before the amount and the extension.
const _requestQrFileStem = 'vizor-request';

/// File name the mobile share attaches. Mobile shares one request at a time
/// into another app's inbox, so it does not carry the amount the desktop
/// file name uses to keep several saved requests apart.
const kRequestQrShareFileName = '$_requestQrFileStem.png';

/// Resolves the directory a saved request QR is written into.
typedef RequestQrDirectoryResolver = Future<Directory> Function();

/// Hands [png] to the platform share sheet alongside [text].
typedef RequestShareHandler =
    Future<void> Function({
      required String text,
      required Uint8List png,
      required String fileName,
    });

/// Downloads if the platform has one, otherwise the app's documents
/// directory — the toast names whichever folder was actually used, so the
/// fallback is not a silent one.
Future<Directory> defaultRequestQrDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } on Object {
    // Not every platform implements Downloads; fall through to documents.
  }
  return getApplicationDocumentsDirectory();
}

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

final requestQrDirectoryResolverProvider = Provider<RequestQrDirectoryResolver>(
  (ref) => defaultRequestQrDirectory,
);

final requestShareHandlerProvider = Provider<RequestShareHandler>(
  (ref) => defaultRequestShare,
);

/// A request QR that reached disk.
class SavedRequestQr {
  const SavedRequestQr({required this.path, required this.folderName});

  /// Absolute path of the written PNG.
  final String path;

  /// Name of the folder it landed in, for the confirmation toast. "Downloads"
  /// when that is where it went, the fallback folder's own name otherwise.
  final String folderName;
}

/// Writes [png] as `vizor-request-<amount>.png` and returns where it landed.
///
/// An existing file of the same name is never overwritten — a second request
/// for the same amount gets `-2`, and so on. Silently replacing the first one
/// would destroy a file the user may already have sent somewhere.
Future<SavedRequestQr> saveRequestQrPng({
  required Uint8List png,
  required String amountZec,
  required RequestQrDirectoryResolver resolveDirectory,
}) async {
  final directory = await resolveDirectory();
  await directory.create(recursive: true);

  final baseName = requestQrFileName(amountZec);
  var file = File('${directory.path}${Platform.pathSeparator}$baseName');
  final stem = baseName.substring(0, baseName.length - '.png'.length);
  for (var attempt = 2; await file.exists() && attempt < 100; attempt++) {
    file = File('${directory.path}${Platform.pathSeparator}$stem-$attempt.png');
  }

  await file.writeAsBytes(png, flush: true);
  return SavedRequestQr(
    path: file.path,
    folderName: _folderNameOf(directory.path),
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
