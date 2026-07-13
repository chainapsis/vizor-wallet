import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable, install-local record that the desktop Pay button was activated.
const payIntroductionButtonClickedStorageKey = 'vizor_pay_button_clicked';

abstract interface class PayIntroductionBadgeStore {
  Future<bool> hasClickedPay();

  Future<void> markPayClicked();
}

class SharedPreferencesPayIntroductionBadgeStore
    implements PayIntroductionBadgeStore {
  const SharedPreferencesPayIntroductionBadgeStore();

  @override
  Future<bool> hasClickedPay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(payIntroductionButtonClickedStorageKey) ?? false;
  }

  @override
  Future<void> markPayClicked() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setBool(
      payIntroductionButtonClickedStorageKey,
      true,
    );
    if (!saved) {
      throw StateError('Could not persist the Pay button clicked state.');
    }
  }
}

final payIntroductionBadgeStoreProvider = Provider<PayIntroductionBadgeStore>(
  (_) => const SharedPreferencesPayIntroductionBadgeStore(),
);

/// Test seam for previewing the pre-click state without mutating storage.
final payIntroductionBadgePersistenceEnabledProvider = Provider<bool>(
  (_) => true,
);

class PayIntroductionBadgeClickedNotifier extends AsyncNotifier<bool> {
  var _clickedInSession = false;

  @override
  Future<bool> build() async {
    if (!ref.watch(payIntroductionBadgePersistenceEnabledProvider)) {
      return _clickedInSession;
    }
    try {
      final stored = await ref
          .watch(payIntroductionBadgeStoreProvider)
          .hasClickedPay();
      return _clickedInSession || stored;
    } catch (error) {
      debugPrint('Pay button clicked-state load failed: $error');
      return _clickedInSession;
    }
  }

  void markClicked() {
    if (_clickedInSession || state.value == true) return;
    _clickedInSession = true;
    state = const AsyncData(true);
    if (!ref.read(payIntroductionBadgePersistenceEnabledProvider)) return;
    Future<void>(() async {
      try {
        await ref.read(payIntroductionBadgeStoreProvider).markPayClicked();
      } catch (error) {
        debugPrint('Pay button clicked-state persistence failed: $error');
      }
    });
  }
}

final payIntroductionBadgeClickedProvider =
    AsyncNotifierProvider<PayIntroductionBadgeClickedNotifier, bool>(
      PayIntroductionBadgeClickedNotifier.new,
    );

/// Test seam for full-app suites that rely on `pumpAndSettle`: the coin bob
/// loops forever in production, which never settles. Reduce motion at runtime
/// is handled separately via `MediaQuery.disableAnimations`.
final payIntroductionBadgeMotionEnabledProvider = Provider<bool>((_) => true);
