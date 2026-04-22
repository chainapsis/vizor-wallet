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

  @override
  AppSecurityState build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return AppSecurityState(
      isPasswordConfigured: bootstrap.isPasswordConfigured,
      isUnlocked: bootstrap.isUnlocked,
    );
  }

  Future<void> configurePassword(String password) async {
    final error = validateWalletPassword(password);
    if (error != null) {
      throw ArgumentError(error);
    }
    await _store.configurePassword(password);
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
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
