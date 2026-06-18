import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../widgets/mobile/receive_address_info_sheet.dart';
import '../../widgets/receive_address_widgets.dart';

const _renewShieldedAddressErrorMessage =
    "We couldn't refresh your shielded address. Try again, or use your current one.";

/// Mobile receive screen — Figma `Receive` (4514:110524): pool tabs,
/// QR with the renew control on its bottom edge, compact address line,
/// and share/copy actions, composed from the shared receive widgets.
class MobileReceiveScreen extends ConsumerStatefulWidget {
  const MobileReceiveScreen({
    this.initialType = ReceiveAddressType.shielded,
    super.key,
  });

  final ReceiveAddressType initialType;

  @override
  ConsumerState<MobileReceiveScreen> createState() =>
      _MobileReceiveScreenState();
}

class _MobileReceiveScreenState extends ConsumerState<MobileReceiveScreen> {
  late ReceiveAddressType _selectedType;
  late final PageController _pageController;
  String? _shieldedAddress;
  String? _transparentAddress;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _pageController = PageController(initialPage: _selectedType.index);
    unawaited(_loadAddresses());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    if (accountUuid == null) {
      if (!mounted) return;
      setState(() {
        _shieldedAddress = '';
        _transparentAddress = '';
      });
      return;
    }

    final service = ref.read(receiveAddressServiceProvider);
    try {
      final shielded = await service.loadShieldedAddress(
        accountUuid: accountUuid,
        currentShieldedAddress: accountState?.activeAddress,
      );
      if (!mounted) return;
      setState(() => _shieldedAddress = shielded);
    } catch (e) {
      log('MobileReceive: ERROR loading shielded address: $e');
      if (!mounted) return;
      setState(() => _shieldedAddress = '');
    }
    try {
      final transparent = await service.loadTransparentAddress(
        accountUuid: accountUuid,
      );
      if (!mounted) return;
      setState(() => _transparentAddress = transparent);
    } catch (e) {
      log('MobileReceive: ERROR loading transparent address: $e');
      if (!mounted) return;
      setState(() => _transparentAddress = '');
    }
  }

  String get _selectedAddress => switch (_selectedType) {
    ReceiveAddressType.shielded => _shieldedAddress ?? '',
    ReceiveAddressType.transparent => _transparentAddress ?? '',
  };

  bool get _isShielded => _selectedType == ReceiveAddressType.shielded;

  String _addressFor(ReceiveAddressType type) => switch (type) {
    ReceiveAddressType.shielded => _shieldedAddress ?? '',
    ReceiveAddressType.transparent => _transparentAddress ?? '',
  };

  void _selectType(ReceiveAddressType type) {
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          type.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _handlePageChanged(int page) {
    final type = ReceiveAddressType.values[page];
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
  }

  Future<void> _renewShieldedAddress() async {
    if (_renewing) return;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    setState(() => _renewing = true);
    try {
      final address = await ref
          .read(receiveAddressServiceProvider)
          .renewShieldedAddress(accountUuid: accountUuid);
      if (!mounted) return;
      setState(() => _shieldedAddress = address);
    } catch (e) {
      log('MobileReceive: ERROR renewing shielded address: $e');
      if (!mounted) return;
      showAppToast(context, _renewShieldedAddressErrorMessage);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  Future<void> _copyAddress() async {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    showAppToast(context, 'Address copied');
  }

  void _shareAddress() {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    unawaited(SharePlus.instance.share(ShareParams(text: address)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountName =
        ref.watch(accountProvider).value?.activeAccount?.name ?? '';
    final poolLabel = _isShielded ? 'shielded' : 'transparent';

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Receive $kZcashDefaultCurrencyTicker',
                titleStyle: AppTypography.headlineLarge,
                height: _MobileReceiveMetrics.topNavHeight,
                onBack: () => context.pop(),
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
                    const SizedBox(height: _MobileReceiveMetrics.topGap),
                    Center(
                      child: ReceiveTabs(
                        width: _MobileReceiveMetrics.tabsWidth,
                        height: _MobileReceiveMetrics.tabsHeight,
                        iconSize: _MobileReceiveMetrics.tabsIconSize,
                        iconGap: AppSpacing.xs,
                        labelStyle: AppTypography.labelLarge,
                        labelFontWeight: FontWeight.w500,
                        alwaysDarkSelected: true,
                        selectedType: _selectedType,
                        onChanged: _selectType,
                      ),
                    ),
                    const SizedBox(height: _MobileReceiveMetrics.tabsToQrGap),
                    Center(
                      child: SizedBox(
                        width: _MobileReceiveMetrics.qrWrapWidth,
                        height: _MobileReceiveMetrics.qrCodeHeight,
                        child: PageView(
                          key: const ValueKey('mobile_receive_qr_pager'),
                          controller: _pageController,
                          onPageChanged: _handlePageChanged,
                          children: [
                            for (final type in ReceiveAddressType.values)
                              _ReceiveQrPage(
                                key: ValueKey('mobile_receive_qr_${type.name}'),
                                type: type,
                                address: _addressFor(type),
                                renewing: _renewing,
                                onRenew: () =>
                                    unawaited(_renewShieldedAddress()),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: _MobileReceiveMetrics.qrToAddressGap,
                    ),
                    Center(
                      child: _ReceiveAddressSummary(
                        accountName: accountName,
                        type: _selectedType,
                        address: _selectedAddress,
                        onShowHelp: () => unawaited(
                          showReceiveAddressInfoSheet(context, _selectedType),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    Center(
                      child: SizedBox(
                        width: _MobileReceiveMetrics.buttonStackWidth,
                        height: _MobileReceiveMetrics.buttonStackHeight,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppButton(
                              key: const ValueKey('mobile_receive_share'),
                              expand: true,
                              constrainContent: true,
                              height: _MobileReceiveMetrics.buttonHeight,
                              variant: _isShielded
                                  ? AppButtonVariant.primary
                                  : AppButtonVariant.secondary,
                              onPressed: _selectedAddress.isEmpty
                                  ? null
                                  : _shareAddress,
                              leading: const AppIcon(
                                AppIcons.share,
                                size: _MobileReceiveMetrics.buttonIconSize,
                              ),
                              child: Text(
                                'Share $poolLabel address',
                                style: AppTypography.labelMedium.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            _CopyAddressTextButton(
                              key: const ValueKey('mobile_receive_copy'),
                              label: 'Copy $poolLabel address',
                              enabled: _selectedAddress.isNotEmpty,
                              onTap: () => unawaited(_copyAddress()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _MobileReceiveMetrics {
  static const topNavHeight = 74.0;
  static const topGap = 16.5;
  static const tabsWidth = 320.0;
  static const tabsHeight = 44.0;
  static const tabsIconSize = 20.0;
  static const tabsToQrGap = 32.0;

  static const qrWrapWidth = 292.0;
  static const qrCodeHeight = 340.0;
  static const qrSize = 260.0;
  static const qrPaddingX = 16.0;
  static const qrPaddingY = 24.0;
  static const qrBadgeSize = 54.26;
  static const renewTop = 292.0;
  static const renewSize = 48.0;

  static const qrToAddressGap = 24.0;
  static const addressWidth = 288.0;
  static const addressHeight = 70.0;
  static const accountNameHeight = 26.0;
  static const addressLineHeight = 40.0;

  static const buttonStackWidth = 300.0;
  static const buttonStackHeight = 112.0;
  static const buttonHeight = AppButtonSizing.largeHeight;
  static const buttonIconSize = 20.0;
}

class _ReceiveQrPage extends StatelessWidget {
  const _ReceiveQrPage({
    required this.type,
    required this.address,
    required this.renewing,
    required this.onRenew,
    super.key,
  });

  final ReceiveAddressType type;
  final String address;
  final bool renewing;
  final VoidCallback onRenew;

  bool get _isShielded => type == ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _MobileReceiveMetrics.qrWrapWidth,
      height: _MobileReceiveMetrics.qrCodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: ReceiveQrSurface(
              address: address,
              size: _MobileReceiveMetrics.qrSize,
              paddingX: _MobileReceiveMetrics.qrPaddingX,
              paddingY: _MobileReceiveMetrics.qrPaddingY,
              type: type,
              badgeSize: _MobileReceiveMetrics.qrBadgeSize,
            ),
          ),
          if (_isShielded)
            Positioned(
              top: _MobileReceiveMetrics.renewTop,
              child: ReceiveRenewButton(
                renewing: renewing,
                size: _MobileReceiveMetrics.renewSize,
                onTap: onRenew,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReceiveAddressSummary extends StatelessWidget {
  const _ReceiveAddressSummary({
    required this.accountName,
    required this.type,
    required this.address,
    required this.onShowHelp,
  });

  final String accountName;
  final ReceiveAddressType type;
  final String address;
  final VoidCallback onShowHelp;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('mobile_receive_address_summary'),
      width: _MobileReceiveMetrics.addressWidth,
      height: _MobileReceiveMetrics.addressHeight,
      child: Column(
        children: [
          SizedBox(
            height: _MobileReceiveMetrics.accountNameHeight,
            child: Text(
              accountName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: ReceiveAddressLine(
              key: ValueKey('mobile_receive_address_line_${type.name}'),
              type: type,
              address: address,
              secondaryTint: true,
              height: _MobileReceiveMetrics.addressLineHeight,
              helpButtonSize: _MobileReceiveMetrics.addressLineHeight,
              helpIconSize: 20,
              helpIconColor: colors.icon.muted,
              helpGap: 10,
              scaleToFit: true,
              onShowHelp: onShowHelp,
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyAddressTextButton extends StatelessWidget {
  const _CopyAddressTextButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = enabled ? colors.text.accent : colors.text.disabled;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: _MobileReceiveMetrics.buttonStackWidth,
          height: _MobileReceiveMetrics.buttonHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.copy,
                size: _MobileReceiveMetrics.buttonIconSize,
                color: color,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
