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
    commitPasswordSetup();
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
    // Persist the verifier and open the secure-storage session before account
    // creation/import writes the encrypted mnemonic. Publishing provider state
    // is still delayed until commit so the router never sees half-completed
    // onboarding.
    await _store.configurePassword(password);
    _isPasswordSetupPrepared = true;
  }

  void commitPasswordSetup() {
    if (!_isPasswordSetupPrepared) {
      throw StateError('Password setup was not prepared.');
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
    await _store.clearPasswordConfiguration();
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

  Future<bool> confirmPassword(String password) async {
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    return _store.verifyPasswordOnly(password);
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
