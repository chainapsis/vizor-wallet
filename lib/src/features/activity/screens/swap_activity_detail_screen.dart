import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/widgets/swap_activity_panel.dart';

class SwapActivityDetailScreen extends ConsumerStatefulWidget {
  const SwapActivityDetailScreen({
    required this.swapIntentId,
    this.returnTarget = SwapActivityReturnTarget.activity,
    this.autoSignZecDeposit = false,
    this.launchExternalUri,
    super.key,
  });

  final String swapIntentId;
  final SwapActivityReturnTarget returnTarget;
  final bool autoSignZecDeposit;
  final Future<void> Function(Uri uri)? launchExternalUri;

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
        key: const ValueKey('swap_activity_detail_pane'),
        padding: EdgeInsets.zero,
        child: SwapActivityDetailSurface(
          intentId: widget.swapIntentId,
          returnTarget: widget.returnTarget,
          autoSignZecDeposit: widget.autoSignZecDeposit,
          launchExternalUri: widget.launchExternalUri,
        ),
      ),
    );
  }
}
