/// Receive-address building blocks shared by the desktop receive screen
/// and the mobile receive screen: the shielded/transparent segmented
/// tabs, the QR surface with the embedded pool badge, the renew button,
/// the compact address line, and the copy button.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show CircularProgressIndicator, Colors;
import 'package:flutter/widgets.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

/// Which receiving pool an address belongs to.
enum ReceiveAddressType { shielded, transparent }

class ReceiveTabs extends StatelessWidget {
  const ReceiveTabs({
    required this.selectedType,
    required this.onChanged,
    this.width = 256,
    this.height = 36,
    this.iconSize = AppIconSize.medium,
    this.iconGap = AppSpacing.xxs,
    this.labelStyle,
    this.labelFontWeight = FontWeight.w400,
    this.alwaysDarkSelected = false,
    super.key,
  });

  final ReceiveAddressType selectedType;
  final ValueChanged<ReceiveAddressType> onChanged;

  /// 256 matches the desktop pane; mobile stretches wider.
  final double width;

  /// 36 matches the desktop pane; the mobile receive frame uses 44.
  final double height;
  final double iconSize;
  final double iconGap;
  final TextStyle? labelStyle;
  final FontWeight? labelFontWeight;

  /// Mobile Figma keeps the selected segment dark on both tabs; the
  /// desktop pane lightens it on the transparent tab.
  final bool alwaysDarkSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shieldedActive = selectedType == ReceiveAddressType.shielded;
    final darkSelected = alwaysDarkSelected || shieldedActive;
    final activeBg =
        darkSelected ? colors.background.inverse : colors.background.ground;
    final activeText = darkSelected ? colors.text.inverse : colors.text.accent;

    return Container(
      key: const ValueKey('receive_address_type_tabs'),
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: colors.background.raised,
        shape: StadiumBorder(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment:
                selectedType == ReceiveAddressType.shielded
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                key: const ValueKey('receive_address_type_tabs_indicator'),
                width: (width - 8) / 2,
                decoration: ShapeDecoration(
                  color: activeBg,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _ReceiveTab(
                key: const ValueKey('receive_address_type_tab_shielded'),
                label: 'Shielded',
                iconName: AppIcons.shieldKeyhole,
                active: selectedType == ReceiveAddressType.shielded,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
                iconSize: iconSize,
                iconGap: iconGap,
                labelStyle: labelStyle,
                labelFontWeight: labelFontWeight,
                onTap: () => onChanged(ReceiveAddressType.shielded),
              ),
              _ReceiveTab(
                key: const ValueKey('receive_address_type_tab_transparent'),
                label: 'Transparent',
                iconName: AppIcons.transparentBalance,
                active: selectedType == ReceiveAddressType.transparent,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
                iconSize: iconSize,
                iconGap: iconGap,
                labelStyle: labelStyle,
                labelFontWeight: labelFontWeight,
                onTap: () => onChanged(ReceiveAddressType.transparent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiveTab extends StatelessWidget {
  const _ReceiveTab({
    required this.label,
    required this.iconName,
    required this.active,
    required this.activeTextColor,
    required this.inactiveTextColor,
    required this.iconSize,
    required this.iconGap,
    required this.labelStyle,
    required this.labelFontWeight,
    required this.onTap,
    super.key,
  });

  final String label;
  final String iconName;
  final bool active;
  final Color activeTextColor;
  final Color inactiveTextColor;
  final double iconSize;
  final double iconGap;
  final TextStyle? labelStyle;
  final FontWeight? labelFontWeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? activeTextColor : inactiveTextColor;
    return Expanded(
      child: MouseRegion(
        cursor: active ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? null : onTap,
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(iconName, size: iconSize, color: color),
                SizedBox(width: iconGap),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: (labelStyle ?? AppTypography.labelMedium).copyWith(
                      color: color,
                      fontWeight: labelFontWeight,
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

class ReceiveQrSurface extends StatelessWidget {
  const ReceiveQrSurface({
    required this.address,
    required this.size,
    required this.paddingX,
    required this.paddingY,
    required this.type,
    this.badgeSize = 48,
    super.key,
  });

  static const _wrapperRadius = 32.0;

  final String address;
  final double size;
  final double paddingX;
  final double paddingY;
  final ReceiveAddressType type;

  /// Diameter of the embedded pool badge — 48 on desktop, 56 in the
  /// mobile receive frame.
  final double badgeSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final isShielded = type == ReceiveAddressType.shielded;
    final usesDarkQrSurface = isDark || isShielded;
    final qrColor =
        usesDarkQrSurface
            ? (isDark ? colors.text.accent : colors.text.inverse)
            : colors.text.accent;
    final qrBackground =
        usesDarkQrSurface
            ? (isDark ? colors.background.ground : colors.background.inverse)
            : colors.background.ground;
    final embeddedImageAsset = _ReceiveQrEmbeddedImage.assetFor(
      type,
      usesDarkQrSurface: usesDarkQrSurface,
    );

    return Container(
      width: size + paddingX * 2,
      height: size + paddingY * 2,
      padding: EdgeInsets.symmetric(horizontal: paddingX, vertical: paddingY),
      decoration: BoxDecoration(
        color: qrBackground,
        borderRadius: BorderRadius.circular(_wrapperRadius),
        border: Border.all(
          color:
              usesDarkQrSurface
                  ? colors.border.subtle
                  : colors.border.inverseOpacity,
        ),
      ),
      child:
          address.isNotEmpty
              ? _CachedQrBitmap(
                data: address,
                color: qrColor,
                size: size,
                type: type,
                embeddedImageAsset: embeddedImageAsset,
                embeddedImageScale: badgeSize / size,
              )
              : Center(
                child: Text(
                  "We couldn't load your address. Try again in a moment.",
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
    );
  }
}

abstract final class _ReceiveQrEmbeddedImage {
  static const _shield = 'assets/icons/receive_qr_shield_crimson.png';
  static const _transparentLight =
      'assets/icons/receive_qr_transparent_light.png';
  static const _transparentDark =
      'assets/icons/receive_qr_transparent_dark.png';

  static String assetFor(
    ReceiveAddressType type, {
    required bool usesDarkQrSurface,
  }) {
    return switch (type) {
      ReceiveAddressType.shielded => _shield,
      ReceiveAddressType.transparent =>
        usesDarkQrSurface ? _transparentLight : _transparentDark,
    };
  }
}

class _CachedQrBitmap extends StatefulWidget {
  const _CachedQrBitmap({
    required this.data,
    required this.color,
    required this.size,
    required this.type,
    required this.embeddedImageAsset,
    required this.embeddedImageScale,
  });

  static const _bitmapSize = 1536;

  final String data;
  final Color color;
  final double size;
  final ReceiveAddressType type;
  final String embeddedImageAsset;
  final double embeddedImageScale;

  @override
  State<_CachedQrBitmap> createState() => _CachedQrBitmapState();
}

const _transparentMinimumQrVersion = 9;

class _CachedQrBitmapState extends State<_CachedQrBitmap> {
  ui.Image? _image;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_renderQr());
  }

  @override
  void didUpdateWidget(covariant _CachedQrBitmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.color != widget.color ||
        oldWidget.type != widget.type ||
        oldWidget.embeddedImageAsset != widget.embeddedImageAsset ||
        oldWidget.embeddedImageScale != widget.embeddedImageScale) {
      final previous = _image;
      setState(() {
        _image = null;
        _error = null;
      });
      _disposeImageAfterFrame(previous);
      unawaited(_renderQr());
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _renderQr() async {
    final generation = ++_generation;
    try {
      final qrCode = _qrCodeForData(
        widget.data,
        widget.type,
        QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final image = await qrImage.toImage(
        size: _CachedQrBitmap._bitmapSize,
        decoration: PrettyQrDecoration(
          quietZone: PrettyQrQuietZone.zero,
          image: PrettyQrDecorationImage(
            image: AssetImage(widget.embeddedImageAsset),
            scale: widget.embeddedImageScale,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            clipper: const _ReceiveQrEmbeddedImageClipper(),
            position: PrettyQrDecorationImagePosition.embedded,
          ),
          shape: _ReceiveQrShape(color: widget.color, type: widget.type),
        ),
      );
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }

      final previous = _image;
      setState(() {
        _image = image;
        _error = null;
      });
      _disposeImageAfterFrame(previous);
    } catch (e) {
      log('Receive: ERROR rendering QR bitmap: $e');
      if (!mounted || generation != _generation) return;
      final previous = _image;
      setState(() {
        _image = null;
        _error = e;
      });
      _disposeImageAfterFrame(previous);
    }
  }

  void _disposeImageAfterFrame(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return RawImage(
        image: image,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    }

    if (_error != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Text(
            'QR unavailable',
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

QrCode _qrCodeForData(
  String data,
  ReceiveAddressType type,
  int errorCorrectLevel,
) {
  final natural = QrCode.fromData(
    data: data,
    errorCorrectLevel: errorCorrectLevel,
  );
  if (type != ReceiveAddressType.transparent ||
      natural.typeNumber >= _transparentMinimumQrVersion) {
    return natural;
  }
  return QrCode(_transparentMinimumQrVersion, errorCorrectLevel)..addData(data);
}

class _ReceiveQrShape extends PrettyQrShape {
  const _ReceiveQrShape({required this.color, required this.type});

  final Color color;
  final ReceiveAddressType type;

  static const _finderReferenceDimension = 49.0;

  @override
  void paint(PrettyQrPaintingContext context) {
    PrettyQrSmoothSymbol(roundFactor: 1, color: color).paint(
      context.copyWith(
        matrix: _withoutComponent(
          context.matrix,
          PrettyQrComponentType.finderPattern,
        ),
      ),
    );
    _paintFinderPatterns(context);
  }

  void _paintFinderPatterns(PrettyQrPaintingContext context) {
    final module = context.moduleDimension;
    final visualModule =
        type == ReceiveAddressType.transparent
            ? math.min(
              module,
              context.boundsDimension / _finderReferenceDimension,
            )
            : module;
    final ringPaint =
        ui.Paint()
          ..color = color
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = visualModule / 1.5;
    final dotPaint =
        ui.Paint()
          ..color = color
          ..style = ui.PaintingStyle.fill;

    for (final pattern in context.matrix.positionDetectionPatterns) {
      final center = context.estimatedBounds.topLeft.translate(
        (pattern.left + PrettyQrPositionDetectionPattern.dimension / 2) *
            module,
        (pattern.top + PrettyQrPositionDetectionPattern.dimension / 2) * module,
      );
      context.canvas.drawCircle(center, visualModule * 3, ringPaint);
      context.canvas.drawCircle(center, visualModule * 1.5, dotPaint);
    }
  }

  PrettyQrMatrix _withoutComponent(
    PrettyQrMatrix matrix,
    PrettyQrComponentType component,
  ) {
    return PrettyQrMatrix(
      version: matrix.version,
      modules: [
        for (final module in matrix)
          module.type == component ? module.toBlank() : module,
      ],
    );
  }

  @override
  int get hashCode => Object.hash(_ReceiveQrShape, color, type);

  @override
  bool operator ==(Object other) {
    return other is _ReceiveQrShape &&
        other.color == color &&
        other.type == type;
  }
}

class _ReceiveQrEmbeddedImageClipper implements PrettyQrClipper {
  const _ReceiveQrEmbeddedImageClipper();

  static const _cornerRadiusRatio = 9.789 / 36.0;

  @override
  Path getClip(Size size) {
    final radius = size.shortestSide * _cornerRadiusRatio;
    return Path()..addRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );
  }
}

class ReceiveRenewButton extends StatelessWidget {
  const ReceiveRenewButton({
    required this.renewing,
    required this.size,
    required this.onTap,
    super.key,
  });

  final bool renewing;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor:
          onTap == null || renewing
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: renewing ? null : onTap,
        child: SizedBox(
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
              child:
                  renewing
                      ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.text.homeCard,
                        ),
                      )
                      : AppIcon(
                        AppIcons.renew,
                        size: AppIconSize.large,
                        color: colors.text.homeCard,
                        semanticLabel: 'Generate new shielded address',
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiveAddressLine extends StatelessWidget {
  const ReceiveAddressLine({
    required this.type,
    required this.address,
    required this.onShowHelp,
    this.secondaryTint = false,
    this.height = 24,
    this.helpButtonSize = 24,
    this.helpIconSize,
    this.helpGap = AppSpacing.xxs,
    this.helpIconColor,
    this.textStyle,
    this.scaleToFit = false,
    super.key,
  });

  final ReceiveAddressType type;
  final String address;
  final VoidCallback onShowHelp;

  /// The mobile receive frame renders the address in the secondary
  /// grey; the desktop pane keeps the dark accent.
  final bool secondaryTint;

  final double height;
  final double helpButtonSize;
  final double? helpIconSize;
  final double helpGap;
  final Color? helpIconColor;
  final TextStyle? textStyle;
  final bool scaleToFit;

  @override
  Widget build(BuildContext context) {
    final addressText = RichText(
      overflow: scaleToFit ? TextOverflow.visible : TextOverflow.clip,
      maxLines: 1,
      textAlign: TextAlign.center,
      text: TextSpan(
        style: (textStyle ?? AppTypography.labelLarge).copyWith(
          color:
              secondaryTint
                  ? context.colors.text.secondary
                  : context.colors.text.accent,
        ),
        children: _addressSpans(context, address),
      ),
    );
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child:
                scaleToFit
                    ? FittedBox(fit: BoxFit.scaleDown, child: addressText)
                    : addressText,
          ),
          SizedBox(width: helpGap),
          _IconOnlyButton(
            iconName: AppIcons.help,
            size: helpButtonSize,
            iconSize: helpIconSize,
            iconColor: helpIconColor,
            onTap: onShowHelp,
            semanticLabel: 'About this address type',
          ),
        ],
      ),
    );
  }
}

List<TextSpan> _addressSpans(BuildContext context, String address) {
  if (address.isEmpty) {
    return [
      TextSpan(
        text: "Address couldn't be loaded. Try again.",
        style: TextStyle(color: context.colors.text.secondary),
      ),
    ];
  }

  return [TextSpan(text: _compactAddress(address))];
}

String _compactAddress(String address) {
  const leadingLength = 13;
  const trailingLength = 11;
  const separator = ' ... ';
  if (address.length <= leadingLength + trailingLength + separator.length) {
    return address;
  }
  return '${address.substring(0, leadingLength)}$separator'
      '${address.substring(address.length - trailingLength)}';
}

class _IconOnlyButton extends StatelessWidget {
  const _IconOnlyButton({
    required this.iconName,
    required this.size,
    this.iconSize,
    this.iconColor,
    required this.onTap,
    required this.semanticLabel,
  });

  final String iconName;
  final double size;
  final double? iconSize;
  final Color? iconColor;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: AppIcon(
              iconName,
              size: iconSize ?? AppIconSize.medium,
              color: iconColor ?? context.colors.button.ghost.label,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiveCopyAddressButton extends StatelessWidget {
  const ReceiveCopyAddressButton({
    required this.label,
    required this.type,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final ReceiveAddressType type;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = type == ReceiveAddressType.shielded;
    final background =
        enabled
            ? (isShielded
                ? colors.button.primary.bg
                : colors.button.secondary.bg)
            : colors.button.disabled.bg;
    final labelColor =
        enabled
            ? (isShielded
                ? colors.button.primary.label
                : colors.button.secondary.label)
            : colors.button.disabled.label;
    final borderColor =
        enabled && isShielded
            ? colors.button.primary.border
            : Colors.transparent;

    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: background,
              shape: StadiumBorder(
                side:
                    isShielded
                        ? BorderSide(color: borderColor, width: 1.5)
                        : BorderSide.none,
              ),
            ),
            child: SizedBox(
              width: 230,
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppIcon(
                      isShielded
                          ? AppIcons.shieldKeyhole
                          : AppIcons.transparentBalance,
                      size: 20,
                      color: labelColor,
                    ),
                    const SizedBox(width: AppSpacing.xs),
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
        ),
      ),
    );
  }
}

/// One bullet of the address-type explainer.
class ReceiveAddressInfoItem {
  const ReceiveAddressInfoItem({required this.iconName, required this.text});

  final String iconName;
  final String text;
}

/// Copy for the address-type explainer, shared by the desktop info
/// dialog and the mobile info sheet so the two form factors cannot
/// drift apart.
String receiveAddressInfoTitle(ReceiveAddressType type) =>
    type == ReceiveAddressType.shielded
        ? 'Shielded address'
        : 'Transparent address';

String receiveAddressInfoSubtitle(ReceiveAddressType type) =>
    type == ReceiveAddressType.shielded
        ? 'Strong privacy by default.'
        : 'Publicly visible';

/// [touchUi] picks the interaction verb in the renew bullet ("tap" on
/// phones, "click" with a pointer).
List<ReceiveAddressInfoItem> receiveAddressInfoItems(
  ReceiveAddressType type, {
  required bool touchUi,
}) {
  if (type == ReceiveAddressType.shielded) {
    return [
      const ReceiveAddressInfoItem(
        iconName: AppIcons.shieldKeyhole,
        text:
            'Tx details — sender, receiver, and amount — are encrypted on-chain & hidden.',
      ),
      ReceiveAddressInfoItem(
        iconName: AppIcons.renew,
        text:
            'A new Zcash Shielded address is generated only when you '
            '${touchUi ? 'tap' : 'click'} the Renew button.',
      ),
      const ReceiveAddressInfoItem(
        iconName: AppIcons.wallet,
        text:
            'Each new address is a diversified address derived from the same key. They all receive to the same wallet.',
      ),
    ];
  }
  return [
    const ReceiveAddressInfoItem(
      iconName: AppIcons.unlock,
      text:
          'All tx details — sender, receiver, and amount — are publicly visible on-chain.',
    ),
    const ReceiveAddressInfoItem(
      iconName: AppIcons.dragon,
      text:
          'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.',
    ),
    ReceiveAddressInfoItem(
      iconName: AppIcons.shieldKeyholeOutline,
      text:
          'After receiving $kZcashDefaultCurrencyTicker to your transparent '
          "address, Vizor will guide you to shield the balance. Otherwise, "
          "you won't be able to send it.",
    ),
  ];
}
