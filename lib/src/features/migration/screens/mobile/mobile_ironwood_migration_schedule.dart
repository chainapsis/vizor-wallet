part of 'mobile_ironwood_migration_flow_screen.dart';

class MobileIronwoodMigrationScheduleScreen extends ConsumerWidget {
  const MobileIronwoodMigrationScheduleScreen({this.previewStatus, super.key});

  final rust_sync.MigrationStatus? previewStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MobileMigrationScheduleLoader(
      previewStatus: previewStatus,
      preparation: false,
    );
  }
}

class MobileIronwoodMigrationPreparationScheduleScreen extends ConsumerWidget {
  const MobileIronwoodMigrationPreparationScheduleScreen({
    this.previewStatus,
    super.key,
  });

  final rust_sync.MigrationStatus? previewStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MobileMigrationScheduleLoader(
      previewStatus: previewStatus,
      preparation: true,
    );
  }
}

class _MobileMigrationScheduleLoader extends ConsumerWidget {
  const _MobileMigrationScheduleLoader({
    required this.previewStatus,
    required this.preparation,
  });

  final rust_sync.MigrationStatus? previewStatus;
  final bool preparation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = previewStatus;
    final syncState = ref.watch(syncProvider).asData?.value;
    if (preview != null) {
      return _screen(
        context,
        status: preview,
        currentHeight: _mobileMigrationHeight(syncState),
      );
    }

    final request = ref.watch(ironwoodMigrationInputsProvider).statusRequest;
    if (request == null) {
      return _screen(
        context,
        currentHeight: _mobileMigrationHeight(syncState),
        unavailable: true,
      );
    }
    final coordinator = ref.watch(ironwoodMigrationCoordinatorProvider);
    return ref
        .watch(ironwoodMigrationStatusProvider(request))
        .when(
          skipLoadingOnReload: true,
          loading: () => _screen(context, currentHeight: 0),
          error: (_, _) {
            final cached = coordinator.statuses[request.accountUuid];
            return _screen(
              context,
              status: cached,
              currentHeight: _mobileMigrationHeight(syncState),
              unavailable: cached == null,
              onRetry: () =>
                  ref.invalidate(ironwoodMigrationStatusProvider(request)),
            );
          },
          data: (status) => _screen(
            context,
            status: status,
            currentHeight: _mobileMigrationHeight(syncState),
          ),
        );
  }

  Widget _screen(
    BuildContext context, {
    rust_sync.MigrationStatus? status,
    required int currentHeight,
    bool unavailable = false,
    VoidCallback? onRetry,
  }) {
    void returnToStatus() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/migration/private/status');
      }
    }

    return _MobileIronwoodMigrationBackScope(
      // Same destination as the chevron: the scope pops when this screen was
      // pushed, and falls back to the status route when it was not.
      onFallback: () => context.go('/migration/private/status'),
      child: Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: preparation
                    ? 'Preparation Schedule'
                    : 'Migration Schedule',
                titleStyle: AppTypography.headlineSmall.copyWith(
                  color: context.colors.text.accent,
                ),
                onBack: returnToStatus,
              ),
              Expanded(
                child: unavailable
                    ? _MobileMigrationScheduleError(onRetry: onRetry)
                    : status == null
                    ? const Center(
                        child: AppIcon(
                          AppIcons.loader,
                          size: 24,
                          semanticLabel: 'Loading migration schedule',
                        ),
                      )
                    : preparation
                    ? _MobilePreparationScheduleContent(
                        status: status,
                        currentHeight: currentHeight,
                        onReturn: returnToStatus,
                      )
                    : _MobileMigrationScheduleContent(
                        status: status,
                        currentHeight: currentHeight,
                        onReturn: returnToStatus,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileMigrationScheduleContent extends StatelessWidget {
  const _MobileMigrationScheduleContent({
    required this.status,
    required this.currentHeight,
    required this.onReturn,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final parts = orderedMigrationParts(status.parts);
    final total = migrationTargetTotal(status);
    final completed = migrationCompletedValue(status);
    final estimatedCompletionHeight = status.estimatedCompletionHeight;
    final duration = estimatedCompletionHeight == null
        ? 'Schedule pending'
        : currentHeight <= 0
        ? 'Calculating'
        : migrationHeightRemainingDurationLabel(
            estimatedCompletionHeight,
            currentHeight: currentHeight,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          Expanded(
            child: parts.isEmpty
                ? Center(
                    child: Text(
                      'Preparing schedule',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey(
                      'mobile_ironwood_migration_schedule_list',
                    ),
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    itemCount: parts.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.s),
                    itemBuilder: (context, index) {
                      final part = parts[index];
                      return _MobileMigrationPartScheduleRow(
                        key: ValueKey(
                          'mobile_ironwood_migration_schedule_part_'
                          '${part.partIndex}',
                        ),
                        number: index + 1,
                        part: part,
                        total: total,
                        currentHeight: currentHeight,
                      );
                    },
                  ),
          ),
          _MobileMigrationScheduleFooter(
            primaryIcon: AppIcons.wallet,
            title: 'Ironwood spendable',
            value: '${_migrationDisplayZec(completed)} ZEC',
            secondaryIcon: AppIcons.migrationTimer,
            secondaryLabel: 'Duration',
            secondaryValue: duration,
            onReturn: onReturn,
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationPartScheduleRow extends StatelessWidget {
  const _MobileMigrationPartScheduleRow({
    required this.number,
    required this.part,
    required this.total,
    required this.currentHeight,
    super.key,
  });

  final int number;
  final rust_sync.MigrationPartStatus part;
  final BigInt total;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    final (label, icon, iconSize, color) = _migrationPartScheduleState(
      context,
      part,
      currentHeight: currentHeight,
    );
    return SizedBox(
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text:
                        '$number. ${_migrationDisplayZec(part.valueZatoshi)} ZEC ',
                    style: AppTypography.labelLarge.copyWith(
                      color: context.colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(
                        text: _mobileSchedulePercentage(
                          part.valueZatoshi,
                          total,
                        ),
                        style: AppTypography.labelLarge.copyWith(
                          color: context.colors.text.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 150,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (icon != null) ...[
                      AppIcon(icon, size: iconSize, color: color),
                      const SizedBox(width: AppSpacing.xxs),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobilePreparationScheduleContent extends StatelessWidget {
  const _MobilePreparationScheduleContent({
    required this.status,
    required this.currentHeight,
    required this.onReturn,
  });

  final rust_sync.MigrationStatus status;
  final int currentHeight;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final transactions = orderedMigrationPreparationTransactions(status);
    final rounds = _mobilePreparationRounds(transactions);
    final currentRound = _mobileCurrentPreparationRound(rounds);
    final finalHeight = transactions.fold<int>(
      currentHeight,
      (height, transaction) =>
          math.max(height, transaction.projectedCompletionHeight),
    );
    final duration = currentHeight <= 0
        ? 'Calculating'
        : migrationHeightRemainingDurationLabel(
            finalHeight,
            currentHeight: currentHeight,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          _MobilePreparationScheduleSummary(
            rounds: rounds.isEmpty
                ? 'Calculating'
                : '$currentRound of ${rounds.length}',
            estimatedCompletion: duration,
            currentHeight: currentHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      'Preparing schedule',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const ValueKey(
                      'mobile_ironwood_preparation_schedule_list',
                    ),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    itemCount: rounds.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        _MobilePreparationRoundSection(
                          round: rounds[index].$1,
                          transactions: rounds[index].$2,
                        ),
                  ),
          ),
          _MobileMigrationScheduleFooter(
            primaryIcon: AppIcons.migrationSplit,
            title: 'Preparation progress',
            value:
                '${status.denominationSplitCompletedCount} of '
                '${status.denominationSplitTotalCount}',
            secondaryIcon: AppIcons.migrationTimer,
            secondaryLabel: 'Ready in',
            secondaryValue: duration,
            onReturn: onReturn,
          ),
        ],
      ),
    );
  }
}

class _MobilePreparationRoundSection extends StatelessWidget {
  const _MobilePreparationRoundSection({
    required this.round,
    required this.transactions,
  });

  final int round;
  final List<rust_sync.MigrationPreparationTransactionStatus> transactions;

  @override
  Widget build(BuildContext context) {
    final total = transactions.fold(
      BigInt.zero,
      (sum, transaction) => sum + transaction.approximateValueZatoshi,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Split round $round',
          style: AppTypography.labelLarge.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var index = 0; index < transactions.length; index++) ...[
          _MobilePreparationTransactionCard(
            transaction: transactions[index],
            roundTotal: total,
          ),
          if (index != transactions.length - 1)
            const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _MobilePreparationTransactionCard extends StatelessWidget {
  const _MobilePreparationTransactionCard({
    required this.transaction,
    required this.roundTotal,
  });

  final rust_sync.MigrationPreparationTransactionStatus transaction;
  final BigInt roundTotal;

  @override
  Widget build(BuildContext context) {
    final state = transaction.state;
    final completed =
        state == rust_sync.MigrationPreparationTransactionState.completed;
    final active =
        state == rust_sync.MigrationPreparationTransactionState.broadcasted ||
        state == rust_sync.MigrationPreparationTransactionState.confirming;
    final stateLabel = switch (state) {
      rust_sync.MigrationPreparationTransactionState.awaitingInputs =>
        'Next round',
      rust_sync.MigrationPreparationTransactionState.scheduled => 'Scheduled',
      rust_sync.MigrationPreparationTransactionState.broadcasted =>
        'Waiting to be mined',
      rust_sync.MigrationPreparationTransactionState.confirming =>
        'Confirming ${transaction.confirmationCount}/'
            '${transaction.confirmationTarget}',
      rust_sync.MigrationPreparationTransactionState.completed => 'Completed',
    };
    final stateColor = completed
        ? context.colors.text.positiveStrong
        : context.colors.text.secondary;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.background.ground,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      key: ValueKey(
                        'mobile_ironwood_preparation_value_'
                        '${transaction.stageIndex}',
                      ),
                      '${_migrationDisplayZec(transaction.approximateValueZatoshi)} ZEC '
                      '${_mobileSchedulePercentage(transaction.approximateValueZatoshi, roundTotal)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: context.colors.text.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Row(
                    key: ValueKey(
                      'mobile_ironwood_preparation_state_'
                      '${transaction.stageIndex}',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (completed) ...[
                        AppIcon(
                          AppIcons.checkCircle,
                          size: 16,
                          color: context.colors.icon.success,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ] else if (active) ...[
                        AppIcon(
                          AppIcons.loader,
                          size: 16,
                          color: context.colors.icon.regular,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ] else if (state ==
                          rust_sync
                              .MigrationPreparationTransactionState
                              .scheduled) ...[
                        AppIcon(
                          AppIcons.block,
                          size: 16,
                          color: context.colors.icon.regular,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                      Text(
                        stateLabel,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.right,
                        style: AppTypography.labelLarge.copyWith(
                          color: stateColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (transaction.outputs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < transaction.outputs.length;
                  index++
                ) ...[
                  _MobilePreparationOutputRow(
                    output: transaction.outputs[index],
                  ),
                  if (index != transaction.outputs.length - 1)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MobilePreparationOutputRow extends StatelessWidget {
  const _MobilePreparationOutputRow({required this.output});

  final rust_sync.MigrationPreparationOutputStatus output;

  @override
  Widget build(BuildContext context) {
    final value =
        output.kind == rust_sync.MigrationPreparationOutputKind.migration
        ? output.targetValueZatoshi ?? output.valueZatoshi
        : output.valueZatoshi;
    final destination = switch (output.kind) {
      rust_sync.MigrationPreparationOutputKind.migration => 'Migration note',
      rust_sync.MigrationPreparationOutputKind.change => 'Change',
      rust_sync.MigrationPreparationOutputKind.continuation =>
        output.nextRound == null ? 'Next round' : 'Round ${output.nextRound}',
    };
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          AppIcon(
            AppIcons.subArrow,
            size: 16,
            color: context.colors.icon.regular,
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              '${_migrationDisplayZec(value)} ZEC',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          Text(
            destination,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobilePreparationScheduleSummary extends StatelessWidget {
  const _MobilePreparationScheduleSummary({
    required this.rounds,
    required this.estimatedCompletion,
    required this.currentHeight,
  });

  final String rounds;
  final String estimatedCompletion;
  final int currentHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.s,
      ),
      child: Column(
        children: [
          _MobilePreparationScheduleInfoRow(
            label: 'Rounds remaining',
            value: rounds,
            emphasized: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobilePreparationScheduleInfoRow(
            label: 'Est. completion',
            value: estimatedCompletion,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MobilePreparationScheduleInfoRow(
            label: 'Current block',
            value: currentHeight <= 0
                ? '—'
                : formatGroupedInteger(currentHeight),
            trailingIcon: AppIcons.block,
          ),
        ],
      ),
    );
  }
}

class _MobilePreparationScheduleInfoRow extends StatelessWidget {
  const _MobilePreparationScheduleInfoRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final bool emphasized;
  final String? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final color = emphasized
        ? context.colors.text.accent
        : context.colors.text.primary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: color),
          ),
        ),
        if (trailingIcon != null) ...[
          AppIcon(trailingIcon!, size: 16, color: context.colors.icon.regular),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Text(value, style: AppTypography.labelLarge.copyWith(color: color)),
      ],
    );
  }
}

class _MobileMigrationScheduleFooter extends StatelessWidget {
  const _MobileMigrationScheduleFooter({
    required this.primaryIcon,
    required this.title,
    required this.value,
    required this.secondaryIcon,
    required this.secondaryLabel,
    required this.secondaryValue,
    required this.onReturn,
  });

  final String primaryIcon;
  final String title;
  final String value;
  final String secondaryIcon;
  final String secondaryLabel;
  final String secondaryValue;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Column(
                children: [
                  _MobileMigrationFooterRow(
                    icon: primaryIcon,
                    label: title,
                    value: value,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MobileMigrationFooterRow(
                    icon: secondaryIcon,
                    label: secondaryLabel,
                    value: secondaryValue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                key: const ValueKey('mobile_ironwood_schedule_return_button'),
                onPressed: onReturn,
                expand: true,
                height: 50,
                child: const Text('Return'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMigrationFooterRow extends StatelessWidget {
  const _MobileMigrationFooterRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: AppIcon(icon, size: 20, color: context.colors.icon.regular),
          ),
          Expanded(
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationScheduleError extends StatelessWidget {
  const _MobileMigrationScheduleError({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Migration schedule unavailable',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              "Vizor couldn't load the latest schedule. "
              'Your saved migration state is unchanged.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

int _mobileMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  return mobileIronwoodSafelyObservedHeight(
    scannedHeight: syncState.scannedHeight,
    chainTipHeight: syncState.chainTipHeight,
  );
}

String _mobileSchedulePercentage(BigInt value, BigInt total) {
  if (total <= BigInt.zero) return '0%';
  final basisPoints = (value * BigInt.from(10_000)) ~/ total;
  final percentage = basisPoints.toDouble() / 100;
  return percentage == percentage.roundToDouble()
      ? '${percentage.toInt()}%'
      : '${percentage.toStringAsFixed(1)}%';
}

(String, String?, double, Color) _migrationPartScheduleState(
  BuildContext context,
  rust_sync.MigrationPartStatus part, {
  required int currentHeight,
}) {
  final scheduledHeight = part.effectiveScheduledHeight ?? part.scheduledHeight;
  final scheduledInFuture =
      scheduledHeight != null && scheduledHeight > currentHeight;
  return switch (part.state) {
    rust_sync.MigrationPartState.completed => (
      'Completed',
      AppIcons.checkCircle,
      20,
      context.colors.text.positiveStrong,
    ),
    rust_sync.MigrationPartState.confirming => (
      'Confirming ${part.confirmationCount}/${part.confirmationTarget}',
      AppIcons.loader,
      20,
      context.colors.text.secondary,
    ),
    rust_sync.MigrationPartState.migrating => (
      'Migrating…',
      AppIcons.loader,
      20,
      context.colors.text.secondary,
    ),
    rust_sync.MigrationPartState.needsInput => (
      'Ready to sign',
      AppIcons.migrationSign,
      20,
      const Color(0xFFB83AD9),
    ),
    rust_sync.MigrationPartState.preparing => (
      'Preparing',
      AppIcons.block,
      16,
      context.colors.text.secondary,
    ),
    rust_sync.MigrationPartState.scheduled => (
      scheduledHeight == null
          ? 'Schedule pending'
          : scheduledHeight <= currentHeight
          ? 'Due now'
          : formatGroupedInteger(scheduledHeight),
      scheduledInFuture ? AppIcons.block : null,
      scheduledInFuture ? 16 : 0,
      context.colors.text.secondary,
    ),
  };
}

List<(int, List<rust_sync.MigrationPreparationTransactionStatus>)>
_mobilePreparationRounds(
  List<rust_sync.MigrationPreparationTransactionStatus> transactions,
) {
  final grouped =
      <int, List<rust_sync.MigrationPreparationTransactionStatus>>{};
  for (final transaction in transactions) {
    grouped.putIfAbsent(transaction.round, () => []).add(transaction);
  }
  return [for (final entry in grouped.entries) (entry.key, entry.value)]
    ..sort((left, right) => left.$1.compareTo(right.$1));
}

int _mobileCurrentPreparationRound(
  List<(int, List<rust_sync.MigrationPreparationTransactionStatus>)> rounds,
) {
  for (var index = 0; index < rounds.length; index++) {
    if (rounds[index].$2.any(
      (transaction) =>
          transaction.state !=
          rust_sync.MigrationPreparationTransactionState.completed,
    )) {
      return index + 1;
    }
  }
  return rounds.length;
}
