import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/security/password_policy.dart';
import '../core/storage/app_secure_store.dart';

class AppSecurityState {
  const AppSecurityState({
    required this.isPasswordConfigured,
    required this.isUnlocked,
  });

  final bool isPasswordConfigured;
  final bool isUnlocked;

  bool get requiresUnlock => isPasswordConfigured && !isUnlocked;

  AppSecurityState copyWith({bool? isPasswordConfigured, bool? isUnlocked}) {
    return AppSecurityState(
      isPasswordConfigured: isPasswordConfigured ?? this.isPasswordConfigured,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}

class AppSecurityNotifier extends Notifier<AppSecurityState> {
  static final _store = AppSecureStore.instance;
  bool _isPasswordSetupPrepared = false;

  @override
  AppSecurityState build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return AppSecurityState(
      isPasswordConfigured: bootstrap.isPasswordConfigured,
      isUnlocked: bootstrap.isUnlocked,
    );
  }

  Future<void> configurePassword(String password) async {
    await preparePasswordSetup(password);
    await commitPasswordSetup(password);
  }

  Future<void> preparePasswordSetup(String password) async {
    if (state.isPasswordConfigured) {
      throw StateError('Password is already configured.');
    }
    if (_isPasswordSetupPrepared) {
      throw StateError('Password setup is already pending.');
    }
    final error = validateWalletPassword(password);
    if (error != null) {
      throw ArgumentError(error);
    }
    // Account creation/import needs an unlocked secure-storage session to
    // persist the mnemonic, but publishing the app security state here would
    // expose a half-completed onboarding state to the router.
    _store.setSessionPassword(password);
    _isPasswordSetupPrepared = true;
  }

  Future<void> commitPasswordSetup(String password) async {
    if (!_isPasswordSetupPrepared) {
      throw StateError('Password setup was not prepared.');
    }
    try {
      await _store.configurePassword(password);
    } catch (_) {
      _isPasswordSetupPrepared = false;
      await _store.clearPasswordConfiguration();
      rethrow;
    }
    _isPasswordSetupPrepared = false;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  Future<void> rollbackPasswordSetup() async {
    if (!_isPasswordSetupPrepared) return;
    _isPasswordSetupPrepared = false;
    _store.clearSessionPassword();
  }

  Future<bool> unlock(String password) async {
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    final isValid = await _store.verifyPassword(password);
    if (isValid) {
      state = state.copyWith(isUnlocked: true);
    }
    return isValid;
  }

  void lock() {
    _store.clearSessionPassword();
    state = state.copyWith(isUnlocked: false);
  }

  void reset() {
    _store.clearSessionPassword();
    state = const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: false,
    );
  }
}

final appSecurityProvider =
    NotifierProvider<AppSecurityNotifier, AppSecurityState>(
      AppSecurityNotifier.new,
    );
