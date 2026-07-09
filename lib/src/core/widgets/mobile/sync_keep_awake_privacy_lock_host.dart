import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/onboarding/mobile/mobile_passcode_screen.dart';
import '../../../features/onboarding/mobile/passcode_widgets.dart';
import '../../../features/onboarding/shared/onboarding_welcome_art.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_keep_awake_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../feedback/app_haptics.dart';
import '../../formatting/sync_status_label.dart';
import '../../layout/app_form_factor.dart';
import '../../layout/mobile/mobile_top_nav.dart';
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
    final mode = ref.watch(syncKeepAwakePrivacyLockModeProvider);
    final visible = mode != SyncKeepAwakePrivacyLockMode.hidden;
    _syncIdleTimer(active: active, interaction: interaction, visible: visible);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (visible)
          Positioned.fill(child: SyncKeepAwakePrivacyLockScreen(mode: mode)),
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
      if (visible) return;
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

class SyncKeepAwakePrivacyLockScreen extends ConsumerStatefulWidget {
  const SyncKeepAwakePrivacyLockScreen({
    this.mode = SyncKeepAwakePrivacyLockMode.syncing,
    super.key,
  });

  final SyncKeepAwakePrivacyLockMode mode;

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
  static const _logoToDoneStatusGap = 156.0;
  static const _minimumLogoToDoneStatusGap = 48.0;
  static const _doneStatusHeight = 200.0;
  static const _doneStatusToButtonGap = 147.0;
  static const _minimumDoneStatusToButtonGap = 48.0;
  static const _bodyWidth = 130.0;
  static const _doneBodyWidth = 200.0;

  @override
  ConsumerState<SyncKeepAwakePrivacyLockScreen> createState() =>
      _SyncKeepAwakePrivacyLockScreenState();
}

class _SyncKeepAwakePrivacyLockScreenState
    extends ConsumerState<SyncKeepAwakePrivacyLockScreen> {
  var _showPasscode = false;
  var _passcodeEntry = '';
  var _submittingPasscode = false;
  String? _passcodeError;

  @override
  void didUpdateWidget(SyncKeepAwakePrivacyLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode == SyncKeepAwakePrivacyLockMode.hidden && _showPasscode) {
      _resetPasscodePrompt();
    }
  }

  void _openPasscodePrompt() {
    setState(() {
      _showPasscode = true;
      _passcodeEntry = '';
      _passcodeError = null;
      _submittingPasscode = false;
    });
  }

  void _returnToStatusScreen() {
    if (_submittingPasscode) return;
    setState(_resetPasscodePrompt);
  }

  void _resetPasscodePrompt() {
    _showPasscode = false;
    _passcodeEntry = '';
    _passcodeError = null;
    _submittingPasscode = false;
  }

  void _onPasscodeDigit(int digit) {
    if (_submittingPasscode || _passcodeEntry.length >= kMobilePasscodeLength) {
      return;
    }
    setState(() {
      _passcodeEntry += '$digit';
      _passcodeError = null;
    });
    if (_passcodeEntry.length == kMobilePasscodeLength) {
      unawaited(_submitPasscode());
    }
  }

  void _onPasscodeBackspace() {
    if (_submittingPasscode || _passcodeEntry.isEmpty) return;
    setState(() {
      _passcodeEntry = _passcodeEntry.substring(0, _passcodeEntry.length - 1);
      _passcodeError = null;
    });
  }

  Future<void> _submitPasscode() async {
    if (_submittingPasscode) return;
    final passcode = _passcodeEntry;
    setState(() {
      _submittingPasscode = true;
      _passcodeError = null;
    });

    var confirmed = false;
    try {
      confirmed = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(passcode);
    } catch (_) {
      confirmed = false;
    }
    if (!mounted) return;

    if (confirmed) {
      ref.read(syncKeepAwakePrivacyLockProvider.notifier).unlock();
      return;
    }

    unawaited(AppHaptics.error());
    setState(() {
      _submittingPasscode = false;
      _passcodeEntry = '';
      _passcodeError = 'Incorrect Passcode';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showPasscode) {
      return _SyncKeepAwakePasscodeConfirmScreen(
        mode: widget.mode,
        entryLength: _passcodeEntry.length,
        error: _passcodeError,
        submitting: _submittingPasscode,
        onBack: _returnToStatusScreen,
        onDigit: _onPasscodeDigit,
        onBackspace: _onPasscodeBackspace,
      );
    }

    return _SyncKeepAwakeStatusScreen(
      mode: widget.mode,
      onUnlockPressed: _openPasscodePrompt,
    );
  }
}

class _SyncKeepAwakeStatusScreen extends ConsumerWidget {
  const _SyncKeepAwakeStatusScreen({
    required this.mode,
    required this.onUnlockPressed,
  });

  final SyncKeepAwakePrivacyLockMode mode;
  final VoidCallback onUnlockPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final done = mode == SyncKeepAwakePrivacyLockMode.done;
    final interrupted = mode == SyncKeepAwakePrivacyLockMode.interrupted;
    final sync = done || interrupted
        ? null
        : ref.watch(syncProvider).asData?.value;
    final progress = sync?.displayPercentage ?? sync?.percentage ?? 0.0;
    final main = switch (mode) {
      SyncKeepAwakePrivacyLockMode.done => const _SyncKeepAwakeStatusLockup(
        iconName: AppIcons.checkCircle,
        iconKey: ValueKey('sync_keep_awake_privacy_done_check'),
        title: 'Synced',
        body: 'Synced successfully.\nYou can unlock Vizor.',
        success: true,
      ),
      SyncKeepAwakePrivacyLockMode.interrupted =>
        const _SyncKeepAwakeStatusLockup(
          iconName: AppIcons.warning,
          iconKey: ValueKey('sync_keep_awake_privacy_interrupted_warning'),
          title: 'Sync paused',
          body: 'Unlock Vizor to continue.',
          success: false,
        ),
      SyncKeepAwakePrivacyLockMode.hidden ||
      SyncKeepAwakePrivacyLockMode.syncing => _SyncKeepAwakeProgressLockup(
        progress: progress,
      ),
    };
    final semanticsLabel = switch (mode) {
      SyncKeepAwakePrivacyLockMode.done => 'Vizor is synced',
      SyncKeepAwakePrivacyLockMode.interrupted => 'Vizor sync is paused',
      SyncKeepAwakePrivacyLockMode.hidden ||
      SyncKeepAwakePrivacyLockMode.syncing => 'Vizor is syncing',
    };

    return Material(
      color: colors.background.window,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: semanticsLabel,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _resolveVerticalLayout(
                availableHeight: constraints.maxHeight,
                screenHeight: MediaQuery.sizeOf(context).height,
                mode: mode,
              );
              return Column(
                children: [
                  SizedBox(height: layout.topGap),
                  const VizorWordmark(
                    key: ValueKey('sync_keep_awake_privacy_logo'),
                    width: SyncKeepAwakePrivacyLockScreen._logoWidth,
                    height: SyncKeepAwakePrivacyLockScreen._logoHeight,
                  ),
                  SizedBox(height: layout.logoToMainGap),
                  main,
                  SizedBox(height: layout.mainToButtonGap),
                  AppButton(
                    key: const ValueKey(
                      'sync_keep_awake_privacy_unlock_button',
                    ),
                    onPressed: onUnlockPressed,
                    leading: AppIcon(done ? AppIcons.faceId : AppIcons.unlock),
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
    required SyncKeepAwakePrivacyLockMode mode,
  }) {
    final spec = _SyncKeepAwakeLayoutSpec.forMode(mode);
    if (screenHeight >= SyncKeepAwakePrivacyLockScreen._figmaReferenceHeight) {
      return _SyncKeepAwakeVerticalLayout(
        topGap: SyncKeepAwakePrivacyLockScreen._logoTopGap,
        logoToMainGap: spec.logoToMainGap,
        mainToButtonGap: spec.mainToButtonGap,
      );
    }

    var logoToMainGap = spec.logoToMainGap;
    var mainToButtonGap = spec.mainToButtonGap;
    final targetStackHeight = math.max(
      spec.minimumStackHeight,
      availableHeight -
          (SyncKeepAwakePrivacyLockScreen._shortScreenOuterMargin * 2),
    );
    final reduction = math.min(
      spec.stackHeight - targetStackHeight,
      (spec.logoToMainGap - spec.minimumLogoToMainGap) +
          (spec.mainToButtonGap - spec.minimumMainToButtonGap),
    );

    if (reduction > 0) {
      final logoReducible = spec.logoToMainGap - spec.minimumLogoToMainGap;
      final buttonReducible =
          spec.mainToButtonGap - spec.minimumMainToButtonGap;
      final totalReducible = logoReducible + buttonReducible;
      logoToMainGap -= reduction * logoReducible / totalReducible;
      mainToButtonGap -= reduction * buttonReducible / totalReducible;
    }

    final stackHeight =
        SyncKeepAwakePrivacyLockScreen._logoHeight +
        logoToMainGap +
        spec.mainHeight +
        mainToButtonGap +
        AppButtonSizingMobile.largeHeight;

    return _SyncKeepAwakeVerticalLayout(
      topGap: math.max(0, (availableHeight - stackHeight) / 2),
      logoToMainGap: logoToMainGap,
      mainToButtonGap: mainToButtonGap,
    );
  }
}

class _SyncKeepAwakeLayoutSpec {
  const _SyncKeepAwakeLayoutSpec({
    required this.logoToMainGap,
    required this.minimumLogoToMainGap,
    required this.mainHeight,
    required this.mainToButtonGap,
    required this.minimumMainToButtonGap,
  });

  final double logoToMainGap;
  final double minimumLogoToMainGap;
  final double mainHeight;
  final double mainToButtonGap;
  final double minimumMainToButtonGap;

  double get stackHeight =>
      SyncKeepAwakePrivacyLockScreen._logoHeight +
      logoToMainGap +
      mainHeight +
      mainToButtonGap +
      AppButtonSizingMobile.largeHeight;

  double get minimumStackHeight =>
      SyncKeepAwakePrivacyLockScreen._logoHeight +
      minimumLogoToMainGap +
      mainHeight +
      minimumMainToButtonGap +
      AppButtonSizingMobile.largeHeight;

  factory _SyncKeepAwakeLayoutSpec.forMode(SyncKeepAwakePrivacyLockMode mode) {
    if (mode == SyncKeepAwakePrivacyLockMode.done ||
        mode == SyncKeepAwakePrivacyLockMode.interrupted) {
      return const _SyncKeepAwakeLayoutSpec(
        logoToMainGap: SyncKeepAwakePrivacyLockScreen._logoToDoneStatusGap,
        minimumLogoToMainGap:
            SyncKeepAwakePrivacyLockScreen._minimumLogoToDoneStatusGap,
        mainHeight: SyncKeepAwakePrivacyLockScreen._doneStatusHeight,
        mainToButtonGap: SyncKeepAwakePrivacyLockScreen._doneStatusToButtonGap,
        minimumMainToButtonGap:
            SyncKeepAwakePrivacyLockScreen._minimumDoneStatusToButtonGap,
      );
    }
    return const _SyncKeepAwakeLayoutSpec(
      logoToMainGap: SyncKeepAwakePrivacyLockScreen._logoToRingGap,
      minimumLogoToMainGap:
          SyncKeepAwakePrivacyLockScreen._minimumLogoToRingGap,
      mainHeight: SyncKeepAwakePrivacyLockScreen._ringSize,
      mainToButtonGap: SyncKeepAwakePrivacyLockScreen._ringToButtonGap,
      minimumMainToButtonGap:
          SyncKeepAwakePrivacyLockScreen._minimumRingToButtonGap,
    );
  }
}

class _SyncKeepAwakeVerticalLayout {
  const _SyncKeepAwakeVerticalLayout({
    required this.topGap,
    required this.logoToMainGap,
    required this.mainToButtonGap,
  });

  final double topGap;
  final double logoToMainGap;
  final double mainToButtonGap;
}

class _SyncKeepAwakePasscodeConfirmScreen extends ConsumerWidget {
  const _SyncKeepAwakePasscodeConfirmScreen({
    required this.mode,
    required this.entryLength,
    required this.submitting,
    required this.onBack,
    required this.onDigit,
    required this.onBackspace,
    this.error,
  });

  final SyncKeepAwakePrivacyLockMode mode;
  final int entryLength;
  final bool submitting;
  final VoidCallback onBack;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final String? error;

  static const _topNavHeight = 74.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final sync = ref.watch(syncProvider).asData?.value;
    final progress = sync?.displayPercentage ?? sync?.percentage ?? 0.0;
    return Material(
      key: const ValueKey('sync_keep_awake_privacy_passcode_screen'),
      color: colors.background.window,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Confirm passcode to unlock Vizor',
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: _titleForMode(progress),
                titleStyle: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
                height: _topNavHeight,
                onBack: submitting ? null : onBack,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 640;
                    final verticalPadding = compact
                        ? AppSpacing.s
                        : AppSpacing.md;
                    final topGap = compact ? 0.0 : AppSpacing.md;
                    final sectionGap = compact ? AppSpacing.xs : AppSpacing.md;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: verticalPadding,
                      ),
                      child: Column(
                        children: [
                          SizedBox(height: topGap),
                          Text(
                            'Welcome Back',
                            textAlign: TextAlign.center,
                            style: AppTypography.displayLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                          Text(
                            _bodyForMode(),
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.primary,
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          SizedBox(
                            height: kPasscodePromptDigitsHeight,
                            child: PasscodePromptField(
                              length: kMobilePasscodeLength,
                              filled: entryLength,
                              error: error,
                              minGap: 0,
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          PasscodeNumpad(
                            onDigit: onDigit,
                            onBackspace: onBackspace,
                            canDelete: entryLength > 0,
                            enabled: !submitting,
                          ),
                          const Spacer(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleForMode(double progress) {
    return switch (mode) {
      SyncKeepAwakePrivacyLockMode.done => 'Synced',
      SyncKeepAwakePrivacyLockMode.interrupted => 'Sync paused',
      SyncKeepAwakePrivacyLockMode.hidden ||
      SyncKeepAwakePrivacyLockMode.syncing =>
        '${formatSyncStatusPercentage(progress)}% Syncing...',
    };
  }

  String _bodyForMode() {
    if (submitting) return 'Checking passcode...';
    return switch (mode) {
      SyncKeepAwakePrivacyLockMode.done =>
        'Synced successfully. Unlock Vizor to continue.',
      SyncKeepAwakePrivacyLockMode.interrupted =>
        'Sync paused. Unlock Vizor to continue.',
      SyncKeepAwakePrivacyLockMode.hidden ||
      SyncKeepAwakePrivacyLockMode.syncing =>
        'Vizor is syncing, stick around ...',
    };
  }
}

class _SyncKeepAwakeStatusLockup extends StatelessWidget {
  const _SyncKeepAwakeStatusLockup({
    required this.iconName,
    required this.iconKey,
    required this.title,
    required this.body,
    required this.success,
  });

  final String iconName;
  final Key iconKey;
  final String title;
  final String body;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: SyncKeepAwakePrivacyLockScreen._doneStatusHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: AppIcon(
                iconName,
                key: iconKey,
                size: 40,
                color: success ? colors.sync.lightSuccess : colors.icon.warning,
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          Positioned(
            top: 150,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: SyncKeepAwakePrivacyLockScreen._doneBodyWidth,
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
