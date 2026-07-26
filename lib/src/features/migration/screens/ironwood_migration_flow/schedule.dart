part of '../ironwood_migration_flow_screen.dart';

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
      return _frame(context, null, ref.watch(syncProvider).asData?.value);
    }
    return ref
        .watch(ironwoodMigrationStatusProvider(request))
        .when(
          skipLoadingOnReload: true,
          loading: () => _frame(context, null, null),
          error: (_, _) => _frame(context, null, null),
          data: (status) =>
              _frame(context, status, ref.watch(syncProvider).asData?.value),
        );
  }

  Widget _frame(
    BuildContext context,
    rust_sync.MigrationStatus? status,
    SyncState? syncState,
  ) {
    return _IronwoodMigrationFrame(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(
          label: 'Ironwood Migration',
          onTap: () => context.go('/migration/private/status'),
        ),
      ),
      disableSidebarActions: true,
      child: status == null
          ? const Center(child: CircularProgressIndicator())
          : _MigrationScheduleContent(
              status: status,
              currentHeight: _currentMigrationHeight(syncState),
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
      ..sort((a, b) {
        final aOrder = a.scheduleOrder ?? a.partIndex;
        final bOrder = b.scheduleOrder ?? b.partIndex;
        return aOrder.compareTo(bOrder);
      });
    final total = _sumTargetValues(status);
    final completed = parts
        .where((part) => part.state == rust_sync.MigrationPartState.completed)
        .fold<BigInt>(BigInt.zero, (sum, part) => sum + part.valueZatoshi);

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
          const SizedBox(height: 30),
          _MigrationLiveMetric(
            icon: AppIcons.shieldKeyhole,
            label: 'Ironwood spendable',
            value: '${_formatZecAmountCompact(completed)} ZEC',
            accent: true,
          ),
          const SizedBox(height: 14),
          _MigrationLiveMetric(
            icon: AppIcons.time,
            label: 'Est. completion',
            value: _transferEstimatedCompletion(
              status,
              currentHeight: currentHeight,
              needsInput: false,
              parts: parts,
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: ListView.separated(
              itemCount: parts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final part = parts[index];
                return _MigrationScheduleRow(
                  number: index + 1,
                  value: part.valueZatoshi,
                  total: total,
                  state: part.state,
                );
              },
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
    required this.value,
    required this.total,
    required this.state,
  });

  final int number;
  final BigInt value;
  final BigInt total;
  final rust_sync.MigrationPartState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = switch (state) {
      rust_sync.MigrationPartState.completed => 'Completed',
      rust_sync.MigrationPartState.migrating => 'Migrating...',
      rust_sync.MigrationPartState.confirming => 'Confirming...',
      rust_sync.MigrationPartState.needsInput => 'Needs approval',
      _ => 'Scheduled',
    };
    final completed = state == rust_sync.MigrationPartState.completed;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$number. ${_formatZecAmountCompact(value)} ZEC '
                '${_migrationPercentage(value, total)}',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            if (completed) ...[
              const AppIcon(
                AppIcons.checkCircle,
                size: 14,
                color: Color(0xFF00C875),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              status,
              style: AppTypography.bodySmall.copyWith(
                color: completed
                    ? const Color(0xFF00C875)
                    : colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
