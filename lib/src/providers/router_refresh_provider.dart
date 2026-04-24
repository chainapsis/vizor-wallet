import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final routerRefreshProvider = Provider<RouterRefreshController>((ref) {
  final controller = RouterRefreshController();
  ref.onDispose(controller.dispose);
  return controller;
});

class RouterRefreshController extends ChangeNotifier {
  int _pauseDepth = 0;
  bool _hasPendingRefresh = false;

  void requestRefresh() {
    if (_pauseDepth > 0) {
      _hasPendingRefresh = true;
      return;
    }
    notifyListeners();
  }

  Future<T> pauseWhile<T>(Future<T> Function() action) async {
    _pauseDepth++;
    var shouldFlush = false;
    try {
      final result = await action();
      shouldFlush = true;
      return result;
    } finally {
      _pauseDepth--;
      if (_pauseDepth == 0 && _hasPendingRefresh) {
        _hasPendingRefresh = false;
        if (shouldFlush) {
          notifyListeners();
        }
      }
    }
  }
}
