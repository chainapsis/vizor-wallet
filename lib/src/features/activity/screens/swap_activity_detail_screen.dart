import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/widgets/swap_activity_panel.dart';
import '../../swap/widgets/swap_near_intents_attribution.dart';

class SwapActivityDetailScreen extends ConsumerStatefulWidget {
  const SwapActivityDetailScreen({
    required this.swapIntentId,
    this.returnTarget = SwapActivityReturnTarget.activity,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String swapIntentId;
  final SwapActivityReturnTarget returnTarget;
  final bool autoSignZecDeposit;

  @override
  ConsumerState<SwapActivityDetailScreen> createState() =>
      _SwapActivityDetailScreenState();
}

class _SwapActivityDetailScreenState
    extends ConsumerState<SwapActivityDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: widget.returnTarget.label,
                minWidth: 60,
                onTap: () => context.go(widget.returnTarget.path),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: SwapActivityDetailSurface(
                          intentId: widget.swapIntentId,
                          autoSignZecDeposit: widget.autoSignZecDeposit,
                        ),
                      ),
                      if (constraints.maxHeight >= 520)
                        const Positioned(
                          left: 0,
                          bottom: AppSpacing.md,
                          child: SwapNearIntentsAttribution(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
