import 'package:flutter/widgets.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/primitives.dart';

enum VotingChoiceTone { yes, no, multi, skipped }

class VotingChoicePalette {
  const VotingChoicePalette({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;
}

VotingChoicePalette votingChoicePalette(BuildContext context, String label) {
  final colors = context.colors;
  final isDark = context.appTheme == AppThemeData.dark;

  switch (votingChoiceTone(label)) {
    case VotingChoiceTone.yes:
      return VotingChoicePalette(
        background: isDark
            ? GreenPrimitives.p150Dark
            : GreenPrimitives.p50Light,
        border: (isDark ? GreenPrimitives.p400Dark : GreenPrimitives.p300Light)
            .withValues(alpha: 0.35),
        text: isDark ? GreenPrimitives.p500Dark : GreenPrimitives.p400Light,
      );
    case VotingChoiceTone.no:
      return VotingChoicePalette(
        background: isDark
            ? CrimsonPrimitives.p150Dark
            : CrimsonPrimitives.p50Light,
        border:
            (isDark ? CrimsonPrimitives.p400Dark : CrimsonPrimitives.p300Light)
                .withValues(alpha: 0.35),
        text: isDark ? CrimsonPrimitives.p500Dark : CrimsonPrimitives.p400Light,
      );
    case VotingChoiceTone.multi:
      return VotingChoicePalette(
        background: colors.background.utilitySuccessSubtle,
        border: colors.background.utilitySuccessAlpha,
        text: colors.text.success,
      );
    case VotingChoiceTone.skipped:
      return VotingChoicePalette(
        background: colors.background.neutralSubtleOpacity,
        border: colors.border.subtle,
        text: colors.text.secondary,
      );
  }
}

VotingChoiceTone votingChoiceTone(String label) {
  final normalized = label.trim().toLowerCase();
  if (normalized == 'skipped') return VotingChoiceTone.skipped;
  if (_startsWithChoiceWord(normalized, const ['yes', 'support'])) {
    return VotingChoiceTone.yes;
  }
  if (_startsWithChoiceWord(normalized, const ['no', 'oppose'])) {
    return VotingChoiceTone.no;
  }
  return VotingChoiceTone.multi;
}

bool _startsWithChoiceWord(String label, List<String> words) {
  for (final word in words) {
    if (label == word || RegExp('^$word\\b').hasMatch(label)) {
      return true;
    }
  }
  return false;
}
