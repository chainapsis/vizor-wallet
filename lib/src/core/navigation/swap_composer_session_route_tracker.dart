/// Tracks the route boundary of an in-memory Swap/Pay composing session.
/// Review and signing stay in the session; leaving both flows ends it.
class SwapComposerSessionRouteTracker {
  SwapComposerSessionRouteTracker({required String initialPath})
    : _wasComposing = _isComposerPath(initialPath);

  bool _wasComposing;

  bool didEndSession(String path) {
    final isComposing = _isComposerPath(path);
    final ended = _wasComposing && !isComposing;
    _wasComposing = isComposing;
    return ended;
  }

  static bool _isComposerPath(String path) => switch (path) {
    '/swap' ||
    '/swap/review' ||
    '/swap/keystone-sign' ||
    '/swap/ledger-sign' ||
    '/pay' ||
    '/pay/review' => true,
    _ => false,
  };
}
