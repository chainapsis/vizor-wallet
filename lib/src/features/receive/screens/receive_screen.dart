import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart'
    show CircularProgressIndicator, ScaffoldMessenger, SnackBar, Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/receive_address_provider.dart';
import '../../../providers/wallet_provider.dart';

enum _ReceiveAddressType { shielded, transparent }

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
  bool _isLoading = true;
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

    setState(() {
      _isLoading = true;
      _errorText = null;
      _activeAccountUuid = accountUuid;
      _isRenewingShielded = false;
      _shieldedAddress = walletAddress;
      _transparentAddress = null;
    });

    try {
      final addresses = await ref
          .read(receiveAddressServiceProvider)
          .loadAddresses(
            accountUuid: accountUuid,
            currentShieldedAddress: walletAddress,
          );
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      setState(() {
        _shieldedAddress = addresses.shieldedAddress;
        _transparentAddress = addresses.transparentAddress;
        _isLoading = false;
      });
    } catch (e) {
      log('Receive: ERROR loading addresses: $e');
      if (!mounted) return;
      setState(() {
        _shieldedAddress ??= walletAddress;
        _isLoading = false;
        _errorText = e.toString();
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
      setState(() {
        _isRenewingShielded = false;
        _errorText = e.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _copySelectedAddress() {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Address copied')));
  }

  String get _selectedAddress {
    return switch (_selectedType) {
      _ReceiveAddressType.shielded => _shieldedAddress ?? '',
      _ReceiveAddressType.transparent => _transparentAddress ?? '',
    };
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

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: _ReceivePane(
          selectedType: _selectedType,
          address: address,
          errorText: _errorText,
          isLoading: _isLoading,
          isRenewingShielded: _isRenewingShielded,
          onBack: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
          onTypeChanged: (type) => setState(() => _selectedType = type),
          onRenewShielded: isShielded ? _renewShieldedAddress : null,
          onCopy: _copySelectedAddress,
          onShowHelp: () => _showAddressInfo(context, _selectedType),
        ),
      ),
    );
  }
}

Future<void> _showAddressInfo(BuildContext context, _ReceiveAddressType type) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x33626767),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) => _ReceiveInfoDialog(type: type),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ReceivePane extends StatelessWidget {
  const _ReceivePane({
    required this.selectedType,
    required this.address,
    required this.errorText,
    required this.isLoading,
    required this.isRenewingShielded,
    required this.onBack,
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
  final VoidCallback onBack;
  final ValueChanged<_ReceiveAddressType> onTypeChanged;
  final VoidCallback? onRenewShielded;
  final VoidCallback onCopy;
  final VoidCallback onShowHelp;

  bool get _isShielded => selectedType == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onTap: onBack),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 752),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Receive ZEC',
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReceiveTabs(
                      selectedType: selectedType,
                      onChanged: onTypeChanged,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: isLoading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              height: 276,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : _ReceiveQrBlock(
                              key: ValueKey(selectedType),
                              type: selectedType,
                              address: address,
                              renewing: isRenewingShielded,
                              onRenew: onRenewShielded,
                              onShowHelp: onShowHelp,
                            ),
                    ),
                    const SizedBox(height: 73),
                    _CopyAddressButton(
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
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
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
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _hovered ? 0.75 : 1,
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scaleX: -1,
                  child: AppIcon(
                    AppIcons.chevronForward,
                    size: AppIconSize.medium,
                    color: colors.icon.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Back',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
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

class _ReceiveTabs extends StatelessWidget {
  const _ReceiveTabs({required this.selectedType, required this.onChanged});

  final _ReceiveAddressType selectedType;
  final ValueChanged<_ReceiveAddressType> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = _neutralInverse(context);
    final activeText = _neutralInverseLabel(context);

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
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(color: color),
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
    required this.onRenew,
    required this.onShowHelp,
    super.key,
  });

  final _ReceiveAddressType type;
  final String address;
  final bool renewing;
  final VoidCallback? onRenew;
  final VoidCallback onShowHelp;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 356,
      height: 276.5,
      child: Column(
        children: [
          SizedBox(
            width: 194.5,
            height: 242.5,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (_isShielded)
                  Positioned.fill(
                    top: -6,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ShieldQrBackgroundPainter(
                          color: _brandTeal(context).withValues(alpha: 0.16),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 24,
                  child: _QrSurface(
                    address: address,
                    iconName: _isShielded
                        ? AppIcons.shieldKeyhole
                        : AppIcons.transparentBalance,
                  ),
                ),
                if (_isShielded)
                  Positioned(
                    top: 194.5,
                    child: _RenewButton(renewing: renewing, onTap: onRenew),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AddressLine(address: address, onShowHelp: onShowHelp),
        ],
      ),
    );
  }
}

class _QrSurface extends StatelessWidget {
  const _QrSurface({required this.address, required this.iconName});

  final String address;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qrColor = colors.text.accent;
    final qrBackground = colors.background.ground;
    final iconBg = colors.background.ground.withValues(alpha: 0.96);

    return Container(
      width: 162.5,
      height: 162.5,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: qrBackground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (address.isNotEmpty)
            QrImageView(
              data: 'zcash:$address',
              size: 154.5,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              padding: EdgeInsets.zero,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: qrColor),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: qrColor,
              ),
            )
          else
            Center(
              child: Text(
                'No address',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border.subtle),
            ),
            child: Center(
              child: AppIcon(
                iconName,
                size: AppIconSize.large,
                color: _brandTeal(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenewButton extends StatelessWidget {
  const _RenewButton({required this.renewing, required this.onTap});

  final bool renewing;
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
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.background.ground,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border.subtle),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: renewing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _brandTeal(context),
                    ),
                  )
                : AppIcon(
                    AppIcons.renew,
                    size: 20,
                    color: colors.icon.accent,
                    semanticLabel: 'Renew shielded address',
                  ),
          ),
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.address, required this.onShowHelp});

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
        text: 'Address unavailable',
        style: TextStyle(color: context.colors.text.secondary),
      ),
    ];
  }

  final compact = _compactAddress(address);
  final brand = _brandTeal(context);
  if (compact.length <= 10) return [TextSpan(text: compact)];

  final startHighlight = math.min(5, compact.length);
  final endHighlight = math.max(startHighlight, compact.length - 5);
  return [
    TextSpan(
      text: compact.substring(0, startHighlight),
      style: TextStyle(color: brand),
    ),
    TextSpan(text: compact.substring(startHighlight, endHighlight)),
    TextSpan(
      text: compact.substring(endHighlight),
      style: TextStyle(color: brand),
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
              color: context.colors.icon.regular,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyAddressButton extends StatefulWidget {
  const _CopyAddressButton({
    required this.label,
    required this.primary,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CopyAddressButton> createState() => _CopyAddressButtonState();
}

class _CopyAddressButtonState extends State<_CopyAddressButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = widget.primary
        ? _brandTeal(context)
        : colors.button.secondary.bg;
    final label = widget.primary
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF041316)
              : const Color(0xFFE0F3F5))
        : colors.button.secondary.label;
    final effectiveBg = !widget.enabled
        ? colors.button.disabled.bg
        : _pressed
        ? background.withValues(alpha: 0.84)
        : _hovered
        ? background.withValues(alpha: 0.92)
        : background;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled
          ? (_) => setState(() {
              _hovered = false;
              _pressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: widget.enabled
            ? () => setState(() => _pressed = false)
            : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: 256,
          height: 44,
          decoration: ShapeDecoration(
            color: effectiveBg,
            shape: const StadiumBorder(),
          ),
          child: IconTheme.merge(
            data: IconThemeData(
              color: widget.enabled ? label : colors.button.disabled.label,
              size: AppIconSize.medium,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.label,
                  style: AppTypography.labelLarge.copyWith(
                    color: widget.enabled
                        ? label
                        : colors.button.disabled.label,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const AppIcon(AppIcons.copy, size: AppIconSize.medium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiveInfoDialog extends StatelessWidget {
  const _ReceiveInfoDialog({required this.type});

  final _ReceiveAddressType type;

  bool get _isShielded => type == _ReceiveAddressType.shielded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = _isShielded
        ? const [
            _InfoItem(
              iconName: AppIcons.lock,
              text:
                  'Tx details - sender, receiver, and amount - are encrypted on-chain & hidden.',
            ),
            _InfoItem(
              iconName: AppIcons.renew,
              text:
                  'A new Zcash Shielded address is generated every time you open the Receive page or click Renew button.',
            ),
            _InfoItem(
              iconName: AppIcons.wallet,
              text:
                  'Each new address is a diversified address derived from the same key. They all receive to the same wallet.',
            ),
          ]
        : const [
            _InfoItem(
              iconName: AppIcons.unlock,
              text:
                  'All tx details - sender, receiver, and amount - are publicly visible on-chain.',
            ),
            _InfoItem(
              iconName: AppIcons.transparentBalance,
              text:
                  'Commonly used by exchanges that require transparency or regulatory clarity. Also the default for compatibility across many wallets.',
            ),
            _InfoItem(
              iconName: AppIcons.shieldKeyholeOutline,
              text:
                  'After receiving ZEC to your transparent address, Vizor will guide you to shield the balance. Otherwise, you won\'t be able to send it.',
            ),
          ];

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Center(
        child: Container(
          width: 312,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(
              AppRadii.medium + AppSpacing.xs,
            ),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isShielded
                            ? 'Shielded Address'
                            : 'Transparent Address',
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      Text(
                        _isShielded
                            ? 'Strong privacy by default.'
                            : 'Publicly visible',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Column(
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: item,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _DialogCloseButton(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
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
    final bg = filled ? _brandTeal(context) : colors.background.raised;
    final iconColor = filled ? const Color(0xFFFFFFFF) : colors.icon.accent;

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

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.iconName, required this.text});

  final String iconName;
  final String text;

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
              color: colors.icon.accent,
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

class _ShieldQrBackgroundPainter extends CustomPainter {
  const _ShieldQrBackgroundPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (var i = 0; i < 18; i++) {
      final width = 80.0 + i * 22;
      final height = 42.0 + i * 14;
      canvas.drawOval(
        Rect.fromCenter(center: center, width: width, height: height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShieldQrBackgroundPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

Color _brandTeal(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF3EC4CE)
      : const Color(0xFF0996A0);
}

Color _neutralInverse(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE1E1E1)
      : const Color(0xFF2E3232);
}

Color _neutralInverseLabel(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF141818)
      : const Color(0xFFFFFFFF);
}
