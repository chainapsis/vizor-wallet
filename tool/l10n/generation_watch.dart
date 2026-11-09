import 'dart:async';

/// Coalesce saves and serialize work. A save during generation queues one
/// follow-up pass; there is never a competing generator process.
class GenerationWatch {
  GenerationWatch({
    required this.generate,
    required this.onError,
    this.debounce = const Duration(milliseconds: 500),
  });

  final Future<void> Function() generate;
  final void Function(Object error, StackTrace stack) onError;
  final Duration debounce;
  Timer? _timer;
  Completer<void>? _active;
  bool _dirty = false;
  bool _closed = false;

  void schedule({bool immediate = false}) {
    if (_closed) return;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : debounce, _run);
  }

  Future<void> _run() async {
    _timer = null;
    if (_closed || _active != null) return;
    _dirty = false;
    final active = _active = Completer<void>();
    try {
      await generate();
    } catch (error, stack) {
      onError(error, stack);
    } finally {
      _active = null;
      active.complete();
      if (_dirty && !_closed) schedule();
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _active?.future;
  }
}
