import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import '../core/layout/app_form_factor.dart';
import '../services/biometric_unlock.dart';

const kBiometricUnlockEnabledKey = 'zcash_biometric_unlock_enabled';

/// Channel wrapper — overridable in tests.
final biometricUnlockServiceProvider = Provider<BiometricUnlock>(
  (ref) => BiometricUnlock(),
);

/// Synchronous best-effort "biometric unlock enabled" hint from the startup
/// bootstrap snapshot. Lets the unlock screen paint the biometric backdrop on
/// the very first frame instead of flashing the numpad while
/// [biometricUnlockProvider] resolves its async availability probe. Falls back
/// to false when no bootstrap snapshot is available (widgetbook / tests that
/// don't override [appBootstrapProvider]).
final biometricUnlockEnabledHintProvider = Provider<bool>((ref) {
  try {
    return ref.watch(
      appBootstrapProvider.select((b) => b.biometricUnlockEnabled),
    );
  } catch (_) {
    return false;
  }
});

class BiometricUnlockState {
  const BiometricUnlockState({
    required this.availability,
    required this.enabled,
  });

  static const initial = BiometricUnlockState(
    availability: BiometricAvailability.unavailable,
    enabled: false,
  );

  final BiometricAvailability availability;

  /// The UI affordance flag. The escrow item itself is the truth; this
  /// only decides whether surfaces offer the biometric path before any
  /// prompt is shown.
  final bool enabled;

  bool get usable => availability.usable && enabled;

  BiometricUnlockState copyWith({
    BiometricAvailability? availability,
    bool? enabled,
  }) {
    return BiometricUnlockState(
      availability: availability ?? this.availability,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Orchestrates the passcode escrow: the enabled flag in secure
/// storage, availability probing, and the invalidation fallback (a
/// biometric re-enrollment invalidates the escrow → drop the flag and
/// let the passcode path take over).
class BiometricUnlockNotifier extends AsyncNotifier<BiometricUnlockState> {
  static final _store = AppSecureStore.instance;

  BiometricUnlock get _service => ref.read(biometricUnlockServiceProvider);

  @override
  Future<BiometricUnlockState> build() async {
    final availability = await _service.availability();
    final enabled =
        await _store.readPlain(kBiometricUnlockEnabledKey) == 'true';
    return BiometricUnlockState(availability: availability, enabled: enabled);
  }

  Future<BiometricUnlockState> _current() async => state.value ?? await future;

  /// Writes the escrow for [passcode] and flips the flag on.
  Future<void> enable(String passcode) async {
    await _service.enable(passcode);
    await _store.writePlain(kBiometricUnlockEnabledKey, 'true');
    final current = await _current();
    state = AsyncData(current.copyWith(enabled: true));
  }

  /// Deletes the escrow and flips the flag off. Safe to call when
  /// already disabled (reset/sign-out hygiene).
  Future<void> disable() async {
    try {
      await _service.disable();
    } on BiometricUnlockException catch (e) {
      // Deletion is hygiene; a missing item must not block a reset.
      log('BiometricUnlock.disable: ignoring ${e.kind.name}');
    }
    await _store.writePlain(kBiometricUnlockEnabledKey, 'false');
    final current = await _current();
    state = AsyncData(current.copyWith(enabled: false));
  }

  /// Read the biometric-protected wallet passcode. A failed native prompt must
  /// never turn off the second factor or alter a subsequent unlock attempt.
  Future<String?> readPasscode({required String reason}) async {
    try {
      return await _service.read(reason: reason);
    } on BiometricUnlockException catch (error) {
      if (kAppFormFactor != AppFormFactor.mobile &&
          (error.kind == BiometricUnlockErrorKind.invalidated ||
              error.kind == BiometricUnlockErrorKind.unavailable)) {
        await disable();
      }
      return null;
    }
  }

  Future<void> refreshAvailability() async {
    final availability = await _service.availability();
    final current = await _current();
    state = AsyncData(current.copyWith(availability: availability));
  }
}

final biometricUnlockProvider =
    AsyncNotifierProvider<BiometricUnlockNotifier, BiometricUnlockState>(
      BiometricUnlockNotifier.new,
    );
