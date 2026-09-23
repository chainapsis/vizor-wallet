import 'package:flutter/material.dart';

/// Lays out the sheet at its final position without painting, then runs the
/// normal Material entrance after its initial corners are ready.
class PreparedModalSheetRoute<T> extends ModalBottomSheetRoute<T> {
  PreparedModalSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.modalBarrierColor,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.isDismissible,
    required super.enableDrag,
  }) : super(
         isScrollControlled: true,
         useSafeArea: true,
         backgroundColor: Colors.transparent,
         elevation: 0,
       );

  bool _waiting = true;
  bool _disposed = false;
  bool _popped = false;

  @override
  void install() {
    super.install();
    // ModalRoute exposes a completed animation while offstage, so Flutter
    // performs the genuine final sheet layout (including its constraints).
    offstage = true;
  }

  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    controller!.stop(canceled: false);
    return pushed;
  }

  void cornersReady() {
    if (!_waiting || _disposed) return;
    _waiting = false;
    // Allow the prepared shape to rebuild while still offstage first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _popped || !isActive) return;
      offstage = false;
      controller!.forward(from: 0);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  bool didPop(T? result) {
    _waiting = false;
    _popped = true;
    return super.didPop(result);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
