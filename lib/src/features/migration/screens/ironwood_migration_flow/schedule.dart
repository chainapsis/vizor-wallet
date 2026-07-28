part of '../ironwood_migration_flow_screen.dart';

class IronwoodMigrationPreparationScheduleScreen extends ConsumerWidget {
  const IronwoodMigrationPreparationScheduleScreen({
    this.previewStatus,
    super.key,
  });

  final rust_sync.MigrationStatus? previewStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewStatus;
    if (preview != null) {
      return _frame(context, preview, ref.watch(syncProvider).asData?.value);
    }

    final request = ref.watch(ironwoodMigrationInputsProvider).statusRequest;
    if (request == null) {
      return _frame(
        context,
        null,
        ref.watch(syncProvider).asData?.value,
        statusUnavailable: true,
      );
    }
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    return ref
        .watch(ironwoodMigrationStatusProvider(request))
        .when(
          skipLoadingOnReload: true,
          loading: () => _frame(context, null, null),
          error: (_, _) {
            final cachedStatus = coordinator.statuses[request.accountUuid];
            return cachedStatus == null
                ? _frame(
                    context,
                    null,
                    null,
                    statusUnavailable: true,
                    onRetry: () => ref.invalidate(
                      ironwoodMigrationStatusProvider(request),
                    ),
                  )
                : _frame(
                    context,
                    cachedStatus,
                    ref.watch(syncProvider).asData?.value,
                  );
          },
          data: (status) =>
              _frame(context, status, ref.watch(syncProvider).asData?.value),
        );
  }

  Widget _frame(
    BuildContext context,
    rust_sync.MigrationStatus? status,
    SyncState? syncState, {
    bool statusUnavailable = false,
    VoidCallback? onRetry,
  }) {
    return _IronwoodMigrationFrame(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(
          key: const ValueKey(
            'ironwood_migration_preparation_schedule_back_button',
          ),
          label: 'Ironwood Migration',
          onTap: () => context.go('/migration/private/status'),
        ),
      ),
      disableSidebarActions: true,
      child: statusUnavailable
          ? _MigrationScheduleErrorContent(onRetry: onRetry)
          : status == null
          ? const Center(child: CircularProgressIndicator())
          : _MigrationPreparationScheduleContent(
              status: status,
              currentHeight: _currentMigrationHeight(syncState),
            ),
    );
  }
}

class IronwoodMigrationScheduleScreen extends ConsumerWidget {
  const IronwoodMigrationScheduleScreen({this.previewStatus, super.key});

  final rust_sync.MigrationStatus? previewStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewStatus;
    if (preview != null) {
      return _frame(context, preview, ref.watch(syncProvider).asData?.value);
    }

    final request = ref.watch(ironwoodMigrationInputsProvider).statusRequest;
    if (request == null) {
      return _frame(
        context,
        null,
        ref.watch(syncProvider).asData?.value,
        statusUnavailable: true,
      );
    }
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    return ref
        .watch(ironwoodMigrationStatusProvider(request))
        .when(
          skipLoadingOnReload: true,
          loading: () => _frame(context, null, null),
          error: (_, _) {
            final cachedStatus = coordinator.statuses[request.accountUuid];
            return cachedStatus == null
                ? _frame(
                    context,
                    null,
                    null,
                    statusUnavailable: true,
                    onRetry: () => ref.invalidate(
                      ironwoodMigrationStatusProvider(request),
                    ),
                  )
                : _frame(
                    context,
                    cachedStatus,
                    ref.watch(syncProvider).asData?.value,
                  );
          },
          data: (status) =>
              _frame(context, status, ref.watch(syncProvider).asData?.value),
        );
  }

  Widget _frame(
    BuildContext context,
    rust_sync.MigrationStatus? status,
    SyncState? syncState, {
    bool statusUnavailable = false,
    VoidCallback? onRetry,
  }) {
    return _IronwoodMigrationFrame(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(
          key: const ValueKey('ironwood_migration_schedule_back_button'),
          label: 'Ironwood Migration',
          onTap: () => context.go('/migration/private/status'),
        ),
      ),
      disableSidebarActions: true,
      child: statusUnavailable
          ? _MigrationScheduleErrorContent(onRetry: onRetry)
          : status == null
          ? const Center(child: CircularProgressIndicator())
          : _MigrationScheduleContent(
              status: status,
              currentHeight: _currentMigrationHeight(syncState),
            ),
    );
  }
}

class _MigrationPreparationScheduleContent extends StatelessWidget {
  const _MigrationPreparationScheduleContent({
    required this.status,
    required this.currentHeight,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final transactions = _orderedPreparationTransactions(status);
    final remaining = _preparationRemainingCount(status);
    final total = _preparationTotalCount(status);

    return SizedBox(
      width: 420,
      height: 656,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          Text(
            'Preparation Schedule',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: 35),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                _MigrationSummaryMetric(
                  label: 'Splits remaining',
                  value: '$remaining of $total',
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Est. completion',
                  value: _preparationCompletionEstimateDisplay(
                    status,
                    currentHeight,
                  ),
                  secondary: true,
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Current block',
                  value: formatGroupedInteger(currentHeight),
                  valueIcon: AppIcons.block,
                  secondary: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      'Preparing schedule',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListView.separated(
                      key: const ValueKey(
                        'ironwood_migration_preparation_schedule_list',
                      ),
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      itemCount: transactions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _MigrationPreparationScheduleRow(
                            key: ValueKey(
                              'ironwood_migration_preparation_schedule_stage_${transactions[index].stageIndex}',
                            ),
                            number: index + 1,
                            transaction: transactions[index],
                          ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MigrationPreparationScheduleRow extends StatelessWidget {
  const _MigrationPreparationScheduleRow({
    required this.number,
    required this.transaction,
    super.key,
  });

  final int number;
  final rust_sync.MigrationPreparationTransactionStatus transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: _preparationScheduleRowSemantics(number, transaction),
      excludeSemantics: true,
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.large),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$number. ~${_formatZecAmountCompact(transaction.approximateValueZatoshi)} ZEC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _MigrationPreparationScheduleStatus(transaction: transaction),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationPreparationScheduleStatus extends StatelessWidget {
  const _MigrationPreparationScheduleStatus({required this.transaction});

  final rust_sync.MigrationPreparationTransactionStatus transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = transaction.state;
    final active =
        state == rust_sync.MigrationPreparationTransactionState.broadcasted ||
        state == rust_sync.MigrationPreparationTransactionState.confirming;
    final completed =
        state == rust_sync.MigrationPreparationTransactionState.completed;
    final awaiting =
        state == rust_sync.MigrationPreparationTransactionState.awaitingInputs;
    final height =
        completed ||
            state == rust_sync.MigrationPreparationTransactionState.confirming
        ? transaction.minedHeight
        : transaction.scheduledHeight;
    final label = height == null
        ? awaiting
              ? 'Pending'
              : 'Due now'
        : formatGroupedInteger(height);
    final style = AppTypography.labelLarge.copyWith(
      color: completed
          ? colors.text.positiveStrong
          : awaiting
          ? const Color(0xFFB83AD9)
          : colors.text.secondary,
      fontWeight: FontWeight.w400,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active)
          IronwoodMigrationShimmerText(
            text: label,
            style: style,
            baseColor: colors.text.secondary,
            highlightColor: colors.text.accent,
            textAlign: TextAlign.right,
          )
        else
          Text(label, textAlign: TextAlign.right, style: style),
        const SizedBox(width: 4),
        AppIcon(
          completed
              ? AppIcons.checkCircle
              : active
              ? AppIcons.loader
              : awaiting
              ? AppIcons.migrationSplit
              : AppIcons.block,
          size: 16,
          color: completed
              ? colors.icon.success
              : awaiting
              ? const Color(0xFFB83AD9)
              : active
              ? colors.icon.accent
              : colors.icon.regular,
        ),
      ],
    );
  }
}

String _preparationScheduleRowSemantics(
  int number,
  rust_sync.MigrationPreparationTransactionStatus transaction,
) {
  final state = switch (transaction.state) {
    rust_sync.MigrationPreparationTransactionState.awaitingInputs =>
      'waiting for previous split',
    rust_sync.MigrationPreparationTransactionState.scheduled => 'scheduled',
    rust_sync.MigrationPreparationTransactionState.broadcasted =>
      'broadcast, waiting to be mined',
    rust_sync.MigrationPreparationTransactionState.confirming =>
      'confirming, ${transaction.confirmationCount} of '
          '${transaction.confirmationTarget} confirmations',
    rust_sync.MigrationPreparationTransactionState.completed => 'completed',
  };
  return 'Split $number, approximately '
      '${_formatZecAmountCompact(transaction.approximateValueZatoshi)} ZEC, '
      '$state.';
}

class _MigrationScheduleErrorContent extends StatelessWidget {
  const _MigrationScheduleErrorContent({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('ironwood_migration_schedule_error'),
      width: 420,
      height: 656,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Migration schedule unavailable',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 318,
            child: Text(
              "Vizor couldn't load the latest migration schedule. "
              'Your saved migration state is unchanged.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 24),
            AppButton(
              key: const ValueKey('ironwood_migration_schedule_retry'),
              onPressed: onRetry,
              height: 44,
              minWidth: 160,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MigrationScheduleContent extends StatelessWidget {
  const _MigrationScheduleContent({
    required this.status,
    required this.currentHeight,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = [..._displayMigrationParts(status)]
      ..sort(_compareMigrationPartsByExpectedProcessingOrder);
    final total = _sumTargetValues(status);
    final completed = parts
        .where((part) => part.state == rust_sync.MigrationPartState.completed)
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);
    final leftToMigrate = total - completed;

    return SizedBox(
      width: 420,
      height: 656,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 18),
          Text(
            'Migration Schedule',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: 35),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                _MigrationSummaryMetric(
                  label: 'Left to migrate',
                  value:
                      '${_formatZecAmountCompact(leftToMigrate > BigInt.zero ? leftToMigrate : BigInt.zero)} ZEC',
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Est. completion',
                  value: _migrationCompletionEstimateDisplay(
                    status,
                    currentHeight: currentHeight,
                    needsInput: false,
                    parts: parts,
                  ),
                  secondary: true,
                ),
                const SizedBox(height: 16),
                _MigrationSummaryMetric(
                  label: 'Current block',
                  value: formatGroupedInteger(currentHeight),
                  valueIcon: AppIcons.block,
                  secondary: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.separated(
                key: const ValueKey('ironwood_migration_schedule_list'),
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                itemCount: parts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final part = parts[index];
                  return KeyedSubtree(
                    key: ValueKey(
                      'ironwood_migration_schedule_part_${part.partIndex}',
                    ),
                    child: _MigrationScheduleRow(
                      number: index + 1,
                      part: part,
                      total: total,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MigrationScheduleRow extends StatelessWidget {
  const _MigrationScheduleRow({
    required this.number,
    required this.part,
    required this.total,
  });

  final int number;
  final rust_sync.MigrationPartStatus part;
  final BigInt total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = part.valueZatoshi;
    return Semantics(
      label: _migrationScheduleRowSemantics(number, part),
      excludeSemantics: true,
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.large),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: '$number. ${_formatZecAmountCompact(value)} ZEC ',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: _migrationPercentage(value, total),
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _MigrationSchedulePartStatus(part: part),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MigrationSchedulePartStatus extends StatelessWidget {
  const _MigrationSchedulePartStatus({required this.part});

  final rust_sync.MigrationPartStatus part;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = part.state;
    final active =
        state == rust_sync.MigrationPartState.migrating ||
        state == rust_sync.MigrationPartState.confirming;
    final completed = state == rust_sync.MigrationPartState.completed;
    final needsInput = state == rust_sync.MigrationPartState.needsInput;
    final height = part.scheduledHeight;
    final label = height == null
        ? needsInput
              ? 'Ready to sign'
              : 'Schedule pending'
        : formatGroupedInteger(height);
    final textStyle = AppTypography.labelLarge.copyWith(
      color: completed
          ? colors.text.positiveStrong
          : needsInput
          ? const Color(0xFFB83AD9)
          : colors.text.secondary,
      fontWeight: FontWeight.w400,
    );
    final icon = completed
        ? AppIcons.checkCircle
        : active
        ? AppIcons.loader
        : needsInput
        ? AppIcons.migrationSign
        : AppIcons.block;
    final iconColor = completed
        ? colors.icon.success
        : needsInput
        ? const Color(0xFFB83AD9)
        : active
        ? colors.icon.accent
        : colors.icon.regular;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active)
          IronwoodMigrationShimmerText(
            text: label,
            style: textStyle,
            baseColor: colors.text.secondary,
            highlightColor: colors.text.accent,
            textAlign: TextAlign.right,
          )
        else
          Text(label, textAlign: TextAlign.right, style: textStyle),
        const SizedBox(width: 4),
        AppIcon(icon, size: 16, color: iconColor),
      ],
    );
  }
}

String _migrationScheduleRowSemantics(
  int number,
  rust_sync.MigrationPartStatus part,
) {
  final height = part.scheduledHeight;
  final heightLabel = height == null
      ? 'schedule pending'
      : 'block ${formatGroupedInteger(height)}';
  final stateLabel = switch (part.state) {
    rust_sync.MigrationPartState.preparing => 'preparing',
    rust_sync.MigrationPartState.scheduled => 'scheduled',
    rust_sync.MigrationPartState.migrating => 'broadcast, waiting to be mined',
    rust_sync.MigrationPartState.confirming =>
      'confirming, ${part.confirmationCount} of '
          '${part.confirmationTarget} confirmations',
    rust_sync.MigrationPartState.completed => 'completed',
    rust_sync.MigrationPartState.needsInput => 'ready to sign',
  };
  return 'Note $number, ${_formatZecAmountCompact(part.valueZatoshi)} ZEC, '
      '$heightLabel, $stateLabel.';
}
