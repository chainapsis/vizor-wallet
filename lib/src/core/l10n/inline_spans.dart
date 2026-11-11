import 'package:flutter/widgets.dart';

/// Character substituted into a localized message where an inline widget (an
/// icon, a link) goes. Pass it as the message argument and map it to the span
/// in [inlineSlotSpans].
const String kInlineSlot = '￼';

/// Splits an already-localized [text] into spans, replacing each key of
/// [slots] with its span, in order of appearance. A message takes the slot
/// text as a placeholder, so a translator places it wherever the grammar needs
/// it instead of stitching fixed-order fragments around an icon or highlight.
List<InlineSpan> inlineSlotSpans(String text, Map<String, InlineSpan> slots) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  while (true) {
    String? nextKey;
    var nextStart = -1;
    for (final key in slots.keys) {
      if (key.isEmpty) continue;
      final start = text.indexOf(key, cursor);
      if (start >= 0 && (nextStart < 0 || start < nextStart)) {
        nextKey = key;
        nextStart = start;
      }
    }
    if (nextKey == null) break;
    if (nextStart > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, nextStart)));
    }
    spans.add(slots[nextKey]!);
    cursor = nextStart + nextKey.length;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

/// Gives each of [emphasized] (passed into the message as placeholders) [style]
/// within the localized [text].
List<InlineSpan> emphasisSpans(
  String text,
  List<String> emphasized,
  TextStyle style,
) => inlineSlotSpans(text, {
  for (final phrase in emphasized) phrase: TextSpan(text: phrase, style: style),
});
