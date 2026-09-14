// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

/// One state axis of a surface as a knob.
///
/// Always a dropdown: the settings panel at the default window size is too
/// narrow for a segmented control, which wraps its labels. [label] is the
/// product vocabulary ('Quote', not 'quoteState') and so are the option
/// labels, which is why [labelBuilder] is required: the enum name is a code
/// name, and the generic fallback [wbEnumLabel] lowercases acronyms
/// (`notEnoughZec` becomes 'Not enough zec'). Pass [wbEnumLabel] explicitly
/// for an axis whose enum names are already product words.
T wbStateKnob<T extends Enum>(
  BuildContext context, {
  required String label,
  required List<T> options,
  required String Function(T value) labelBuilder,
  T? initial,
}) {
  return context.knobs.object.dropdown<T>(
    label: label,
    options: options,
    initialOption: initial,
    labelBuilder: labelBuilder,
  );
}

/// Boolean state axis as a knob.
bool wbBoolKnob(
  BuildContext context, {
  required String label,
  bool initial = false,
}) {
  return context.knobs.boolean(label: label, initialValue: initial);
}

/// Generic option label: camelCase enum name to a sentence-case phrase
/// (`awaitingSignature` → 'Awaiting signature'). Opt in per knob; it has no
/// product vocabulary, so it lowercases acronyms.
String wbEnumLabel(Enum value) => wbSentenceCaseFromCamel(value.name);

/// Splits [name] on lower-to-upper boundaries and sentence-cases the result.
///
/// Acronyms are lowercased with everything else ('zecUsd' → 'Zec usd'), which
/// is why product vocabulary belongs in a caller-supplied `labelBuilder`.
String wbSentenceCaseFromCamel(String name) {
  if (name.isEmpty) return name;
  final spaced = name
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'),
        (match) => ' ${match[1]}',
      )
      .toLowerCase();
  return spaced[0].toUpperCase() + spaced.substring(1);
}
