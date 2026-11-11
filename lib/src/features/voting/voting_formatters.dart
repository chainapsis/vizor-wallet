import '../../core/formatting/number_format.dart';
import '../../core/l10n/l10n.dart' show AppLocalizations;
import '../../core/formatting/zec_amount.dart';
import '../../services/voting/pir_snapshot_resolver.dart';

/// Formats raw zatoshi voting power as e.g. `12.5 ZEC`.
///
/// Delegates to [ZecAmount] for the decimal formatting. The denomination is
/// kept as the literal `ZEC` to preserve existing output across networks.
String formatVotingPower(BigInt zatoshi) {
  const denomination = 'ZEC'; // l10n-ignore: currency code
  return ZecAmount.fromZatoshi(zatoshi)
      .pretty(denomStyle: ZecDenomStyle.upper, denomination: denomination)
      .toString();
}

String formatBlockHeight(int height) => formatGroupedInteger(height);

/// Explains why no PIR endpoint could serve a round's snapshot height.
///
/// The wallet reports this from two places — the session provider when
/// resolution fails, and the status screen when it renders the diagnostics a
/// failed session left behind — so the wording lives here rather than being
/// written twice and drifting.
///
/// Set [includeDiagnostics] for the provider's log-facing copy; the screen
/// leaves it off, because a per-endpoint dump is not something a user can act
/// on.
String pirSnapshotMismatchMessage(
  AppLocalizations l10n, {
  required int expectedSnapshotHeight,
  required List<PirSnapshotEndpointDiagnostic> diagnostics,
  bool includeDiagnostics = false,
}) {
  final expected = formatBlockHeight(expectedSnapshotHeight);
  final reportedHeights = diagnostics
      .map((diagnostic) => diagnostic.reportedHeight)
      .nonNulls
      .toSet();

  bool everyStatusIs(PirSnapshotEndpointStatus status) =>
      diagnostics.isNotEmpty &&
      diagnostics.every((diagnostic) => diagnostic.status == status);

  if (everyStatusIs(PirSnapshotEndpointStatus.behind) &&
      reportedHeights.isNotEmpty) {
    final highest = formatBlockHeight(
      reportedHeights.reduce((left, right) => left > right ? left : right),
    );
    return l10n.votingPirBehind(expected, highest);
  }

  if (everyStatusIs(PirSnapshotEndpointStatus.ahead) &&
      reportedHeights.isNotEmpty) {
    final lowest = formatBlockHeight(
      reportedHeights.reduce((left, right) => left < right ? left : right),
    );
    return l10n.votingPirAhead(expected, lowest);
  }

  if (everyStatusIs(PirSnapshotEndpointStatus.timeoutOrNetworkError)) {
    return l10n.votingPirUnreachable;
  }

  if (!includeDiagnostics) return l10n.votingPirNoMatch(expected);
  return l10n.votingPirNoMatchDiagnostics(
    expected,
    pirSnapshotDiagnosticsLog(diagnostics),
  );
}

/// One-line per-endpoint dump for logs and the provider's error detail.
String pirSnapshotDiagnosticsLog(
  List<PirSnapshotEndpointDiagnostic> diagnostics,
) {
  if (diagnostics.isEmpty) return 'none'; // l10n-ignore: log text
  return diagnostics.map(_pirSnapshotDiagnosticLog).join('; ');
}

String _pirSnapshotDiagnosticLog(PirSnapshotEndpointDiagnostic diagnostic) {
  final height = diagnostic.reportedHeight == null
      ? ''
      : ' height=${diagnostic.reportedHeight}';
  final statusCode = diagnostic.httpStatusCode == null
      ? ''
      : ' http=${diagnostic.httpStatusCode}';
  final message = diagnostic.message == null || diagnostic.message!.isEmpty
      ? ''
      : ' message=${diagnostic.message}';
  return '${diagnostic.endpoint} status=${diagnostic.status.name}' // l10n-ignore: log text
      '$height$statusCode$message';
}
