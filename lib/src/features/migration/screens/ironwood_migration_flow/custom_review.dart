part of '../ironwood_migration_flow_screen.dart';

class IronwoodMigrationCustomContent extends ConsumerStatefulWidget {
  const IronwoodMigrationCustomContent({
    required this.data,
    this.previewPlan,
    this.mobileLayout = false,
    super.key,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final bool mobileLayout;

  @override
  ConsumerState<IronwoodMigrationCustomContent> createState() =>
      _IronwoodMigrationCustomContentState();
}

class _IronwoodMigrationCustomContentState
    extends ConsumerState<IronwoodMigrationCustomContent> {
  static const _amountGroupPresets = [4, 12, 32, 64];
  static const _parallelSchedulePresets = [1, 2, 4, 8, 16, 32];

  var _amountGroupCount = 12;
  var _parallelScheduleCount = 2;
  late BigInt _planSeed;
  rust_sync.OrchardMigrationPrivatePlan? _previewPlan;
  var _isStarting = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    final preview = widget.previewPlan;
    _previewPlan = preview;
    _amountGroupCount = preview?.customAmountGroupCount ?? _amountGroupCount;
    _parallelScheduleCount =
        preview?.customParallelScheduleCount ?? _parallelScheduleCount;
    _planSeed = preview?.customPlanSeed ?? _newCustomPlanSeed();
  }

  IronwoodMigrationCustomPlanRequest get _request =>
      IronwoodMigrationCustomPlanRequest(
        amountGroupCount: _amountGroupCount,
        parallelScheduleCount: _parallelScheduleCount,
        planSeed: _planSeed,
      );

  void _selectAmountGroupCount(int value) {
    setState(() {
      _amountGroupCount = value;
      _parallelScheduleCount = math.min(_parallelScheduleCount, value);
      _previewPlan = null;
      _startError = null;
    });
  }

  void _selectParallelScheduleCount(int value) {
    setState(() {
      _parallelScheduleCount = value;
      _previewPlan = null;
      _startError = null;
    });
  }

  void _resample() {
    setState(() {
      _planSeed = _newCustomPlanSeed();
      _previewPlan = null;
      _startError = null;
    });
  }

  Future<void> _startCustomMigration(
    rust_sync.OrchardMigrationPrivatePlan plan,
  ) async {
    if (_isStarting) return;
    if (widget.mobileLayout) {
      setState(() {
        _isStarting = true;
        _startError = null;
      });
      try {
        final authorization = await ref
            .read(ironwoodMigrationServiceProvider)
            .notificationAuthorizationStatus();
        if (!mounted) return;
        context.go(
          authorization.allowsBackgroundMigration
              ? '/migration/private/start'
              : '/migration/private/notifications',
          extra: plan,
        );
      } catch (_) {
        if (!mounted) return;
        // Notification status is fail-closed. The explanation screen lets the
        // user retry permission or explicitly continue with Vizor open.
        context.go('/migration/private/notifications', extra: plan);
      } finally {
        if (mounted) setState(() => _isStarting = false);
      }
      return;
    }
    IronwoodMigrationStatusRequest? statusRequest;
    setState(() {
      _isStarting = true;
      _startError = null;
    });
    try {
      final accountState = await ref.read(accountProvider.future);
      if (!mounted) return;
      final accountUuid = accountState.activeAccountUuid;
      if (accountUuid == null) {
        throw StateError('No active account is selected.');
      }
      statusRequest = IronwoodMigrationStatusRequest(
        network: ref.read(ironwoodMigrationInputsProvider).network,
        accountUuid: accountUuid,
      );
      if (accountState.activeAccount?.isHardware ?? false) {
        await ref
            .read(ironwoodMigrationServiceProvider)
            .saveCustomMigrationDraft(
              accountUuid: accountUuid,
              approvedPlan: plan,
            );
        if (!mounted) return;
        context.go(
          '/migration/private/keystone/denominations/sign',
          extra: plan.scheduledTransfers,
        );
        return;
      }
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .startSoftwareCustomMigration(
            accountUuid: accountUuid,
            approvedPlan: plan,
          );
      if (!mounted) return;
      _invalidateIronwoodMigrationStatusState(
        ref,
        statusRequest: statusRequest,
      );
      context.go('/migration/private/status');
    } catch (error) {
      if (!mounted) return;
      final request = statusRequest;
      if (request != null && await _customMigrationMayHaveStarted(request)) {
        if (!mounted) return;
        _invalidateIronwoodMigrationStatusState(ref, statusRequest: request);
        context.go('/migration/private/status');
        return;
      }
      if (!mounted) return;
      setState(() {
        _startError = _privateMigrationStartErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<bool> _customMigrationMayHaveStarted(
    IronwoodMigrationStatusRequest request,
  ) async {
    ref.invalidate(ironwoodMigrationStatusProvider(request));
    try {
      final status = await ref
          .read(ironwoodMigrationStatusProvider(request).future)
          .timeout(_privateStatusStartVerificationTimeout);
      return status.activeRunId != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewPlan;
    final planAsync = preview == null
        ? ref.watch(ironwoodMigrationCustomPlanProvider(_request))
        : AsyncValue<rust_sync.OrchardMigrationPrivatePlan?>.data(preview);
    final plan = planAsync.asData?.value;
    final colors = context.colors;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Custom migration',
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose an amount distribution and migration schedule. The expected '
          'note distribution and timeline update with every change.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CustomPresetControl(
          key: const ValueKey('custom_migration_amount_group_control'),
          optionKeyPrefix: 'custom_migration_amount_group',
          title: 'Amount groups',
          valueLabel: '$_amountGroupCount groups',
          value: _amountGroupCount,
          body:
              'Choose how many groups are used to build the migration amount '
              'mix. More groups generally produce more, lower-value notes.',
          options: _amountGroupPresets,
          onSelected: _selectAmountGroupCount,
          headerAction: AppIconHoverButton(
            key: const ValueKey('custom_migration_resample'),
            icon: AppIcons.dice,
            semanticLabel: 'Try a different balance sample',
            tooltip:
                'Generate a new balance distribution with the same settings.',
            size: 28,
            iconSize: 18,
            onTap: _resample,
          ),
        ),
        const SizedBox(height: 12),
        _CustomPresetControl(
          key: const ValueKey('custom_migration_parallel_schedule_control'),
          optionKeyPrefix: 'custom_migration_parallel_schedule',
          title: 'Parallel migration schedules',
          valueLabel: '$_parallelScheduleCount at once',
          value: _parallelScheduleCount,
          body:
              'Run this many migration schedules in parallel. More parallel '
              'schedules shorten the overall timeline.',
          options: _parallelSchedulePresets
              .where((value) => value <= _amountGroupCount)
              .toList(),
          onSelected: _selectParallelScheduleCount,
        ),
      ],
    );
    final summary = plan == null ? null : _CustomPlanSummary(plan: plan);
    final distribution = planAsync.isLoading
        ? const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          )
        : planAsync.hasError || plan == null
        ? const _PrivateReviewUnavailable(
            title: "Couldn't build a custom plan",
            body: 'Wait for sync to finish, then try again.',
          )
        : _CustomDenominationHistogram(plan: plan);
    final timeline = plan == null ? null : _CustomScheduleTimeline(plan: plan);
    final footer = plan == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_startError != null) ...[
                Text(
                  _startError!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.warning,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              Center(
                child: AppButton(
                  key: const ValueKey('custom_migration_continue_button'),
                  expand: widget.mobileLayout,
                  constrainContent: widget.mobileLayout,
                  onPressed: _isStarting
                      ? null
                      : () => unawaited(_startCustomMigration(plan)),
                  height: 44,
                  minWidth: 230,
                  trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                  child: Text(
                    _isStarting ? 'Saving plan...' : 'Continue to signing',
                  ),
                ),
              ),
            ],
          );

    return _CustomMigrationLayout(
      mobileLayout: widget.mobileLayout,
      header: header,
      controls: controls,
      summary: summary,
      distribution: distribution,
      timeline: timeline,
      footer: footer,
    );
  }
}

class _CustomMigrationLayout extends StatelessWidget {
  const _CustomMigrationLayout({
    required this.mobileLayout,
    required this.header,
    required this.controls,
    required this.distribution,
    this.summary,
    this.timeline,
    this.footer,
  });

  final bool mobileLayout;
  final Widget header;
  final Widget controls;
  final Widget? summary;
  final Widget distribution;
  final Widget? timeline;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    if (mobileLayout) {
      return SizedBox(
        key: const ValueKey('ironwood_migration_custom_screen'),
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            34,
            AppSpacing.sm,
            24,
          ),
          child: _singleColumn(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 960.0;
        final contentWidth = math.min(
          960.0,
          math.max(420.0, availableWidth - 40),
        );
        final useWorkspace = contentWidth >= 720;
        return SizedBox(
          key: const ValueKey('ironwood_migration_custom_screen'),
          width: contentWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            child: useWorkspace ? _workspace() : _singleColumn(),
          ),
        );
      },
    );
  }

  Widget _workspace() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 18),
        Table(
          columnWidths: const {
            0: FixedColumnWidth(330),
            1: FixedColumnWidth(16),
            2: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            TableRow(children: [controls, const SizedBox(), distribution]),
            if (summary != null || timeline != null)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: summary ?? const SizedBox(),
                  ),
                  const SizedBox(),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: timeline ?? const SizedBox(),
                  ),
                ],
              ),
          ],
        ),
        if (footer != null) ...[const SizedBox(height: 18), footer!],
      ],
    );
  }

  Widget _singleColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 18),
        controls,
        if (summary != null) ...[const SizedBox(height: 16), summary!],
        const SizedBox(height: 12),
        distribution,
        if (timeline != null) ...[const SizedBox(height: 12), timeline!],
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    );
  }
}

BigInt _newCustomPlanSeed() {
  final random = math.Random.secure();
  return (BigInt.from(random.nextInt(1 << 30)) << 30) |
      BigInt.from(random.nextInt(1 << 30));
}

class _CustomPresetControl extends StatelessWidget {
  const _CustomPresetControl({
    required this.optionKeyPrefix,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.body,
    required this.options,
    required this.onSelected,
    this.headerAction,
    super.key,
  });

  final String optionKeyPrefix;
  final String title;
  final String valueLabel;
  final int value;
  final String body;
  final List<int> options;
  final ValueChanged<int> onSelected;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                if (headerAction != null) ...[
                  headerAction!,
                  const SizedBox(width: 8),
                ],
                Text(
                  valueLabel,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  GestureDetector(
                    key: ValueKey('${optionKeyPrefix}_$option'),
                    onTap: () => onSelected(option),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: option == value
                            ? colors.text.accent
                            : colors.background.raised,
                        shape: StadiumBorder(
                          side: BorderSide(color: colors.border.subtle),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          '$option',
                          style: AppTypography.labelMedium.copyWith(
                            color: option == value
                                ? colors.background.ground
                                : colors.text.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomPlanSummary extends StatelessWidget {
  const _CustomPlanSummary({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final signingRounds =
        (plan.plannedBatchCount / math.max(1, plan.signingBatchLimit)).ceil();
    return _CustomPlanCard(
      key: const ValueKey('custom_migration_plan_summary'),
      title: 'Exact plan',
      children: [
        _CustomFact(
          label: 'Balance to migrate',
          value: '${_formatZecAmountCompact(plan.totalInputZatoshi)} ZEC',
        ),
        _CustomFact(
          label: 'Ironwood notes',
          value: '${plan.plannedBatchCount}',
        ),
        _CustomFact(
          label: 'Preparation transactions',
          value: '${plan.denominationSplitStageCount}',
        ),
        _CustomFact(label: 'Signing batches', value: '$signingRounds'),
        _CustomFact(
          label: 'Estimated fees',
          value:
              '${_formatZecAmountCompact(plan.estimatedTotalFeeZatoshi)} ZEC',
        ),
      ],
    );
  }
}

class _CustomDenominationHistogram extends StatelessWidget {
  const _CustomDenominationHistogram({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final counts = <BigInt, int>{};
    for (final value in plan.targetValuesZatoshi) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((left, right) => right.key.compareTo(left.key));
    final maxCount = entries.fold<int>(
      1,
      (maximum, entry) => math.max(maximum, entry.value),
    );
    return _CustomPlanCard(
      key: const ValueKey('custom_migration_histogram'),
      title: 'Expected note distribution',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = constraints.maxWidth >= 340 ? 2 : 1;
            final rowWidth = columnCount == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: rowWidth,
                    child: _CustomHistogramRow(
                      denomination: entry.key,
                      count: entry.value,
                      maxCount: maxCount,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CustomHistogramRow extends StatelessWidget {
  const _CustomHistogramRow({
    required this.denomination,
    required this.count,
    required this.maxCount,
  });

  final BigInt denomination;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 240;
        return Row(
          children: [
            SizedBox(
              width: compact ? 52 : 74,
              child: Text(
                _formatZecAmountCompact(denomination),
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 8,
                    width: constraints.maxWidth * count / maxCount,
                    decoration: BoxDecoration(
                      color: GreenPrimitives.p500Light,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: compact ? 6 : 10),
            SizedBox(
              width: compact ? 30 : 42,
              child: Text(
                '×$count',
                textAlign: TextAlign.right,
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CustomScheduleTimeline extends StatelessWidget {
  const _CustomScheduleTimeline({required this.plan});

  final rust_sync.OrchardMigrationPrivatePlan plan;

  @override
  Widget build(BuildContext context) {
    final transfers = [...plan.scheduledTransfers]
      ..sort((left, right) => left.blockOffset.compareTo(right.blockOffset));
    final firstOffset = transfers.isEmpty ? 0 : transfers.first.blockOffset;
    final lastOffset = transfers.isEmpty ? 0 : transfers.last.blockOffset;
    final preparationOffset = migrationPlanPreparationDelayBlocks(plan);
    final firstBroadcastOffset = preparationOffset + firstOffset;
    final lastBroadcastOffset = preparationOffset + lastOffset;
    final firstLabel = firstBroadcastOffset == 0
        ? 'Immediately'
        : _formatMigrationBlockDurationEstimate(firstBroadcastOffset);
    final lastLabel = lastBroadcastOffset == 0
        ? 'Immediately'
        : _formatMigrationBlockDurationEstimate(lastBroadcastOffset);
    return _CustomPlanCard(
      key: const ValueKey('custom_migration_timeline'),
      title: 'Expected migration timeline',
      children: [
        _CustomTimelineTrack(transfers: transfers),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _CustomFact(label: 'First message', value: firstLabel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CustomFact(label: 'Last message', value: lastLabel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _CustomFact(
          label: 'All funds complete in',
          value: migrationPlanCompletionDurationLabel(plan),
        ),
        const SizedBox(height: 4),
        Text(
          'Sampled block by block. Actual clock time changes with Zcash block '
          'production and confirmation timing.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _CustomTimelineTrack extends StatelessWidget {
  const _CustomTimelineTrack({required this.transfers});

  final List<rust_sync.MigrationScheduledTransfer> transfers;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lastOffset = transfers.isEmpty
        ? 1
        : math.max(1, transfers.last.blockOffset);
    final stride = math.max(1, (transfers.length / 72).ceil());
    final visible = [
      for (var index = 0; index < transfers.length; index += stride)
        transfers[index],
    ];
    return SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 14,
              child: Container(height: 2, color: colors.border.subtle),
            ),
            for (final transfer in visible)
              Positioned(
                left:
                    (constraints.maxWidth - 7) *
                    transfer.blockOffset /
                    lastOffset,
                top: 11,
                child: DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: GreenPrimitives.p500Light,
                    shape: CircleBorder(),
                  ),
                  child: const SizedBox.square(dimension: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomPlanCard extends StatelessWidget {
  const _CustomPlanCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CustomFact extends StatelessWidget {
  const _CustomFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
