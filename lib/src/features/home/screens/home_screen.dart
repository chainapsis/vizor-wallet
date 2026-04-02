import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _canBackgroundSync = false;
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(syncProvider.notifier).startSync();
      _checkBackgroundSyncAvailability();
    });
  }

  Future<void> _checkBackgroundSyncAvailability() async {
    final available = await SyncNotifier.isBackgroundSyncAvailable();
    log('[zcash] BackgroundSync available: $available');
    if (mounted) setState(() => _canBackgroundSync = available);
  }

  String _formatZec(BigInt zatoshi) {
    final zec = zatoshi.toDouble() / 100000000;
    if (zec == 0) return '0.00';
    if (zec < 0.01) return zec.toStringAsFixed(8);
    return zec.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) => _buildBody(
          context,
          wallet,
          syncState.value ?? SyncState(),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBody(BuildContext context, WalletState wallet, SyncState sync) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildTopBar(context)),
          SliverToBoxAdapter(child: _buildHeroBalance(context, sync)),
          SliverToBoxAdapter(child: _buildActionButtons(context)),
          SliverToBoxAdapter(child: _buildActivityHeader(context)),
          if (sync.error != null)
            SliverToBoxAdapter(child: _buildSyncError(context, sync)),
          if (sync.isSyncing && sync.error == null)
            SliverToBoxAdapter(child: _buildSyncItem(context, sync)),
          if (_canBackgroundSync && sync.isSyncing && !sync.isBackgroundMode && sync.error == null)
            SliverToBoxAdapter(child: _buildBackgroundSyncButton(context)),
          if (sync.isBackgroundMode && sync.error == null)
            SliverToBoxAdapter(child: _buildStopBackgroundSyncButton(context)),
          SliverToBoxAdapter(child: _buildActivityPlaceholder(context, sync)),
          // Recent transactions
          if (sync.recentTransactions.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildTransactionItem(context, sync.recentTransactions[index]),
                childCount: sync.recentTransactions.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: colors.onSurface.withValues(alpha: 0.8), size: 22),
              const SizedBox(width: 8),
              Text(
                'Zcash',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.qr_code_scanner, color: colors.onSurface),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBalance(BuildContext context, SyncState sync) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Shielded Balance badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user, size: 14, color: colors.tertiary),
                const SizedBox(width: 6),
                Text(
                  'SHIELDED BALANCE',
                  style: text.labelSmall?.copyWith(color: colors.tertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Balance
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatZec(sync.totalBalance),
                style: text.displayLarge,
              ),
              const SizedBox(width: 8),
              Text(
                'ZEC',
                style: text.displayMedium?.copyWith(color: colors.secondary),
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: _ActionButton(
              icon: Icons.north_east,
              label: 'SEND',
              filled: true,
              onTap: () => context.push('/send'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.south_west,
              label: 'RECEIVE',
              filled: false,
              onTap: () => context.push('/receive'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncError(BuildContext context, SyncState sync) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).startSync(),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.error_outline, color: colors.error, size: 24),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sync Error', style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to retry',
                    style: text.labelSmall?.copyWith(color: colors.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundSyncButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).enableBackgroundSync(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_sync, size: 16, color: colors.secondary),
              const SizedBox(width: 8),
              Text(
                'SYNC IN BACKGROUND',
                style: text.labelSmall?.copyWith(color: colors.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopBackgroundSyncButton(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).disableBackgroundSync(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_disabled, size: 16, color: colors.secondary),
              const SizedBox(width: 8),
              Text(
                'STOP BACKGROUND SYNC',
                style: text.labelSmall?.copyWith(color: colors.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent Activity', style: text.titleLarge),
          GestureDetector(
            onTap: () => context.push('/history'),
            child: Text(
              'VIEW ALL',
              style: text.labelLarge?.copyWith(color: colors.secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncItem(BuildContext context, SyncState sync) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = (sync.percentage * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.sync, color: colors.secondary, size: 24),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Syncing...', style: text.titleMedium),
                    const SizedBox(width: 8),
                    Text(
                      '$pct%',
                      style: text.labelSmall?.copyWith(color: colors.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: sync.percentage.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: colors.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation(colors.secondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityPlaceholder(BuildContext context, SyncState sync) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (!sync.isSyncing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.tertiary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(Icons.check_circle, color: colors.tertiary, size: 24),
              ),
            ),
            const SizedBox(width: 20),
            Text('Wallet Synchronized', style: text.titleMedium),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildTransactionItem(BuildContext context, rust_sync.TransactionInfo tx) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isIncoming = tx.accountBalanceDelta >= 0;
    final zec = tx.accountBalanceDelta.abs() / 100000000;
    final sign = isIncoming ? '+' : '-';
    final amount = '$sign${zec.toStringAsFixed(zec < 0.01 ? 8 : 3)} ZEC';

    // Format date
    String dateStr = '';
    if (tx.blockTime > BigInt.zero) {
      final date = DateTime.fromMillisecondsSinceEpoch(tx.blockTime.toInt() * 1000);
      dateStr = '${_monthName(date.month)} ${date.day}, ${date.year} \u2022 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      dateStr = 'Pending';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isIncoming ? Icons.check_circle : Icons.arrow_outward,
                color: isIncoming ? colors.tertiary : colors.secondary,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncoming ? 'Received' : 'Sent',
                  style: text.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: text.bodySmall?.copyWith(color: colors.outline),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: text.titleMedium?.copyWith(
                  color: isIncoming ? colors.tertiary : colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isIncoming ? 'SHIELDED' : 'EXTERNAL',
                style: text.labelSmall?.copyWith(color: colors.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month];
  }

  Widget _buildBottomNav(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.account_balance_wallet,
                label: 'WALLET',
                isActive: _currentNavIndex == 0,
                onTap: () => setState(() => _currentNavIndex = 0),
              ),
              _BottomNavItem(
                icon: Icons.history,
                label: 'HISTORY',
                isActive: _currentNavIndex == 1,
                onTap: () {
                  setState(() => _currentNavIndex = 1);
                  context.push('/history');
                },
              ),
              _BottomNavItem(
                icon: Icons.settings,
                label: 'SETTINGS',
                isActive: _currentNavIndex == 2,
                onTap: () => setState(() => _currentNavIndex = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bg = filled ? colors.primary : colors.surfaceContainerHigh;
    final fg = filled ? colors.onPrimary : colors.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 12),
            Text(label, style: text.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = isActive ? colors.onSurface : colors.outline;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? colors.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: fg),
            const SizedBox(height: 4),
            Text(label, style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w500,
              color: fg,
            )),
          ],
        ),
      ),
    );
  }
}
