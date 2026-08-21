import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns a desktop activity row by its visual index.
///
/// Full-screen rows use stable transaction/swap identities so their element
/// state survives pending-to-settled updates. Compact home rows retain the
/// older prefix-and-index keys.
Finder desktopActivityRowFinder(String rowKeyPrefix, int index) {
  if (rowKeyPrefix != 'activity_screen') {
    return find.byKey(ValueKey('${rowKeyPrefix}_row_$index'));
  }
  return desktopActivityRowsFinder().at(index);
}

Finder desktopActivityRowsFinder() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      (key.value.startsWith('tx:') || key.value.startsWith('swap:'));
});

Finder desktopActivityRowFinderForKey(Key key) {
  if (key case ValueKey<String>(
    value: final value,
  ) when value.startsWith('activity_screen_row_')) {
    final index = int.parse(value.substring('activity_screen_row_'.length));
    return desktopActivityRowFinder('activity_screen', index);
  }
  return find.byKey(key);
}
