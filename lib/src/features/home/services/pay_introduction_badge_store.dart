import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable, install-local acknowledgement for the desktop Pay introduction.
const payIntroductionBadgeSeenStorageKey = 'vizor_pay_introduction_badge_seen';

abstract interface class PayIntroductionBadgeStore {
  Future<bool> hasSeen();

  Future<void> markSeen();
}

class SharedPreferencesPayIntroductionBadgeStore
    implements PayIntroductionBadgeStore {
  const SharedPreferencesPayIntroductionBadgeStore();

  @override
  Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(payIntroductionBadgeSeenStorageKey) ?? false;
  }

  @override
  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setBool(payIntroductionBadgeSeenStorageKey, true);
    if (!saved) {
      throw StateError('Could not persist the Pay introduction badge state.');
    }
  }
}

final payIntroductionBadgeStoreProvider = Provider<PayIntroductionBadgeStore>(
  (_) => const SharedPreferencesPayIntroductionBadgeStore(),
);

/// Test seam for previewing the first-visit state without mutating storage.
/// Production keeps persistence enabled so only the `NEW` marker is one-shot.
final payIntroductionBadgePersistenceEnabledProvider = Provider<bool>(
  (_) => true,
);
