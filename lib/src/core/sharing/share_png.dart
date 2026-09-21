import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Shares one PNG. Keeping text out avoids a second item in Save to Files.
Future<ShareResult> sharePng({
  required Uint8List png,
  required String fileName,
  Rect? sharePositionOrigin,
}) => SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(png, mimeType: 'image/png')],
    fileNameOverrides: [fileName],
    sharePositionOrigin: sharePositionOrigin,
  ),
);
