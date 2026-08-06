import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

const _tooltipGap = 11.0;
const _tooltipWidth = 224.0;
const _tooltipPointerWidth = 8.0;
const _tooltipPointerHeight = 24.0;
final _keystoneFirmwareUri = Uri.parse('https://keyst.one/firmware');

Future<void> _openKeystoneFirmware() async {
  try {
    await launchUrl(_keystoneFirmwareUri, mode: LaunchMode.externalApplication);
  } on Exception {
    // The tooltip remains usable when the operating system cannot open a URL.
  }
}

/// Anchors the desktop Keystone scan-help tooltip beside a request QR without
/// changing the QR's layout or centering.
///
/// The tooltip is shown when [visible] becomes true and stays dismissed for
/// the remainder of that visible session after the user closes it.
class KeystoneScanHelpOverlay extends StatefulWidget {
  const KeystoneScanHelpOverlay({
    required this.visible,
    required this.child,
    super.key,
  });

  final bool visible;
  final Widget child;

  @override
  State<KeystoneScanHelpOverlay> createState() =>
      _KeystoneScanHelpOverlayState();
}

class _KeystoneScanHelpOverlayState extends State<KeystoneScanHelpOverlay> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant KeystoneScanHelpOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _hide();
      return;
    }
    if (!oldWidget.visible) {
      _dismissed = false;
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.visible ||
          _dismissed ||
          _overlayController.isShowing) {
        return;
      }
      _overlayController.show();
    });
  }

  void _dismiss() {
    _dismissed = true;
    _hide();
  }

  void _hide() {
    if (!_overlayController.isShowing) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayController.isShowing) {
          _overlayController.hide();
        }
      });
      return;
    }
    _overlayController.hide();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (_) => AppTheme(
        data: context.appTheme,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.centerRight,
          followerAnchor: Alignment.centerLeft,
          offset: const Offset(_tooltipGap, 0),
          child: _KeystoneScanHelpTooltip(onDismiss: _dismiss),
        ),
      ),
      child: CompositedTransformTarget(link: _layerLink, child: widget.child),
    );
  }
}

class _KeystoneScanHelpTooltip extends StatelessWidget {
  const _KeystoneScanHelpTooltip({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/icons/keystone_scan_help_pointer.svg',
            width: _tooltipPointerWidth,
            height: _tooltipPointerHeight,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(
              colors.background.inverse,
              BlendMode.srcIn,
            ),
          ),
          Container(
            key: const ValueKey('keystone_scan_help_tooltip'),
            width: _tooltipWidth,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.inverse,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Scanning issues?',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: colors.text.inverse,
                          ),
                        ),
                      ),
                      _KeystoneTooltipAction(
                        key: const ValueKey('keystone_scan_help_close'),
                        semanticLabel: 'Close scan help',
                        onActivate: onDismiss,
                        builder: (context, focused) => DecoratedBox(
                          decoration: BoxDecoration(
                            border: focused
                                ? Border.all(color: colors.text.inverse)
                                : null,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: SizedBox.square(
                            dimension: 24,
                            child: Center(
                              child: AppIcon(
                                AppIcons.cross,
                                size: 16,
                                color: colors.icon.inverse,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                RichText(
                  text: TextSpan(
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.inverse.withValues(alpha: 0.6),
                    ),
                    children: [
                      const TextSpan(
                        text: 'Update to the latest Keystone firmware at ',
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: _KeystoneTooltipAction(
                          key: const ValueKey('keystone_firmware_link'),
                          semanticLabel: 'Open Keystone firmware page',
                          link: true,
                          onActivate: () => unawaited(_openKeystoneFirmware()),
                          builder: (context, focused) => Text(
                            'keyst.one/firmware',
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.inverse.withValues(alpha: 0.6),
                              decoration: focused
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: focused
                                  ? colors.text.inverse.withValues(alpha: 0.6)
                                  : null,
                              decorationStyle: focused
                                  ? TextDecorationStyle.solid
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _TooltipActionBuilder =
    Widget Function(BuildContext context, bool focused);

class _KeystoneTooltipAction extends StatefulWidget {
  const _KeystoneTooltipAction({
    required this.semanticLabel,
    required this.onActivate,
    required this.builder,
    this.link = false,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onActivate;
  final _TooltipActionBuilder builder;
  final bool link;

  @override
  State<_KeystoneTooltipAction> createState() => _KeystoneTooltipActionState();
}

class _KeystoneTooltipActionState extends State<_KeystoneTooltipAction> {
  bool _focused = false;

  void _setFocused(bool focused) {
    if (_focused == focused) return;
    setState(() => _focused = focused);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final activates =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (!activates) return KeyEventResult.ignored;

    if (event is KeyUpEvent) widget.onActivate();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !widget.link,
      link: widget.link,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: widget.onActivate,
      child: Focus(
        onFocusChange: _setFocused,
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onActivate,
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}
