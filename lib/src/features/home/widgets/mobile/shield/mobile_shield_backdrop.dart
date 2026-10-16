import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The caller owns this still until navigation returns. The scene clones its
/// image so the reverse route transition can finish after that owner releases it.
class MobileShieldBackdrop {
  const MobileShieldBackdrop(this.image);

  final ui.Image image;

  void dispose() => image.dispose();
}

/// Captures the complete mobile shell, including the floating tab bar, without
/// rebuilding home or reading wallet state for decorative content.
class MobileShieldBackdropHost extends StatefulWidget {
  const MobileShieldBackdropHost({required this.child, super.key});

  final Widget child;

  static MobileShieldBackdrop? capture(BuildContext context) => context
      .findAncestorStateOfType<_MobileShieldBackdropHostState>()
      ?._capture();

  @override
  State<MobileShieldBackdropHost> createState() =>
      _MobileShieldBackdropHostState();
}

class _MobileShieldBackdropHostState extends State<MobileShieldBackdropHost> {
  final _boundaryKey = GlobalKey();

  MobileShieldBackdrop? _capture() {
    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! _RenderShieldRepaintBoundary || boundary.size.isEmpty) {
      return null;
    }
    try {
      final image = boundary.captureLastFrame(
        MediaQuery.devicePixelRatioOf(context),
      );
      return image == null ? null : MobileShieldBackdrop(image);
    } catch (error) {
      // Missing/unfinished decorative capture must not block shielding.
      debugPrint('Shield backdrop capture unavailable: $error');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      _ShieldRepaintBoundary(key: _boundaryKey, child: widget.child);
}

class _ShieldRepaintBoundary extends RepaintBoundary {
  const _ShieldRepaintBoundary({required super.child, super.key});

  @override
  _RenderShieldRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderShieldRepaintBoundary();
}

class _RenderShieldRepaintBoundary extends RenderRepaintBoundary {
  ui.Image? captureLastFrame(double pixelRatio) {
    final painted = layer;
    if (painted is! OffsetLayer) {
      return null;
    }
    // Snapshot what is on screen now, even if a balance or animation update
    // has already requested the next paint. Access to the layer stays with
    // its render owner.
    return painted.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }
}
