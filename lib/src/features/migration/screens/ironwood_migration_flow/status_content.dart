part of '../ironwood_migration_flow_screen.dart';

String _migrationSpendableBalanceLabel({
  required List<BigInt> values,
  required List<_MigrationBatchStatus> statuses,
}) {
  var spendable = BigInt.zero;
  for (var i = 0; i < values.length; i++) {
    if (i < statuses.length && statuses[i] == _MigrationBatchStatus.complete) {
      spendable += values[i];
    }
  }
  return '${_formatZecAmountCompact(spendable)} ZEC';
}

List<rust_sync.MigrationPartStatus> _displayMigrationParts(
  rust_sync.MigrationStatus status,
) {
  final parts = [...status.parts];
  if (status.phase != kIronwoodMigrationReadyToMigratePhase) {
    return parts;
  }

  final hasTransferProgress =
      status.pendingTxCount > 0 ||
      status.broadcastedTxCount > 0 ||
      status.confirmedTxCount > 0 ||
      status.scheduledBroadcasts.isNotEmpty ||
      parts.any(
        (part) =>
            part.state == rust_sync.MigrationPartState.scheduled ||
            part.state == rust_sync.MigrationPartState.migrating ||
            part.state == rust_sync.MigrationPartState.confirming ||
            part.state == rust_sync.MigrationPartState.needsInput ||
            part.scheduleStartHeight != null ||
            part.scheduledHeight != null,
      );
  if (hasTransferProgress) return parts;
  return const <rust_sync.MigrationPartStatus>[];
}

class _MigrationStatusContent extends StatefulWidget {
  const _MigrationStatusContent({
    required this.status,
    required this.action,
    required this.isAdvancing,
    required this.currentHeight,
    required this.onAction,
  });

  final rust_sync.MigrationStatus status;
  final _StatusAction action;
  final bool isAdvancing;
  final int currentHeight;
  final VoidCallback? onAction;

  @override
  State<_MigrationStatusContent> createState() =>
      _MigrationStatusContentState();
}

class _MigrationStatusContentState extends State<_MigrationStatusContent> {
  String? _progressRunId;
  int _maxSeenCurrentHeight = 0;
  final Map<String, double> _maxSeenProgress = {};

  void _syncProgressRun(String runId) {
    if (_progressRunId == runId) return;
    _progressRunId = runId;
    _maxSeenCurrentHeight = 0;
    _maxSeenProgress.clear();
  }

  int _displayCurrentHeight(int currentHeight) {
    if (currentHeight > _maxSeenCurrentHeight) {
      _maxSeenCurrentHeight = currentHeight;
    }
    if (_maxSeenCurrentHeight > 0) return _maxSeenCurrentHeight;
    return currentHeight;
  }

  List<String> _progressKeys({
    required String runId,
    required String progressScope,
    required List<rust_sync.MigrationPartStatus> parts,
    required int count,
  }) {
    return [
      for (var i = 0; i < count; i++)
        '$runId:$progressScope:part:${parts.isNotEmpty && i < parts.length ? parts[i].partIndex : i}',
    ];
  }

  List<double> _monotonicProgresses({
    required List<String> keys,
    required List<_MigrationBatchStatus> statuses,
    required List<double> rawProgresses,
  }) {
    return [
      for (var i = 0; i < keys.length; i++)
        _monotonicProgress(
          key: keys[i],
          status: i < statuses.length
              ? statuses[i]
              : _MigrationBatchStatus.none,
          rawProgress: i < rawProgresses.length ? rawProgresses[i] : 0.0,
        ),
    ];
  }

  double _monotonicProgress({
    required String key,
    required _MigrationBatchStatus status,
    required double rawProgress,
  }) {
    final clampedProgress = status == _MigrationBatchStatus.complete
        ? 1.0
        : rawProgress.clamp(0, 1).toDouble();
    final previous = _maxSeenProgress[key] ?? 0.0;
    final next = math.max(previous, clampedProgress);
    _maxSeenProgress[key] = next;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final runId = status.activeRunId ?? 'inactive';
    _syncProgressRun(runId);

    final parts = _displayMigrationParts(status);
    var values = parts.isNotEmpty
        ? [for (final part in parts) part.valueZatoshi]
        : [for (final value in status.targetValuesZatoshi) value];
    if (values.isEmpty && status.phase != kIronwoodMigrationCompletePhase) {
      values = [BigInt.zero];
    }
    final partNumbers = parts.isNotEmpty
        ? [for (final part in parts) part.partIndex + 1]
        : [for (var i = 0; i < values.length; i++) i + 1];
    final statuses = status.phase == kIronwoodMigrationCompletePhase
        ? List<_MigrationBatchStatus>.filled(
            values.length,
            _MigrationBatchStatus.complete,
          )
        : parts.isNotEmpty
        ? [for (final part in parts) _migrationBatchStatus(part.state)]
        : _legacyMigrationBatchStatuses(status, values.length);
    if (widget.action == _StatusAction.needsInput &&
        !statuses.contains(_MigrationBatchStatus.needsInput)) {
      final inputIndex = statuses.indexWhere(
        (status) => status != _MigrationBatchStatus.complete,
      );
      if (inputIndex >= 0) {
        statuses[inputIndex] = _MigrationBatchStatus.needsInput;
      }
    }
    final total = values.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
    final displayCurrentHeight = _displayCurrentHeight(widget.currentHeight);
    final rawProgresses = _migrationBatchProgresses(
      status: status,
      parts: parts,
      statuses: statuses,
      currentHeight: displayCurrentHeight,
      isAdvancing: widget.isAdvancing,
    );
    final rawSegmentProgresses = [
      for (var i = 0; i < values.length; i++)
        _migrationSegmentProgress(
          values: values,
          totalZatoshi: total,
          statuses: statuses,
          progresses: rawProgresses,
          index: i,
        ),
    ];
    final progressKeys = _progressKeys(
      runId: runId,
      progressScope:
          status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase
          ? 'denomination'
          : 'transfer',
      parts: parts,
      count: values.length,
    );
    final progresses = _monotonicProgresses(
      keys: progressKeys,
      statuses: statuses,
      rawProgresses: rawSegmentProgresses,
    );
    if (_shouldShowPreparingStatusContent(status)) {
      return _MigrationPreparingStatusContent(
        key: ValueKey('ironwood_migration_preparing_${status.activeRunId}'),
        status: status,
        values: values,
        totalZatoshi: total,
        statuses: statuses,
        progresses: progresses,
        progressKeys: progressKeys,
      );
    }

    final spendableLabel = _migrationSpendableBalanceLabel(
      values: values,
      statuses: statuses,
    );
    final buttonLabel = switch (widget.action) {
      _StatusAction.needsInput => 'Sign with Keystone',
      _StatusAction.retry => 'Retry migration',
      _ => 'Go home',
    };
    final actionRequiresContinuation =
        widget.action == _StatusAction.needsInput ||
        widget.action == _StatusAction.retry;

    return SizedBox(
      key: ValueKey('ironwood_migration_status_${status.phase}'),
      width: 420,
      height: 656,
      child: Stack(
        children: [
          Positioned(
            top: 37.5,
            left: 12,
            width: 396,
            child: Column(
              children: [
                Text(
                  'Migration in Progress',
                  style: AppTypography.headlineSmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 24,
            width: 396,
            height: 540,
            child: _MigrationStatusBatchPanel(
              values: values,
              partNumbers: partNumbers,
              totalZatoshi: total,
              statuses: statuses,
              progresses: progresses,
              progressKeys: progressKeys,
              completionLabel: _transferEstimatedCompletion(
                status,
                currentHeight: displayCurrentHeight,
                needsInput: widget.action == _StatusAction.needsInput,
                parts: parts,
              ),
              spendableLabel: spendableLabel,
            ),
          ),
          Positioned(
            left: 95,
            top: 596,
            width: 230,
            child: Center(
              child: AppButton(
                key: const ValueKey('ironwood_migration_status_action_button'),
                onPressed: widget.isAdvancing && actionRequiresContinuation
                    ? null
                    : actionRequiresContinuation
                    ? widget.onAction
                    : () => context.go('/home'),
                variant: actionRequiresContinuation
                    ? AppButtonVariant.primary
                    : AppButtonVariant.secondary,
                height: 36,
                minWidth: widget.action == _StatusAction.needsInput ? 150 : 96,
                expand: false,
                child: SizedBox(
                  width: widget.action == _StatusAction.needsInput
                      ? 118
                      : widget.action == _StatusAction.retry
                      ? 92
                      : 64,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(buttonLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _shouldShowPreparingStatusContent(rust_sync.MigrationStatus status) =>
    status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase;
