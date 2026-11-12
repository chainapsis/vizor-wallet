import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../services/device_owner_auth.dart';

final deviceOwnerAuthProvider = Provider<DeviceOwnerAuth>(
  (ref) => DeviceOwnerAuth(),
);

Future<bool> verifyDeviceOwnerForWalletReset(
  WidgetRef ref,
  AppLocalizations l10n,
) {
  return ref
      .read(deviceOwnerAuthProvider)
      .verify(reason: l10n.walletResetDeviceAuthReason);
}
