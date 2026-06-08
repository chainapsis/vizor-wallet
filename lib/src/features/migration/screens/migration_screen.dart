import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_view_state.dart';
import '../widgets/migration_signing_overlay.dart';

class MigrationExpectedTransferCount {
  const MigrationExpectedTransferCount({
    required this.accountUuid,
    required this.count,
  });

  final String accountUuid;
  final int count;
}

class MigrationExpectedTransferCountNotifier
    extends Notifier<MigrationExpectedTransferCount?> {
  @override
  MigrationExpectedTransferCount? build() => null;

  void setCount(String accountUuid, int count) {
    state = MigrationExpectedTransferCount(
      accountUuid: accountUuid,
      count: count,
    );
  }
}

final migrationExpectedTransferCountProvider =
    NotifierProvider<
      MigrationExpectedTransferCountNotifier,
      MigrationExpectedTransferCount?
    >(MigrationExpectedTransferCountNotifier.new);

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  bool _signing = false;

  void _startSigning() => setState(() => _signing = true);
  void _cancelSigning() => setState(() => _signing = false);

  void _completeSigning(rust_sync.IronwoodMigrationResult result) {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final totalCount = result.totalCount;
    if (accountUuid != null && totalCount > 0) {
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .setCount(accountUuid, totalCount);
    }
    setState(() => _signing = false);
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final account = accountState?.activeAccount;
    final accountUuid = accountState?.activeAccountUuid;
    final isHardware = account?.isHardware ?? false;
    final sync = ref.watch(syncProvider).value;
    final migrationTransactions = _migrationTransactions(
      sync?.recentTransactions ?? const [],
    );
    final expectedTransferCount = ref.watch(
      migrationExpectedTransferCountProvider,
    );
    final scopedExpectedTransferCount =
        expectedTransferCount?.accountUuid == accountUuid
        ? expectedTransferCount?.count
        : null;
    final completedMigrationCount = migrationTransactions
        .where(_isCompletedMigration)
        .length;
    final expectedMigrationInProgress =
        scopedExpectedTransferCount != null &&
        completedMigrationCount < scopedExpectedTransferCount;
    final hasPendingMigration =
        migrationTransactions.any(_isPendingMigration) ||
        expectedMigrationInProgress;
    final hasCompletedMigration = migrationTransactions.any(
      _isCompletedMigration,
    );

    final viewState = migrationViewState(
      isHardware: isHardware,
      hasPendingMigration: hasPendingMigration,
      hasCompletedMigration: hasCompletedMigration,
      orchardBalance: sync?.orchardBalance ?? BigInt.zero,
      ironwoodBalance: sync?.ironwoodBalance ?? BigInt.zero,
    );

    final Widget body = switch (viewState) {
      MigrationViewState.softwareRequired => const _SoftwareRequiredView(),
      MigrationViewState.idle => _IdleView(onStart: _startSigning),
      MigrationViewState.inProgress => _InProgressView(
        migrationTransactions: migrationTransactions,
        expectedTransferCount: scopedExpectedTransferCount,
        amountZatoshi: _migrationDisplayAmount(sync, migrationTransactions),
      ),
      MigrationViewState.complete => const _CompleteView(),
    };

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: body,
            ),
            if (_signing)
              MigrationSigningOverlay(
                onCancel: _cancelSigning,
                onComplete: _completeSigning,
              ),
          ],
        ),
      ),
    );
  }
}

List<rust_sync.TransactionInfo> _migrationTransactions(
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where((tx) => tx.txKind == 'migration')
      .toList(growable: false);
}

bool _isPendingMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight == BigInt.zero && !tx.expiredUnmined;

bool _isCompletedMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight != BigInt.zero && !tx.expiredUnmined;

BigInt _migrationDisplayAmount(
  SyncState? sync,
  List<rust_sync.TransactionInfo> migrationTransactions,
) {
  final txAmount = migrationTransactions.fold<BigInt>(
    BigInt.zero,
    (sum, tx) => sum + tx.displayAmount,
  );
  if (txAmount > BigInt.zero) return txAmount;
  return sync?.orchardBalance ?? BigInt.zero;
}

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final orchard =
        ref.watch(syncProvider).value?.orchardBalance ?? BigInt.zero;
    final amount = ZecAmount.fromZatoshi(
      orchard,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.idleTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.idleBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _PoolTransition(),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MigrationCopy.readyToMigrateLabel,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                amount,
                key: const ValueKey('migration_ready_amount'),
                style: AppTypography.displaySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                MigrationCopy.poolFlow,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        const _Bullets(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_start_button'),
          onPressed: onStart,
          leading: const AppIcon(AppIcons.doubleArrowVertical),
          child: const Text(MigrationCopy.startCta),
        ),
      ],
    );
  }
}

class _SoftwareRequiredView extends StatelessWidget {
  const _SoftwareRequiredView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.softwareRequiredTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Text(
            MigrationCopy.softwareRequiredBody,
            key: const ValueKey('migration_software_required'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InProgressView extends StatelessWidget {
  const _InProgressView({
    required this.migrationTransactions,
    required this.expectedTransferCount,
    required this.amountZatoshi,
  });
  final List<rust_sync.TransactionInfo> migrationTransactions;
  final int? expectedTransferCount;
  final BigInt amountZatoshi;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final total = [
      migrationTransactions.length,
      expectedTransferCount ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    final completed = migrationTransactions.where(_isCompletedMigration).length;
    final progress = migrationTransactions.isEmpty ? null : completed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.inProgressTitle,
          key: const ValueKey('migration_in_progress_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.inProgressBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MigrationCopy.migratingAmount(amount),
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                  color: colors.icon.success,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$completed of $total confirmed',
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Column(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0)
                  Divider(height: AppSpacing.md, color: colors.border.subtle),
                _MigrationTransferRow(
                  index: i,
                  total: total,
                  transaction: i < migrationTransactions.length
                      ? migrationTransactions[i]
                      : null,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(
                AppIcons.warning,
                size: AppIconSize.medium,
                color: colors.icon.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  MigrationCopy.keepOpenWarning,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MigrationTransferRow extends StatelessWidget {
  const _MigrationTransferRow({
    required this.index,
    required this.total,
    required this.transaction,
  });

  final int index;
  final int total;
  final rust_sync.TransactionInfo? transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = transaction;
    final isComplete = tx != null && _isCompletedMigration(tx);
    final isFailed = tx?.expiredUnmined ?? false;
    final statusText = isFailed
        ? 'Failed'
        : isComplete
        ? 'Completed'
        : 'In progress';
    final icon = isFailed
        ? AppIcons.warning
        : isComplete
        ? AppIcons.checkCircle
        : AppIcons.time;
    final iconColor = isFailed
        ? colors.icon.destructive
        : isComplete
        ? colors.icon.success
        : colors.icon.muted;

    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            MigrationCopy.transferLabel(index + 1, total),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          statusText,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _CompleteView extends StatelessWidget {
  const _CompleteView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.doneTitle,
          key: const ValueKey('migration_done_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.doneBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _PoolTransition extends StatelessWidget {
  const _PoolTransition();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.fromPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.fromPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
            color: colors.icon.muted,
          ),
        ),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.toPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.toPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '›  ',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bullet(MigrationCopy.bullet1),
        bullet(MigrationCopy.bullet2),
        bullet(MigrationCopy.bullet3),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}
