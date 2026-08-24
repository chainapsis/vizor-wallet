import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../widgets/voting_pane_scroll_area.dart';

class MobileVotingSubmittedScreen extends StatefulWidget {
  const MobileVotingSubmittedScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  State<MobileVotingSubmittedScreen> createState() =>
      _MobileVotingSubmittedScreenState();
}

class _MobileVotingSubmittedScreenState
    extends State<MobileVotingSubmittedScreen> {
  Animation<double>? _routeAnimation;
  bool _celebrationStarted = false;
  bool _celebrationScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (!identical(_routeAnimation, routeAnimation)) {
      _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
      _routeAnimation = routeAnimation;
      _routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
    }
    if (routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed) {
      _scheduleCelebration();
    }
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startCelebration();
    }
  }

  void _scheduleCelebration() {
    if (_celebrationStarted || _celebrationScheduled) return;
    _celebrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _celebrationScheduled = false;
      if (!mounted || _celebrationStarted) return;
      final animation = ModalRoute.of(context)?.animation;
      if (animation != null && animation.status != AnimationStatus.completed) {
        return;
      }
      _startCelebration();
    });
  }

  void _startCelebration() {
    if (!mounted || _celebrationStarted) return;
    _celebrationStarted = true;
    setState(() {});
    unawaited(AppHaptics.sendSuccess());
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onDone();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: mobileTransactionProgressBackgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                excludeFromSemantics: true,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: kMobileTopNavHeight),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const minimumContentHeight = 540.0;
                        final paddedViewportHeight =
                            constraints.maxHeight - AppSpacing.s * 2;
                        final contentHeight =
                            paddedViewportHeight < minimumContentHeight
                            ? minimumContentHeight
                            : paddedViewportHeight;
                        return VotingPaneScrollbar(
                          scrollbarKey: const ValueKey(
                            'mobile_voting_submitted_scrollbar',
                          ),
                          builder: (context, controller) => SingleChildScrollView(
                            controller: controller,
                            primary: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.s,
                              ),
                              child: SizedBox(
                                height: contentHeight,
                                child: Stack(
                                  key: const ValueKey(
                                    'mobile_voting_submitted_content',
                                  ),
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned(
                                      top: 163,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: MobileTransactionProgressBadge(
                                          phase: MobileTransactionProgressPhase
                                              .succeeded,
                                          successIconKey: ValueKey(
                                            'mobile_voting_submitted_success_icon',
                                          ),
                                          successRippleKey: ValueKey(
                                            'mobile_voting_submitted_success_ripple',
                                          ),
                                          terminalAnimationEnabled:
                                              _celebrationStarted,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 293,
                                      left: 0,
                                      right: 0,
                                      child: Text(
                                        'Voted',
                                        key: const ValueKey(
                                          'mobile_voting_submitted_title',
                                        ),
                                        textAlign: TextAlign.center,
                                        style: AppTypography.displayLarge
                                            .copyWith(
                                              color: colors.text.accent,
                                            ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 350,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: SizedBox(
                                          width: 259,
                                          child: Text(
                                            'Your vote has been submitted and '
                                            'can’t be changed.',
                                            textAlign: TextAlign.center,
                                            style: AppTypography
                                                .bodyMediumStrong
                                                .copyWith(
                                                  color: colors.text.primary,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 466,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: SizedBox(
                                          width: 232,
                                          child: AppButton(
                                            key: const ValueKey(
                                              'mobile_voting_submitted_home_button',
                                            ),
                                            onPressed: widget.onDone,
                                            expand: true,
                                            constrainContent: true,
                                            child: const Text('Go home'),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
