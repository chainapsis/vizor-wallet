import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_models.dart';

const _paySelectedAssetKey = 'zcash_pay_selected_asset_v1';

String _paySelectedAssetKeyFor(String accountUuid) =>
    '$_paySelectedAssetKey:$accountUuid';

final paySelectedAssetStoreProvider = Provider<PaySelectedAssetStore>((ref) {
  return AppSecureStorePaySelectedAssetStore(AppSecureStore.instance);
});

/// Pay remembers its payout asset separately from the swap composer
/// preferences so Pay-mode selections never overwrite the saved swap
/// direction/asset.
abstract interface class PaySelectedAssetStore {
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid});

  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  });
}

class AppSecureStorePaySelectedAssetStore implements PaySelectedAssetStore {
  const AppSecureStorePaySelectedAssetStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    final raw = await _storage.readString(
      _paySelectedAssetKeyFor(accountUuid),
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final asset = SwapAsset.fromPersistedJson(jsonDecode(raw));
      if (asset == null || asset == SwapAsset.zec) return null;
      return asset;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {
    await _storage.writeString(
      _paySelectedAssetKeyFor(accountUuid),
      jsonEncode(asset.toPersistedJson()),
    );
  }
}
