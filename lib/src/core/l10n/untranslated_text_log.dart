import 'dart:developer' show log;

/// Logs untranslated Rust, SDK or platform text that a screen replaces with
/// localized copy, so the original stays available when diagnosing a failure.
///
/// Screens call this while building, so each text is logged once while it is
/// among the last few distinct texts.
void logUntranslatedText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !_recent.add(trimmed)) return;
  if (_recent.length > _recentLimit) _recent.remove(_recent.first);
  log(trimmed, name: 'vizor.untranslated');
}

const _recentLimit = 32;
final _recent = <String>{};
