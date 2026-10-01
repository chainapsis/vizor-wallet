/// The part of [text] that must stay visible when it ellipsizes: the first
/// word, plus the ellipsis when more words follow.
String minimumVisibleLabel(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  return words.length > 1 ? '${words.first}…' : words.first;
}
