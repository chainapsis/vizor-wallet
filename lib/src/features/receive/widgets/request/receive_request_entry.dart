/// How "Request ZEC" appears on the Receive screen, before anything is
/// wired.
///
/// The plain Receive QR stays what it is — an address to share. Asking for a
/// specific amount is a different intent, so it gets its own control rather
/// than an editable field on the address screen: adding an amount box to
/// Receive would make every visit look like a form that needs filling in.
///
/// Both widgets here are deterministic mocks for review. Neither reads a
/// provider or navigates.
library;

import 'package:flutter/widgets.dart';

import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../receive_address_widgets.dart';

/// The mobile Receive action stack with the request entry in it.
///
/// Three tiers, in descending commitment: Share hands the address over now,
/// Request starts a new task, Copy is the quiet fallback. The request sits in
/// the middle as a secondary button — it is a real destination, not a link,
/// but it must not outrank the screen's own purpose.
class ReceiveRequestActionStack extends StatelessWidget {
  const ReceiveRequestActionStack({
    required this.isShielded,
    this.onShare,
    this.onRequest,
    this.onCopy,
    super.key,
  });

  final bool isShielded;
  final VoidCallback? onShare;
  final VoidCallback? onRequest;
  final VoidCallback? onCopy;

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final poolLabel = isShielded ? 'shielded' : 'transparent';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: const ValueKey('mobile_receive_share'),
          expand: true,
          constrainContent: true,
          variant: isShielded
              ? AppButtonVariant.primary
              : AppButtonVariant.secondary,
          onPressed: onShare ?? _noop,
          leading: const AppIcon(AppIcons.share, size: 20),
          child: Text(
            'Share $poolLabel address',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('mobile_receive_request'),
          expand: true,
          constrainContent: true,
          variant: AppButtonVariant.secondary,
          onPressed: onRequest ?? _noop,
          leading: const AppIcon(AppIcons.qr, size: 20),
          child: Text(
            'Request ZEC',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Semantics(
          button: true,
          label: 'Copy $poolLabel address',
          excludeSemantics: true,
          child: AppButton(
            key: const ValueKey('mobile_receive_copy'),
            variant: AppButtonVariant.ghost,
            // Full width like the two pills above it, so a longer
            // translation ellipsizes instead of pushing past the margins.
            expand: true,
            constrainContent: true,
            onPressed: onCopy ?? _noop,
            child: Text(
              'Copy $poolLabel address',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: colors.button.ghost.label,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Deterministic mock of the mobile Receive screen carrying the request
/// entry, for review before the real screen is touched.
///
/// It composes the shipped receive parts ([ReceiveTabs], [ReceiveQrSurface],
/// [ReceiveAddressLine]) around [ReceiveRequestActionStack], so what is being
/// reviewed is the arrangement, not a redrawing of the screen.
class MobileReceiveRequestEntryPreview extends StatelessWidget {
  const MobileReceiveRequestEntryPreview({
    required this.type,
    required this.address,
    this.accountName = 'Account Name',
    super.key,
  });

  final ReceiveAddressType type;
  final String address;
  final String accountName;

  static const _qrSize = 260.0;
  static const _qrPaddingX = 16.0;
  static const _qrPaddingY = 24.0;
  static const _qrBadgeSize = 54.26;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = type == ReceiveAddressType.shielded;

    return ColoredBox(
      color: colors.background.window,
      child: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Receive $kZcashDefaultCurrencyTicker',
              titleStyle: AppTypography.headlineLarge,
              onBack: () {},
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.md,
                ),
                children: [
                  Center(
                    child: ReceiveTabs(
                      width: 320,
                      height: 44,
                      iconSize: 20,
                      iconGap: AppSpacing.xs,
                      labelStyle: AppTypography.labelLarge,
                      labelFontWeight: FontWeight.w500,
                      alwaysDarkSelected: true,
                      selectedType: type,
                      onChanged: (_) {},
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Center(
                    child: ReceiveQrSurface(
                      address: address,
                      size: _qrSize,
                      paddingX: _qrPaddingX,
                      paddingY: _qrPaddingY,
                      type: type,
                      badgeSize: _qrBadgeSize,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      accountName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  ReceiveAddressLine(
                    type: type,
                    address: address,
                    secondaryTint: true,
                    onShowHelp: () {},
                  ),
                  const SizedBox(height: AppSpacing.base),
                  ReceiveRequestActionStack(isShielded: isShielded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
