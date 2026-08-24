import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';

class MobileVotingSubmittedScreen extends StatelessWidget {
  const MobileVotingSubmittedScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onDone();
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.s,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const minimumContentHeight = 540.0;
                          final contentHeight =
                              constraints.maxHeight < minimumContentHeight
                              ? minimumContentHeight
                              : constraints.maxHeight;
                          return SingleChildScrollView(
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: contentHeight,
                              child: Stack(
                                key: const ValueKey(
                                  'mobile_voting_submitted_content',
                                ),
                                fit: StackFit.expand,
                                children: [
                                  const Positioned(
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
                                          .copyWith(color: colors.text.accent),
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
                                          style: AppTypography.bodyMediumStrong
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
                                          onPressed: onDone,
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
                          );
                        },
                      ),
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
