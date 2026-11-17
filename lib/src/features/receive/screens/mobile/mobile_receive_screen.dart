import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../main.dart' show log;
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_window_policy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/receive_address_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../widgets/mobile/receive_address_info_sheet.dart';
import '../../widgets/receive_address_widgets.dart';
import 'mobile_receive_request_screen.dart';

bool _shouldRefreshTransparentAddressAfterSyncUpdate(
  SyncState previous,
  SyncState next,
) {
  final completedAt = next.lastSyncCompletedAt;
  final failedAt = next.lastSyncFailedAt;

  return (previous.isSyncing && !next.isSyncing) ||
      (completedAt != null && completedAt != previous.lastSyncCompletedAt) ||
      (failedAt != null && failedAt != previous.lastSyncFailedAt);
}

/// Mobile receive screen — Figma `Receive` (4514:110524): pool tabs,
/// QR with the renew control on its bottom edge, compact address line,
/// and share/copy actions, composed from the shared receive widgets.
class MobileReceiveScreen extends ConsumerStatefulWidget {
  /// Route-local cap; the shell still limits ordinary mobile pages to 440.
  static const maximumWideWidth = 640.0;

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
  // Keep the pager and its QR bitmaps mounted when it moves between columns.
  final _qrPagerKey = GlobalKey();
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
      final transparent = await service.loadTransparentReceiveAddress(
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

  Future<void> _refreshTransparentReceiveAddressAfterSync() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;

    try {
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadTransparentReceiveAddress(accountUuid: accountUuid);
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      if (_transparentAddress == address) return;

      setState(() => _transparentAddress = address);
    } catch (e) {
      log('MobileReceive: ERROR refreshing transparent address after sync: $e');
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
    if (!_pageController.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(type.index);
    } else {
      unawaited(
        _pageController.animateToPage(
          type.index,
          duration: _MobileReceiveMotion.switchDuration,
          curve: _MobileReceiveMotion.switchCurve,
        ),
      );
    }
  }

  double get _page {
    final attached = _pageController.hasClients;
    return attached && _pageController.position.haveDimensions
        ? _pageController.page!
        : _selectedType.index.toDouble();
  }

  // The chip follows the pager, so a swipe moves both together.
  Widget _buildTabs({required double width}) => AnimatedBuilder(
    animation: _pageController,
    builder: (context, _) => ReceiveTabs(
      width: width,
      height: _MobileReceiveMetrics.tabsHeight,
      iconSize: _MobileReceiveMetrics.tabsIconSize,
      iconGap: AppSpacing.xs,
      labelStyle: AppTypography.labelLarge,
      labelFontWeight: FontWeight.w500,
      alwaysDarkSelected: true,
      selectedType: _selectedType,
      position: _page,
      onChanged: _selectType,
    ),
  );

  // The address follows the pager like the chip, so it moves with the cards
  // instead of swapping at the tap.
  Widget _buildAddressSummary({
    required String accountName,
    bool adaptive = false,
  }) => AnimatedBuilder(
    animation: _pageController,
    builder: (context, _) => _ReceiveAddressSummary(
      adaptive: adaptive,
      accountName: accountName,
      position: _page,
      selectedType: _selectedType,
      addressFor: _addressFor,
      onShowHelp: () =>
          unawaited(showReceiveAddressInfoSheet(context, _selectedType)),
    ),
  );

  void _handlePageChanged(int page) {
    final type = ReceiveAddressType.values[page];
    if (_selectedType == type) return;
    // A swipe switches the pool without the tabs, so it ticks here; a tap
    // already ticked in the tabs and set the type before the pager moved.
    unawaited(AppHaptics.selection());
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
      showAppToast(context, context.l10n.receiveRenewAddressError);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  Future<void> _copyAddress() async {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: address));
    unawaited(AppHaptics.copy());
    if (!mounted) return;
    showAppToast(context, context.l10n.commonAddressCopied);
  }

  void _shareAddress() {
    final address = _selectedAddress;
    if (address.isEmpty) return;
    unawaited(SharePlus.instance.share(ShareParams(text: address)));
  }

  void _openRequest() {
    // Snapshotted here: renewing the shielded address or swiping to the other
    // pool behind the page must not repoint a link being handed out.
    final address = _selectedAddress;
    if (address.isEmpty) return;
    unawaited(openReceiveRequest(context, address: address));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(syncProvider, (previous, next) {
      final previousState = previous?.asData?.value;
      final nextState = next.asData?.value;
      if (previousState != null &&
          nextState != null &&
          _shouldRefreshTransparentAddressAfterSyncUpdate(
            previousState,
            nextState,
          )) {
        unawaited(_refreshTransparentReceiveAddressAfterSync());
      }
    });

    final colors = context.colors;
    final activeAccount = ref.watch(accountProvider).value?.activeAccount;
    final accountName = activeAccount?.name ?? '';
    final scanOptimizedQr = activeAccount?.isKeystone ?? false;
    final l10n = context.l10n;
    final copyLabel = _isShielded
        ? l10n.commonCopyShieldedAddress
        : l10n.receiveCopyTransparentAddress;
    final shareLabel = _isShielded
        ? l10n.receiveShareShieldedAddress
        : l10n.receiveShareTransparentAddress;

    if (MobileWindowPolicyScope.of(context).usesWideLayout) {
      return _buildWide(
        context,
        accountName: accountName,
        scanOptimizedQr: scanOptimizedQr,
      );
    }

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: context.l10n.receiveTitle(kZcashDefaultCurrencyTicker),

                height: _MobileReceiveMetrics.topNavHeight,
                onBack: () => context.pop(),
                trailing: _ShareNavButton(
                  label: shareLabel,
                  onTap: _selectedAddress.isEmpty ? null : _shareAddress,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    kMobilePageMargin,
                    AppSpacing.s,
                    kMobilePageMargin,
                    AppSpacing.md,
                  ),
                  children: [
                    const SizedBox(height: _MobileReceiveMetrics.topGap),
                    Center(
                      child: _buildTabs(width: _MobileReceiveMetrics.tabsWidth),
                    ),
                    const SizedBox(height: _MobileReceiveMetrics.tabsToQrGap),
                    Center(
                      child: _buildQrPager(scanOptimizedQr: scanOptimizedQr),
                    ),
                    const SizedBox(
                      height: _MobileReceiveMetrics.qrToAddressGap,
                    ),
                    Center(
                      child: _buildAddressSummary(accountName: accountName),
                    ),
                    const SizedBox(height: AppSpacing.base),
                    Center(
                      child: SizedBox(
                        width: _MobileReceiveMetrics.buttonStackWidth,
                        // Share lives in the top nav; copy and request each
                        // take the column's full width.
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppButton(
                              key: const ValueKey('mobile_receive_copy'),
                              expand: true,
                              constrainContent: true,
                              height: _MobileReceiveMetrics.buttonHeight,
                              variant: _isShielded
                                  ? AppButtonVariant.primary
                                  : AppButtonVariant.secondary,
                              onPressed: _selectedAddress.isEmpty
                                  ? null
                                  : () => unawaited(_copyAddress()),
                              leading: const AppIcon(
                                AppIcons.copy,
                                size: _MobileReceiveMetrics.buttonIconSize,
                              ),
                              child: Text(
                                l10n.commonCopyAddress,
                                semanticsLabel: copyLabel,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            AppButton(
                              key: const ValueKey('mobile_receive_request'),
                              expand: true,
                              constrainContent: true,
                              height: _MobileReceiveMetrics.buttonHeight,
                              variant: AppButtonVariant.secondary,
                              onPressed: _selectedAddress.isEmpty
                                  ? null
                                  : _openRequest,
                              child: Text(
                                l10n.receiveRequestButton(
                                  kZcashDefaultCurrencyTicker,
                                ),
                              ),
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

  /// Outside a split pane the pager spans the content width and leaves its
  /// cards unclipped, so they slide apart with a gap and leave at the screen
  /// edge. A split pane has no such edge, so its column clips and fades them.
  Widget _buildQrPager({
    required bool scanOptimizedQr,
    bool contained = false,
  }) => SizedBox(
    key: _qrPagerKey,
    width: contained ? _MobileReceiveMetrics.qrWrapWidth : double.infinity,
    height: _MobileReceiveMetrics.qrCodeHeight,
    child: PageView(
      key: const ValueKey('mobile_receive_qr_pager'),
      controller: _pageController,
      // Builds the other pool's code ahead so a switch never waits on it.
      allowImplicitScrolling: true,
      clipBehavior: contained ? Clip.hardEdge : Clip.none,
      onPageChanged: _handlePageChanged,
      children: [
        for (final type in ReceiveAddressType.values)
          AnimatedBuilder(
            animation: _pageController,
            builder: (context, child) {
              final distance = (_page - type.index).abs().clamp(0.0, 1.0);
              // The leaving card steps back and the arriving one comes
              // forward, so a switch reads as two cards, not a sliding strip.
              final receded = Transform.scale(
                scale: 1 - _MobileReceiveMotion.recedeScale * distance,
                child: child,
              );
              return Opacity(
                opacity: contained
                    ? 1 - distance
                    : 1 - _MobileReceiveMotion.recedeFade * distance,
                child: receded,
              );
            },
            child: Center(
              child: _ReceiveQrPage(
                key: ValueKey('mobile_receive_qr_${type.name}'),
                type: type,
                address: _addressFor(type),
                renewing: _renewing,
                scanOptimizedQr: scanOptimizedQr,
                onRenew: () => unawaited(_renewShieldedAddress()),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildWide(
    BuildContext context, {
    required String accountName,
    required bool scanOptimizedQr,
  }) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: AppToastHost(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final split =
                constraints.maxWidth >= _MobileReceiveMetrics.minimumSplitWidth;
            // A narrow wide-window pane still fits the unchanged 292px card.
            final horizontalPadding = math.min(
              AppSpacing.sm,
              math.max(
                0.0,
                (constraints.maxWidth - _MobileReceiveMetrics.qrWrapWidth) / 2,
              ),
            );
            final qr = _buildQrPager(
              scanOptimizedQr: scanOptimizedQr,
              contained: split,
            );
            final details = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAddressSummary(accountName: accountName, adaptive: true),
                const SizedBox(height: AppSpacing.md),
                _buildWideActions(),
              ],
            );
            return SingleChildScrollView(
              key: const ValueKey('mobile_receive_wide_scroll'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                AppSpacing.md,
              ),
              child: Column(
                children: [
                  MobileTopNav.back(
                    title: context.l10n.receiveTitle(
                      kZcashDefaultCurrencyTicker,
                    ),

                    height: _MobileReceiveMetrics.topNavHeight,
                    onBack: () => context.pop(),
                    trailing: _ShareNavButton(
                      label: _isShielded
                          ? context.l10n.receiveShareShieldedAddress
                          : context.l10n.receiveShareTransparentAddress,
                      onTap: _selectedAddress.isEmpty ? null : _shareAddress,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildTabs(
                    width: math.min(
                      _MobileReceiveMetrics.tabsWidth,
                      constraints.maxWidth - horizontalPadding * 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (split)
                    Row(
                      key: const ValueKey('mobile_receive_split'),
                      children: [
                        qr,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: details),
                      ],
                    )
                  else
                    Column(
                      key: const ValueKey('mobile_receive_stacked'),
                      children: [
                        qr,
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: _MobileReceiveMetrics.buttonStackWidth,
                          child: details,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _buildWideActions() {
    final l10n = context.l10n;
    final copyLabel = _isShielded
        ? l10n.commonCopyShieldedAddress
        : l10n.receiveCopyTransparentAddress;
    final enabled = _selectedAddress.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          key: const ValueKey('mobile_receive_copy'),
          expand: true,
          constrainContent: true,
          growWithContent: true,
          height: _MobileReceiveMetrics.buttonHeight,
          variant: _isShielded
              ? AppButtonVariant.primary
              : AppButtonVariant.secondary,
          onPressed: enabled ? () => unawaited(_copyAddress()) : null,
          leading: const AppIcon(
            AppIcons.copy,
            size: _MobileReceiveMetrics.buttonIconSize,
          ),
          child: Text(
            l10n.commonCopyAddress,
            semanticsLabel: copyLabel,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          key: const ValueKey('mobile_receive_request'),
          expand: true,
          constrainContent: true,
          growWithContent: true,
          height: _MobileReceiveMetrics.buttonHeight,
          variant: AppButtonVariant.secondary,
          onPressed: enabled ? _openRequest : null,
          child: Text(
            l10n.receiveRequestButton(kZcashDefaultCurrencyTicker),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

abstract final class _MobileReceiveMetrics {
  // 260px QR + 16px gap + 220px actions + 16px padding on each side, with
  // room to spare.
  static const minimumSplitWidth = 560.0;
  static const topNavHeight = 74.0;
  static const topGap = 16.5;
  static const tabsWidth = 320.0;
  static const tabsHeight = 44.0;
  static const tabsIconSize = 20.0;
  static const tabsToQrGap = 32.0;

  // The QR is 228px, about 12% under the design's 260, so the whole page
  // fits one phone screen; a camera still reads it easily at that size.
  // The card, the renew button's place and the badge scale with it.
  static const qrWrapWidth = qrSize + qrPaddingX * 2;
  static const qrCodeHeight = renewTop + renewSize;
  static const qrSize = 228.0;
  static const qrPaddingX = 16.0;
  static const qrPaddingY = 24.0;

  /// The pool badge in the code's centre: the design's 54.26 at 260, so it
  /// covers the same share of the code.
  static const qrBadgeSize = 54.26 * qrSize / 260;

  /// The renew button straddles the card's lower edge.
  static const renewTop = qrSize + qrPaddingY * 2 - renewSize / 3;
  static const renewSize = 48.0;

  static const qrToAddressGap = 24.0;
  // The address and the buttons share the QR card's width, so the column
  // has one left and right edge.
  static const addressWidth = qrWrapWidth;
  static const addressHeight = 70.0;
  static const accountNameHeight = 26.0;
  static const addressLineHeight = 40.0;

  static const buttonStackWidth = qrWrapWidth;
  static const buttonHeight = AppButtonSizing.largeHeight;
  static const buttonIconSize = 20.0;

  /// Top-nav share: the back chevron's tap target and icon size.
  static const navButtonSize = 44.0;
  static const navIconSize = 24.0;
}

abstract final class _MobileReceiveMotion {
  /// Tab-driven pool switch. iOS-style ease-out: the cards move as soon as
  /// the tab is tapped and settle without a long tail.
  static const switchDuration = Duration(milliseconds: 300);
  static const switchCurve = Cubic(0.32, 0.72, 0, 1);

  /// How far a card shrinks and fades one full page away from center.
  static const recedeScale = 0.06;

  /// Unclipped cards leave at the screen edge, so they only half fade.
  static const recedeFade = 0.5;

  /// How far the address line drifts with the cards at a pool switch.
  static const addressSlide = 12.0;

  /// The share of a switch over which the outgoing address fades. The
  /// pager's curve covers most of the distance early, so the outgoing line
  /// leaves as the cards start to move and the incoming one fades in over
  /// the rest, as they settle.
  static const addressFadeOut = 0.35;
}

class _ReceiveQrPage extends StatelessWidget {
  const _ReceiveQrPage({
    required this.type,
    required this.address,
    required this.renewing,
    required this.scanOptimizedQr,
    required this.onRenew,
    super.key,
  });

  final ReceiveAddressType type;
  final String address;
  final bool renewing;
  final bool scanOptimizedQr;
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
              scanOptimized: scanOptimizedQr,
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
    required this.position,
    required this.selectedType,
    required this.addressFor,
    required this.onShowHelp,
    this.adaptive = false,
  });

  final String accountName;

  /// The QR pager's position: a pool's index at rest, fractional mid-switch.
  final double position;

  /// The pool being switched to: set at a tab tap, or halfway through a swipe.
  final ReceiveAddressType selectedType;
  final String Function(ReceiveAddressType type) addressFor;
  final VoidCallback onShowHelp;
  final bool adaptive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // One address line at a time, following the pager. The outgoing address
    // fades and drifts out over the first part of a switch; the selected
    // one fades in over the rest. Mid-swipe both sides of the handover sit at
    // the same low opacity, so the swap at the midpoint does not jump.
    final arrival = (position - selectedType.index).abs().clamp(0.0, 1.0);
    const handover = 1 - _MobileReceiveMotion.addressFadeOut;
    final showsSelected = arrival <= handover;
    final type = showsSelected
        ? selectedType
        : ReceiveAddressType.values[position.round().clamp(
            0,
            ReceiveAddressType.values.length - 1,
          )];
    final opacity = showsSelected
        ? 1 - arrival / handover
        : (arrival - handover) / (1 - handover);
    final offset = position - type.index;
    // The pager runs right to left in RTL, so the drift mirrors with it.
    final drift = Directionality.of(context) == TextDirection.rtl ? 1 : -1;
    return SizedBox(
      key: const ValueKey('mobile_receive_address_summary'),
      width: _MobileReceiveMetrics.addressWidth,
      // Minimum heights, so larger text grows the summary instead of
      // clipping the account name.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: adaptive ? 0 : _MobileReceiveMetrics.addressHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: adaptive
                    ? 0
                    : _MobileReceiveMetrics.accountNameHeight,
              ),
              child: Text(
                accountName,
                maxLines: adaptive ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: colors.text.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(
                  drift * offset * _MobileReceiveMotion.addressSlide,
                  0,
                ),
                child: ReceiveAddressLine(
                  key: ValueKey('mobile_receive_address_line_${type.name}'),
                  type: type,
                  address: addressFor(type),
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Share in the top nav's trailing slot, opposite the back chevron and drawn
/// like it: a bare icon on a 44pt target.
class _ShareNavButton extends StatelessWidget {
  const _ShareNavButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        key: const ValueKey('mobile_receive_share'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: _MobileReceiveMetrics.navButtonSize,
          child: Center(
            child: AppIcon(
              AppIcons.share,
              size: _MobileReceiveMetrics.navIconSize,
              color: onTap == null ? colors.icon.disabled : colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}
