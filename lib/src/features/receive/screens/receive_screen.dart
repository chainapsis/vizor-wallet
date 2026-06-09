import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Colors, ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/wallet_provider.dart';

enum _ReceiveAddressType { shielded, transparent }

const _renewShieldedAddressErrorMessage =
    "We couldn't refresh your shielded address. Try again, or use your current one.";

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  _ReceiveAddressType _selectedType = _ReceiveAddressType.shielded;
  String? _shieldedAddress;
  String? _transparentAddress;
  String? _activeAccountUuid;
  String? _errorText;
  String? _transparentErrorText;
  String? _transparentLoadingAccountUuid;
  _ReceiveAddressType? _infoDialogType;
  bool _isLoading = true;
  bool _isLoadingTransparent = false;
  bool _isRenewingShielded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      _loadAddresses();
    });
  }

  Future<void> _loadAddresses() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final walletAddress = ref.read(walletProvider).value?.unifiedAddress;
    if (accountUuid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'No active account';
      });
      return;
    }

    final service = ref.read(receiveAddressServiceProvider);
    final cachedTransparentAddress = service.getCachedTransparentAddress(
      accountUuid,
    );

    setState(() {
      _isLoading = true;
      _errorText = null;
      _transparentErrorText = null;
      _activeAccountUuid = accountUuid;
      _isRenewingShielded = false;
      _isLoadingTransparent = false;
      _transparentLoadingAccountUuid = null;
      _shieldedAddress = walletAddress;
      _transparentAddress = cachedTransparentAddress;
    });

    if (_selectedType == _ReceiveAddressType.transparent &&
        cachedTransparentAddress == null) {
      unawaited(_loadTransparentAddress(accountUuid: accountUuid));
    }

    try {
      final shieldedAddress = await service.loadShieldedAddress(
        accountUuid: accountUuid,
        currentShieldedAddress: walletAddress,
      );
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      setState(() {
        _shieldedAddress = shieldedAddress;
        _isLoading = false;
      });
    } catch (e) {
      log('Receive: ERROR loading addresses: $e');
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      setState(() {
        _shieldedAddress ??= walletAddress;
        _isLoading = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _loadTransparentAddress({String? accountUuid}) async {
    final targetAccountUuid =
        accountUuid ?? ref.read(accountProvider).value?.activeAccountUuid;
    if (targetAccountUuid == null) return;

    final service = ref.read(receiveAddressServiceProvider);
    final cachedAddress = service.getCachedTransparentAddress(
      targetAccountUuid,
    );
    if (cachedAddress != null) {
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid !=
          targetAccountUuid) {
        return;
      }
      setState(() {
        _transparentAddress = cachedAddress;
        _transparentErrorText = null;
        _isLoadingTransparent = false;
        _transparentLoadingAccountUuid = null;
      });
      return;
    }

    if (_isLoadingTransparent &&
        _transparentLoadingAccountUuid == targetAccountUuid) {
      return;
    }

    setState(() {
      _isLoadingTransparent = true;
      _transparentLoadingAccountUuid = targetAccountUuid;
      _transparentErrorText = null;
    });

    try {
      final address = await service.loadTransparentAddress(
        accountUuid: targetAccountUuid,
      );
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid !=
          targetAccountUuid) {
        return;
      }
      setState(() {
        _transparentAddress = address;
        _isLoadingTransparent = false;
        _transparentLoadingAccountUuid = null;
      });
    } catch (e) {
      log('Receive: ERROR loading transparent address: $e');
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid !=
          targetAccountUuid) {
        return;
      }
      setState(() {
        _isLoadingTransparent = false;
        _transparentLoadingAccountUuid = null;
        _transparentErrorText = e.toString();
      });
    }
  }

  Future<void> _renewShieldedAddress() async {
    if (_isRenewingShielded) return;

    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;

    setState(() {
      _isRenewingShielded = true;
      _errorText = null;
    });

    try {
      final newAddress = await ref
          .read(receiveAddressServiceProvider)
          .renewShieldedAddress(accountUuid: accountUuid);
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        setState(() => _isRenewingShielded = false);
        return;
      }
      setState(() {
        _shieldedAddress = newAddress;
        _isRenewingShielded = false;
      });
      log('Receive: renewed shielded diversified address');
    } catch (e) {
      log('Receive: ERROR renewing shielded address: $e');
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      setState(() {
        _isRenewingShielded = false;
        _errorText = '$_renewShieldedAddressErrorMessage\nDetails: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_renewShieldedAddressErrorMessage)),
      );
    }
  }

  void _copySelectedAddress() {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    Clipboard.setData(ClipboardData(text: address));
    showAppToast(context, 'Address copied');
  }

  void _selectAddressType(_ReceiveAddressType type) {
    if (_selectedType == type) return;

    setState(() => _selectedType = type);
    if (type == _ReceiveAddressType.transparent) {
      unawaited(_loadTransparentAddress());
    }
  }

  String get _selectedAddress {
    return switch (_selectedType) {
      _ReceiveAddressType.shielded => _shieldedAddress ?? '',
      _ReceiveAddressType.transparent => _transparentAddress ?? '',
    };
  }

  void _showAddressInfo(_ReceiveAddressType type) {
    setState(() => _infoDialogType = type);
  }

  void _dismissAddressInfo() {
    if (_infoDialogType == null) return;
    setState(() => _infoDialogType = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != null && nextUuid != _activeAccountUuid) {
        unawaited(_loadAddresses());
      }
    });

    final address = _selectedAddress;
    final isShielded = _selectedType == _ReceiveAddressType.shielded;
    final isLoadingSelectedAddress = isShielded
        ? _isLoading
        : _isLoadingTransparent;
    final selectedErrorText = isShielded ? _errorText : _transparentErrorText;
    final infoDialogType = _infoDialogType;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ReceivePane(
              selectedType: _selectedType,
              address: address,
              errorText: selectedErrorText,
              isLoading: isLoadingSelectedAddress,
              isRenewingShielded: _isRenewingShielded,
              onTypeChanged: _selectAddressType,
              onRenewShielded: isShielded ? _renewShieldedAddress : null,
              onCopy: _copySelectedAddress,
              onShowHelp: () => _showAddressInfo(_selectedType),
            ),
            if (infoDialogType != null)
              AppPaneModalOverlay(
                onDismiss: _dismissAddressInfo,
                child: _ReceiveInfoDialog(
                  type: infoDialogType,
                  onClose: _dismissAddressInfo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReceivePane extends StatelessWidget {
  const _ReceivePane({
    required this.selectedType,
    required this.address,
    required this.errorText,
    required this.isLoading,
    required this.isRenewingShielded,
    required this.onTypeChanged,
    required this.onRenewShielded,
    required this.onCopy,
    required this.onShowHelp,
  });

  final _ReceiveAddressType selectedType;
  final String address;
  final String? errorText;
  final bool isLoading;
  final bool isRenewingShielded;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onCopy;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ReceivePaneToolbar(),
        Expanded(
          child: _ReceiveContentLayout(
            selectedType: selectedType,
            address: address,
            errorText: errorText,
            isLoading: isLoading,
            isRenewingShielded: isRenewingShielded,
            onTypeChanged: onTypeChanged,
            onRenewShielded: onRenewShielded,
            onCopy: onCopy,
            onShowHelp: onShowHelp,
          ),
        ),
      ],
    );
  }
}

class _ReceivePaneToolbar extends StatelessWidget {
  const _ReceivePaneToolbar();

  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _height,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppRouteBackLink(
            key: ValueKey('receive_pane_back_button'),
            minWidth: 60,
          ),
        ),
      ),
    );
  }
}

class _ReceiveContentLayout extends StatelessWidget {
  const _ReceiveContentLayout({
    required this.selectedType,
    required this.address,
    required this.errorText,
    required this.isLoading,
    required this.isRenewingShielded,
    required this.onTypeChanged,
    required this.onRenewShielded,
    required this.onCopy,
    required this.onShowHelp,
  });

  static const _contentWidth = 420.0;
  static const _contentHeight = 656.0;
  static const _contentHeightWithError = 724.0;

  final _ReceiveAddressType selectedType;
  final String address;
  final String? errorText;
  final bool isLoading;
  final bool isRenewingShielded;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onCopy;
  final VoidCallback onShowHelp;

  bool get _isShielded => selectedType == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final contentHeight = errorText == null
        ? _contentHeight
        : _contentHeightWithError;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : contentHeight;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(viewportHeight, contentHeight),
            ),
            child: Center(
              child: SizedBox(
                width: _contentWidth,
                height: contentHeight,
                child: Stack(
                  clipBehavior: Clip.none,
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
                              'Receive $kZcashDefaultCurrencyTicker',
                              maxLines: 1,
                              style: AppTypography.headlineLarge.copyWith(
                                color: colors.text.accent,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Positioned(
                            left: 67,
                            top: 103.5,
                            width: 262,
                            height: 414,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: isLoading
                                  ? const SizedBox(
                                      key: ValueKey('loading'),
                                      width: 262,
                                      height: 414,
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : _ReceiveQrBlock(
                                      key: ValueKey(selectedType),
                                      type: selectedType,
                                      address: address,
                                      renewing: isRenewingShielded,
                                      onTypeChanged: onTypeChanged,
                                      onRenew: onRenewShielded,
                                      onShowHelp: onShowHelp,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 95,
                      top: 596,
                      width: 230,
                      height: 44,
                      child: _CopyAddressButton(
                        key: ValueKey(
                          _isShielded
                              ? 'receive_copy_shielded_address_button'
                              : 'receive_copy_transparent_address_button',
                        ),
                        label: _isShielded
                            ? 'Copy Shielded Address'
                            : 'Copy Transparent Address',
                        type: selectedType,
                        enabled: address.isNotEmpty && !isLoading,
                        onTap: onCopy,
                      ),
                    ),
                    if (errorText != null)
                      Positioned(
                        left: 12,
                        top: 656,
                        width: 396,
                        child: Text(
                          errorText!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.warning,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReceiveQrBlock extends StatelessWidget {
  const _ReceiveQrBlock({
    required this.type,
    required this.address,
    required this.renewing,
    required this.onTypeChanged,
    required this.onRenew,
    required this.onShowHelp,
    super.key,
  });

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

  final _ReceiveAddressType type;
  final String address;
  final bool renewing;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenew;
  final VoidCallback onShowHelp;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _height,
      child: Column(
        children: [
          SizedBox(
            width: 256,
            height: _tabsHeight,
            child: _ReceiveTabs(selectedType: type, onChanged: onTypeChanged),
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
                        child: _QrSurface(
                          address: address,
                          size: _qrSurfaceSize,
                          paddingX: _qrPaddingX,
                          paddingY: _qrPaddingY,
                          type: type,
                        ),
                      ),
                      if (_isShielded)
                        Positioned(
                          top: _renewTop,
                          child: _RenewButton(
                            key: const ValueKey(
                              'receive_renew_shielded_address_button',
                            ),
                            renewing: renewing,
                            size: _renewSize,
                            onTap: onRenew,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: _addressGap),
                _AddressLine(
                  type: type,
                  address: address,
                  onShowHelp: onShowHelp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiveTabs extends StatelessWidget {
  const _ReceiveTabs({required this.selectedType, required this.onChanged});

  final _ReceiveAddressType selectedType;
  final ValueChanged<_ReceiveAddressType> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shieldedActive = selectedType == _ReceiveAddressType.shielded;
    final activeBg = shieldedActive
        ? colors.background.inverse
        : colors.background.ground;
    final activeText = shieldedActive
        ? colors.text.inverse
        : colors.text.accent;

    return Container(
      key: const ValueKey('receive_address_type_tabs'),
      width: 256,
      height: 36,
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
            alignment: selectedType == _ReceiveAddressType.shielded
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                key: const ValueKey('receive_address_type_tabs_indicator'),
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
              _ReceiveTab(
                key: const ValueKey('receive_address_type_tab_shielded'),
                label: 'Shielded',
                iconName: AppIcons.shieldKeyhole,
                active: selectedType == _ReceiveAddressType.shielded,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
                onTap: () => onChanged(_ReceiveAddressType.shielded),
              ),
              _ReceiveTab(
                key: const ValueKey('receive_address_type_tab_transparent'),
                label: 'Transparent',
                iconName: AppIcons.transparentBalance,
                active: selectedType == _ReceiveAddressType.transparent,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
                onTap: () => onChanged(_ReceiveAddressType.transparent),
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
    required this.onTap,
    super.key,
  });

  final String label;
  final String iconName;
  final bool active;
  final Color activeTextColor;
  final Color inactiveTextColor;
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
        ),
      ),
    );
  }
}

class _QrSurface extends StatelessWidget {
  const _QrSurface({
    required this.address,
    required this.size,
    required this.paddingX,
    required this.paddingY,
    required this.type,
  });

  static const _wrapperRadius = 32.0;

  final String address;
  final double size;
  final double paddingX;
  final double paddingY;
  final _ReceiveAddressType type;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final isShielded = type == _ReceiveAddressType.shielded;
    final usesDarkQrSurface = isDark || isShielded;
    final qrColor = usesDarkQrSurface
        ? (isDark ? colors.text.accent : colors.text.inverse)
        : colors.text.accent;
    final qrBackground = usesDarkQrSurface
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
          color: usesDarkQrSurface
              ? colors.border.subtle
              : colors.border.inverseOpacity,
        ),
      ),
      child: address.isNotEmpty
          ? _CachedQrBitmap(
              data: address,
              color: qrColor,
              size: size,
              embeddedImageAsset: embeddedImageAsset,
              embeddedImageScale: 48 / size,
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
    _ReceiveAddressType type, {
    required bool usesDarkQrSurface,
  }) {
    return switch (type) {
      _ReceiveAddressType.shielded => _shield,
      _ReceiveAddressType.transparent =>
        usesDarkQrSurface ? _transparentLight : _transparentDark,
    };
  }
}

class _CachedQrBitmap extends StatefulWidget {
  const _CachedQrBitmap({
    required this.data,
    required this.color,
    required this.size,
    required this.embeddedImageAsset,
    required this.embeddedImageScale,
  });

  static const _bitmapSize = 1536;

  final String data;
  final Color color;
  final double size;
  final String embeddedImageAsset;
  final double embeddedImageScale;

  @override
  State<_CachedQrBitmap> createState() => _CachedQrBitmapState();
}

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
      final qrCode = QrCode.fromData(
        data: widget.data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
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
          shape: PrettyQrSmoothSymbol(roundFactor: 1, color: widget.color),
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

class _RenewButton extends StatelessWidget {
  const _RenewButton({
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
      cursor: onTap == null || renewing
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
              child: renewing
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

class _AddressLine extends StatelessWidget {
  const _AddressLine({
    required this.type,
    required this.address,
    required this.onShowHelp,
  });

  final _ReceiveAddressType type;
  final String address;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: RichText(
              overflow: TextOverflow.clip,
              maxLines: 1,
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTypography.labelLarge.copyWith(
                  color: context.colors.text.accent,
                ),
                children: _addressSpans(context, address),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          _IconOnlyButton(
            iconName: AppIcons.help,
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
    required this.onTap,
    required this.semanticLabel,
  });

  final String iconName;
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
          width: 24,
          height: 24,
          child: Center(
            child: AppIcon(
              iconName,
              color: context.colors.button.ghost.label,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyAddressButton extends StatelessWidget {
  const _CopyAddressButton({
    required this.label,
    required this.type,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final _ReceiveAddressType type;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded = type == _ReceiveAddressType.shielded;
    final background = enabled
        ? (isShielded ? colors.button.primary.bg : colors.button.secondary.bg)
        : colors.button.disabled.bg;
    final labelColor = enabled
        ? (isShielded
              ? colors.button.primary.label
              : colors.button.secondary.label)
        : colors.button.disabled.label;
    final borderColor = enabled && isShielded
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
                side: isShielded
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

class _ReceiveInfoDialog extends StatelessWidget {
  const _ReceiveInfoDialog({required this.type, required this.onClose});

  final _ReceiveAddressType type;
  final VoidCallback onClose;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _isShielded ? 'Shielded Address' : 'Transparent Address';
    final subtitle = _isShielded
        ? 'Strong privacy by default.'
        : 'Publicly visible';
    final items = _isShielded
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
                  'A new Zcash Shielded address is generated only when you click the Renew button.',
            ),
            _InfoItemData(
              iconName: AppIcons.wallet,
              height: 63,
              text:
                  'Each new address is a diversified address derived from the same key. They all receive to the same wallet.',
            ),
          ]
        : [
            const _InfoItemData(
              iconName: AppIcons.unlock,
              height: 42,
              text:
                  'All tx details - sender, receiver, and amount - are publicly visible on-chain.',
            ),
            const _InfoItemData(
              iconName: AppIcons.dragon,
              height: 84,
              text:
                  'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.',
            ),
            _InfoItemData(
              iconName: AppIcons.shieldAsset,
              height: 105,
              text:
                  'After receiving $kZcashDefaultCurrencyTicker to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.',
            ),
          ];

    return Container(
      key: ValueKey(
        _isShielded
            ? 'receive_shielded_info_modal'
            : 'receive_transparent_info_modal',
      ),
      width: 312,
      height: _isShielded ? 382 : 403,
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
            height: _isShielded ? 205 : 247,
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
          SizedBox(
            width: 280,
            height: 36,
            child: AppButton(
              onPressed: onClose,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              height: 36,
              minWidth: 280,
              child: const Text('Close'),
            ),
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
                size: AppIconSize.medium,
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
