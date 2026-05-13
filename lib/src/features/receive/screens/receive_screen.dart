import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, ScaffoldMessenger, SnackBar, Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    showAppToast(context, 'Address Copied');
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

    final accountState = ref.watch(accountProvider).value;
    final canRenewShieldedAddress =
        accountState?.activeAccount?.isHardware != true;
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
              canRenewShieldedAddress: canRenewShieldedAddress,
              onTypeChanged: _selectAddressType,
              onRenewShielded: isShielded && canRenewShieldedAddress
                  ? _renewShieldedAddress
                  : null,
              onCopy: _copySelectedAddress,
              onShowHelp: () => _showAddressInfo(_selectedType),
            ),
            if (infoDialogType != null)
              AppPaneModalOverlay(
                onDismiss: _dismissAddressInfo,
                child: _ReceiveInfoDialog(
                  type: infoDialogType,
                  canRenewShieldedAddress: canRenewShieldedAddress,
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
    required this.canRenewShieldedAddress,
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
  final bool canRenewShieldedAddress;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onCopy;
  final VoidCallback onShowHelp;

  bool get _isShielded => selectedType == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 752),
                  child: Column(
                    children: [
                      Expanded(
                        child: _ReceiveMainContent(
                          selectedType: selectedType,
                          address: address,
                          isLoading: isLoading,
                          isRenewingShielded: isRenewingShielded,
                          canRenewShieldedAddress: canRenewShieldedAddress,
                          onTypeChanged: onTypeChanged,
                          onRenewShielded: onRenewShielded,
                          onShowHelp: onShowHelp,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CopyAddressButton(
                        key: ValueKey(
                          _isShielded
                              ? 'receive_copy_shielded_address_button'
                              : 'receive_copy_transparent_address_button',
                        ),
                        label: _isShielded
                            ? 'Copy Shielded Address'
                            : 'Copy Transparent Address',
                        primary: _isShielded,
                        enabled: address.isNotEmpty && !isLoading,
                        onTap: onCopy,
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: AppSpacing.s),
                        Text(
                          errorText!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.warning,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiveMainContent extends StatelessWidget {
  const _ReceiveMainContent({
    required this.selectedType,
    required this.address,
    required this.isLoading,
    required this.isRenewingShielded,
    required this.canRenewShieldedAddress,
    required this.onTypeChanged,
    required this.onRenewShielded,
    required this.onShowHelp,
  });

  final _ReceiveAddressType selectedType;
  final String address;
  final bool isLoading;
  final bool isRenewingShielded;
  final bool canRenewShieldedAddress;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _ReceiveQrMetrics.fromConstraints(constraints);
        final contentWidth = math.max(256.0, metrics.blockWidth);
        final contentHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _ReceiveQrMetrics.baseContentHeight;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            height: contentHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (selectedType == _ReceiveAddressType.shielded)
                  Positioned(
                    left:
                        (contentWidth - metrics.blockWidth) / 2 +
                        (metrics.blockWidth - metrics.qrFrameWidth) / 2 +
                        metrics.shieldBgLeft,
                    top: metrics.blockTop + metrics.shieldBgTop,
                    width: metrics.shieldBgWidth,
                    height: metrics.shieldBgHeight,
                    child: IgnorePointer(
                      child: _ShieldQrBackground(color: colors.border.subtle),
                    ),
                  ),
                Positioned(
                  top: _ReceiveQrMetrics.contentInsetY,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Receive $kZcashDefaultCurrencyTicker',
                        style: AppTypography.displaySmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ReceiveTabs(
                        selectedType: selectedType,
                        onChanged: onTypeChanged,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: (contentWidth - metrics.blockWidth) / 2,
                  top: metrics.blockTop,
                  width: metrics.blockWidth,
                  height: metrics.blockHeight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: isLoading
                        ? SizedBox(
                            key: const ValueKey('loading'),
                            width: metrics.blockWidth,
                            height: metrics.blockHeight,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _ReceiveQrBlock(
                            key: ValueKey(selectedType),
                            type: selectedType,
                            address: address,
                            renewing: isRenewingShielded,
                            metrics: metrics,
                            canRenewShieldedAddress: canRenewShieldedAddress,
                            onRenew: onRenewShielded,
                            onShowHelp: onShowHelp,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReceiveQrMetrics {
  const _ReceiveQrMetrics({
    required this.blockWidth,
    required this.blockHeight,
    required this.blockTop,
    required this.qrFrameWidth,
    required this.qrFrameHeight,
    required this.qrSurfaceSize,
    required this.qrTop,
    required this.addressGap,
    required this.shieldBgLeft,
    required this.shieldBgTop,
    required this.shieldBgWidth,
    required this.shieldBgHeight,
    required this.renewTop,
    required this.renewSize,
    required this.qrPaddingX,
    required this.qrPaddingY,
  });

  static const _baseContentHeight = 520.0;
  static const _contentInsetY = AppSpacing.md;
  static const _fixedBeforeQr = 44.0 + AppSpacing.md + 36.0 + AppSpacing.md;
  static const _baseBlockWidth = 356.0;
  static const _baseBlockHeight = 344.0;
  static const _baseQrSurfaceSize = 230.0;
  static const _baseQrPaddingX = 16.0;
  static const _baseQrPaddingY = 24.0;
  static const _baseAddressGap = 10.0;
  static const _addressLineHeight = 24.0;
  static const _baseRenewTop = 268.533203125;
  static const _baseRenewSize = 40.0;
  static const _baseRenewOverlap =
      _baseQrSurfaceSize + _baseQrPaddingY * 2 - _baseRenewTop;
  static const _baseRenewBottomGap =
      _baseBlockHeight -
      _baseAddressGap -
      _addressLineHeight -
      _baseRenewTop -
      _baseRenewSize;
  static const _baseEmbeddedImageSize = 48.0;
  static const _baseShieldBgWidth = 636.0;
  static const _baseShieldBgHeight = 555.0;
  static const _baseShieldBgCenterYOffset = 40.2333984375;
  static const _minQrSurfaceSize = 112.0;

  static double get baseContentHeight => _baseContentHeight;
  static double get contentInsetY => _contentInsetY;
  static double get embeddedImageScale =>
      _baseEmbeddedImageSize / _baseQrSurfaceSize;

  final double blockWidth;
  final double blockHeight;
  final double blockTop;
  final double qrFrameWidth;
  final double qrFrameHeight;
  final double qrSurfaceSize;
  final double qrTop;
  final double addressGap;
  final double shieldBgLeft;
  final double shieldBgTop;
  final double shieldBgWidth;
  final double shieldBgHeight;
  final double renewTop;
  final double renewSize;
  final double qrPaddingX;
  final double qrPaddingY;

  static _ReceiveQrMetrics fromConstraints(BoxConstraints constraints) {
    final maxContentHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : _baseContentHeight;
    final maxContentWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 752.0;

    const frameHeightExtra =
        _baseQrPaddingY * 2 +
        _baseRenewSize -
        _baseRenewOverlap +
        _baseRenewBottomGap;
    const blockHeightExtra =
        frameHeightExtra + _baseAddressGap + _addressLineHeight;
    final maxSurfaceByHeight =
        maxContentHeight -
        _contentInsetY * 2 -
        _fixedBeforeQr -
        blockHeightExtra;
    final maxSurfaceByWidth = maxContentWidth - _baseQrPaddingX * 2;

    final qrSurfaceSize = math.max(
      _minQrSurfaceSize,
      math.min(maxSurfaceByHeight, maxSurfaceByWidth),
    );
    final scale = qrSurfaceSize / _baseQrSurfaceSize;
    final qrFrameWidth = qrSurfaceSize + _baseQrPaddingX * 2;
    final qrFrameHeight =
        qrSurfaceSize +
        _baseQrPaddingY * 2 +
        _baseRenewSize +
        _baseRenewBottomGap -
        _baseRenewOverlap;
    final shieldBgWidth = _baseShieldBgWidth * scale;
    final shieldBgHeight = _baseShieldBgHeight * scale;
    final computedBlockWidth = math.max(_baseBlockWidth, qrFrameWidth);
    final blockHeight = qrFrameHeight + _baseAddressGap + _addressLineHeight;
    final blockTop = math.max(
      _contentInsetY + _fixedBeforeQr,
      maxContentHeight - _contentInsetY - blockHeight,
    );

    return _ReceiveQrMetrics(
      blockWidth: math.min(maxContentWidth, computedBlockWidth),
      blockHeight: blockHeight,
      blockTop: blockTop,
      qrFrameWidth: qrFrameWidth,
      qrFrameHeight: qrFrameHeight,
      qrSurfaceSize: qrSurfaceSize,
      qrTop: 0,
      addressGap: _baseAddressGap,
      shieldBgLeft: qrFrameWidth / 2 - shieldBgWidth / 2,
      shieldBgTop:
          qrFrameHeight / 2 -
          _baseShieldBgCenterYOffset * scale -
          shieldBgHeight / 2,
      shieldBgWidth: shieldBgWidth,
      shieldBgHeight: shieldBgHeight,
      renewTop: qrSurfaceSize + _baseQrPaddingY * 2 - _baseRenewOverlap,
      renewSize: _baseRenewSize,
      qrPaddingX: _baseQrPaddingX,
      qrPaddingY: _baseQrPaddingY,
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
    final activeBg = colors.background.inverse;
    final activeText = colors.text.inverse;

    return Container(
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
                label: 'Shielded',
                iconName: AppIcons.shieldKeyhole,
                active: selectedType == _ReceiveAddressType.shielded,
                activeTextColor: activeText,
                inactiveTextColor: colors.text.accent,
                onTap: () => onChanged(_ReceiveAddressType.shielded),
              ),
              _ReceiveTab(
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
                    style: AppTypography.labelLarge.copyWith(color: color),
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

class _ReceiveQrBlock extends StatelessWidget {
  const _ReceiveQrBlock({
    required this.type,
    required this.address,
    required this.renewing,
    required this.metrics,
    required this.canRenewShieldedAddress,
    required this.onRenew,
    required this.onShowHelp,
    super.key,
  });

  final _ReceiveAddressType type;
  final String address;
  final bool renewing;
  final _ReceiveQrMetrics metrics;
  final bool canRenewShieldedAddress;
  final VoidCallback? onRenew;
  final VoidCallback onShowHelp;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: metrics.blockWidth,
      height: metrics.blockHeight,
      child: Column(
        children: [
          SizedBox(
            width: metrics.qrFrameWidth,
            height: metrics.qrFrameHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: metrics.qrTop,
                  child: _QrSurface(
                    address: address,
                    size: metrics.qrSurfaceSize,
                    paddingX: metrics.qrPaddingX,
                    paddingY: metrics.qrPaddingY,
                    type: type,
                  ),
                ),
                if (_isShielded && canRenewShieldedAddress)
                  Positioned(
                    top: metrics.renewTop,
                    child: _RenewButton(
                      renewing: renewing,
                      size: metrics.renewSize,
                      onTap: onRenew,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: metrics.addressGap),
          _AddressLine(type: type, address: address, onShowHelp: onShowHelp),
        ],
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
    final qrColor = colors.text.accent;
    final qrBackground = colors.background.base;
    final embeddedImageAsset = _ReceiveQrEmbeddedImage.assetFor(
      type,
      Theme.of(context).brightness,
    );

    return Container(
      width: size + paddingX * 2,
      height: size + paddingY * 2,
      padding: EdgeInsets.symmetric(horizontal: paddingX, vertical: paddingY),
      decoration: BoxDecoration(
        color: qrBackground,
        borderRadius: BorderRadius.circular(_wrapperRadius),
      ),
      child: address.isNotEmpty
          ? _CachedQrBitmap(
              data: address,
              color: qrColor,
              size: size,
              embeddedImageAsset: embeddedImageAsset,
              embeddedImageScale: _ReceiveQrMetrics.embeddedImageScale,
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
  static const _shieldLight = 'assets/icons/receive_qr_shield_light.png';
  static const _shieldDark = 'assets/icons/receive_qr_shield_dark.png';
  static const _transparentLight =
      'assets/icons/receive_qr_transparent_light.png';
  static const _transparentDark =
      'assets/icons/receive_qr_transparent_dark.png';

  static String assetFor(_ReceiveAddressType type, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return switch (type) {
      _ReceiveAddressType.shielded => isDark ? _shieldDark : _shieldLight,
      _ReceiveAddressType.transparent =>
        isDark ? _transparentDark : _transparentLight,
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
  });

  final bool renewing;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const strokeWidth = 3.0;

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
          child: CustomPaint(
            painter: _OutsideCircleBorderPainter(
              color: colors.background.ground,
              strokeWidth: strokeWidth,
            ),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.background.base,
                shape: const CircleBorder(),
              ),
              child: Center(
                child: renewing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.icon.accent,
                        ),
                      )
                    : AppIcon(
                        AppIcons.renew,
                        size: 20,
                        color: colors.icon.accent,
                        semanticLabel: 'Generate new shielded address',
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutsideCircleBorderPainter extends CustomPainter {
  const _OutsideCircleBorderPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final radius = math.min(size.width, size.height) / 2 + strokeWidth / 2;
    final center = ui.Offset(size.width / 2, size.height / 2);
    final paint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _OutsideCircleBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
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
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTypography.codeMedium.copyWith(
                  color: context.colors.text.accent,
                ),
                children: _addressSpans(context, type, address),
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

List<TextSpan> _addressSpans(
  BuildContext context,
  _ReceiveAddressType type,
  String address,
) {
  if (address.isEmpty) {
    return [
      TextSpan(
        text: "Address couldn't be loaded. Try again.",
        style: TextStyle(color: context.colors.text.secondary),
      ),
    ];
  }

  final compact = _compactAddress(address);
  if (type == _ReceiveAddressType.transparent) {
    return [TextSpan(text: compact)];
  }

  final success = context.colors.text.success;
  if (compact.length <= 10) return [TextSpan(text: compact)];

  final startHighlight = math.min(5, compact.length);
  final endHighlight = math.max(startHighlight, compact.length - 5);
  return [
    TextSpan(
      text: compact.substring(0, startHighlight),
      style: TextStyle(color: success),
    ),
    TextSpan(text: compact.substring(startHighlight, endHighlight)),
    TextSpan(
      text: compact.substring(endHighlight),
      style: TextStyle(color: success),
    ),
  ];
}

String _compactAddress(String address) {
  if (address.length <= 38) return address;
  return '${address.substring(0, 17)}...${address.substring(address.length - 17)}';
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
    required this.primary,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool primary;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: enabled ? onTap : null,
      variant: primary ? AppButtonVariant.primary : AppButtonVariant.secondary,
      size: AppButtonSize.large,
      minWidth: 256,
      trailing: const AppIcon(AppIcons.copy),
      child: Text(label),
    );
  }
}

class _ReceiveInfoDialog extends StatelessWidget {
  const _ReceiveInfoDialog({
    required this.type,
    required this.canRenewShieldedAddress,
    required this.onClose,
  });

  final _ReceiveAddressType type;
  final bool canRenewShieldedAddress;
  final VoidCallback onClose;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = _isShielded
        ? canRenewShieldedAddress
              ? const [
                  _InfoItemData(
                    iconName: AppIcons.lock,
                    text:
                        'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.',
                  ),
                  _InfoItemData(
                    iconName: AppIcons.renew,
                    text:
                        'A new Zcash Shielded address is generated only when you click the Renew button.',
                  ),
                  _InfoItemData(
                    iconName: AppIcons.wallet,
                    text:
                        'Each new address is a diversified address derived from the same key. They all receive to the same wallet.',
                  ),
                ]
              : const [
                  _InfoItemData(
                    iconName: AppIcons.lock,
                    text:
                        'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.',
                  ),
                  _InfoItemData(
                    iconName: AppIcons.qr,
                    text:
                        "Keystone provides an Orchard-only shielded address, so Vizor can't renew it from this screen.",
                  ),
                ]
        : [
            const _InfoItemData(
              iconName: AppIcons.unlock,
              text:
                  'All tx details - sender, receiver, and amount - are publicly visible on-chain.',
            ),
            const _InfoItemData(
              iconName: AppIcons.dragon,
              text:
                  'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.',
            ),
            _InfoItemData(
              iconName: AppIcons.shieldAsset,
              text:
                  'After receiving $kZcashDefaultCurrencyTicker to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.',
            ),
          ];

    return Container(
      width: 312,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _InfoHeaderIcon(
                iconName: _isShielded
                    ? AppIcons.shieldKeyhole
                    : AppIcons.transparentBalance,
                filled: _isShielded,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isShielded ? 'Shielded Address' : 'Transparent Address',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    Text(
                      _isShielded
                          ? 'Strong privacy by default.'
                          : 'Publicly visible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _InfoItem(
                    iconName: item.iconName,
                    text: item.text,
                    successIcon: _isShielded,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _DialogCloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _InfoHeaderIcon extends StatelessWidget {
  const _InfoHeaderIcon({required this.iconName, required this.filled});

  final String iconName;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = filled
        ? colors.background.utilitySuccessStrong
        : colors.background.raised;
    final iconColor = filled ? colors.icon.inverse : colors.icon.accent;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: AppIcon(iconName, color: iconColor, size: AppIconSize.medium),
      ),
    );
  }
}

class _InfoItemData {
  const _InfoItemData({required this.iconName, required this.text});

  final String iconName;
  final String text;
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.iconName,
    required this.text,
    this.successIcon = false,
  });

  final String iconName;
  final String text;
  final bool successIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(
              iconName,
              size: AppIconSize.medium,
              color: successIcon ? colors.icon.success : colors.icon.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
      ],
    );
  }
}

class _DialogCloseButton extends StatefulWidget {
  const _DialogCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DialogCloseButton> createState() => _DialogCloseButtonState();
}

class _DialogCloseButtonState extends State<_DialogCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: 44,
          decoration: ShapeDecoration(
            color:
                (_hovered
                        ? colors.button.secondary.bgHover
                        : colors.button.secondary.bg)
                    .withValues(alpha: 0.98),
            shape: const StadiumBorder(),
          ),
          child: Center(
            child: Text(
              'Close',
              style: AppTypography.labelLarge.copyWith(
                color: colors.button.secondary.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldQrBackground extends StatelessWidget {
  const _ShieldQrBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/illustrations/receive_shield_qr_bg.svg',
      fit: BoxFit.fill,
      excludeFromSemantics: true,
      colorFilter: ui.ColorFilter.mode(color, ui.BlendMode.srcIn),
    );
  }
}
