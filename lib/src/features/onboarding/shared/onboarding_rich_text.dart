import 'package:flutter/widgets.dart';

/// Splits an already-localized [text] into spans, giving each of [emphasized]
/// (in order of appearance) [style]. Lets a translator reorder a sentence whose
/// emphasized phrases are passed in as placeholders.
List<InlineSpan> onboardingEmphasisSpans(
  String text,
  List<String> emphasized,
  TextStyle style,
) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final phrase in emphasized) {
    final start = text.indexOf(phrase, cursor);
    if (start < 0 || phrase.isEmpty) continue;
    if (start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, start)));
    }
    spans.add(TextSpan(text: phrase, style: style));
    cursor = start + phrase.length;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }
  return spans;
}
