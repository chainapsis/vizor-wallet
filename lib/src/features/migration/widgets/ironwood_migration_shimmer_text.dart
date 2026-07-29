import 'package:flutter/widgets.dart';

/// A low-contrast activity shimmer for Ironwood migration status text.
class IronwoodMigrationShimmerText extends StatefulWidget {
  const IronwoodMigrationShimmerText({
    required this.text,
    required this.style,
    required this.baseColor,
    required this.highlightColor,
    this.textAlign,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color baseColor;
  final Color highlightColor;
  final TextAlign? textAlign;

  @override
  State<IronwoodMigrationShimmerText> createState() =>
      _IronwoodMigrationShimmerTextState();
}

class _IronwoodMigrationShimmerTextState
    extends State<IronwoodMigrationShimmerText>
    with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1400);
  static const _bandHalf = 0.18;

  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(vsync: this, duration: _period);
  }

  bool get _shouldAnimate =>
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) {
        _activeController.repeat();
      }
    } else {
      _controller
        ?..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldAnimate) {
      return Text(
        widget.text,
        textAlign: widget.textAlign,
        style: widget.style.copyWith(color: widget.baseColor),
      );
    }

    return AnimatedBuilder(
      animation: _activeController,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            final shift = (_activeController.value * 2 - 1) * bounds.width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: const [0.5 - _bandHalf, 0.5, 0.5 + _bandHalf],
              tileMode: TileMode.clamp,
            ).createShader(
              Rect.fromLTWH(
                bounds.left + shift,
                bounds.top,
                bounds.width,
                bounds.height,
              ),
            );
          },
          child: Text(
            widget.text,
            textAlign: widget.textAlign,
            style: widget.style.copyWith(color: const Color(0xFFFFFFFF)),
          ),
        );
      },
    );
  }
}
