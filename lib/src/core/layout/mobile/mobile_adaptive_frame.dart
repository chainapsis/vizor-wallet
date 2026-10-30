import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/sync_display_progress_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/native_mobile_navigation_geometry.dart';
import '../../config/swap_feature_config.dart';
import '../../formatting/sync_status_label.dart';
import '../../navigation/external_action_guard_provider.dart';
import '../../navigation/mobile_destinations.dart';
import '../../navigation/mobile_sidebar_route_observer.dart';
import '../../navigation/mobile_sidebar_exit.dart';
import '../../profile_pictures.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_profile_picture.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/mobile/mobile_account_avatar.dart';
import '../content_overlay_inset.dart';
import 'mobile_navigation_scope.dart';
import 'mobile_wallet_sidebar.dart';
import 'mobile_window_layout.dart';
import 'mobile_window_policy.dart';

/// Wallet route shell below the full-window root Navigator. Resizing changes
/// pane rectangles without replacing the nested Navigator or its state.
class MobileAdaptiveFrame extends ConsumerStatefulWidget {
  const MobileAdaptiveFrame({
    required this.router,
    required this.child,
    super.key,
  });
  final GoRouter router;
  final Widget child;
  @override
  ConsumerState<MobileAdaptiveFrame> createState() =>
      _MobileAdaptiveFrameState();
}

class _MobileAdaptiveFrameState extends ConsumerState<MobileAdaptiveFrame>
    with WidgetsBindingObserver {
  final _navigation = MobileBranchNavigation();
  final _sidebarExit = MobileSidebarExitController();
  MobileNavigationGeometry? _geometry;
  StreamSubscription<MobileNavigationGeometry?>? _subscription;
  int _revision = 0;
  bool _routeUpdatePending = false;
  // Preserve the accepted route's affordances while serializing navigation.
  // Incoming exit scopes may mount on the next frame; neither that gap nor
  // cancellation's temporary busy state should paint disabled button fills.
  ({bool navigation, bool account})? _pendingSidebarPermissions;
  bool get _sidebarNavigationPending => _pendingSidebarPermissions != null;
  late MobileSidebarRouteObserver _routeObserver;
  late final NativeMobileNavigationGeometry _native;

  void _routingChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_routeUpdatePending) return;
      _routeUpdatePending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _routeUpdatePending = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant MobileAdaptiveFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_routingChanged);
      widget.router.routerDelegate.addListener(_routingChanged);
    }
  }

  @override
  void initState() {
    super.initState();
    _sidebarExit.addListener(_routingChanged);
    _native = ref.read(mobileNavigationGeometryServiceProvider);
    WidgetsBinding.instance.addObserver(this);
    widget.router.routerDelegate.addListener(_routingChanged);
    _routeObserver = ref.read(mobileSidebarRouteObserverProvider);
    _routeObserver.addListener(_routingChanged);
    if (_native.supportedHost) {
      _subscription = _native.changes.listen((value) {
        _revision++;
        if (mounted) setState(() => _geometry = value);
      }, onError: (Object _) {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _readGeometry());
    }
  }

  Future<void> _readGeometry() async {
    if (!mounted) return;
    final revision = ++_revision;
    final geometry = await _native.read();
    if (mounted && revision == _revision) setState(() => _geometry = geometry);
  }

  @override
  void didChangeMetrics() {
    // Native layout and Flutter metrics may settle on different frames. Read
    // after this frame and reject stale snapshots by size in the pure policy.
    if (_native.supportedHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _readGeometry());
    }
  }

  @override
  void dispose() {
    _sidebarExit.removeListener(_routingChanged);
    _sidebarExit.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.router.routerDelegate.removeListener(_routingChanged);
    _routeObserver.removeListener(_routingChanged);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final observer = ref.watch(mobileSidebarRouteObserverProvider);
    if (!identical(observer, _routeObserver)) {
      _routeObserver.removeListener(_routingChanged);
      _routeObserver = observer;
      observer.addListener(_routingChanged);
    }
    final path = mobileVisiblePath(widget.router);
    final account = ref.watch(accountProvider).value?.activeAccount;
    final wallet =
        hasMobileWalletSidebar(path) &&
        account != null &&
        !ref.watch(appSecurityProvider).requiresUnlock;
    final swapEnabled = ref.watch(swapFeatureEnabledProvider);
    final media = MediaQuery.of(context);
    final layout = MobileWindowLayout.resolve(
      media: media,
      native: _geometry,
      wallet: wallet,
      navigationItemCount: swapEnabled ? 4 : 3,
    );
    final guard = ref.watch(externalActionGuardProvider);
    bool navigationUnblocked() =>
        !observer.hasPopup &&
        !ref
            .read(externalActionGuardProvider)
            .blocks(ExternalAction.navigation);
    final requiresPolicy = requiresMobileSidebarExitPolicy(path);
    final enabled =
        !guard.blocks(ExternalAction.navigation) &&
        (_pendingSidebarPermissions?.navigation ??
            _sidebarExit.canNavigate(path, requiresPolicy: requiresPolicy));
    final accountEnabled =
        !guard.blocks(ExternalAction.navigation) &&
        (_pendingSidebarPermissions?.account ??
            _sidebarExit.canSwitchAccount(
              path,
              requiresPolicy: requiresPolicy,
            ));
    Future<void> select(String destination) async {
      if (_sidebarNavigationPending ||
          !navigationUnblocked() ||
          mobileVisiblePath(widget.router) != path ||
          !_sidebarExit.canNavigate(path, requiresPolicy: requiresPolicy)) {
        return;
      }
      _pendingSidebarPermissions = (
        navigation: true,
        account: _sidebarExit.canSwitchAccount(
          path,
          requiresPolicy: requiresPolicy,
        ),
      );
      _routingChanged();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      final routeIdentity = _sidebarExit.routeIdentity(path);
      try {
        await ref.read(externalActionGuardProvider.notifier).runNavigation(
          () async {
            if (!await _sidebarExit.prepareLeave(
              path,
              requiresPolicy: requiresPolicy,
            )) {
              if (context.mounted &&
                  mobileVisiblePath(widget.router) == path &&
                  navigationUnblocked()) {
                showAppToast(
                  context,
                  'Could not finish cancellation. Try again.',
                );
              }
              return;
            }
            if (!mounted ||
                !navigationUnblocked() ||
                mobileVisiblePath(widget.router) != path ||
                !identical(routeIdentity, _sidebarExit.routeIdentity(path)) ||
                ref.read(accountProvider).value?.activeAccountUuid !=
                    accountUuid ||
                ref.read(appSecurityProvider).requiresUnlock) {
              return;
            }
            if (!_navigation.select(destination)) widget.router.go(destination);
            await WidgetsBinding.instance.endOfFrame;
          },
        );
      } catch (_) {
        if (context.mounted) {
          showAppToast(context, 'Could not finish cancellation. Try again.');
        }
      } finally {
        _pendingSidebarPermissions = null;
        if (mounted) _routingChanged();
      }
    }

    final wide = layout.mode == MobileNavigationMode.sidebar;
    return MobileWindowPolicyScope(
      policy: layout.windowPolicy,
      child: ContentOverlayInset(
        leftInset: wide ? layout.body.left : 0,
        rightInset: wide ? media.size.width - layout.body.right : 0,
        child: MobileNavigationScope(
          mode: layout.mode,
          railRect: layout.rail,
          contentRect: wide
              ? layout.body.shift(-layout.viewport.topLeft)
              : null,
          availableContentRect: wide
              ? layout.availableContentRect?.shift(-layout.viewport.topLeft)
              : null,
          navigation: _navigation,
          sidebarExit: _sidebarExit,
          child: ColoredBox(
            color: context.colors.background.window,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: layout.viewport,
                  child: MediaQuery(
                    data: mobilePaneMedia(
                      media,
                      layout.viewport,
                      safeRect: layout.contentSafeRect,
                    ),
                    child: ExcludeFocus(
                      excluding: _sidebarNavigationPending,
                      child: AbsorbPointer(
                        absorbing: _sidebarNavigationPending,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
                if (wide)
                  Positioned.fromRect(
                    rect: layout.sidebar!,
                    child: MediaQuery(
                      data: mobilePaneMedia(
                        media,
                        layout.sidebar!,
                        safeRect: layout.contentSafeRect,
                      ),
                      child: MobileWalletSidebar(
                        inputBlocked: _sidebarNavigationPending,
                        accountName: account?.name ?? '',
                        avatar: MobileAccountAvatar(
                          profilePictureId:
                              account?.profilePictureId ??
                              kDefaultProfilePictureId,
                          size: AppProfilePictureSize.navLarge,
                          hardwareSignerKind: account?.hardwareSignerKind,
                          badgeRingColor: context.colors.background.raised,
                        ),
                        status: SyncStatusLabel.from(
                          ref.watch(syncProvider).value ?? SyncState(),
                          displayWholePercentage: ref.watch(
                            syncDisplayWholePercentageProvider,
                          ),
                          networkPrivacy: ref.watch(networkPrivacyProvider),
                        ),
                        currentPath: path,
                        swapEnabled: swapEnabled,
                        onSelect: enabled
                            ? (destination) => unawaited(select(destination))
                            : null,
                        onAccountTap: !accountEnabled
                            ? null
                            : () {
                                if (_sidebarNavigationPending ||
                                    !navigationUnblocked() ||
                                    !_sidebarExit.canSwitchAccount(
                                      mobileVisiblePath(widget.router),
                                      requiresPolicy:
                                          requiresMobileSidebarExitPolicy(
                                            mobileVisiblePath(widget.router),
                                          ),
                                    )) {
                                  return;
                                }
                                unawaited(
                                  ref
                                      .read(
                                        externalActionGuardProvider.notifier,
                                      )
                                      .runNavigation(
                                        () => showMobileAccountsSheet(context),
                                      ),
                                );
                              },
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
