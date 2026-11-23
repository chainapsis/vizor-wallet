import 'package:flutter/widgets.dart';

import '../formatting/address_line.dart';

export '../formatting/address_line.dart' show AddressLine;

/// Renders an [AddressLine] in the widest form that fits, so the compacted
/// address is never cut short a second time.
///
/// In order: the whole line; without the text after the address. A contact
/// name that still does not fit moves to its own line above the address
/// (shortened to at least [_minLabelCharacters] characters if it must), so it
/// stays visible. Without a name (or room for one): the line without the text
/// after the address; the address alone (not for [AddressLine.keepBefore]).
/// A line with an [AddressLine.shortAddress] tries that before wrapping.
/// When none fits (large text on a narrow screen), the address wraps onto
/// further lines, below the text before it when that is kept, rather than
/// losing its tail.
class AddressLineText extends StatelessWidget {
  const AddressLineText(
    this.line, {
    this.style,
    this.textAlign,
    this.singleLine = false,
    super.key,
  });

  final AddressLine line;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Keeps the line to one line, for a row of fixed height (a list row): what
  /// would wrap is ellipsized instead, after the short form has been tried.
  final bool singleLine;

  static const _minLabelCharacters = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var (text, :wraps) = _fittedText(context, constraints.maxWidth);
        if (singleLine && wraps) {
          text = line.withShortAddress?.address ?? line.address;
          wraps = false;
        }
        return Text(
          text,
          // Screen readers hear the whole line, whatever gave way on screen.
          semanticsLabel: line.text,
          maxLines: wraps ? null : 1,
          softWrap: wraps,
          overflow: wraps ? null : TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        );
      },
    );
  }

  (String, {bool wraps}) _fittedText(BuildContext context, double maxWidth) {
    if (!maxWidth.isFinite) return (line.text, wraps: false);
    final textStyle = _effectiveStyle(context);
    final painter = _painter(context);
    try {
      bool fits(String text) {
        painter.text = TextSpan(text: text, style: textStyle);
        painter.layout();
        return painter.width <= maxWidth;
      }

      final fitted = _fit(line, fits);
      // A long form that would wrap gives way to the short form.
      final short = line.withShortAddress;
      return fitted.wraps && short != null ? _fit(short, fits) : fitted;
    } finally {
      painter.dispose();
    }
  }

  (String, {bool wraps}) _fit(AddressLine line, bool Function(String) fits) {
    final whole = line.text;
    if (fits(whole)) return (whole, wraps: false);
    final label = line.contactLabel;
    if (label != null) {
      if (line.after.isNotEmpty) {
        final named = line.compose(label: label, withAfter: false);
        if (fits(named)) return (named, wraps: false);
      }
      if (_nameLine(line, label, fits) case final nameLine?) {
        final withAfter = '${line.address}${line.after}';
        final addressLine = fits(withAfter) ? withAfter : line.address;
        return ('$nameLine\n$addressLine', wraps: true);
      }
      final unnamed = line.compose(label: null);
      if (fits(unnamed)) return (unnamed, wraps: false);
    }
    final withoutAfter = line.compose(label: null, withAfter: false);
    if (fits(withoutAfter)) return (withoutAfter, wraps: false);
    if (!line.keepBefore && fits(line.address)) {
      return (line.address, wraps: false);
    }
    final before = line.keepBefore ? line.before.trimRight() : '';
    return (
      before.isEmpty ? line.address : '$before\n${line.address}',
      wraps: true,
    );
  }

  /// The contact name's own line: the text before the address and the name
  /// (`To: Mike`), with the name shortened to the longest form that fits.
  /// Without room for even [_minLabelCharacters] characters, the name alone
  /// (unless [AddressLine.keepBefore]); null when that does not fit either.
  String? _nameLine(
    AddressLine line,
    String label,
    bool Function(String) fits,
  ) {
    return _shortestNameLine(line.before, label, fits) ??
        (line.keepBefore || line.before.isEmpty
            ? null
            : _shortestNameLine('', label, fits));
  }

  String? _shortestNameLine(
    String before,
    String label,
    bool Function(String) fits,
  ) {
    final whole = '$before$label';
    if (fits(whole)) return whole;
    final characters = label.characters;
    String shortenedTo(int count) =>
        '$before${characters.take(count).toString().trimRight()}…'; // l10n-ignore: truncation mark

    var low = _minLabelCharacters;
    var high = characters.length - 1;
    if (high < low || !fits(shortenedTo(low))) return null;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(shortenedTo(mid))) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return shortenedTo(low);
  }

  /// The style [Text] resolves from [style].
  TextStyle _effectiveStyle(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    return MediaQuery.boldTextOf(context)
        ? effectiveStyle.merge(const TextStyle(fontWeight: FontWeight.bold))
        : effectiveStyle;
  }

  /// Measures with the scale, direction and locale [Text] uses.
  TextPainter _painter(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context);
    return TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
      textWidthBasis: defaultStyle.textWidthBasis,
      textHeightBehavior:
          defaultStyle.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
    );
  }
}
