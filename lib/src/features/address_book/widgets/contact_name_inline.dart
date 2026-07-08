import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Compact single-line "matched contact" indicator: a crimson user icon
/// followed by the contact name, optionally with a compact address in
/// parentheses. Codifies the matched-address convention used by the swap
/// status detail rows.
class ContactNameInline extends StatelessWidget {
  const ContactNameInline({
    required this.name,
    this.address,
    this.textStyle,
    this.iconSize = 14,
    super.key,
  });

  /// The contact's label/nickname.
  final String name;

  /// Optional compact address appended as " (address)". Callers pass an
  /// already-compacted form (per-surface truncation params vary).
  final String? address;

  /// Text style for the name; defaults to labelLarge in the accent color.
  final TextStyle? textStyle;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style =
        textStyle ??
        AppTypography.labelLarge.copyWith(color: colors.text.accent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.user, size: iconSize, color: colors.icon.brandCrimson),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            contactAddressDisplayText(label: name, compactAddress: address),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// String form of [ContactNameInline] for string-only pipelines (review
/// detail lines, activity headers): `"Rowan (0x0cd7…7181)"`, or just the
/// label when [compactAddress] is null/empty.
String contactAddressDisplayText({
  required String label,
  String? compactAddress,
}) {
  final address = compactAddress?.trim() ?? '';
  return address.isEmpty ? label : '$label ($address)';
}
