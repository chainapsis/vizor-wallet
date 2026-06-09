import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';

enum ReceiveDesktopPreviewState {
  shielded,
  transparent,
  shieldedModal,
  transparentModal,
}

class ReceiveDesktopPreview extends StatelessWidget {
  const ReceiveDesktopPreview({required this.state, super.key});

  final ReceiveDesktopPreviewState state;

  static const size = Size(1080, 720);

  bool get _isShielded =>
      state == ReceiveDesktopPreviewState.shielded ||
      state == ReceiveDesktopPreviewState.shieldedModal;

  bool get _showsModal =>
      state == ReceiveDesktopPreviewState.shieldedModal ||
      state == ReceiveDesktopPreviewState.transparentModal;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return SizedBox.fromSize(
      size: ReceiveDesktopPreview.size,
      child: _ReceiveWindow(
        isDark: isDark,
        isShielded: _isShielded,
        showsModal: _showsModal,
      ),
    );
  }
}

class _ReceiveWindow extends StatelessWidget {
  const _ReceiveWindow({
    required this.isDark,
    required this.isShielded,
    required this.showsModal,
  });

  final bool isDark;
  final bool isShielded;
  final bool showsModal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.10 : 0.12,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.macosUtility.window,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 48,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Row(
                    children: [
                      const _PreviewSidebar(),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _ReceiveTrailingPane(
                          isShielded: isShielded,
                          showsModal: showsModal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(left: 20, top: 20, child: _WindowControls()),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _WindowControl(color: Color(0xFFFF736A)),
        SizedBox(width: 9),
        _WindowControl(color: Color(0xFFFEBC2E)),
        SizedBox(width: 9),
        _WindowControl(color: Color(0xFFB8B8B8)),
      ],
    );
  }
}

class _WindowControl extends StatelessWidget {
  const _WindowControl({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
    );
  }
}

class _PreviewSidebar extends StatelessWidget {
  const _PreviewSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
        child: Container(
          width: 256,
          height: 704,
          decoration: BoxDecoration(
            color: colors.macosUtility.navPanel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.macosUtility.thinBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 44,
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 48, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountHeader(),
                SizedBox(height: AppSpacing.md),
                _SidebarItem(
                  iconName: AppIcons.home,
                  label: 'Home',
                  active: true,
                ),
                SizedBox(height: AppSpacing.xs),
                _SidebarItem(iconName: AppIcons.swapArrows, label: 'Swap'),
                SizedBox(height: AppSpacing.xs),
                _SidebarItem(iconName: AppIcons.history, label: 'Activity'),
                Spacer(),
                _SidebarItem(iconName: AppIcons.cog, label: 'Settings'),
                SizedBox(height: AppSpacing.xs),
                _SidebarItem(iconName: AppIcons.logOut, label: 'Sign out'),
                SizedBox(height: AppSpacing.md),
                _SyncStatus(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        const AppProfilePicture(
          profilePictureId: kDefaultProfilePictureId,
          size: AppProfilePictureSize.large,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '142.23 ZEC',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        AppIcon(AppIcons.copy, size: 16, color: colors.icon.regular),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.iconName,
    required this.label,
    this.active = false,
  });

  final String iconName;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = active ? colors.navPanel.activeIcon : colors.icon.accent;
    final textColor = active ? colors.navPanel.activeLabel : colors.text.accent;

    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: active ? colors.navPanel.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          AppIcon(iconName, size: 20, color: iconColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Container(
          width: 5,
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0xFF0DC87D),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(999)),
          ),
        ),
        const SizedBox(width: 19),
        Text(
          '34% Syncing...',
          style: AppTypography.labelMedium.copyWith(
            color: colors.sync.textSyncing,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _ReceiveTrailingPane extends StatelessWidget {
  const _ReceiveTrailingPane({
    required this.isShielded,
    required this.showsModal,
  });

  final bool isShielded;
  final bool showsModal;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        Positioned.fill(child: _ReceivePaneContent(isShielded: isShielded)),
        if (showsModal)
          Positioned.fill(child: _ReceiveInfoOverlay(isShielded: isShielded)),
      ],
    );
  }
}

class _ReceivePaneContent extends StatelessWidget {
  const _ReceivePaneContent({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: AppSpacing.md,
          top: AppSpacing.xs,
          child: AppBackLink(
            key: const ValueKey('receive_preview_pane_back_button'),
            label: 'Home',
            minWidth: 60,
            onTap: () {},
          ),
        ),
        Positioned(
          left: 190,
          top: 48,
          width: 420,
          height: 656,
          child: _ReceiveContentArea(isShielded: isShielded),
        ),
      ],
    );
  }
}

class _ReceiveContentArea extends StatelessWidget {
  const _ReceiveContentArea({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 12,
          top: 16,
          width: 396,
          height: 556,
          child: Stack(
            children: [
              Positioned(
                left: 70,
                top: 38.5,
                width: 256,
                height: 33,
                child: Text(
                  'Receive ZEC',
                  maxLines: 1,
                  style: AppTypography.headlineLarge.copyWith(
                    color: context.colors.text.accent,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Positioned(
                left: 67,
                top: 103.5,
                width: 262,
                height: 414,
                child: _QrCodeBlock(isShielded: isShielded),
              ),
            ],
          ),
        ),
        Positioned(
          left: 95,
          top: 596,
          width: 230,
          height: 44,
          child: _CopyAddressButton(isShielded: isShielded),
        ),
      ],
    );
  }
}

class _QrCodeBlock extends StatelessWidget {
  const _QrCodeBlock({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = _qrBlockAsset(isShielded, isDark);

    return Image.asset(
      asset,
      key: ValueKey('receive_preview_qr_block_$asset'),
      width: 262,
      height: 414,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
  }
}

String _qrBlockAsset(bool isShielded, bool isDark) {
  if (isShielded) {
    return isDark
        ? 'assets/illustrations/receive_qr_block_shielded_dark.png'
        : 'assets/illustrations/receive_qr_block_shielded_light.png';
  }
  return isDark
      ? 'assets/illustrations/receive_qr_block_transparent_dark.png'
      : 'assets/illustrations/receive_qr_block_transparent_light.png';
}

class _CopyAddressButton extends StatelessWidget {
  const _CopyAddressButton({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return _FixedPillButton(
      width: 230,
      height: 44,
      label: isShielded ? 'Copy Shielded Address' : 'Copy Transparent Address',
      iconName: isShielded
          ? AppIcons.shieldKeyhole
          : AppIcons.transparentBalance,
      variant: isShielded
          ? _FixedPillButtonVariant.primary
          : _FixedPillButtonVariant.secondary,
    );
  }
}

enum _FixedPillButtonVariant { primary, secondary, ghost }

class _FixedPillButton extends StatelessWidget {
  const _FixedPillButton({
    required this.width,
    required this.height,
    required this.label,
    this.iconName,
    this.variant = _FixedPillButtonVariant.primary,
  });

  final double width;
  final double height;
  final String label;
  final String? iconName;
  final _FixedPillButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (
      background,
      labelColor,
      borderColor,
      borderWidth,
    ) = switch (variant) {
      _FixedPillButtonVariant.primary => (
        colors.button.primary.bg,
        colors.button.primary.label,
        colors.button.primary.border,
        1.5,
      ),
      _FixedPillButtonVariant.secondary => (
        colors.button.secondary.bg,
        colors.button.secondary.label,
        Colors.transparent,
        0.0,
      ),
      _FixedPillButtonVariant.ghost => (
        Colors.transparent,
        colors.button.ghost.label,
        Colors.transparent,
        0.0,
      ),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: StadiumBorder(
            side: borderWidth == 0
                ? BorderSide.none
                : BorderSide(color: borderColor, width: borderWidth),
          ),
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (iconName != null) ...[
                  AppIcon(iconName!, size: 20, color: labelColor),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium.copyWith(
                      color: labelColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiveInfoOverlay extends StatelessWidget {
  const _ReceiveInfoOverlay({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.neutralScrim,
        borderRadius: BorderRadius.circular(AppWindowSizing.paneRadius),
      ),
      child: Center(child: _ReceiveInfoModal(isShielded: isShielded)),
    );
  }
}

class _ReceiveInfoModal extends StatelessWidget {
  const _ReceiveInfoModal({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = isShielded ? 'Shielded Address' : 'Transparent Address';
    final subtitle = isShielded
        ? 'Strong privacy by default.'
        : 'Publicly visible';
    final items = isShielded
        ? const [
            _InfoItemData(
              iconName: AppIcons.shieldKeyhole,
              height: 63,
              text:
                  'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.',
            ),
            _InfoItemData(
              iconName: AppIcons.renew,
              height: 63,
              text:
                  'A new Zcash Shielded address\ngenerated every time you '
                  'open the\nReceive page or click Renew button.',
            ),
            _InfoItemData(
              iconName: AppIcons.wallet,
              height: 63,
              text:
                  'Each new address is a diversified\naddress derived from '
                  'the same key.\nThey all receive to the same wallet.',
            ),
          ]
        : const [
            _InfoItemData(
              iconName: AppIcons.unlock,
              height: 42,
              text:
                  'All tx details - sender, receiver, and amount - are publicly visible on-chain.',
            ),
            _InfoItemData(
              iconName: AppIcons.dragon,
              height: 84,
              text:
                  'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.',
            ),
            _InfoItemData(
              iconName: AppIcons.shieldAsset,
              height: 105,
              text:
                  "After receiving ZEC to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won't be able to send it.",
            ),
          ];

    return Container(
      key: ValueKey(
        isShielded
            ? 'receive_preview_shielded_info_modal'
            : 'receive_preview_transparent_info_modal',
      ),
      width: 312,
      height: isShielded ? 382 : 403,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            height: 45,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 280,
            height: isShielded ? 205 : 247,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _InfoItem(data: items[i]),
                  if (i != items.length - 1)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
          const Spacer(),
          const _FixedPillButton(
            width: 280,
            height: 36,
            label: 'Close',
            variant: _FixedPillButtonVariant.ghost,
          ),
        ],
      ),
    );
  }
}

class _InfoItemData {
  const _InfoItemData({
    required this.iconName,
    required this.height,
    required this.text,
  });

  final String iconName;
  final double height;
  final String text;
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.data});

  final _InfoItemData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: data.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(
                data.iconName,
                size: 16,
                color: colors.icon.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              data.text,
              maxLines: (data.height / 21).floor(),
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
