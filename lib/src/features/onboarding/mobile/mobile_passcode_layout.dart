import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold, RawScrollbar;
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import 'passcode_widgets.dart';

/// Shared passcode presentation; authentication belongs to callers.
/// Input controls never participate in the copy area's accessibility scroll.
class MobilePasscodeLayout extends StatelessWidget {
  const MobilePasscodeLayout({
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onDigit,
    required this.onBackspace,
    this.navigation,
    this.footer,
    this.error,
    this.onHelp,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final int filled;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final Widget? navigation;
  final Widget? footer;
  final String? error;
  final VoidCallback? onHelp;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final compact = bounds.maxHeight < 740;
          return Column(
            children: [
              if (navigation != null)
                SizedBox(
                  height: compact ? 56 : 74,
                  child: Center(child: navigation),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compact ? 8 : 0,
                    16,
                    compact ? 8 : (footer == null ? 48 : 24),
                  ),
                  child: _portrait(context, compact),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  TextStyle _titleStyle(BuildContext context, bool compact) =>
      AppTypography.displayLarge.copyWith(
        color: context.colors.text.accent,
        fontSize: compact ? 32 : null,
        height: compact ? 36 / 32 : null,
      );
  TextStyle _subtitleStyle(BuildContext context) => AppTypography
      .bodyMediumStrong
      .copyWith(color: context.colors.text.primary);
  TextStyle _errorStyle(BuildContext context) =>
      AppTypography.labelLarge.copyWith(color: context.colors.text.destructive);

  double _textHeight(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  Widget _copy(
    BuildContext context,
    bool compact, {
    bool includeError = false,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        key: const ValueKey('passcode_layout_title'),
        textAlign: TextAlign.center,
        style: _titleStyle(context, compact),
      ),
      SizedBox(height: compact ? 8 : 12),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: _subtitleStyle(context),
      ),
      if (includeError && error != null) ...[
        const SizedBox(height: 8),
        _error(context),
      ],
    ],
  );

  Widget _error(BuildContext context) => Text(
    error ?? ' ',
    key: const ValueKey('passcode_layout_error'),
    textAlign: TextAlign.center,
    style: _errorStyle(context),
  );

  Widget _dots(double height) => SizedBox(
    height: height,
    key: const ValueKey('passcode_layout_dots'),
    child: Center(
      child: PasscodeDots(length: 6, filled: filled, horizontalPadding: 7),
    ),
  );

  Widget _keypad(double width) => SizedBox(
    key: const ValueKey('passcode_layout_keypad'),
    width: width,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: kPasscodeKeypadWidth,
        child: MediaQuery.withNoTextScaling(
          child: PasscodeNumpad(
            onDigit: onDigit,
            onBackspace: onBackspace,
            canDelete: filled > 0,
            onHelp: onHelp,
            enabled: enabled,
          ),
        ),
      ),
    ),
  );

  Widget _portrait(BuildContext context, bool compact) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final gap = compact ? 8.0 : 24.0;
            final dotsHeight = compact ? 36.0 : 57.0;
            final errorGap = compact ? 4.0 : 8.0;
            final copyHeight =
                _textHeight(
                  context,
                  title,
                  _titleStyle(context, compact),
                  bounds.maxWidth,
                ) +
                (compact ? 8 : 12) +
                _textHeight(
                  context,
                  subtitle,
                  _subtitleStyle(context),
                  bounds.maxWidth,
                );
            final errorHeight = _textHeight(
              context,
              error ?? ' ',
              _errorStyle(context),
              bounds.maxWidth,
            );
            final otherHeight =
                copyHeight + gap + dotsHeight + errorGap + errorHeight + gap;
            // Existing keypad is 320 wide / 368 tall. Prefer its original 80px keys,
            // reducing only as needed and never below 48px touch targets.
            final maxWidth = math.min(320.0, bounds.maxWidth);
            final keyWidth = math.min(
              maxWidth,
              math.max(192.0, (bounds.maxHeight - otherHeight) * 320 / 368),
            );
            final scrollCopy =
                otherHeight + keyWidth * 368 / 320 > bounds.maxHeight + 0.01;
            if (!scrollCopy) {
              // Keep the keypad anchored near the safe-area bottom. At the
              // reference setup size, 48 of the 76 spare pixels sit above the
              // heading; the rest separates the prompt from the keypad.
              final remaining = math.max(
                0.0,
                bounds.maxHeight - otherHeight - keyWidth * 368 / 320,
              );
              final leadingSpace = compact ? 0.0 : remaining * (48 / 76);
              return Column(
                children: [
                  SizedBox(height: leadingSpace),
                  _copy(context, compact),
                  SizedBox(height: gap),
                  _dots(dotsHeight),
                  SizedBox(height: errorGap),
                  _error(context),
                  SizedBox(height: gap),
                  const Spacer(),
                  _keypad(keyWidth),
                ],
              );
            }
            return Column(
              children: [
                Expanded(
                  child: _ScrollablePasscodeCopy(
                    child: _copy(context, compact, includeError: true),
                  ),
                ),
                const SizedBox(height: 8),
                _dots(36),
                const SizedBox(height: 8),
                _keypad(keyWidth),
              ],
            );
          },
        ),
      ),
      if (footer != null) ...[SizedBox(height: compact ? 8 : 16), footer!],
    ],
  );
}

/// Only explanatory copy can scroll. The persistent thumb and edge fades
/// indicate clipped content without covering or moving the input controls.
class _ScrollablePasscodeCopy extends StatefulWidget {
  const _ScrollablePasscodeCopy({required this.child});
  final Widget child;
  @override
  State<_ScrollablePasscodeCopy> createState() =>
      _ScrollablePasscodeCopyState();
}

class _ScrollablePasscodeCopyState extends State<_ScrollablePasscodeCopy> {
  final _controller = ScrollController();
  bool _hasOverflow = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final color = context.colors.background.window;
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          final overflow = notification.metrics.maxScrollExtent > 1;
          if (overflow != _hasOverflow) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && overflow != _hasOverflow) {
                setState(() => _hasOverflow = overflow);
              }
            });
          }
          return false;
        },
        child: Stack(
          children: [
            RawScrollbar(
              key: const ValueKey('passcode_copy_scrollbar'),
              controller: _controller,
              thumbVisibility: true,
              interactive: true,
              thumbColor: context.colors.text.muted,
              thickness: 4,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                key: const ValueKey('passcode_copy_scroll'),
                controller: _controller,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                  child: SizedBox(
                    width: bounds.maxWidth - 24,
                    child: widget.child,
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (!_hasOverflow) return const SizedBox.shrink();
                final hasPosition =
                    _controller.hasClients &&
                    _controller.position.hasContentDimensions;
                final atTop =
                    !hasPosition || _controller.position.extentBefore <= 1;
                final atBottom =
                    hasPosition && _controller.position.extentAfter <= 1;
                return IgnorePointer(
                  child: Column(
                    children: [
                      if (!atTop)
                        _fade(color, false)
                      else
                        const SizedBox(height: 16),
                      const Spacer(),
                      if (!atBottom)
                        _fade(color, true)
                      else
                        const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );

  Widget _fade(Color color, bool bottom) => Container(
    height: 16,
    width: double.infinity,
    key: ValueKey(
      bottom ? 'passcode_copy_bottom_fade' : 'passcode_copy_top_fade',
    ),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: bottom
            ? [color.withValues(alpha: 0), color]
            : [color, color.withValues(alpha: 0)],
      ),
    ),
  );
}
