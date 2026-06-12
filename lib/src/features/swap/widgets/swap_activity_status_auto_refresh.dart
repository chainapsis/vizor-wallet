import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../providers/account_provider.dart';
import '../providers/swap_activity_tracker.dart';

/// Keeps open swap-intent statuses fresh while the wrapped surface is
/// on screen — the same periodic refresh the desktop home and activity
/// screens run inline: `refreshOpenActivities` immediately and then
/// every [swapActivityStatusRefreshInterval], retargeted on account
/// switch, inert while the swap feature is disabled.
///
/// The mobile home and activity tabs wrap their bodies in this so the
/// swap rows they render don't go stale (the tracker has no polling of
/// its own).
class SwapActivityStatusAutoRefresh extends ConsumerStatefulWidget {
  const SwapActivityStatusAutoRefresh({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SwapActivityStatusAutoRefresh> createState() =>
      _SwapActivityStatusAutoRefreshState();
}

class _SwapActivityStatusAutoRefreshState
    extends ConsumerState<SwapActivityStatusAutoRefresh> {
  Timer? _timer;
  String? _accountUuid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncRefresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncRefresh() {
    if (!ref.read(swapFeatureEnabledProvider)) {
      _timer?.cancel();
      _accountUuid = null;
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == _accountUuid && _timer?.isActive == true) {
      return;
    }
    _timer?.cancel();
    _accountUuid = accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return;

    unawaited(_refresh(accountUuid));
    _timer = Timer.periodic(
      swapActivityStatusRefreshInterval,
      (_) => unawaited(_refresh(accountUuid)),
    );
  }

  Future<void> _refresh(String accountUuid) {
    return ref
        .read(swapActivityStatusRefresherProvider)
        .refreshOpenActivities(accountUuid: accountUuid);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      if (previous?.value?.activeAccountUuid != next.value?.activeAccountUuid) {
        _syncRefresh();
      }
    });
    return widget.child;
  }
}
