// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';

import '../src/core/formatting/sync_status_label.dart';
import '../src/core/layout/app_main_sidebar.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/providers/sync_provider.dart';

// Preview mobile metrics with:
// fvm flutter run -t lib/widgetbook.dart --dart-define=VIZOR_FORM_FACTOR=mobile

final _syncingState = SyncState(isSyncing: true, displayPercentage: 0.2);

Widget buildSyncStateDesktopUseCase(BuildContext context) {
  return Center(
    child: ColoredBox(
      color: context.colors.background.raised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: AppSidebarSyncStatus(sync: _syncingState),
      ),
    ),
  );
}

Widget buildSyncStateMobileUseCase(BuildContext context) {
  return Center(
    child: SizedBox(
      width: 393,
      child: ColoredBox(
        color: context.colors.background.window,
        child: _mobileSyncStatus(context, _syncingState),
      ),
    ),
  );
}

Widget _mobileSyncStatus(BuildContext context, SyncState sync) {
  final colors = context.colors;
  final status = SyncStatusLabel.from(sync);
  final (labelColor, indicatorColor, highlightColor) = switch (status.kind) {
    SyncStatusKind.synced => (
      colors.sync.text,
      colors.sync.lightSuccess,
      colors.sync.text,
    ),
    SyncStatusKind.syncing => (
      colors.sync.textSyncing,
      colors.sync.lightSyncing,
      colors.sync.textSyncingHighlight,
    ),
    SyncStatusKind.failed => (
      colors.sync.textError,
      colors.sync.lightError,
      colors.sync.textError,
    ),
  };

  return MobileTopNav.account(
    accountName: 'Account1',
    syncLabel: status.label,
    syncLabelColor: labelColor,
    syncIndicatorColor: indicatorColor,
    syncHighlightColor: highlightColor,
    syncAnimated: status.kind == SyncStatusKind.syncing,
  );
}
