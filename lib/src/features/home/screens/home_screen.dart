import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';

// Design system colors from Stitch
const _surface = Color(0xFFF9F9F9);
const _surfaceContainerLow = Color(0xFFF2F4F4);
const _surfaceContainerHigh = Color(0xFFE4E9EA);
const _onSurface = Color(0xFF2D3435);
const _primary = Color(0xFF5F5E5E);
const _onPrimary = Color(0xFFFAF7F6);
const _secondary = Color(0xFF4D626C);
const _tertiary = Color(0xFF1C6D25);
const _outline = Color(0xFF757C7D);

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
      backgroundColor: _surface,
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) => _buildBody(
          context,
          wallet,
          syncState.value ?? SyncState(),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody(BuildContext context, WalletState wallet, SyncState sync) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Top bar
          SliverToBoxAdapter(child: _buildTopBar()),
          // Hero balance
          SliverToBoxAdapter(child: _buildHeroBalance(sync)),
          // Action buttons
          SliverToBoxAdapter(child: _buildActionButtons(context)),
          // Recent Activity header
          SliverToBoxAdapter(child: _buildActivityHeader(context)),
          // Sync status item (if syncing)
          if (sync.isSyncing)
            SliverToBoxAdapter(child: _buildSyncItem(sync)),
          // Background sync button (between sync item and transactions)
          if (_canBackgroundSync && sync.isSyncing && !sync.isBackgroundMode)
            SliverToBoxAdapter(child: _buildBackgroundSyncButton()),
          if (sync.isBackgroundMode)
            SliverToBoxAdapter(child: _buildStopBackgroundSyncButton()),
          // Placeholder transactions
          SliverToBoxAdapter(child: _buildActivityPlaceholder(sync)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: _onSurface.withValues(alpha: 0.8), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Zcash',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.5,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: _onSurface),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBalance(SyncState sync) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Shielded Balance badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user, size: 14, color: _tertiary),
                const SizedBox(width: 6),
                Text(
                  'SHIELDED BALANCE',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: _tertiary,
                  ),
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
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w800,
                  fontSize: 56,
                  height: 1.0,
                  letterSpacing: -2,
                  color: _onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ZEC',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w600,
                  fontSize: 28,
                  color: _secondary,
                ),
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

  Widget _buildBackgroundSyncButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).enableBackgroundSync(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_sync, size: 16, color: _secondary),
              const SizedBox(width: 8),
              Text(
                'SYNC IN BACKGROUND',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: _secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStopBackgroundSyncButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).disableBackgroundSync(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_disabled, size: 16, color: _secondary),
              const SizedBox(width: 8),
              Text(
                'STOP BACKGROUND SYNC',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: _secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.3,
              color: _onSurface,
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/history'),
            child: Text(
              'VIEW ALL',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.5,
                color: _secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncItem(SyncState sync) {
    final pct = (sync.percentage * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.sync, color: _secondary, size: 24),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Syncing...',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: _outline,
                      ),
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
                      backgroundColor: _surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(_secondary),
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

  Widget _buildActivityPlaceholder(SyncState sync) {
    if (sync.isSyncing && sync.chainTipHeight == 0) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(24, 32, 24, 0),
        child: Center(
          child: Text(
            'Waiting for sync...',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: _outline,
            ),
          ),
        ),
      );
    }

    if (!sync.isSyncing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _tertiary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.check_circle, color: _tertiary, size: 24),
              ),
            ),
            const SizedBox(width: 20),
            const Text(
              'Wallet Synchronized',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: _onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.9),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: filled ? _primary : _surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: filled ? _onPrimary : _onSurface),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 2,
                color: filled ? _onPrimary : _onSurface,
              ),
            ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive ? _onSurface : _outline,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
                color: isActive ? _onSurface : _outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
