import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/onboarding/shared/onboarding_welcome_art.dart';
import '../../../providers/sync_keep_awake_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../formatting/sync_status_label.dart';
import '../../layout/app_form_factor.dart';
import '../../theme/app_theme.dart';
import '../app_button.dart';
import '../app_icon.dart';

class SyncKeepAwakePrivacyLockHost extends ConsumerStatefulWidget {
  const SyncKeepAwakePrivacyLockHost({
    required this.child,
    this.idleTimeout = kSyncKeepAwakePrivacyIdleTimeout,
    super.key,
  });

  final Widget child;
  final Duration idleTimeout;

  @override
  ConsumerState<SyncKeepAwakePrivacyLockHost> createState() =>
      _SyncKeepAwakePrivacyLockHostState();
}

class _SyncKeepAwakePrivacyLockHostState
    extends ConsumerState<SyncKeepAwakePrivacyLockHost> {
  Timer? _idleTimer;
  bool _clearScheduled = false;

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor != AppFormFactor.mobile) return widget.child;

    final active = ref.watch(syncKeepAwakeActiveProvider);
    final interaction = ref.watch(syncKeepAwakeInteractionProvider);
    final visible = ref.watch(syncKeepAwakePrivacyLockVisibleProvider);
    _syncIdleTimer(active: active, interaction: interaction, visible: visible);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (visible)
          const Positioned.fill(child: SyncKeepAwakePrivacyLockScreen()),
      ],
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _syncIdleTimer({
    required bool active,
    required SyncKeepAwakeInteractionState interaction,
    required bool visible,
  }) {
    if (!active) {
      _idleTimer?.cancel();
      _idleTimer = null;
      _clearAfterFrameIfInactive();
      return;
    }

    if (visible) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    final remaining =
        widget.idleTimeout - interaction.idleDuration(DateTime.now());
    _idleTimer?.cancel();
    _idleTimer = Timer(
      remaining <= Duration.zero ? Duration.zero : remaining,
      () => _lockIfStillIdle(interaction.revision),
    );
  }

  void _lockIfStillIdle(int expectedRevision) {
    if (!mounted) return;
    if (!ref.read(syncKeepAwakeActiveProvider)) return;
    if (ref.read(syncKeepAwakePrivacyLockProvider).isLocked) return;

    final interaction = ref.read(syncKeepAwakeInteractionProvider);
    if (interaction.revision != expectedRevision) {
      _syncIdleTimer(active: true, interaction: interaction, visible: false);
      return;
    }

    ref.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
  }

  void _clearAfterFrameIfInactive() {
    if (_clearScheduled ||
        !ref.read(syncKeepAwakePrivacyLockProvider).isLocked) {
      return;
    }
    _clearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearScheduled = false;
      if (!mounted || ref.read(syncKeepAwakeActiveProvider)) return;
      ref.read(syncKeepAwakePrivacyLockProvider.notifier).clear();
    });
  }
}

class SyncKeepAwakePrivacyLockScreen extends ConsumerWidget {
  const SyncKeepAwakePrivacyLockScreen({super.key});

  static const _figmaReferenceHeight = 852.0;
  static const _shortScreenOuterMargin = 32.0;
  static const _logoTopGap = 110.0;
  static const _logoWidth = 106.0;
  static const _logoHeight = 40.0;
  static const _logoToRingGap = 81.0;
  static const _minimumLogoToRingGap = 48.0;
  static const _ringSize = 303.0;
  static const _ringToButtonGap = 129.0;
  static const _minimumRingToButtonGap = 48.0;
  static const _bodyWidth = 130.0;
  static const _contentStackHeight =
      _logoHeight +
      _logoToRingGap +
      _ringSize +
      _ringToButtonGap +
      AppButtonSizingMobile.largeHeight;
  static const _minimumContentStackHeight =
      _logoHeight +
      _minimumLogoToRingGap +
      _ringSize +
      _minimumRingToButtonGap +
      AppButtonSizingMobile.largeHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final sync = ref.watch(syncProvider).asData?.value;
    final progress = sync?.displayPercentage ?? sync?.percentage ?? 0.0;

    return Material(
      color: colors.background.window,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Vizor is syncing',
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _resolveVerticalLayout(
                availableHeight: constraints.maxHeight,
                screenHeight: MediaQuery.sizeOf(context).height,
              );
              return Column(
                children: [
                  SizedBox(height: layout.topGap),
                  const VizorWordmark(
                    key: ValueKey('sync_keep_awake_privacy_logo'),
                    width: _logoWidth,
                    height: _logoHeight,
                  ),
                  SizedBox(height: layout.logoToRingGap),
                  _SyncKeepAwakeProgressLockup(progress: progress),
                  SizedBox(height: layout.ringToButtonGap),
                  AppButton(
                    key: const ValueKey(
                      'sync_keep_awake_privacy_unlock_button',
                    ),
                    onPressed: () => ref
                        .read(syncKeepAwakePrivacyLockProvider.notifier)
                        .unlock(),
                    leading: const AppIcon(AppIcons.unlock),
                    minWidth: 165,
                    child: const Text('Unlock Vizor'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  _SyncKeepAwakeVerticalLayout _resolveVerticalLayout({
    required double availableHeight,
    required double screenHeight,
  }) {
    if (screenHeight >= _figmaReferenceHeight) {
      return const _SyncKeepAwakeVerticalLayout(
        topGap: _logoTopGap,
        logoToRingGap: _logoToRingGap,
        ringToButtonGap: _ringToButtonGap,
      );
    }

    var logoToRingGap = _logoToRingGap;
    var ringToButtonGap = _ringToButtonGap;
    final targetStackHeight = math.max(
      _minimumContentStackHeight,
      availableHeight - (_shortScreenOuterMargin * 2),
    );
    final reduction = math.min(
      _contentStackHeight - targetStackHeight,
      (_logoToRingGap - _minimumLogoToRingGap) +
          (_ringToButtonGap - _minimumRingToButtonGap),
    );

    if (reduction > 0) {
      final logoReducible = _logoToRingGap - _minimumLogoToRingGap;
      final buttonReducible = _ringToButtonGap - _minimumRingToButtonGap;
      final totalReducible = logoReducible + buttonReducible;
      logoToRingGap -= reduction * logoReducible / totalReducible;
      ringToButtonGap -= reduction * buttonReducible / totalReducible;
    }

    final stackHeight =
        _logoHeight +
        logoToRingGap +
        _ringSize +
        ringToButtonGap +
        AppButtonSizingMobile.largeHeight;

    return _SyncKeepAwakeVerticalLayout(
      topGap: math.max(0, (availableHeight - stackHeight) / 2),
      logoToRingGap: logoToRingGap,
      ringToButtonGap: ringToButtonGap,
    );
  }
}

class _SyncKeepAwakeVerticalLayout {
  const _SyncKeepAwakeVerticalLayout({
    required this.topGap,
    required this.logoToRingGap,
    required this.ringToButtonGap,
  });

  final double topGap;
  final double logoToRingGap;
  final double ringToButtonGap;
}

class _SyncKeepAwakeProgressLockup extends StatelessWidget {
  const _SyncKeepAwakeProgressLockup({required this.progress});

  static const _progressAnimationDuration = Duration(milliseconds: 420);

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final targetProgress = progress.clamp(0.0, 1.0).toDouble();
    return SizedBox.square(
      dimension: SyncKeepAwakePrivacyLockScreen._ringSize,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: targetProgress, end: targetProgress),
        duration: _progressAnimationDuration,
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) {
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SyncKeepAwakeSegmentedRingPainter(
                    progress: animatedProgress,
                    trackColor: colors.background.raised,
                    progressColor: colors.sync.lightSuccess,
                  ),
                ),
              ),
              Positioned(
                top: 118,
                left: 0,
                right: 0,
                child: Text(
                  '${formatSyncStatusPercentage(animatedProgress)}%',
                  textAlign: TextAlign.center,
                  style: AppTypography.displayLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              Positioned(
                top: 170,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: SyncKeepAwakePrivacyLockScreen._bodyWidth,
                    child: Text(
                      'Vizor is syncing,\nstick around ...',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncKeepAwakeSegmentedRingPainter extends CustomPainter {
  const _SyncKeepAwakeSegmentedRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const segmentCount = 96;
    const progressTickLength = 28.0;
    const trackTickLength = 16.0;
    const strokeWidth = 2.5;
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
    final center = Offset(size.width / 2, size.height / 2);
    final tickCenterRadius =
        (size.shortestSide / 2) - (progressTickLength / 2) - 1;
    final scaledProgress = segmentCount * clampedProgress;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < segmentCount; index++) {
      final angle = (-math.pi / 2) + (math.pi * 2 * index / segmentCount);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final segmentFill = (scaledProgress - index).clamp(0.0, 1.0).toDouble();
      final tickLength =
          trackTickLength +
          ((progressTickLength - trackTickLength) * segmentFill);
      final tickCenter = center + direction * tickCenterRadius;
      final inner = tickCenter - (direction * tickLength / 2);
      final outer = tickCenter + (direction * tickLength / 2);
      final paint = trackPaint
        ..color = Color.lerp(trackColor, progressColor, segmentFill)!;

      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SyncKeepAwakeSegmentedRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
