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
      context.l10n,
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
                    context.l10n.migrationFlowTitle,
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
                      context.l10n.migrationMobilePreparingBody,
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
                            children: _notesHeadingSpans(
                              context,
                              partCount,
                              colors.text.secondary,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xxs),
                        child: Text(
                          '$totalAmount ZEC', // l10n-ignore: amount format
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
            label: context.l10n.commonGoHome,
            onPressed: () => context.go('/home'),
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
    final blockTimes = ref.watch(blockSpacingProvider).fromTip(etaHeight);
    final parts = _mobileMigrationPartPresentations(
      context.l10n,
      status: status,
      previewPlan: widget.previewPlan,
      explicitParts: widget.previewParts,
      blockTimes: blockTimes,
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
              ? context.l10n.migrationSchedulePending
              : _migrationArrivalLabel(
                  context.l10n,
                  widget.previewPlan!,
                  blockTimes,
                )
        : migrationApproximateCompletionTimingLabel(
            context.l10n,
            status,
            blockTimes: blockTimes,
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
              context.l10n.migrationMobilePartsPlaceholder,
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
          context.l10n.migrationFlowTitle,
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
                  children: _notesHeadingSpans(
                    context,
                    partCount,
                    colors.text.secondary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: Text(
                '$totalAmount ZEC', // l10n-ignore: amount format
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
        _ReviewRow(
          label: context.l10n.migrationSummaryEstCompletion,
          value: completion,
        ),
        const SizedBox(height: AppSpacing.xs),
        _ReviewRow(
          label: context.l10n.migrationMobileSpendableBalance,
          value: spendable == '-'
              ? spendable
              : '$spendable ZEC', // l10n-ignore: amount format
        ),
        const SizedBox(height: AppSpacing.md),
        _MigrationCanLeaveMessage(
          primary: needsCredentialRecovery
              ? context.l10n.migrationMobileRecoveryRequired
              : coordinatorError != null
              ? context.l10n.migrationErrorContinue
              : needsAttention
              ? context.l10n.migrationMobileKeepOpenUnlocked
              : waitingForSafeBlock
              ? context.l10n.migrationMobileWaitSafeBlock
              : null,
          secondary: needsCredentialRecovery
              ? context.l10n.migrationMobileSavedTxError
              : coordinatorError != null || needsAttention
              ? context.l10n.migrationMobileRetryAutomatically
              : waitingForSafeBlock
              ? context.l10n.migrationMobileCanLeave
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
            child: Text(
              recoveryInProgress
                  ? context.l10n.migrationMobileRecovering
                  : context.l10n.migrationMobileRecover,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _MobileStatusBackHomeButton(
          key: const ValueKey('mobile_ironwood_status_back_home_button'),
          label: context.l10n.commonGoHome,
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
                  context.l10n.migrationMobileRebuildTitle,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.migrationMobileRebuildBody,
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
                  child: Text(context.l10n.migrationMobileRebuildAction),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  expand: true,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(context.l10n.commonCancel),
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

/// "Migration 3 notes" with the count in a muted colour; the count's position
/// is the translator's.
List<InlineSpan> _notesHeadingSpans(
  BuildContext context,
  int partCount,
  Color mutedColor,
) {
  final notes = context.l10n.migrationMobileStatusNotesCount(partCount);
  return emphasisSpans(context.l10n.migrationMobileStatusNotesTitle(notes), [
    notes,
  ], TextStyle(color: mutedColor));
}
