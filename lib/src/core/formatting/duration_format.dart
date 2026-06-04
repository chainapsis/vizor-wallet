/// Formats a [Duration] as elapsed seconds with two decimals, e.g. `1.23s`.
String formatElapsedSeconds(Duration duration) {
  return '${(duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s';
}
