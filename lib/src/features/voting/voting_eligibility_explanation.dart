import '../../core/formatting/date_format.dart';
import 'voting_formatters.dart';

/// Shared closing line for account-level voting ineligibility.
const kVotingEligibilityGuidance = 'Switch to an eligible account to vote.';

/// Why this account's funds were left out of a voting round.
///
/// Mapped from the Rust eligibility check, which selects
/// `get_unspent_ironwood_notes_at_historical_height` and then applies the
/// 0.125 ZEC bundle minimum. Spending a snapshot note *after* the snapshot
/// does not remove it; notes received or created later do not count.
enum VotingEligibilityExclusionReason {
  /// No Ironwood notes were unspent at the snapshot height.
  noNotesAtSnapshot,

  /// Snapshot notes existed but did not form a 0.125 ZEC voting bundle.
  belowMinimum,

  /// Eligible overall, with a privacy-trim tail left out.
  privacyTrim,

  /// A voting-eligibility failure that is not one of the known reasons.
  unknown,
}

/// Snapshot cutoff plus the plain-language exclusion reason.
class VotingEligibilityExplanation {
  const VotingEligibilityExplanation({
    required this.reason,
    this.snapshotHeight,
    this.snapshotDate,
    this.customBody,
  });

  final VotingEligibilityExclusionReason reason;
  final int? snapshotHeight;
  final DateTime? snapshotDate;
  final String? customBody;

  /// Calendar date when the round JSON includes one; otherwise the block.
  String get snapshotValue {
    final date = snapshotDate;
    if (date != null) return formatMonthDayYear(date);
    final height = snapshotHeight;
    if (height != null) return 'Block ${formatBlockHeight(height)}';
    return 'This voting round snapshot';
  }

  /// Block line shown under a calendar snapshot date.
  String? get snapshotBlockLabel {
    final height = snapshotHeight;
    if (height == null || snapshotDate == null) return null;
    return 'Block ${formatBlockHeight(height)}';
  }

  String get snapshotSentenceFragment {
    final date = snapshotDate;
    final height = snapshotHeight;
    if (date != null && height != null) {
      return 'snapshot ${formatMonthDayYear(date)} (block ${formatBlockHeight(height)})';
    }
    if (date != null) return 'snapshot ${formatMonthDayYear(date)}';
    if (height != null) {
      return 'snapshot block ${formatBlockHeight(height)}';
    }
    return 'the voting round snapshot';
  }

  String get reasonTitle => switch (reason) {
    VotingEligibilityExclusionReason.noNotesAtSnapshot =>
      'No Ironwood notes at the snapshot',
    VotingEligibilityExclusionReason.belowMinimum =>
      'Below the 0.125 ZEC minimum',
    VotingEligibilityExclusionReason.privacyTrim =>
      'Some funds were left out',
    VotingEligibilityExclusionReason.unknown => 'Not eligible for this round',
  };

  String get reasonBody {
    final customBody = this.customBody;
    if (customBody != null && customBody.isNotEmpty) return customBody;
    return switch (reason) {
      VotingEligibilityExclusionReason.noNotesAtSnapshot =>
        'Only Ironwood notes this account held at the snapshot can vote. '
            'Notes you received or created after that point do not count, '
            'even if you later moved funds or finished Ironwood.',
      VotingEligibilityExclusionReason.belowMinimum =>
        'Voting needs at least 0.125 ZEC in eligible Ironwood notes at the '
            'snapshot. This account was below that minimum.',
      VotingEligibilityExclusionReason.privacyTrim =>
        'A small amount is left out of this vote to keep your submission '
            'less identifiable.',
      VotingEligibilityExclusionReason.unknown =>
        'This account is not eligible for this voting round.',
    };
  }

  /// Single paragraph used by status screens and existing string matchers.
  String get combinedMessage {
    if (reason == VotingEligibilityExclusionReason.privacyTrim) {
      return reasonBody;
    }
    return '$reasonBody Eligibility is measured at $snapshotSentenceFragment. '
        '$kVotingEligibilityGuidance';
  }

  static VotingEligibilityExplanation? fromPrivacyTrimNotice(String? message) {
    if (message == null || message.isEmpty) return null;
    if (!message.contains('is left out of this vote')) return null;
    return VotingEligibilityExplanation(
      reason: VotingEligibilityExclusionReason.privacyTrim,
      customBody: message,
    );
  }

  factory VotingEligibilityExplanation.fromMessage(
    String message, {
    DateTime? snapshotDate,
    int? snapshotHeight,
  }) {
    final normalized = _normalizedEligibilityMessage(message);
    final height = snapshotHeight ?? snapshotHeightFromEligibilityText(message);
    if (_noNotesPattern.hasMatch(normalized) ||
        normalized.contains('only ironwood notes this account held') ||
        normalized.contains('no eligible ironwood notes') ||
        normalized.contains('no eligible shielded funds') ||
        normalized.contains('no spendable voting notes')) {
      return VotingEligibilityExplanation(
        reason: VotingEligibilityExclusionReason.noNotesAtSnapshot,
        snapshotHeight: height,
        snapshotDate: snapshotDate,
      );
    }
    if (_minimumPattern.hasMatch(normalized) ||
        normalized.contains('below the 0.125 zec minimum') ||
        normalized.contains('0.125 zec in eligible ironwood') ||
        normalized.contains('0.125 zec') ||
        normalized.contains('12500000 zatoshi')) {
      return VotingEligibilityExplanation(
        reason: VotingEligibilityExclusionReason.belowMinimum,
        snapshotHeight: height,
        snapshotDate: snapshotDate,
      );
    }
    return VotingEligibilityExplanation(
      reason: VotingEligibilityExclusionReason.unknown,
      snapshotHeight: height,
      snapshotDate: snapshotDate,
      customBody: _bodyWithoutGuidance(message),
    );
  }
}

int? snapshotHeightFromEligibilityText(String text) {
  final match = _snapshotHeightPattern.firstMatch(text);
  if (match == null) return null;
  return int.tryParse(match.group(1)!.replaceAll(',', ''));
}

String _normalizedEligibilityMessage(String message) {
  return _bodyWithoutGuidance(message).toLowerCase();
}

String _bodyWithoutGuidance(String message) {
  var text = message.trim();
  if (text.endsWith(kVotingEligibilityGuidance)) {
    text = text
        .substring(0, text.length - kVotingEligibilityGuidance.length)
        .trimRight();
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

final _snapshotHeightPattern = RegExp(
  r'snapshot(?: block| height)?\s+([\d,]+)',
  caseSensitive: false,
);

final _noNotesPattern = RegExp(
  r'no (?:eligible|spendable) (?:ironwood |shielded )?notes',
  caseSensitive: false,
);

final _minimumPattern = RegExp(
  r'(?:minimum voting eligibility|at least (?:one eligible|0\.125))',
  caseSensitive: false,
);
