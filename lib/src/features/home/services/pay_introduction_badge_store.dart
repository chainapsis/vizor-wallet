import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable, install-local record that the Pay introduction was completed.
///
/// This key shipped with the v0.0.37 click-gated treatment. Keep the exact
/// value so users whose decoration already disappeared never see it again.
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

/// Desktop-only visibility for the one-shot Pay introduction.
///
/// The existing click record is claimed before the decoration is shown, while
/// the returned state keeps it visible for the current Home visit. This makes
/// the introduction install-wide and account-independent without reviving it
/// for users who already completed the v0.0.37 treatment.
class DesktopPayIntroductionVisibleNotifier extends AsyncNotifier<bool> {
  var _dismissedInSession = false;

  @override
  Future<bool> build() async {
    if (_dismissedInSession) return false;
    if (!ref.watch(payIntroductionBadgePersistenceEnabledProvider)) {
      return true;
    }

    try {
      final store = ref.watch(payIntroductionBadgeStoreProvider);
      if (await store.hasClickedPay()) return false;

      // Persist before rendering so an app exit or account-driven rebuild
      // cannot turn this into a repeated introduction.
      await store.markPayClicked();
      return !_dismissedInSession;
    } catch (error) {
      // Fail closed: a storage failure must not create a decoration that can
      // reappear on every launch.
      debugPrint('Desktop Pay introduction persistence failed: $error');
      return false;
    }
  }

  void dismiss() {
    if (_dismissedInSession) return;
    _dismissedInSession = true;
    state = const AsyncData(false);
  }
}

final desktopPayIntroductionVisibleProvider =
    AsyncNotifierProvider.autoDispose<
      DesktopPayIntroductionVisibleNotifier,
      bool
    >(DesktopPayIntroductionVisibleNotifier.new);

/// Test seam for full-app suites that rely on `pumpAndSettle`: the coin bob
/// loops forever in production, which never settles. Reduce motion at runtime
/// is handled separately via `MediaQuery.disableAnimations`.
final payIntroductionBadgeMotionEnabledProvider = Provider<bool>((_) => true);
