import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../providers/account_initialization_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../activity/gift_card_activity_index.dart';
import '../../activity/swap_activity_row_items_provider.dart';

class HomeInitializationPresentation {
  const HomeInitializationPresentation({
    this.showImporting = false,
    this.activityUnavailable = false,
  });

  final bool showImporting;
  final bool activityUnavailable;
}

/// Shared by both Home form factors and the desktop sidebar. Warming these
/// local indexes while mobile's normal Home is unmounted avoids a second set
/// of skeletons after the restore finishes. No recovery/network work starts.
final homeInitializationPresentationProvider =
    NotifierProvider<
      HomeInitializationPresentationNotifier,
      HomeInitializationPresentation
    >(HomeInitializationPresentationNotifier.new);

class HomeInitializationPresentationNotifier
    extends Notifier<HomeInitializationPresentation> {
  final _homeReady = <Object>{};

  @override
  HomeInitializationPresentation build() {
    final uuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    if (uuid == null ||
        ref.watch(appSecurityProvider.select((s) => s.requiresUnlock))) {
      return const HomeInitializationPresentation();
    }
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      uuid,
    );
    final entries = ref.watch(accountInitializationProvider);
    final tokens = entries.values.map((entry) => entry.token).toSet();
    _homeReady.removeWhere((token) => !tokens.contains(token));
    final initialization = entries[uuid];
    if (initialization == null) {
      return HomeInitializationPresentation(
        showImporting: sync.isImportingAccount,
      );
    }
    final readFailed = initialization.reads == InitialAccountReads.unavailable;
    if (readFailed) _homeReady.add(initialization.token);
    if (_homeReady.contains(initialization.token) ||
        initialization.kind == AccountInitializationKind.created ||
        sync.failure != null ||
        sync.error != null ||
        readFailed) {
      return HomeInitializationPresentation(activityUnavailable: readFailed);
    }

    final localSources = <AsyncValue<Object?>>[
      ref.watch(giftCardActivityIndexProvider(uuid)),
      if (ref.watch(swapFeatureEnabledProvider))
        ref.watch(swapActivityRowItemsProvider(uuid)),
    ];
    final localReadsPending = localSources.any(
      (source) => source.isLoading && !source.hasValue,
    );
    final localReadFailed = localSources.any(
      (source) => source.hasError && !source.hasValue,
    );
    final accountReadsReady =
        initialization.reads == InitialAccountReads.available;
    if (accountReadsReady && !localReadsPending) {
      _homeReady.add(initialization.token);
    }
    return HomeInitializationPresentation(
      showImporting:
          (!accountReadsReady || localReadsPending) &&
          (initialization.kind == AccountInitializationKind.restored ||
              initialization.scanStarted),
      activityUnavailable: accountReadsReady && localReadFailed,
    );
  }
}
