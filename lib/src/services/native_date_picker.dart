import 'package:flutter/services.dart';

/// iOS-native date picker sheet (`UICalendarView` in a content-fit
/// detent), presented over the Flutter view by `DatePickerHandler.swift`
/// on the `com.zcash.wallet/date_picker` channel.
///
/// Dates cross the channel as `yyyy-MM-dd` strings — never epoch
/// timestamps — so a calendar day survives the Dart↔Swift hop without
/// timezone drift.
///
/// Only iOS registers a handler. Callers branch on `Platform.isIOS`
/// first and keep the Flutter calendar sheet as the fallback for
/// Android and for any channel failure (e.g. the handler requires
/// iOS 16+ and reports `unavailable` below that).
abstract final class NativeDatePicker {
  static const channel = MethodChannel('com.zcash.wallet/date_picker');

  /// Presents the picker and resolves with the chosen day, or null when
  /// the user cancels (swipe-down / programmatic [cancel]).
  ///
  /// Throws [PlatformException] / [MissingPluginException] when the
  /// native picker cannot be shown — callers fall back to the Flutter
  /// calendar sheet.
  static Future<DateTime?> pickDate({
    DateTime? initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required bool isDarkTheme,
    Color? accentColor,
  }) async {
    final raw = await channel.invokeMethod<String>('pickDate', {
      if (initialDate != null) 'initial': encodeDate(initialDate),
      'min': encodeDate(firstDate),
      'max': encodeDate(lastDate),
      'isDarkTheme': isDarkTheme,
      if (accentColor != null) 'accentColorHex': _encodeColor(accentColor),
    });
    return raw == null ? null : decodeDate(raw);
  }

  /// Dismisses a presented picker, resolving its [pickDate] with null.
  /// No-op when nothing is presented. Exists for the e2e tour — the
  /// test process cannot tap native UIKit views to dismiss them.
  static Future<void> cancel() async {
    await channel.invokeMethod<void>('cancel');
  }

  static String encodeDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime decodeDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) {
      throw FormatException('Expected yyyy-MM-dd, got "$raw"');
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// `RRGGBB` — alpha is dropped; the picker tint is always opaque.
  static String _encodeColor(Color color) {
    String channelHex(double value) =>
        (value * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '${channelHex(color.r)}${channelHex(color.g)}${channelHex(color.b)}';
  }
}
