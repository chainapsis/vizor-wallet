import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _platformChannel = MethodChannel(
  'com.zcash.wallet/figma_compare_capture',
);

String resolveFigmaCompareOutputPath(String configuredPath) {
  if (File(configuredPath).isAbsolute) return configuredPath;
  return Directory.systemTemp.uri
      .resolve('vizor-figma-compare/$configuredPath')
      .toFilePath();
}

String figmaCompareWindowCapturePath(String contentPath) {
  final dot = contentPath.lastIndexOf('.');
  if (dot <= contentPath.lastIndexOf(Platform.pathSeparator)) {
    return '$contentPath.window.png';
  }
  return '${contentPath.substring(0, dot)}.window${contentPath.substring(dot)}';
}

class FigmaCompareCaptureController {
  const FigmaCompareCaptureController({
    required this.captureBoundaryKey,
    MethodChannel channel = _platformChannel,
  }) : _channel = channel;

  final GlobalKey captureBoundaryKey;
  final MethodChannel _channel;

  Future<void> capture({
    required String contentOutputPath,
    double pixelRatio = 1,
    Duration settleDelay = const Duration(milliseconds: 350),
  }) async {
    if (!kDebugMode) {
      throw StateError('Figma comparison capture is available in debug only.');
    }

    await Directory(
      File(contentOutputPath).parent.path,
    ).create(recursive: true);

    String? captureToken;
    try {
      if (Platform.isMacOS) {
        final response = await _channel.invokeMapMethod<String, Object?>(
          'beginCapture',
        );
        captureToken = response?['token'] as String?;
        if (captureToken == null) {
          throw StateError('macOS capture preparation returned no token.');
        }
      }

      await _waitForStableFrame(settleDelay);
      await _captureFlutterContent(contentOutputPath, pixelRatio);

      if (Platform.isMacOS) {
        await _channel.invokeMethod<void>('captureWindow', {
          'token': captureToken,
          'path': figmaCompareWindowCapturePath(contentOutputPath),
        });
      }
    } finally {
      if (Platform.isMacOS && captureToken != null) {
        final restored = await _channel.invokeMapMethod<String, Object?>(
          'endCapture',
          {'token': captureToken},
        );
        debugPrint(
          'Figma comparison window restored: '
          'minimized=${restored?['windowMiniaturized']}, '
          'visible=${restored?['windowVisible']}, '
          'appHidden=${restored?['appHidden']}',
        );
      }
    }
  }

  Future<void> _waitForStableFrame(Duration settleDelay) async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (settleDelay > Duration.zero) await Future<void>.delayed(settleDelay);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _captureFlutterContent(String path, double pixelRatio) async {
    final renderObject = captureBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Figma comparison capture boundary is unavailable.');
    }
    if (renderObject.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Flutter did not encode the comparison image.');
      }
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  }
}
