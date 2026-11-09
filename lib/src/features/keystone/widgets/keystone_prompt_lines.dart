import 'package:flutter/widgets.dart';

import '../../../core/l10n/inline_spans.dart';

/// Lays out a localized Keystone prompt as the scan screens were designed:
/// the line holding [kInlineSlot] wraps its words around [icon] with
/// [inlineGap], other lines are centered text [lineGap] apart, and [trailing]
/// (a help button) follows the last line. Translators place the slot and the
/// line breaks in the message.
class KeystonePromptLines extends StatelessWidget {
  const KeystonePromptLines({
    required this.text,
    required this.icon,
    required this.style,
    required this.inlineGap,
    required this.lineGap,
    this.trailing,
    this.trailingGap = 0,
    super.key,
  });

  final String text;
  final Widget icon;
  final TextStyle style;
  final double inlineGap;
  final double lineGap;
  final Widget? trailing;
  final double trailingGap;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, line) in lines.indexed) ...[
          if (index > 0) SizedBox(height: lineGap),
          _line(line, last: index == lines.length - 1),
        ],
      ],
    );
  }

  Widget _line(String line, {required bool last}) {
    final trailing = last ? this.trailing : null;
    if (line.contains(kInlineSlot)) {
      final slot = line.indexOf(kInlineSlot);
      final before = line.substring(0, slot).trim();
      final after = line.substring(slot + kInlineSlot.length).trim();
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: inlineGap,
        runSpacing: lineGap,
        children: [
          if (before.isNotEmpty) Text(before, style: style),
          icon,
          if (after.isNotEmpty) Text(after, style: style),
          ?trailing,
        ],
      );
    }
    final text = Text(line, textAlign: TextAlign.center, style: style);
    if (trailing == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(fit: FlexFit.loose, child: text),
        SizedBox(width: trailingGap),
        trailing,
      ],
    );
  }
}
