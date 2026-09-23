import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Process-lifetime exit gate. Hiding or backgrounding a window never sets it.
class AppShutdownSignal extends ChangeNotifier {
  bool _isShuttingDown = false;

  bool get isShuttingDown => _isShuttingDown;

  void begin() {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    notifyListeners();
  }
}

final appShutdownSignal = AppShutdownSignal();
final appShutdownSignalProvider = Provider((ref) => appShutdownSignal);
