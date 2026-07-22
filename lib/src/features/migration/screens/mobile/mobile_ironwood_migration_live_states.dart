part of 'mobile_ironwood_migration_flow_screen.dart';

class _MobileMigrationPreparing extends StatelessWidget {
  const _MobileMigrationPreparing({
    required this.data,
    required this.isHardware,
    this.status,
    this.previewPlan,
  });

  final IronwoodMigrationFlowData data;
  final bool isHardware;
  final rust_sync.MigrationStatus? status;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final partCount = _mobilePlannedBatchCount(
      status,
      previewPlan: previewPlan,
    );
    final confirmationCount = status?.denominationConfirmationCount ?? 0;
    final confirmationTarget = status?.denominationConfirmationTarget ?? 0;
    final parts = _mobilePreparingPartPresentations(
      status: status,
      previewPlan: previewPlan,
    );
    final totalAmount = _mobileMigrationTotalAmountText(
      status,
      previewPlan: previewPlan,
      fallback: data.amountText,
    );
    final compact = MediaQuery.sizeOf(context).height < 650;
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_migration_status_preparing'),
      data: data,
      showAccountNav: false,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: Column(
        children: [
          SizedBox(height: compact ? 28 : 81),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  Text(
                    'Migration in Progress',
                    key: const ValueKey(
                      'mobile_ironwood_migration_preparing_title',
                    ),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 300,
                    child: Text(
                      'Preparing your balance for migration. This step usually '
                      'takes 10-20 mins.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 39),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: AppTypography.bodyLarge.copyWith(
                              color: colors.text.accent,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              const TextSpan(text: 'Migration '),
                              TextSpan(
                                text: '$partCount notes',
                                style: TextStyle(color: colors.text.secondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xxs),
                        child: Text(
                          '$totalAmount ZEC',
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MobileMigrationStatusRail(parts: parts),
                  const SizedBox(height: AppSpacing.base),
                  _MobileIronwoodWaitingStatusCard(
                    partCount: partCount,
                    confirmedConfirmations: confirmationCount,
                    confirmationTarget: confirmationTarget,
                    requiresKeystoneApproval: isHardware,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _MobileStatusBackHomeButton(
            label: 'Go home',
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
    );
  }
}

class _MobileKeystoneMigrationReady extends StatelessWidget {
  const _MobileKeystoneMigrationReady({
    required this.data,
    required this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final batchCount = _mobilePlannedBatchCount(status);
    final transactionLabel = batchCount == 1
        ? '1 migration transaction'
        : '$batchCount migration transactions';
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_keystone_ready'),
      data: data,
      child: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.s),
                const AppIcon(AppIcons.qr, size: 40),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Ready for Keystone',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'The split transactions are confirmed. Use Keystone again to '
                  'approve the Ironwood migration transactions.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                _MobileStatusCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF00A460),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(
                              dimension: 20,
                              child: Center(
                                child: AppIcon(
                                  AppIcons.check,
                                  size: 14,
                                  color: Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          const Expanded(
                            child: Text('Split transactions confirmed'),
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.lg),
                      Text(
                        'Keystone approval',
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$transactionLabel ready to sign',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_keystone_batch_sign_button',
                  ),
                  expand: true,
                  onPressed: () =>
                      context.go('/migration/private/keystone/batch/sign'),
                  child: const Text('Continue'),
                ),
                const SizedBox(height: AppSpacing.xs),
                _MobileStatusBackHomeButton(
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileMigrationMigrating extends ConsumerStatefulWidget {
  const _MobileMigrationMigrating({
    required this.data,
    required this.previewPlan,
    required this.previewParts,
    this.enableRecovery = false,
    this.forceRecoveryPreview = false,
    this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final rust_sync.MigrationStatus? status;
  final bool enableRecovery;
  final bool forceRecoveryPreview;

  @override
  ConsumerState<_MobileMigrationMigrating> createState() =>
      _MobileMigrationMigratingState();
}

class _MobileMigrationMigratingState
    extends ConsumerState<_MobileMigrationMigrating> {
  bool _schedulingBackgroundRetry = false;
  bool _backgroundRetryScheduled = false;
  String? _recoveryError;

  Future<void> _sendOneDue(String accountUuid) async {
    setState(() => _recoveryError = null);
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .sendOneDue(accountUuid);
    } catch (_) {
      if (mounted) {
        setState(() {
          _recoveryError = "Couldn't send the transfer. Try again.";
        });
      }
    }
  }

  Future<void> _retryInBackground(String accountUuid) async {
    setState(() {
      _schedulingBackgroundRetry = true;
      _recoveryError = null;
    });
    try {
      final scheduled = await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retryInBackground(accountUuid);
      if (!mounted) return;
      setState(() {
        _backgroundRetryScheduled = scheduled;
        if (!scheduled) {
          _recoveryError = "Couldn't schedule a background retry.";
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _recoveryError = "Couldn't schedule a background retry.";
        });
      }
    } finally {
      if (mounted) setState(() => _schedulingBackgroundRetry = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final colors = context.colors;
    final accountUuid = widget.enableRecovery
        ? ref.watch(accountProvider).value?.activeAccountUuid
        : null;
    final syncState = widget.enableRecovery
        ? (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
            accountUuid,
          )
        : null;
    final totalAmount = _mobileMigrationTotalAmountText(
      status,
      previewPlan: widget.previewPlan,
      fallback: widget.data.amountText,
    );
    final parts = _mobileMigrationPartPresentations(
      status: status,
      previewPlan: widget.previewPlan,
      explicitParts: widget.previewParts,
      currentHeight: _mobileMigrationHeight(syncState),
    );
    final partCount = parts.isNotEmpty
        ? parts.length
        : _mobilePlannedBatchCount(status, previewPlan: widget.previewPlan);
    final completion = status == null
        ? widget.previewPlan == null
              ? 'Schedule pending'
              : _migrationArrivalLabel(widget.previewPlan!)
        : migrationCompletionTimingLabel(
            status,
            currentHeight: _mobileMigrationHeight(syncState),
          );
    final spendable = _mobileSpendableAmountText(
      status,
      ironwoodBalance: syncState?.hasBalanceData ?? false
          ? syncState!.ironwoodBalance
          : null,
    );
    final compact = MediaQuery.sizeOf(context).height < 650;
    final recoveryRequired =
        widget.forceRecoveryPreview ||
        (status != null &&
            _hasDueMobileMigrationTransfer(
              status,
              currentHeight: _mobileMigrationHeight(syncState),
            ));
    final coordinator = widget.enableRecovery
        ? ref.watch(ironwoodMigrationCoordinatorProvider)
        : const IronwoodMigrationCoordinatorState();
    final supportsBackgroundRetry =
        widget.forceRecoveryPreview ||
        (widget.enableRecovery &&
            ref
                .read(ironwoodMigrationServiceProvider)
                .supportsBackgroundMigrationRetry);
    final sending =
        accountUuid != null &&
        coordinator.advancingAccounts.contains(accountUuid);
    final partsContent = parts.isEmpty
        ? Center(
            child: Text(
              'Migration parts will appear as transactions are prepared.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          )
        : _MobileIronwoodActiveStatus(parts: parts);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compact ? 20 : 46),
        Text(
          'Migration in Progress',
          textAlign: TextAlign.center,
          style: AppTypography.headlineLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: compact ? AppSpacing.md : 44),
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    const TextSpan(text: 'Migration '),
                    TextSpan(
                      text: '$partCount notes',
                      style: TextStyle(color: colors.text.secondary),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: Text(
                '$totalAmount ZEC',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.xs : 3),
        if (compact)
          SizedBox(
            height: math.min(156, math.max(72, parts.length * 52).toDouble()),
            child: partsContent,
          )
        else
          SizedBox(height: recoveryRequired ? 180 : 304, child: partsContent),
        SizedBox(height: compact || recoveryRequired ? AppSpacing.s : 52),
        _ReviewRow(
          label: 'Est. completion',
          value: completion,
          showInfo: true,
          onInfoPressed: () =>
              unawaited(_showMobileMigrationTimingSheet(context)),
        ),
        const SizedBox(height: AppSpacing.xs),
        _ReviewRow(
          label: 'Currently spendable balance',
          value: spendable == '-' ? spendable : '$spendable ZEC',
        ),
        const SizedBox(height: AppSpacing.md),
        if (recoveryRequired &&
            (widget.forceRecoveryPreview || accountUuid != null))
          _MobileMigrationRecoveryCard(
            sending: sending,
            schedulingBackground: _schedulingBackgroundRetry,
            backgroundRetryScheduled: _backgroundRetryScheduled,
            error: _recoveryError ?? coordinator.errors[accountUuid],
            supportsBackgroundRetry: supportsBackgroundRetry,
            onSendOne: widget.forceRecoveryPreview
                ? () {}
                : () => unawaited(_sendOneDue(accountUuid!)),
            onRetryInBackground: widget.forceRecoveryPreview
                ? () {}
                : () => unawaited(_retryInBackground(accountUuid!)),
          )
        else
          const _MigrationCanLeaveMessage(),
        SizedBox(height: compact || recoveryRequired ? AppSpacing.md : 38),
        Transform.translate(
          offset: Offset(0, compact || recoveryRequired ? 0 : 14),
          child: _MobileStatusBackHomeButton(
            key: const ValueKey('mobile_ironwood_status_back_home_button'),
            label: 'Go home',
            onPressed: () => context.go('/home'),
          ),
        ),
      ],
    );
    return _MobileMigrationStatusScaffold(
      key: const ValueKey('mobile_ironwood_migration_status_migrating'),
      data: widget.data,
      showAccountNav: false,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.s,
      ),
      child: compact || recoveryRequired
          ? SingleChildScrollView(child: body)
          : body,
    );
  }
}

int _mobileMigrationHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  if (syncState.scannedHeight > 0 && syncState.chainTipHeight > 0) {
    return math.min(syncState.scannedHeight, syncState.chainTipHeight);
  }
  return math.max(syncState.scannedHeight, syncState.chainTipHeight);
}

bool _hasDueMobileMigrationTransfer(
  rust_sync.MigrationStatus status, {
  required int currentHeight,
}) {
  if (currentHeight <= 0) return false;
  return status.scheduledBroadcasts.any((broadcast) {
    if (broadcast.status.toLowerCase() != 'scheduled') return false;
    if (broadcast.scheduledHeight <= 0) return false;
    return broadcast.scheduledHeight + kIronwoodMigrationLateGraceBlocks <=
        currentHeight;
  });
}
