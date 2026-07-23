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
    final resignCount = status.parts
        .where((part) => part.state == rust_sync.MigrationPartState.needsInput)
        .length;
    final needsResign = resignCount > 0;
    final batchCount = needsResign
        ? resignCount
        : _mobilePlannedBatchCount(status);
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
                  needsResign ? 'Needs input' : 'Ready for Keystone',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  needsResign
                      ? batchCount == 1
                            ? 'This migration transaction needs a fresh '
                                  'Keystone signature before it can be '
                                  'broadcast.'
                            : 'These migration transactions need fresh '
                                  'Keystone signatures before they can be '
                                  'broadcast.'
                      : 'The split transactions are confirmed. Use Keystone '
                            'again to approve the Ironwood migration '
                            'transactions.',
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
                        needsResign
                            ? '$transactionLabel ${batchCount == 1 ? 'needs' : 'need'} to be signed again'
                            : '$transactionLabel ready to sign',
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
                  child: Text(needsResign ? 'Sign again' : 'Continue'),
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
    this.status,
  });

  final IronwoodMigrationFlowData data;
  final rust_sync.OrchardMigrationPrivatePlan? previewPlan;
  final List<MobileIronwoodMigrationPartPresentation>? previewParts;
  final rust_sync.MigrationStatus? status;

  @override
  ConsumerState<_MobileMigrationMigrating> createState() =>
      _MobileMigrationMigratingState();
}

class _MobileMigrationMigratingState
    extends ConsumerState<_MobileMigrationMigrating> {
  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final colors = context.colors;
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final migrationCoordinator = ref.watch(
      ironwoodMigrationCoordinatorProvider,
    );
    final coordinatorError = accountUuid == null
        ? null
        : migrationCoordinator.errors[accountUuid];
    final needsCredentialRecovery =
        accountUuid != null &&
        ironwoodMigrationNeedsCredentialRecovery(coordinatorError);
    final recoveryInProgress =
        accountUuid != null &&
        migrationCoordinator.advancingAccounts.contains(accountUuid);
    final syncState = (ref.watch(syncProvider).value ?? SyncState())
        .scopedToAccount(accountUuid);
    final totalAmount = _mobileMigrationTotalAmountText(
      status,
      previewPlan: widget.previewPlan,
      fallback: widget.data.amountText,
    );
    final etaHeight = _mobileMigrationEtaHeight(syncState);
    final parts = _mobileMigrationPartPresentations(
      status: status,
      previewPlan: widget.previewPlan,
      explicitParts: widget.previewParts,
      currentHeight: etaHeight,
    );
    final partCount = parts.isNotEmpty
        ? parts.length
        : _mobilePlannedBatchCount(status, previewPlan: widget.previewPlan);
    final needsAttention = parts.any(
      (part) => part.status == MobileIronwoodMigrationPartStatus.needsInput,
    );
    final waitingForSafeBlock =
        status?.phase == kIronwoodMigrationReadyToMigratePhase &&
        status?.nextActionHeight != null &&
        etaHeight > 0 &&
        status!.nextActionHeight! > etaHeight;
    final completion = status == null
        ? widget.previewPlan == null
              ? 'Schedule pending'
              : _migrationArrivalLabel(widget.previewPlan!)
        : migrationApproximateCompletionTimingLabel(
            status,
            currentHeight: etaHeight,
          );
    final spendable = _mobileSpendableAmountText(
      status,
      ironwoodBalance: syncState.hasBalanceData
          ? syncState.ironwoodBalance
          : null,
    );
    final compact = MediaQuery.sizeOf(context).height < 650;
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
        : _MobileIronwoodActiveStatus(
            parts: parts,
            onPartTap: accountUuid == null
                ? null
                : (_) => unawaited(_retryMigration(accountUuid)),
          );
    final content = Column(
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
          SizedBox(height: 304, child: partsContent),
        SizedBox(height: compact ? AppSpacing.s : 52),
        _ReviewRow(label: 'Est. completion', value: completion),
        const SizedBox(height: AppSpacing.xs),
        _ReviewRow(
          label: 'Currently spendable balance',
          value: spendable == '-' ? spendable : '$spendable ZEC',
        ),
        const SizedBox(height: AppSpacing.md),
        _MigrationCanLeaveMessage(
          primary: needsCredentialRecovery
              ? 'Migration recovery required.'
              : coordinatorError != null
              ? "Couldn't continue migration. Try again."
              : needsAttention
              ? 'Keep Vizor open & unlocked.'
              : waitingForSafeBlock
              ? 'Waiting for a safe block to continue.'
              : null,
          secondary: needsCredentialRecovery
              ? "Two saved transactions couldn't be reopened."
              : coordinatorError != null || needsAttention
              ? 'Vizor will retry automatically.'
              : waitingForSafeBlock
              ? 'You can leave this screen.'
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (needsCredentialRecovery) ...[
          AppButton(
            key: const ValueKey('mobile_ironwood_credential_recovery_button'),
            expand: true,
            onPressed: recoveryInProgress
                ? null
                : () => unawaited(_confirmRecovery(accountUuid)),
            child: Text(recoveryInProgress ? 'Recovering...' : 'Recover'),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _MobileStatusBackHomeButton(
          key: const ValueKey('mobile_ironwood_status_back_home_button'),
          label: 'Go home',
          onPressed: () => context.go('/home'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('mobile_ironwood_migration_content_scroll'),
              child: content,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          actions,
        ],
      ),
    );
  }

  Future<void> _retryMigration(String accountUuid) async {
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .retry(accountUuid);
    } catch (_) {
      // The coordinator retains the account-scoped error for presentation and
      // the next automatic retry.
    }
  }

  Future<void> _confirmRecovery(String accountUuid) async {
    final appTheme = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppTheme(
        data: appTheme,
        child: const _MobileMigrationRecoveryDialog(),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .recover(accountUuid);
    } catch (_) {
      // The coordinator retains the account-scoped error for presentation.
    }
  }
}

class _MobileMigrationRecoveryDialog extends StatelessWidget {
  const _MobileMigrationRecoveryDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Rebuild migration?',
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Vizor will first check that the pending transactions were '
                  'not sent. It will then rebuild the migration for only your '
                  'remaining balance. Any confirmed transfers will stay '
                  'unchanged.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  key: const ValueKey(
                    'mobile_ironwood_confirm_credential_recovery',
                  ),
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Rebuild'),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _mobileMigrationEtaHeight(SyncState? syncState) {
  if (syncState == null) return 0;
  if (syncState.chainTipHeight > 0) return syncState.chainTipHeight;
  return syncState.scannedHeight;
}
