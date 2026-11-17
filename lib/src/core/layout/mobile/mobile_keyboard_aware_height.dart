import 'package:flutter/widgets.dart';

/// The height a sheet body may take above the keyboard: the window height
/// less the keyboard, the top safe area and [reserved], clamped between
/// [min] and [max].
///
/// Only [builder] follows the keyboard. A sheet that sizes its body here,
/// rather than reading MediaQuery in its own build, is not rebuilt on every
/// frame of the keyboard animation. Keep [builder] to the sizing and pass
/// the body as [child], which is then only laid out again.
class MobileKeyboardAwareHeight extends StatelessWidget {
  const MobileKeyboardAwareHeight({
    required this.reserved,
    required this.min,
    required this.max,
    required this.builder,
    this.child,
    super.key,
  });

  /// Room kept for what the sheet shows outside the sized body, such as its
  /// title, fields and margins.
  final double reserved;
  final double min;
  final double max;
  final Widget Function(BuildContext context, double height, Widget? child)
  builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final available =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.paddingOf(context).top -
        reserved;
    return builder(context, available.clamp(min, max).toDouble(), child);
  }
}
