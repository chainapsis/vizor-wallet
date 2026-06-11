import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/unsupported_sheet.dart';
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
  const MobileReceiveScreen({super.key});

  @override
  ConsumerState<MobileReceiveScreen> createState() =>
      _MobileReceiveScreenState();
}

class _MobileReceiveScreenState extends ConsumerState<MobileReceiveScreen> {
  ReceiveAddressType _selectedType = ReceiveAddressType.shielded;
  String? _shieldedAddress;
  String? _transparentAddress;
  bool _renewing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAddresses());
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
    // TODO(mobile-share): hook up the platform share sheet (share_plus
    // or equivalent); until then the gap is explicit.
    unawaited(showUnsupportedSheet(context));
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
                    Center(
                      child: ReceiveTabs(
                        width: 330,
                        alwaysDarkSelected: true,
                        selectedType: _selectedType,
                        onChanged: (type) =>
                            setState(() => _selectedType = type),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: SizedBox(
                        // QR surface plus room for the renew button
                        // hanging off its bottom edge.
                        height: 300 + 24,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ReceiveQrSurface(
                              address: _selectedAddress,
                              size: 300 - AppSpacing.sm * 2,
                              paddingX: AppSpacing.sm,
                              paddingY: AppSpacing.sm,
                              type: _selectedType,
                            ),
                            if (_isShielded)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: ReceiveRenewButton(
                                    renewing: _renewing,
                                    size: 44,
                                    onTap: () =>
                                        unawaited(_renewShieldedAddress()),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      accountName,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ReceiveAddressLine(
                      type: _selectedType,
                      address: _selectedAddress,
                      secondaryTint: true,
                      onShowHelp: () => unawaited(
                        showReceiveAddressInfoSheet(context, _selectedType),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    AppButton(
                      expand: true,
                      variant: _isShielded
                          ? AppButtonVariant.primary
                          : AppButtonVariant.secondary,
                      onPressed: _selectedAddress.isEmpty
                          ? null
                          : _shareAddress,
                      leading: const AppIcon(AppIcons.share, size: 20),
                      child: Text('Share $poolLabel address'),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Center(
                      child: _CopyAddressTextButton(
                        key: const ValueKey('mobile_receive_copy'),
                        label: 'Copy $poolLabel address',
                        enabled: _selectedAddress.isNotEmpty,
                        onTap: () => unawaited(_copyAddress()),
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.copy, size: AppIconSize.medium, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
