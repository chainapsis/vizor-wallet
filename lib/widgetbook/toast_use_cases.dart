// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/content_overlay_inset.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_toast.dart';
import '../src/core/widgets/network_fallback_toast.dart';

Widget buildToastUseCase(BuildContext context) {
  final colors = context.colors;
  return ColoredBox(
    color: colors.background.ground,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          AppToast(message: 'Address copied'),
          SizedBox(height: AppSpacing.sm),
          AppToast(message: 'Transaction hash copied'),
        ],
      ),
    ),
  );
}

// --- App toast playground ---------------------------------------------------

/// One [AppToast] on the plain ground, every axis a parameter.
///
/// The width cap is what makes the two-line wrap visible: the pill sizes to
/// its content, so an unconstrained parent never wraps.
Widget appToastPlaygroundFixture(
  BuildContext context, {
  required AppToastTone tone,
  required String iconName,
  required String message,
}) {
  return ColoredBox(
    color: context.colors.background.ground,
    child: Center(
      child: SizedBox(
        width: 280,
        child: Align(
          child: AppToast(message: message, iconName: iconName, tone: tone),
        ),
      ),
    ),
  );
}

// --- Network fallback toast -------------------------------------------------

/// Copy `RpcEndpointFailoverNotifier` hands the toast when it switches away
/// from the selected endpoint.
const String kWbEndpointFailoverNotice =
    'Selected endpoint is unstable. Switched to fallback endpoint.';

/// Copy the same notifier hands the toast when the primary recovers.
const String kWbEndpointRecoveredNotice =
    'Selected endpoint recovered. Switched back.';

/// One [NetworkFallbackToast] at a fixed width.
///
/// Theme treatment (dark border vs light double shadow) comes from the Theme
/// addon, so it is not a knob here.
Widget networkFallbackToastFixture(
  BuildContext context, {
  required String message,
  required double width,
}) {
  return ColoredBox(
    color: context.colors.background.window,
    child: Center(
      child: SizedBox(
        width: width,
        child: NetworkFallbackToast(message: message),
      ),
    ),
  );
}

/// [NetworkFallbackToastHost] over a plain pane, with a trigger that calls the
/// real `showNetworkFallbackToast` from a descendant context.
///
/// [sidebarInset] mounts a [ContentOverlayInset] the way a desktop shell does,
/// so the toast clears the sidebar column; with no shell the published inset
/// is zero and the toast centres over the whole window.
Widget networkFallbackToastHostFixture(
  BuildContext context, {
  required bool sidebarInset,
  required double topPadding,
  required String message,
}) {
  Widget body = _WbToastTrigger(
    optionKey: 'network|$sidebarInset|$topPadding|$message',
    label: 'Show notice',
    onShow: (triggerContext) =>
        showNetworkFallbackToast(triggerContext, message),
  );
  if (sidebarInset) {
    body = ContentOverlayInset(
      leftInset: appDesktopPaneLeftInset(kAppDesktopSidebarWidth),
      rightInset: kAppDesktopShellMargin,
      child: body,
    );
  }
  return _wbToastHostFrame(
    context,
    topPadding: topPadding,
    child: NetworkFallbackToastHost(child: body),
  );
}

// --- App toast host ---------------------------------------------------------

/// [AppToastHost] over a plain pane, or the same trigger with no host so the
/// `showAppToast` root-overlay fallback runs instead.
///
/// The no-host option is only guaranteed to show the overlay fallback in the
/// isolated test harness: `showAppToast` first reuses the last mounted
/// `AppToastHost` process-wide, so in a live widgetbook session a host left
/// behind by another gallery can still catch it.
Widget appToastHostFixture(
  BuildContext context, {
  required bool hasHost,
  required double topPadding,
  required AppToastTone tone,
  required String message,
}) {
  final trigger = _WbToastTrigger(
    optionKey: 'app|$hasHost|$topPadding|${tone.name}|$message',
    label: 'Show toast',
    onShow: (triggerContext) => showAppToast(
      triggerContext,
      message,
      tone: tone,
      iconName: tone == AppToastTone.destructive
          ? AppIcons.warning
          : AppIcons.checkCircle,
    ),
  );
  return _wbToastHostFrame(
    context,
    topPadding: topPadding,
    // The overlay fallback reads the window's own padding, not this frame's,
    // so the inset axis only moves the in-shell toast.
    child: hasHost ? AppToastHost(child: trigger) : Center(child: trigger),
  );
}

/// Window-sized box whose `padding.top` is what both hosts read for their
/// `max(32, top + 8)` offset.
Widget _wbToastHostFrame(
  BuildContext context, {
  required double topPadding,
  required Widget child,
}) {
  return Center(
    child: SizedBox(
      width: 1080,
      height: 420,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: EdgeInsets.only(top: topPadding),
          viewPadding: EdgeInsets.only(top: topPadding),
          viewInsets: EdgeInsets.zero,
        ),
        child: ColoredBox(color: context.colors.background.base, child: child),
      ),
    ),
  );
}

/// Shows the toast once per knob option and leaves a button to re-show it
/// after the host's auto-dismiss timer clears it.
class _WbToastTrigger extends StatefulWidget {
  const _WbToastTrigger({
    required this.optionKey,
    required this.label,
    required this.onShow,
  });

  final String optionKey;
  final String label;
  final void Function(BuildContext context) onShow;

  @override
  State<_WbToastTrigger> createState() => _WbToastTriggerState();
}

class _WbToastTriggerState extends State<_WbToastTrigger> {
  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(_WbToastTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.optionKey != widget.optionKey) _scheduleShow();
  }

  // Post-frame: the host scope only exists once this subtree is mounted.
  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onShow(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppButton(
        variant: AppButtonVariant.secondary,
        onPressed: () => widget.onShow(context),
        child: Text(widget.label),
      ),
    );
  }
}
