import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CameraPreferenceStore {
  CameraPreferenceStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const _lastQrCameraIdFileName = 'last_qr_camera_id.txt';

  final Future<Directory> Function() _supportDirectory;

  Future<String?> readLastQrCameraId() async {
    final file = await _lastQrCameraIdFile();
    if (!await file.exists()) return null;

    final cameraId = (await file.readAsString()).trim();
    return cameraId.isEmpty ? null : cameraId;
  }

  Future<void> writeLastQrCameraId(String cameraId) async {
    final trimmed = cameraId.trim();
    if (trimmed.isEmpty) return;

    final file = await _lastQrCameraIdFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(trimmed, flush: true);
  }

  Future<File> _lastQrCameraIdFile() async {
    final dir = await _supportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_lastQrCameraIdFileName');
  }
}
