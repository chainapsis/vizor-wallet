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
          // AppBackLink now carries a 12px internal pill inset, so the pane
          // container drops from md (24) to s (12) to keep the chevron at the
          // design position (pane + 24) instead of shifting it to pane + 36.
          left: AppSpacing.s,
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

  static const _width = 262.0;
  static const _height = 414.0;
  static const _tabsHeight = 36.0;
  static const _tabsToQrGap = 32.0;
  static const _qrFrameHeight = 310.0;
  static const _qrSurfaceSize = 230.0;
  static const _qrPaddingX = 16.0;
  static const _qrPaddingY = 24.0;
  static const _addressGap = 12.0;
  static const _renewTop = 262.0;
  static const _renewSize = 48.0;

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey(
        isShielded
            ? 'receive_preview_qr_block_shielded'
            : 'receive_preview_qr_block_transparent',
      ),
      width: _width,
      height: _height,
      child: Column(
        children: [
          SizedBox(
            width: 256,
            height: _tabsHeight,
            child: _PreviewReceiveTabs(isShielded: isShielded),
          ),
          const SizedBox(height: _tabsToQrGap),
          SizedBox(
            width: _width,
            height: _qrFrameHeight + _addressGap + 24,
            child: Column(
              children: [
                SizedBox(
                  width: _width,
                  height: _qrFrameHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 0,
                        child: _PreviewQrSurface(
                          isShielded: isShielded,
                          size: _qrSurfaceSize,
                          paddingX: _qrPaddingX,
                          paddingY: _qrPaddingY,
                        ),
                      ),
                      if (isShielded)
                        const Positioned(
                          top: _renewTop,
                          child: _PreviewRenewButton(size: _renewSize),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: _addressGap),
                _PreviewAddressLine(isShielded: isShielded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewReceiveTabs extends StatelessWidget {
  const _PreviewReceiveTabs({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = isShielded
        ? colors.background.inverse
        : colors.background.ground;
    final activeText = isShielded ? colors.text.inverse : colors.text.accent;

    return Container(
      key: const ValueKey('receive_preview_address_type_tabs'),
      width: 256,
      height: 36,
      decoration: ShapeDecoration(
        color: colors.background.raised,
        shape: const StadiumBorder(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Align(
            alignment: isShielded
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                width: 124,
                decoration: ShapeDecoration(
                  color: activeBg,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _PreviewReceiveTab(
                label: 'Shielded',
                iconName: AppIcons.shieldKeyhole,
                active: isShielded,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
              ),
              _PreviewReceiveTab(
                label: 'Transparent',
                iconName: AppIcons.transparentBalance,
                active: !isShielded,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewReceiveTab extends StatelessWidget {
  const _PreviewReceiveTab({
    required this.label,
    required this.iconName,
    required this.active,
    required this.activeTextColor,
    required this.inactiveTextColor,
  });

  final String label;
  final String iconName;
  final bool active;
  final Color activeTextColor;
  final Color inactiveTextColor;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeTextColor : inactiveTextColor;
    return Expanded(
      child: SizedBox.expand(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(iconName, size: AppIconSize.medium, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewQrSurface extends StatelessWidget {
  const _PreviewQrSurface({
    required this.isShielded,
    required this.size,
    required this.paddingX,
    required this.paddingY,
  });

  final bool isShielded;
  final double size;
  final double paddingX;
  final double paddingY;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final usesDarkQrSurface = isDark || isShielded;
    final qrColor = usesDarkQrSurface
        ? (isDark ? colors.text.accent : colors.text.inverse)
        : colors.text.accent;
    final qrBackground = usesDarkQrSurface
        ? (isDark ? colors.background.ground : colors.background.inverse)
        : colors.background.ground;
    final embeddedImageAsset = _previewQrEmbeddedImageAsset(
      isShielded,
      usesDarkQrSurface: usesDarkQrSurface,
    );

    return Container(
      key: ValueKey(
        isShielded
            ? 'receive_preview_qr_surface_shielded'
            : 'receive_preview_qr_surface_transparent',
      ),
      width: size + paddingX * 2,
      height: size + paddingY * 2,
      padding: EdgeInsets.symmetric(horizontal: paddingX, vertical: paddingY),
      decoration: BoxDecoration(
        color: qrBackground,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: usesDarkQrSurface
              ? colors.border.subtle
              : colors.border.inverseOpacity,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _PreviewQrPainter(
              color: qrColor,
              backgroundColor: qrBackground,
              seed: isShielded ? 7 : 19,
            ),
          ),
          Image.asset(
            embeddedImageAsset,
            width: 48,
            height: 48,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
          ),
        ],
      ),
    );
  }
}

String _previewQrEmbeddedImageAsset(
  bool isShielded, {
  required bool usesDarkQrSurface,
}) {
  if (isShielded) return 'assets/icons/receive_qr_shield_crimson.png';
  return usesDarkQrSurface
      ? 'assets/icons/receive_qr_transparent_light.png'
      : 'assets/icons/receive_qr_transparent_dark.png';
}

class _PreviewQrPainter extends CustomPainter {
  const _PreviewQrPainter({
    required this.color,
    required this.backgroundColor,
    required this.seed,
  });

  final Color color;
  final Color backgroundColor;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final backgroundPaint = Paint()..color = backgroundColor;
    const moduleCount = 29;
    final module = size.width / moduleCount;

    void drawFinder(int row, int column) {
      final center = Offset((column + 3.5) * module, (row + 3.5) * module);
      final outerRadius = module * 3.0;
      final innerRadius = module * 1.45;
      canvas.drawCircle(center, outerRadius, paint);
      canvas.drawCircle(center, outerRadius - module * 0.8, backgroundPaint);
      canvas.drawCircle(center, innerRadius, paint);
    }

    bool inFinder(int row, int column) {
      final inLeft = column <= 6;
      final inRight = column >= 22;
      final inTop = row <= 6;
      final inBottom = row >= 22;
      return (inTop && (inLeft || inRight)) || (inBottom && inLeft);
    }

    for (var row = 0; row < moduleCount; row++) {
      for (var column = 0; column < moduleCount; column++) {
        if (inFinder(row, column)) continue;
        if (row >= 11 && row <= 17 && column >= 11 && column <= 17) continue;

        final filled =
            ((row * 13 + column * 7 + seed) % 5 == 0) ||
            ((row * 3 + column * 11 + seed) % 7 == 0);
        if (!filled) continue;

        final rect = Rect.fromLTWH(
          column * module + module * 0.14,
          row * module + module * 0.14,
          module * 0.72,
          module * 0.72,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(module * 0.24)),
          paint,
        );
      }
    }

    drawFinder(0, 0);
    drawFinder(0, 22);
    drawFinder(22, 0);
  }

  @override
  bool shouldRepaint(covariant _PreviewQrPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.seed != seed;
  }
}

class _PreviewRenewButton extends StatelessWidget {
  const _PreviewRenewButton({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.background.homeCard,
          shadows: [
            BoxShadow(
              color: colors.macosUtility.window,
              blurRadius: 0,
              spreadRadius: 4,
            ),
          ],
          shape: CircleBorder(
            side: BorderSide(color: colors.border.inverseOpacity, width: 2),
          ),
        ),
        child: Center(
          child: AppIcon(
            AppIcons.renew,
            size: AppIconSize.large,
            color: colors.text.homeCard,
          ),
        ),
      ),
    );
  }
}

class _PreviewAddressLine extends StatelessWidget {
  const _PreviewAddressLine({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              isShielded
                  ? 'u1qz4n92r8p2f ... rs5t9p7v4a1'
                  : 't1tvg2412a23k ... k64123hhq6d',
              overflow: TextOverflow.clip,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.help,
            size: AppIconSize.medium,
            color: context.colors.button.ghost.label,
          ),
        ],
      ),
    );
  }
}

class _CopyAddressButton extends StatelessWidget {
  const _CopyAddressButton({required this.isShielded});

  final bool isShielded;

  @override
  Widget build(BuildContext context) {
    return _FixedPillButton(
      width: 230,
      height: 44,
      label: isShielded ? 'Copy shielded address' : 'Copy transparent address',
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
    final title = isShielded ? 'Shielded address' : 'Transparent address';
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
