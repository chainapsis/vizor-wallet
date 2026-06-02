// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_decorative_divider.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/activity/models/activity_row_data.dart';
import '../src/features/activity/swap_activity_row_mapper.dart';
import '../src/features/activity/widgets/activity_table.dart';
import '../src/features/swap/models/swap_models.dart';

Widget buildActivitySwapProgressExternalToZecUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-progress-usdc-zec',
        direction: SwapDirection.externalToZec,
        status: SwapIntentStatus.processing,
        sellAmountText: '101.23 USDC',
        receiveEstimateText: '4.12 ZEC',
        lastStatusCheckedAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      ),
    ),
  );
}

Widget buildActivitySwapProgressZecToExternalUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-progress-zec-usdc',
        direction: SwapDirection.zecToExternal,
        status: SwapIntentStatus.processing,
        sellAmountText: '4.12 ZEC',
        receiveEstimateText: '110.12 USDC',
        lastStatusCheckedAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      ),
    ),
  );
}

Widget buildActivitySwapSendingZecToExternalUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-sending-zec-usdc',
        direction: SwapDirection.zecToExternal,
        status: SwapIntentStatus.awaitingDeposit,
        sellAmountText: '4.12 ZEC',
        receiveEstimateText: '110.12 USDC',
        lastStatusCheckedAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      ),
    ),
  );
}

Widget buildActivitySwapConfirmingZecToExternalUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-confirming-zec-usdc',
        direction: SwapDirection.zecToExternal,
        status: SwapIntentStatus.awaitingDeposit,
        sellAmountText: '4.12 ZEC',
        receiveEstimateText: '110.12 USDC',
        depositTxHash: 'zec-deposit-txid',
        lastStatusCheckedAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      ),
    ),
  );
}

Widget buildActivitySwapSuccessExternalToZecUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-success-usdc-zec',
        direction: SwapDirection.externalToZec,
        status: SwapIntentStatus.complete,
        sellAmountText: '101.23 USDC',
        receiveEstimateText: '4.12 ZEC',
        completedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ),
  );
}

Widget buildActivitySwapSuccessZecToExternalUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-success-zec-usdc',
        direction: SwapDirection.zecToExternal,
        status: SwapIntentStatus.complete,
        sellAmountText: '4.12 ZEC',
        receiveEstimateText: '112.10 USDC',
        completedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ),
  );
}

Widget buildActivitySwapFailedExternalToZecUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-failed-usdc-zec',
        direction: SwapDirection.externalToZec,
        status: SwapIntentStatus.failed,
        sellAmountText: '101.23 USDC',
        receiveEstimateText: '4.12 ZEC',
      ),
    ),
  );
}

Widget buildActivitySwapFailedZecToExternalUseCase(BuildContext context) {
  return _ActivityScreenFrame(
    rows: _swapActivityRows(
      context,
      swapRecord: _swapRecord(
        id: 'figma-swap-failed-zec-usdc',
        direction: SwapDirection.zecToExternal,
        status: SwapIntentStatus.failed,
        sellAmountText: '4.12 ZEC',
        receiveEstimateText: '110.12 USDC',
      ),
    ),
  );
}

class _ActivityScreenFrame extends StatelessWidget {
  const _ActivityScreenFrame({required this.rows});

  final List<ActivityRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.base,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1080,
            height: 720,
            child: ColoredBox(
              color: colors.background.base,
              child: AppDesktopShell(
                sidebar: const _PreviewActivitySidebar(),
                pane: AppDesktopPane(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppBackLink(
                          label: 'Back',
                          minWidth: 60,
                          onTap: () {},
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.s,
                            bottom: AppSpacing.s,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Text(
                                  'Activity',
                                  style: AppTypography.displaySmall.copyWith(
                                    color: colors.text.accent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Center(
                                child: AppDecorativeDivider(width: 256),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                  ),
                                  child: ActivityTable(
                                    rows: rows,
                                    showPagination: true,
                                    pinPaginationToBottom: true,
                                    currentPage: 1,
                                    totalPages: 10,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<ActivityRowData> _swapActivityRows(
  BuildContext context, {
  required SwapIntentRecord swapRecord,
}) {
  return [
    buildSwapActivityRow(
      context: context,
      item: SwapActivityRowItem.fromRecord(swapRecord),
    ),
    _failedSentRow(context),
    _sentRow(context, selected: true),
    _sentRow(context),
    _sentRow(context),
  ];
}

SwapIntentRecord _swapRecord({
  required String id,
  required SwapDirection direction,
  required SwapIntentStatus status,
  required String sellAmountText,
  required String receiveEstimateText,
  DateTime? completedAt,
  String? depositTxHash,
  DateTime? lastStatusCheckedAt,
}) {
  final now = DateTime.now();
  final externalAsset = SwapAsset.live(
    assetId: 'figma-usdc-op',
    symbol: 'USDC',
    blockchain: 'op',
    decimals: 6,
  );
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: direction == SwapDirection.externalToZec
        ? 'USDC -> ZEC'
        : 'ZEC -> USDC',
    sellAmountText: sellAmountText,
    receiveEstimateText: receiveEstimateText,
    status: status,
    nextAction: status == SwapIntentStatus.complete
        ? 'Completed'
        : status == SwapIntentStatus.failed
        ? 'Swap failed'
        : 'In progress',
    direction: direction,
    externalAsset: externalAsset,
    createdAt: now.subtract(const Duration(minutes: 8)),
    updatedAt: now,
    completedAt: completedAt,
    depositTxHash: depositTxHash,
    lastStatusCheckedAt: lastStatusCheckedAt,
  );
}

ActivityRowData _failedSentRow(BuildContext context) {
  final colors = context.colors;
  return ActivityRowData(
    title: 'Send failed',
    leadingIconName: AppIcons.plane,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: 'Transparent',
    amountText: '1.11 ZEC',
    amountIconName: AppIcons.arrowBack,
    amountIconColor: colors.icon.regular,
    amountColor: colors.text.accent,
    amountSubtitle: 'Refunded',
    statusText: 'Failed',
    statusIconName: AppIcons.skull,
    statusColor: colors.text.destructive,
    timestampText: 'Apr, 25 10:25',
  );
}

ActivityRowData _sentRow(BuildContext context, {bool selected = false}) {
  final colors = context.colors;
  return ActivityRowData(
    title: 'Sent',
    leadingIconName: AppIcons.plane,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    subtitle: 'Shielded',
    subtitleIconName: AppIcons.shieldKeyholeOutline,
    amountText: '-4.12 ZEC',
    amountColor: colors.text.accent,
    statusText: 'Completed',
    timestampText: 'Apr, 25 10:25',
    selected: selected,
  );
}

class _PreviewActivitySidebar extends StatelessWidget {
  const _PreviewActivitySidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Home',
                    iconName: AppIcons.home,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Address book',
                    iconName: AppIcons.users,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    active: true,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSuccess,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
