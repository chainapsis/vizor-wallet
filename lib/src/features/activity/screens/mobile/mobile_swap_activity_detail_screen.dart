import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/widgets/swap_activity_panel.dart';

/// Mobile host for the shared swap intent detail surface (status,
/// deposit signing, claim) — the 400 pt surface fits the phone width;
/// smaller devices scale down.
class MobileSwapActivityDetailScreen extends StatelessWidget {
  const MobileSwapActivityDetailScreen({
    required this.swapIntentId,
    this.returnTarget = SwapActivityReturnTarget.activity,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String swapIntentId;
  final SwapActivityReturnTarget returnTarget;
  final bool autoSignZecDeposit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The shared surface is laid out for a 400 pt pane; render
            // it at native size when the phone is wide enough and scale
            // down (preserving hit testing) on narrower devices.
            final scale = constraints.maxWidth >= 400
                ? 1.0
                : constraints.maxWidth / 400;
            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 400,
                  height: constraints.maxHeight / scale,
                  child: SwapActivityDetailSurface(
                    intentId: swapIntentId,
                    returnTarget: returnTarget,
                    autoSignZecDeposit: autoSignZecDeposit,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
