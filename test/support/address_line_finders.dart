import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/address_line_text.dart';

/// An [AddressLineText] whose whole line is [text]. What it paints depends on
/// the width and font, so tests of the line's content match the data.
Finder findAddressLine(String text) => find.byWidgetPredicate(
  (widget) => widget is AddressLineText && widget.line.text == text,
  description: 'AddressLineText "$text"',
);

/// An [AddressLineText] whose whole line contains [pattern].
Finder findAddressLineContaining(String pattern) => find.byWidgetPredicate(
  (widget) => widget is AddressLineText && widget.line.text.contains(pattern),
  description: 'AddressLineText containing "$pattern"',
);
