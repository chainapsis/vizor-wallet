import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Colors, ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../widgets/receive_address_widgets.dart';

const _renewShieldedAddressErrorMessage =
    "We couldn't refresh your shielded address. Try again, or use your current one.";

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  ReceiveAddressType _selectedType = ReceiveAddressType.shielded;
  String? _shieldedAddress;
  String? _transparentAddress;
  String? _activeAccountUuid;
  String? _errorText;
  String? _transparentErrorText;
  String? _transparentLoadingAccountUuid;
  ReceiveAddressType? _infoDialogType;
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

    if (_selectedType == ReceiveAddressType.transparent &&
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

  void _selectAddressType(ReceiveAddressType type) {
    if (_selectedType == type) return;

    setState(() => _selectedType = type);
    if (type == ReceiveAddressType.transparent) {
      unawaited(_loadTransparentAddress());
    }
  }

  String get _selectedAddress {
    return switch (_selectedType) {
      ReceiveAddressType.shielded => _shieldedAddress ?? '',
      ReceiveAddressType.transparent => _transparentAddress ?? '',
    };
  }

  void _showAddressInfo(ReceiveAddressType type) {
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
    final isShielded = _selectedType == ReceiveAddressType.shielded;
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

  final ReceiveAddressType selectedType;
  final String address;
  final String? errorText;
  final bool isLoading;
  final bool isRenewingShielded;
  final ValueChanged<ReceiveAddressType> onTypeChanged;
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

  final ReceiveAddressType selectedType;
  final String address;
  final String? errorText;
  final bool isLoading;
  final bool isRenewingShielded;
  final ValueChanged<ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onCopy;
  final VoidCallback onShowHelp;

  bool get _isShielded => selectedType == ReceiveAddressType.shielded;

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
                      child: ReceiveCopyAddressButton(
                        key: ValueKey(
                          _isShielded
                              ? 'receive_copy_shielded_address_button'
                              : 'receive_copy_transparent_address_button',
                        ),
                        label: _isShielded
                            ? 'Copy shielded address'
                            : 'Copy transparent address',
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

  final ReceiveAddressType type;
  final String address;
  final bool renewing;
  final ValueChanged<ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenew;
  final VoidCallback onShowHelp;

  bool get _isShielded => type == ReceiveAddressType.shielded;

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
            child: ReceiveTabs(selectedType: type, onChanged: onTypeChanged),
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
                        child: ReceiveQrSurface(
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
                          child: ReceiveRenewButton(
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
                ReceiveAddressLine(
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

class _ReceiveInfoDialog extends StatelessWidget {
  const _ReceiveInfoDialog({required this.type, required this.onClose});

  final ReceiveAddressType type;
  final VoidCallback onClose;

  bool get _isShielded => type == ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = _isShielded ? 'Shielded address' : 'Transparent address';
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
