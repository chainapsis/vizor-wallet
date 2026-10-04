import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_keep_awake_provider.dart';
import '../providers/gift_claim_failure_notice_provider.dart';

/// A failure during Face ID waits until Home is actually visible. The notice
/// is acknowledged by the user; the card remains in Received for later inspection.
class GiftClaimFailureToastListener extends ConsumerStatefulWidget {
  const GiftClaimFailureToastListener({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<GiftClaimFailureToastListener> createState() =>
      _GiftClaimFailureToastListenerState();
}

class _GiftClaimFailureToastListenerState
    extends ConsumerState<GiftClaimFailureToastListener> {
  bool _scheduled = false;
  VoidCallback? _dismissToast;
  GiftClaimFailureNotice? _toastNotice;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_schedule);
    ref.listenManual(
      giftClaimFailureNoticeProvider,
      (_, _) => _schedule(),
      fireImmediately: true,
    );
    ref.listenManual(appSecurityProvider, (_, _) => _schedule());
    ref.listenManual(accountProvider, (_, _) => _schedule());
    ref.listenManual(syncKeepAwakePrivacyLockProvider, (_, _) => _schedule());
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final activeAccountUuid = ref
          .read(accountProvider)
          .value
          ?.activeAccountUuid;
      if (widget.router.state.uri.path != '/home' ||
          ref.read(appSecurityProvider).requiresUnlock ||
          ref.read(syncKeepAwakePrivacyLockProvider).isLocked ||
          (_toastNotice != null &&
              _toastNotice!.accountUuid != activeAccountUuid)) {
        _dismissToast?.call();
        _dismissToast = null;
        _toastNotice = null;
        return;
      }
      final notice = ref.read(giftClaimFailureNoticeProvider);
      if (notice == null || notice.accountUuid != activeAccountUuid) {
        _dismissToast?.call();
        _dismissToast = null;
        _toastNotice = null;
        return;
      }
      // A temporary privacy lock hides the toast without consuming its notice.
      // Acknowledgement happens only when the user acts or dismisses it.
      if (_dismissToast != null && identical(_toastNotice, notice)) return;
      _dismissToast?.call();
      _toastNotice = notice;
      _dismissToast = showAppToast(
        context,
        'Couldn’t redeem your gift card.',
        iconName: AppIcons.warning,
        // Keep the recovery action available until it is used or dismissed.
        duration: null,
        onDismiss: () {
          if (!mounted) return;
          ref.read(giftClaimFailureNoticeProvider.notifier).dismiss(notice);
          _dismissToast = null;
          _toastNotice = null;
        },
        action: AppToastAction(
          label: 'View card',
          onPressed: () {
            if (!mounted ||
                ref.read(appSecurityProvider).requiresUnlock ||
                ref.read(syncKeepAwakePrivacyLockProvider).isLocked) {
              return;
            }
            ref.read(giftClaimFailureNoticeProvider.notifier).dismiss(notice);
            widget.router.push(
              Uri(
                path: '/payment-links',
                queryParameters: {'received': notice.link.address},
              ).toString(),
            );
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
