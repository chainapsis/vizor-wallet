import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_models.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../formatting/sync_status_label.dart' show withTabularFigures;
import '../../formatting/zec_amount.dart';
import '../../privacy/privacy_mask.dart';
import '../../theme/app_theme.dart';
import '../app_profile_picture.dart';

/// Whose page it is: the account's picture, its name, and its balance under
/// it, centered. The viewing key and secret passphrase pages open on it.
class MobileAccountHeader extends StatelessWidget {
  const MobileAccountHeader({
    required this.account,
    this.balanceText,
    super.key,
  });

  final AccountInfo account;

  /// The balance line, already masked in privacy mode
  /// ([mobileAccountHeaderBalance]). Null leaves the line out.
  final String? balanceText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final balanceText = this.balanceText;
    return Column(
      key: const ValueKey('mobile_account_header'),
      children: [
        AppProfilePicture(
          profilePictureId: account.profilePictureId,
          size: AppProfilePictureSize.xLarge,
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          account.name,
          key: const ValueKey('mobile_account_header_name'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.bodyLarge.copyWith(
            color: colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (balanceText != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          // The name's size, a step back in color.
          Text(
            balanceText,
            key: const ValueKey('mobile_account_header_balance'),
            textAlign: TextAlign.center,
            style: withTabularFigures(
              AppTypography.bodyLarge.copyWith(color: colors.text.secondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// The balance line for [MobileAccountHeader]. Only the active account's
/// balance is loaded, so another account gets none, and so does one whose
/// balance has not loaded yet. A holding, so privacy mode masks it.
String? mobileAccountHeaderBalance(
  WidgetRef ref,
  AccountInfo? account, {
  required String? activeAccountUuid,
}) {
  if (account == null || account.uuid != activeAccountUuid) return null;
  final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
    account.uuid,
  );
  if (!sync.hasDisplayBalance) return null;
  return hideAmountIfPrivacyMode(
    ZecAmount.fromZatoshi(
      sync.displayTotalBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString(),
    privacyModeEnabled: ref.watch(privacyModeProvider),
  );
}
