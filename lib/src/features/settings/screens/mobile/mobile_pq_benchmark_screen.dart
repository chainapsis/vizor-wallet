import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../rust/api/pq_benchmark.dart';

/// Measures post-quantum signature schemes on this device: key generation,
/// signing a transaction digest and verification, for WOTS+, standalone FORS
/// and three SLH-DSA (SPHINCS+) parameter sets. Experimental; not a wallet feature.
class MobilePqBenchmarkScreen extends StatefulWidget {
  const MobilePqBenchmarkScreen({super.key});

  @override
  State<MobilePqBenchmarkScreen> createState() =>
      _MobilePqBenchmarkScreenState();
}

class _MobilePqBenchmarkScreenState extends State<MobilePqBenchmarkScreen> {
  static const _iterations = 10;

  bool _running = false;
  List<PqSchemeTiming>? _results;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      // Runs on a Rust worker thread, so the UI stays responsive.
      final results = await runPqSignatureBenchmark(iterations: _iterations);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final results = _results;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'PQ signature benchmark',
              onBack: _running ? null : () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                children: [
                  Text(
                    'Median of $_iterations runs per scheme: key generation '
                    'from a seed, signing a 32-byte digest, and verifying.',
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    key: const ValueKey('pq_benchmark_run_button'),
                    onPressed: _running ? null : _run,
                    child: Text(_running ? 'Running…' : 'Run benchmark'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  if (results != null)
                    for (final timing in results) ...[
                      const SizedBox(height: AppSpacing.md),
                      _TimingCard(timing: timing),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({required this.timing});

  final PqSchemeTiming timing;

  static String _duration(double us) {
    if (us >= 1000000) return '${(us / 1000000).toStringAsFixed(2)} s';
    if (us >= 1000) return '${(us / 1000).toStringAsFixed(1)} ms';
    return '${us.toStringAsFixed(0)} µs';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final value = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.primary,
    );
    Widget row(String name, String measured) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(name, style: label)),
          Text(measured, style: value),
        ],
      ),
    );
    return MobileSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timing.scheme, style: value),
          row('Key gen', _duration(timing.keygenUs)),
          row('Sign', _duration(timing.signUs)),
          row('Verify', _duration(timing.verifyUs)),
          row('Signature', '${timing.signatureBytes} B'),
          row('Public key', '${timing.publicKeyBytes} B'),
        ],
      ),
    );
  }
}
