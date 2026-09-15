import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Clipboard hand-off shared by the Receive screen and its request sheet.
final receiveClipboardWriterProvider = Provider<Future<void> Function(String)>(
  (ref) =>
      (text) => Clipboard.setData(ClipboardData(text: text)),
);
