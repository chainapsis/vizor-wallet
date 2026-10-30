import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A Figma icon component: a fixed [box] with the exported SVG placed at the
/// component's inset. When [left]/[top] are omitted the SVG is centered.
class ShieldIcon extends StatelessWidget {
  const ShieldIcon(
    this.name, {
    super.key,
    required this.box,
    required this.width,
    required this.height,
    this.left,
    this.top,
    this.tint,
  });

  final String name;
  final Size box;
  final double width;
  final double height;
  final double? left;
  final double? top;

  /// Recolors a monochrome icon (used where the export lost the instance's
  /// color override).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      'assets/icons/shielding_$name.svg',
      width: width,
      height: height,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint!, BlendMode.srcIn),
    );
    return SizedBox.fromSize(
      size: box,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left ?? (box.width - width) / 2,
            top: top ?? (box.height - height) / 2,
            width: width,
            height: height,
            child: svg,
          ),
        ],
      ),
    );
  }
}
