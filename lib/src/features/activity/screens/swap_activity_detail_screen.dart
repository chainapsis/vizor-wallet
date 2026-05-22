import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../swap/widgets/swap_activity_panel.dart';

class SwapActivityDetailScreen extends ConsumerStatefulWidget {
  const SwapActivityDetailScreen({
    required this.swapIntentId,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String swapIntentId;
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
            const Align(
              alignment: Alignment.centerLeft,
              child: AppRouteBackLink(minWidth: 60),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SizedBox.expand(
                    child: SwapActivityDetailSurface(
                      intentId: widget.swapIntentId,
                      autoSignZecDeposit: widget.autoSignZecDeposit,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
