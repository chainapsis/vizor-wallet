import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps a visible stable row in place across snapshot replacement. Feed
/// offsets let us correct before lazy layout even when many rows were added.
/// Changes below that row leave scrolling entirely to the viewport.
class ActivityScrollAnchor {
  ActivityScrollAnchor({this.topInset = 0, ScrollController? controller})
    : controller = controller ?? ScrollController();
  final double topInset;

  /// Owned and disposed by this anchor, including when supplied by the caller.
  final ScrollController controller;
  final _keys = <String, GlobalKey>{};
  Map<String, double> _offsets = {};
  _CapturedRow? _pending;
  GlobalKey keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  void updateOffsets(Map<String, double> offsets) {
    final pending = _pending;
    if (pending != null && !pending.corrected) {
      final oldOffset = pending.contentOffset;
      final nextOffset = offsets[pending.id];
      if (oldOffset != null && nextOffset != null) {
        if (nextOffset == oldOffset) {
          // Appends and footer skeleton changes do not move the visible row.
          // Skip both layout-time correction and the post-frame jump fallback.
          _pending = null;
        } else if (controller.hasClients &&
            (controller.position.pixels - pending.expectedPixels).abs() <= 1) {
          // ScrollPosition permits layout-time corrections without dispatching
          // scroll callbacks or rebuilding during the build/layout phase.
          controller.position.correctBy(nextOffset - oldOffset);
          pending.expectedPixels = controller.position.pixels;
          pending.corrected = true;
        }
      }
    }
    _offsets = offsets;
  }

  VoidCallback capture() {
    if (!controller.hasClients || controller.position.pixels <= 0) return () {};
    _CapturedRow? captured;
    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      final viewportBox = viewport as RenderBox;
      final y = box.localToGlobal(Offset.zero).dy;
      final start = viewportBox.localToGlobal(Offset.zero).dy + topInset;
      if (y + box.size.height <= start ||
          y >= start + viewportBox.size.height) {
        continue;
      }
      if (captured == null || y < captured.top) {
        captured = _CapturedRow(
          entry.key,
          entry.value,
          y,
          controller.position.pixels,
          _offsets[entry.key],
        );
      }
    }
    return () {
      final row = captured;
      if (row == null) return;
      _pending = row;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!identical(_pending, row)) return;
        _pending = null;
        if (!controller.hasClients ||
            (controller.position.pixels - row.expectedPixels).abs() > 1) {
          return;
        }
        final box = row.key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) return;
        final delta = box.localToGlobal(Offset.zero).dy - row.top;
        final position = controller.position;
        final offset = (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((offset - position.pixels).abs() > 0.5) controller.jumpTo(offset);
      });
    };
  }

  void dispose() {
    controller.dispose();
    _keys.clear();
    _offsets.clear();
    _pending = null;
  }
}

class _CapturedRow {
  _CapturedRow(
    this.id,
    this.key,
    this.top,
    this.expectedPixels,
    this.contentOffset,
  );
  final String id;
  final GlobalKey key;
  final double top;
  final double? contentOffset;
  double expectedPixels;
  bool corrected = false;
}
