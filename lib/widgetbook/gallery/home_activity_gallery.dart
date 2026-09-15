// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/activity/gift_card_activity_index.dart';
import '../../src/features/activity/widgets/received_receipt_view.dart';
import '../../src/features/activity/widgets/shielded_receipt_view.dart';
import '../../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../../src/features/swap/models/swap_models.dart';
import '../activity_use_cases.dart';
import '../home_activity_use_cases.dart';
import '../received_receipt_use_cases.dart';
import '../support/wb_design_status.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';

/// The Home and Activity galleries: one use case per surface. Home drives the
/// real screens through the parameterized fixtures in
/// `home_activity_use_cases.dart`; the Activity cases still dispatch to the
/// `build*UseCase` fixtures figma_compare and the tests bind to.
final List<WidgetbookNode> homeActivityGalleryNodes = [
  WidgetbookFolder(
    name: 'Home',
    children: [
      WidgetbookComponent(
        name: 'Home screen',
        // One surface, one case: the Layout knob swaps the two screens and
        // each layout registers only the axes it has. The shield axis stops
        // at the button; its signing surfaces are the Keystone shielding
        // component.
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildHomeScreenGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Keystone shielding',
        // The desktop overlay and the mobile screen are separate widget
        // classes with their own stage lists, so Stage is declared per layout.
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildHomeKeystoneShieldGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Shielding message',
        // The copy the shielding flow can put in front of the user, each
        // produced by the production mapper rather than restated here. The
        // toast is the mobile vessel; the desktop notice-card shape is
        // uncovered because `_shieldBalanceError` is screen-local state
        // (home_screen.dart:77, :399-400), unreachable from a fixture.
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildHomeShieldMessageGalleryCase,
            designLink: wbNoFigma(
              note:
                  'Code-only: the vessel is the shared toast; what this case '
                  'covers is the message set, which has no frame of its own.',
            ),
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Activity',
    children: [
      WidgetbookComponent(
        name: 'Activity screen',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivityScreenGalleryCase,
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Components',
        children: [
          WidgetbookComponent(
            name: 'Activity feed',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildActivityFeedGalleryCase,
              ),
              WidgetbookUseCase(
                name: 'Receive absorption',
                builder: buildActivityReceiveAbsorptionGalleryCase,
                designLink: wbNoFigma(
                  note:
                      'Code-only: the Absorb receive button is a harness control, '
                      'not app UI; the rows themselves follow the activity row '
                      'design.',
                ),
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Activity row',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildActivityRowGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Transaction row',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildActivityTransactionRowGalleryCase,
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Swap row',
            useCases: [
              WidgetbookUseCase(
                name: 'Playground',
                builder: buildActivitySwapRowGalleryCase,
              ),
            ],
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Transaction status',
        // Two screens sharing the tapped row's args and the same loader
        // seams; only the load axis and the refresh error are per layout.
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivityTransactionStatusGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Received receipt',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivityReceivedReceiptGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Shielded receipt',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivityShieldedReceiptGalleryCase,
            designLink: wbNoFigma(
              note:
                  'Needs design: the self-shield receipt reuses the send and '
                  'receive receipt primitives; no frame exists for it yet.',
            ),
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Swap detail screen',
        // The hosts, not the surface: `SwapActivityDetailSurface` and its
        // deposit/notice/hardware axes are registered once under Screens >
        // Swap. What lives here is the chrome the two screens add — the
        // desktop sidebar shell and the mobile back nav whose title
        // `mobileSwapActivityTitle` derives from status and mode.
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivitySwapDetailScreenGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Gift card detail',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildActivityGiftCardDetailGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Home screen -----------------------------------------------------------

/// Home on both form factors. Balance, activity and sync are shared axes whose
/// option lists differ per layout; the rest belong to one layout only — the
/// wallet state, notice card, shield action and window height to the desktop
/// pane, the voting card, send gate, accounts sheet, keep-awake prompt and
/// frame to the phone. The Ironwood migration states of this screen live in
/// the Ironwood migration gallery on both lanes, so Home never registers them
/// twice.
Widget buildHomeScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final balance = wbStateKnob<HomeBalanceAmount>(
    context,
    label: 'Balance',
    options: homeBalanceOptions(layout),
    initial: HomeBalanceAmount.funded,
    labelBuilder: homeBalanceLabel,
  );
  final activity = wbStateKnob<HomeActivityFeed>(
    context,
    label: 'Activity',
    options: homeActivityFeedOptions(layout),
    initial: HomeActivityFeed.threeRows,
    labelBuilder: homeActivityFeedLabel,
  );
  final sync = wbStateKnob<HomeSyncProgress>(
    context,
    label: 'Sync',
    options: homeSyncProgressOptions(layout),
    labelBuilder: homeSyncProgressLabel,
  );
  final network = wbStateKnob<HomeNetworkRoute>(
    context,
    label: 'Network',
    options: HomeNetworkRoute.values,
    labelBuilder: homeNetworkRouteLabel,
  );
  final priceChange = wbStateKnob<HomePriceChange>(
    context,
    label: '24h change',
    options: HomePriceChange.values,
    labelBuilder: homePriceChangeLabel,
  );
  final privacyMode = wbBoolKnob(context, label: 'Privacy mode');

  if (layout == WbLayout.mobile) {
    return homeMobileFixture(
      balance: balance,
      activity: activity,
      sync: sync,
      network: network,
      account: wbStateKnob<HomeAccountKind>(
        context,
        label: 'Account',
        options: HomeAccountKind.values,
        labelBuilder: homeAccountKindLabel,
      ),
      votingEntryVisible:
          wbStateKnob<HomeMobileVotingEntry>(
            context,
            label: 'Voting entry',
            options: HomeMobileVotingEntry.values,
            labelBuilder: homeMobileVotingEntryLabel,
          ) ==
          HomeMobileVotingEntry.visible,
      sendBlockedByMigration:
          wbStateKnob<HomeMobileSendGate>(
            context,
            label: 'Send',
            options: HomeMobileSendGate.values,
            labelBuilder: homeMobileSendGateLabel,
          ) ==
          HomeMobileSendGate.blockedByMigration,
      accountsSheetOpen:
          wbStateKnob<HomeMobileAccountsSheet>(
            context,
            label: 'Accounts sheet',
            options: HomeMobileAccountsSheet.values,
            labelBuilder: homeMobileAccountsSheetLabel,
          ) ==
          HomeMobileAccountsSheet.open,
      frame: wbStateKnob<HomeMobileFrame>(
        context,
        label: 'Frame',
        options: HomeMobileFrame.values,
        labelBuilder: homeMobileFrameLabel,
      ),
      priceChange: priceChange,
      keepAwakePromptOpen:
          wbStateKnob<HomeMobileKeepAwakePrompt>(
            context,
            label: 'Keep awake prompt',
            options: HomeMobileKeepAwakePrompt.values,
            labelBuilder: homeMobileKeepAwakePromptLabel,
          ) ==
          HomeMobileKeepAwakePrompt.shown,
      payEntry: wbBoolKnob(context, label: 'Pay entry', initial: true),
      privacyMode: privacyMode,
    );
  }
  return homeDesktopFixture(
    wallet: wbStateKnob<HomeWalletState>(
      context,
      label: 'Wallet',
      options: HomeWalletState.values,
      labelBuilder: homeWalletStateLabel,
    ),
    balance: balance,
    activity: activity,
    sync: sync,
    network: network,
    notice: wbStateKnob<HomeNoticeKind>(
      context,
      label: 'Notice',
      options: HomeNoticeKind.values,
      labelBuilder: homeNoticeLabel,
    ),
    shieldAction: wbStateKnob<HomeShieldAction>(
      context,
      label: 'Shield action',
      options: HomeShieldAction.values,
      labelBuilder: homeShieldActionLabel,
    ),
    windowHeight: wbStateKnob<HomeWindowHeight>(
      context,
      label: 'Window height',
      options: HomeWindowHeight.values,
      labelBuilder: homeWindowHeightLabel,
    ),
    priceChange: priceChange,
    payInUsdc: wbBoolKnob(context, label: 'Pay in USDC'),
    privacyMode: privacyMode,
  );
}

/// The mobile home has no large-balance or one/five-row fixtures, so those
/// options are offered on desktop only.
List<HomeBalanceAmount> homeBalanceOptions(WbLayout layout) {
  return layout == WbLayout.mobile
      ? const [
          HomeBalanceAmount.zero,
          HomeBalanceAmount.funded,
          HomeBalanceAmount.fundedTransparent,
        ]
      : HomeBalanceAmount.values;
}

List<HomeActivityFeed> homeActivityFeedOptions(WbLayout layout) {
  return layout == WbLayout.mobile
      ? const [
          HomeActivityFeed.threeRows,
          HomeActivityFeed.giftCards,
          HomeActivityFeed.empty,
        ]
      : HomeActivityFeed.values;
}

/// The importing screen takes the account name from the active account, which
/// the mobile top nav always shows; no unnamed variant on the phone.
List<HomeSyncProgress> homeSyncProgressOptions(WbLayout layout) {
  return layout == WbLayout.mobile
      ? const [
          HomeSyncProgress.synced,
          HomeSyncProgress.importingStarted,
          HomeSyncProgress.importingPartway,
          HomeSyncProgress.importingNearlyDone,
        ]
      : HomeSyncProgress.values;
}

/// The sheet that offers to hold the screen awake for a long sync. Showing it
/// also pins the sync run the production estimator needs to clear its
/// one-minute threshold, so this axis is not orthogonal to `Sync`.
enum HomeMobileKeepAwakePrompt { hidden, shown }

String homeMobileKeepAwakePromptLabel(HomeMobileKeepAwakePrompt prompt) {
  return prompt == HomeMobileKeepAwakePrompt.shown ? 'Shown' : 'Hidden';
}

/// Mobile-only binary axes; the shared axes are the fixture enums.
enum HomeMobileVotingEntry { visible, hidden }

enum HomeMobileSendGate { enabled, blockedByMigration }

enum HomeMobileAccountsSheet { closed, open }

String homeWalletStateLabel(HomeWalletState state) {
  return switch (state) {
    HomeWalletState.data => 'Loaded',
    HomeWalletState.loading => 'Loading',
    HomeWalletState.error => 'Failed to load',
  };
}

String homeBalanceLabel(HomeBalanceAmount balance) {
  return switch (balance) {
    HomeBalanceAmount.zero => 'Zero',
    HomeBalanceAmount.funded => 'Funded',
    HomeBalanceAmount.large => 'Large',
    HomeBalanceAmount.fundedTransparent => 'Funded + transparent',
  };
}

String homeActivityFeedLabel(HomeActivityFeed activity) {
  return switch (activity) {
    HomeActivityFeed.empty => 'No activity',
    HomeActivityFeed.oneRow => 'One row',
    HomeActivityFeed.threeRows => 'Three rows',
    HomeActivityFeed.fiveRows => 'Five rows',
    HomeActivityFeed.giftCards => 'Gift cards',
  };
}

String homeSyncProgressLabel(HomeSyncProgress sync) {
  return switch (sync) {
    HomeSyncProgress.synced => 'Synced',
    HomeSyncProgress.importingStarted => 'Importing 0%',
    HomeSyncProgress.importingPartway => 'Importing 34%',
    HomeSyncProgress.importingNearlyDone => 'Importing 99%',
    HomeSyncProgress.importingUnnamed => 'Importing, no account name',
  };
}

String homeNetworkRouteLabel(HomeNetworkRoute network) {
  return switch (network) {
    HomeNetworkRoute.direct => 'Direct',
    HomeNetworkRoute.torConnecting => 'Tor connecting',
    HomeNetworkRoute.torBlocked => 'Tor blocked',
  };
}

String homeNoticeLabel(HomeNoticeKind notice) {
  return switch (notice) {
    HomeNoticeKind.none => 'None',
    HomeNoticeKind.passwordRotation => 'Password rotation',
    HomeNoticeKind.syncFailure => 'Sync failure, retry',
    HomeNoticeKind.syncFailureEndpointSettings => 'Sync failure, settings',
  };
}

String homeShieldActionLabel(HomeShieldAction action) {
  return switch (action) {
    HomeShieldAction.enabled => 'Enabled',
    HomeShieldAction.hidden => 'Hidden',
  };
}

String homeWindowHeightLabel(HomeWindowHeight height) {
  return switch (height) {
    HomeWindowHeight.full => 'Full',
    HomeWindowHeight.compact => 'Compact',
  };
}

String homePriceChangeLabel(HomePriceChange change) {
  return switch (change) {
    HomePriceChange.up => 'Up',
    HomePriceChange.down => 'Down',
    HomePriceChange.flat => 'Flat',
    HomePriceChange.hidden => 'Hidden',
    HomePriceChange.priceUnavailable => 'No price',
  };
}

String homeAccountKindLabel(HomeAccountKind account) {
  return switch (account) {
    HomeAccountKind.software => 'Software',
    HomeAccountKind.keystone => 'Keystone',
  };
}

String homeMobileFrameLabel(HomeMobileFrame frame) {
  return switch (frame) {
    HomeMobileFrame.phone => 'Phone',
    HomeMobileFrame.unconstrained => 'Unconstrained',
  };
}

String homeMobileVotingEntryLabel(HomeMobileVotingEntry entry) {
  return switch (entry) {
    HomeMobileVotingEntry.visible => 'Visible',
    HomeMobileVotingEntry.hidden => 'Hidden',
  };
}

String homeMobileSendGateLabel(HomeMobileSendGate gate) {
  return switch (gate) {
    HomeMobileSendGate.enabled => 'Enabled',
    HomeMobileSendGate.blockedByMigration => 'Blocked by migration',
  };
}

String homeMobileAccountsSheetLabel(HomeMobileAccountsSheet sheet) {
  return switch (sheet) {
    HomeMobileAccountsSheet.closed => 'Closed',
    HomeMobileAccountsSheet.open => 'Open',
  };
}

// --- Activity screen -------------------------------------------------------

/// The real Activity screens on both form factors. `historyLoader` is their
/// only Rust seam, so the State knob drives every branch of the feed through
/// it; the swap-feature knob only moves the desktop screen, which is the one
/// that gates its swap rows on the flag.
Widget buildActivityScreenGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final state = wbStateKnob<ActivityScreenState>(
    context,
    label: 'State',
    options: ActivityScreenState.values,
    labelBuilder: activityScreenStateLabel,
  );
  final rows = wbStateKnob<ActivityRowSet>(
    context,
    label: 'Rows',
    options: ActivityRowSet.values,
    labelBuilder: activityRowSetLabel,
  );
  final swapFeatureEnabled = wbBoolKnob(
    context,
    label: 'Swap feature',
    initial: true,
  );
  final privacyMode = wbBoolKnob(context, label: 'Privacy mode');

  return layout == WbLayout.mobile
      ? activityMobileFixture(
          state: state,
          rows: rows,
          swapFeatureEnabled: swapFeatureEnabled,
          privacyMode: privacyMode,
        )
      : activityDesktopFixture(
          state: state,
          rows: rows,
          swapFeatureEnabled: swapFeatureEnabled,
          privacyMode: privacyMode,
        );
}

String activityScreenStateLabel(ActivityScreenState state) {
  return switch (state) {
    ActivityScreenState.rows => 'Rows',
    ActivityScreenState.loading => 'Loading',
    ActivityScreenState.empty => 'No activity',
    ActivityScreenState.error => 'Failed to load',
    ActivityScreenState.noAccount => 'No account',
  };
}

String activityRowSetLabel(ActivityRowSet rows) {
  return switch (rows) {
    ActivityRowSet.transactions => 'Transactions',
    ActivityRowSet.giftCards => 'Gift cards',
    ActivityRowSet.withSwapRows => 'With swap rows',
    ActivityRowSet.swapLegAbsorbed => 'Swap leg absorbed',
  };
}

// --- Transaction status ----------------------------------------------------

/// Message row on a receipt: absent, one truncated line, or opened out.
enum ActivityReceiptMessage { none, collapsed, expanded }

String activityReceiptMessageLabel(ActivityReceiptMessage message) {
  return switch (message) {
    ActivityReceiptMessage.none => 'None',
    ActivityReceiptMessage.collapsed => 'Collapsed',
    ActivityReceiptMessage.expanded => 'Expanded',
  };
}

/// The transaction receipt on both form factors. The counterparty axis only
/// reaches the From / To row on the kinds that have one; shielding, migration
/// and Gift Card receipts name their own two ends. `Message: Expanded` fires
/// the screen's own toggle on mount, since the expansion lives in private
/// state.
///
/// The two load seams are per layout: the desktop screen shows its loading and
/// not-found lines in the receipt's own slot, and only the phone prints a
/// refresh error — a failed desktop refresh silently drops the detail to the
/// fallback card, which is a screen defect rather than a state to preview.
Widget buildActivityTransactionStatusGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final kind = wbStateKnob<TxStatusKind>(
    context,
    label: 'Kind',
    options: TxStatusKind.values,
    labelBuilder: activityTxStatusKindLabel,
  );
  final phase = wbStateKnob<TxStatusPhase>(
    context,
    label: 'Phase',
    options: TxStatusPhase.values,
    initial: TxStatusPhase.succeeded,
    labelBuilder: activityTxStatusPhaseLabel,
  );
  final counterparty = wbStateKnob<TxStatusCounterparty>(
    context,
    label: 'Counterparty',
    options: TxStatusCounterparty.values,
    labelBuilder: activityTxStatusCounterpartyLabel,
  );
  final message = wbStateKnob<ActivityReceiptMessage>(
    context,
    label: 'Message',
    options: ActivityReceiptMessage.values,
    labelBuilder: activityReceiptMessageLabel,
  );
  final privacyMode = wbBoolKnob(context, label: 'Privacy mode');

  if (layout == WbLayout.mobile) {
    return mobileTransactionStatusFixture(
      kind: kind,
      phase: phase,
      counterparty: counterparty,
      message: message != ActivityReceiptMessage.none,
      messageExpanded: message == ActivityReceiptMessage.expanded,
      refreshFailed: wbBoolKnob(context, label: 'Refresh failed'),
      privacyMode: privacyMode,
    );
  }
  return activityTransactionStatusDesktopFixture(
    kind: kind,
    phase: phase,
    counterparty: counterparty,
    load: wbStateKnob<TxStatusLoad>(
      context,
      label: 'Load',
      options: TxStatusLoad.values,
      labelBuilder: activityTxStatusLoadLabel,
    ),
    message: message != ActivityReceiptMessage.none,
    messageExpanded: message == ActivityReceiptMessage.expanded,
    privacyMode: privacyMode,
  );
}

String activityTxStatusKindLabel(TxStatusKind kind) {
  return switch (kind) {
    TxStatusKind.sent => 'Sent',
    TxStatusKind.received => 'Received',
    TxStatusKind.shielded => 'Shielded',
    TxStatusKind.migration => 'Migration',
    TxStatusKind.giftCard => 'Gift card',
  };
}

String activityTxStatusPhaseLabel(TxStatusPhase phase) {
  return switch (phase) {
    TxStatusPhase.pending => 'Pending',
    TxStatusPhase.succeeded => 'Succeeded',
    TxStatusPhase.failed => 'Failed',
  };
}

String activityTxStatusLoadLabel(TxStatusLoad load) {
  return switch (load) {
    TxStatusLoad.loaded => 'Loaded',
    TxStatusLoad.loading => 'Loading',
    TxStatusLoad.failed => 'Failed to load',
  };
}

String activityTxStatusCounterpartyLabel(TxStatusCounterparty counterparty) {
  return switch (counterparty) {
    TxStatusCounterparty.contact => 'Contact',
    TxStatusCounterparty.ownAccount => 'Own account',
    TxStatusCounterparty.rawAddress => 'Raw address',
    TxStatusCounterparty.unknown => 'Unknown',
    TxStatusCounterparty.shieldedSender => 'Shielded sender',
  };
}

Widget buildActivityReceiveAbsorptionGalleryCase(BuildContext context) {
  return buildSwapReceiveAbsorbUseCase(context);
}

// --- Activity feed ---------------------------------------------------------

/// The feed itself, on props alone. Host swaps the two widget classes; the
/// header and width knobs are `ActivityFeed`-only props, so the sliver ignores
/// them the way the desktop screen does.
Widget buildActivityFeedGalleryCase(BuildContext context) {
  return activityFeedFixture(
    host: wbStateKnob<ActivityFeedHost>(
      context,
      label: 'Host',
      options: ActivityFeedHost.values,
      labelBuilder: activityFeedHostLabel,
    ),
    state: wbStateKnob<ActivityFeedBodyState>(
      context,
      label: 'State',
      options: ActivityFeedBodyState.values,
      labelBuilder: activityFeedBodyStateLabel,
    ),
    rows: wbStateKnob<ActivityFeedRowShape>(
      context,
      label: 'Rows',
      options: ActivityFeedRowShape.values,
      initial: ActivityFeedRowShape.threeRows,
      labelBuilder: activityFeedRowShapeLabel,
    ),
    width: wbStateKnob<ActivityFeedWidth>(
      context,
      label: 'Width',
      options: ActivityFeedWidth.values,
      labelBuilder: activityFeedWidthLabel,
    ),
    showHeader:
        wbStateKnob<ActivityFeedHeader>(
          context,
          label: 'Header',
          options: ActivityFeedHeader.values,
          labelBuilder: activityFeedHeaderLabel,
        ) ==
        ActivityFeedHeader.shown,
  );
}

/// The `showHeader` prop as a named axis.
enum ActivityFeedHeader { shown, hidden }

String activityFeedHostLabel(ActivityFeedHost host) {
  return switch (host) {
    ActivityFeedHost.column => 'Column',
    ActivityFeedHost.sliver => 'Sliver',
  };
}

String activityFeedBodyStateLabel(ActivityFeedBodyState state) {
  return switch (state) {
    ActivityFeedBodyState.rows => 'Rows',
    ActivityFeedBodyState.loading => 'Loading',
    ActivityFeedBodyState.empty => 'No activity',
    ActivityFeedBodyState.error => 'Failed to load',
  };
}

String activityFeedRowShapeLabel(ActivityFeedRowShape shape) {
  return switch (shape) {
    ActivityFeedRowShape.single => 'One row',
    ActivityFeedRowShape.threeRows => 'Three rows',
    ActivityFeedRowShape.withChildRow => 'With child row',
  };
}

String activityFeedWidthLabel(ActivityFeedWidth width) {
  return switch (width) {
    ActivityFeedWidth.desktopCard => 'Desktop card',
    ActivityFeedWidth.fullWidth => 'Full width',
  };
}

String activityFeedHeaderLabel(ActivityFeedHeader header) {
  return switch (header) {
    ActivityFeedHeader.shown => 'Shown',
    ActivityFeedHeader.hidden => 'Hidden',
  };
}

// --- Activity row ----------------------------------------------------------

/// One row on the feed card. Hover and pressed are the row's own internal
/// state with no prop behind them, so they are not options here.
Widget buildActivityRowGalleryCase(BuildContext context) {
  return activityRowFixture(
    interaction: wbStateKnob<ActivityRowInteraction>(
      context,
      label: 'Interaction',
      options: ActivityRowInteraction.values,
      labelBuilder: activityRowInteractionLabel,
    ),
    density: wbStateKnob<ActivityRowDensity>(
      context,
      label: 'Density',
      options: ActivityRowDensity.values,
      labelBuilder: activityRowDensityLabel,
    ),
    trailing: wbStateKnob<ActivityRowTrailing>(
      context,
      label: 'Trailing',
      options: ActivityRowTrailing.values,
      labelBuilder: activityRowTrailingLabel,
    ),
    status: wbStateKnob<ActivityRowStatus>(
      context,
      label: 'Status',
      options: ActivityRowStatus.values,
      labelBuilder: activityRowStatusLabel,
    ),
    background: wbStateKnob<ActivityRowBackground>(
      context,
      label: 'Background',
      options: ActivityRowBackground.values,
      labelBuilder: activityRowBackgroundLabel,
    ),
    childRow: wbBoolKnob(context, label: 'Child row'),
    privacyMode: wbBoolKnob(context, label: 'Privacy mode'),
  );
}

String activityRowInteractionLabel(ActivityRowInteraction interaction) {
  return switch (interaction) {
    ActivityRowInteraction.rest => 'Rest',
    ActivityRowInteraction.selected => 'Selected',
    ActivityRowInteraction.nonInteractive => 'Not tappable',
  };
}

String activityRowDensityLabel(ActivityRowDensity density) {
  return switch (density) {
    ActivityRowDensity.regular => 'Regular',
    ActivityRowDensity.compact => 'Compact',
  };
}

String activityRowTrailingLabel(ActivityRowTrailing trailing) {
  return switch (trailing) {
    ActivityRowTrailing.amount => 'Amount',
    ActivityRowTrailing.refund => 'Amount + refund icon',
    ActivityRowTrailing.timeout => 'Amount + timeout',
  };
}

String activityRowStatusLabel(ActivityRowStatus status) {
  return switch (status) {
    ActivityRowStatus.completed => 'Completed',
    ActivityRowStatus.inProgress => 'In progress',
    ActivityRowStatus.failed => 'Failed',
  };
}

String activityRowBackgroundLabel(ActivityRowBackground background) {
  return switch (background) {
    ActivityRowBackground.transparent => 'Default',
    ActivityRowBackground.filled => 'Override',
  };
}

// --- Transaction row mapper ------------------------------------------------

/// The transaction-to-row mapper. No Layout knob: the mapper's own desktop /
/// mobile difference is `kAppFormFactor`, so the compiled lane decides it and
/// a knob could not change what renders.
Widget buildActivityTransactionRowGalleryCase(BuildContext context) {
  return transactionActivityRowFixture(
    kind: wbStateKnob<ActivityTxRowKind>(
      context,
      label: 'Kind',
      options: ActivityTxRowKind.values,
      initial: ActivityTxRowKind.sent,
      labelBuilder: activityTxRowKindLabel,
    ),
    status: wbStateKnob<ActivityTxRowStatus>(
      context,
      label: 'Status',
      options: ActivityTxRowStatus.values,
      labelBuilder: activityTxRowStatusLabel,
    ),
    pool: wbStateKnob<ActivityTxRowPool>(
      context,
      label: 'Pool',
      options: ActivityTxRowPool.values,
      initial: ActivityTxRowPool.shielded,
      labelBuilder: activityTxRowPoolLabel,
    ),
    amount: wbStateKnob<ActivityTxRowAmount>(
      context,
      label: 'Amount',
      options: ActivityTxRowAmount.values,
      labelBuilder: activityTxRowAmountLabel,
    ),
    privacyMode: wbBoolKnob(context, label: 'Privacy mode'),
  );
}

String activityTxRowKindLabel(ActivityTxRowKind kind) {
  return switch (kind) {
    ActivityTxRowKind.received => 'Received',
    ActivityTxRowKind.receiving => 'Receiving',
    ActivityTxRowKind.sent => 'Sent',
    ActivityTxRowKind.shielded => 'Shielded',
    ActivityTxRowKind.migration => 'Migration',
    ActivityTxRowKind.giftCardCreated => 'Gift card created',
    ActivityTxRowKind.giftCardRedeemed => 'Gift card redeemed',
    ActivityTxRowKind.unknown => 'Unknown kind',
  };
}

String activityTxRowStatusLabel(ActivityTxRowStatus status) {
  return switch (status) {
    ActivityTxRowStatus.completed => 'Completed',
    ActivityTxRowStatus.inProgress => 'In progress',
    ActivityTxRowStatus.failed => 'Failed, expired',
  };
}

String activityTxRowPoolLabel(ActivityTxRowPool pool) {
  return switch (pool) {
    ActivityTxRowPool.transparent => 'Transparent',
    ActivityTxRowPool.shielded => 'Shielded',
    ActivityTxRowPool.ironwood => 'Ironwood',
    ActivityTxRowPool.mixed => 'Mixed',
    ActivityTxRowPool.none => 'None',
  };
}

String activityTxRowAmountLabel(ActivityTxRowAmount amount) {
  return switch (amount) {
    ActivityTxRowAmount.value => 'Value',
    ActivityTxRowAmount.zero => 'Zero',
  };
}

// --- Swap row mapper -------------------------------------------------------

/// The swap-intent-to-row mapper. Pay copy needs the ZEC-to-asset direction,
/// which is how the send side reads a payment; the asset-to-ZEC leg is always
/// a swap.
Widget buildActivitySwapRowGalleryCase(BuildContext context) {
  return swapActivityRowFixture(
    status: wbStateKnob<SwapIntentStatus>(
      context,
      label: 'Status',
      options: SwapIntentStatus.values,
      initial: SwapIntentStatus.complete,
      labelBuilder: activitySwapRowStatusLabel,
    ),
    mode: wbStateKnob<ActivitySwapRowMode>(
      context,
      label: 'Mode',
      options: ActivitySwapRowMode.values,
      labelBuilder: activitySwapRowModeLabel,
    ),
    direction: wbStateKnob<ActivitySwapRowDirection>(
      context,
      label: 'Direction',
      options: ActivitySwapRowDirection.values,
      labelBuilder: activitySwapRowDirectionLabel,
    ),
    receivedLeg: wbStateKnob<ActivitySwapRowReceivedLeg>(
      context,
      label: 'Received leg',
      options: ActivitySwapRowReceivedLeg.values,
      labelBuilder: activitySwapRowReceivedLegLabel,
    ),
    privacyMode: wbBoolKnob(context, label: 'Privacy mode'),
  );
}

String activitySwapRowStatusLabel(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit => 'Awaiting deposit',
    SwapIntentStatus.awaitingExternalDeposit => 'Awaiting external deposit',
    SwapIntentStatus.depositObserved => 'Deposit observed',
    SwapIntentStatus.processing => 'Processing',
    SwapIntentStatus.providerStatusUnknown => 'Checking status',
    SwapIntentStatus.incompleteDeposit => 'Incomplete deposit',
    SwapIntentStatus.complete => 'Completed',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Timed out',
    SwapIntentStatus.failed => 'Failed',
  };
}

String activitySwapRowModeLabel(ActivitySwapRowMode mode) {
  return switch (mode) {
    ActivitySwapRowMode.swap => 'Swap',
    ActivitySwapRowMode.pay => 'Pay',
  };
}

String activitySwapRowDirectionLabel(ActivitySwapRowDirection direction) {
  return switch (direction) {
    ActivitySwapRowDirection.zecToAsset => 'ZEC to asset',
    ActivitySwapRowDirection.assetToZec => 'Asset to ZEC',
  };
}

String activitySwapRowReceivedLegLabel(ActivitySwapRowReceivedLeg leg) {
  return switch (leg) {
    ActivitySwapRowReceivedLeg.absent => 'Absent',
    ActivitySwapRowReceivedLeg.present => 'Present',
  };
}

// --- Received receipt ------------------------------------------------------

Widget buildActivityReceivedReceiptGalleryCase(BuildContext context) {
  final status = wbStateKnob<ReceivedReceiptStatus>(
    context,
    label: 'Status',
    options: ReceivedReceiptStatus.values,
    initial: ReceivedReceiptStatus.completed,
    labelBuilder: activityReceiptStatusLabel,
  );
  final from = wbStateKnob<ReceivedReceiptFromSource>(
    context,
    label: 'From',
    options: ReceivedReceiptFromSource.values,
    labelBuilder: activityReceiptFromLabel,
  );
  final pool = wbStateKnob<ReceivedReceiptReceivingPool>(
    context,
    label: 'Received on',
    options: ReceivedReceiptReceivingPool.values,
    labelBuilder: activityReceiptPoolLabel,
  );
  final memo = wbStateKnob<ActivityReceiptMessage>(
    context,
    label: 'Message',
    options: ActivityReceiptMessage.values,
    initial: ActivityReceiptMessage.collapsed,
    labelBuilder: activityReceiptMessageLabel,
  );
  final fee = wbBoolKnob(context, label: 'Network fee', initial: true);

  return receivedReceiptFixture(
    status: status,
    from: from,
    receivingPool: pool,
    memo: memo != ActivityReceiptMessage.none,
    memoExpanded: memo == ActivityReceiptMessage.expanded,
    fee: fee,
  );
}

// --- Shielded receipt ------------------------------------------------------

Widget buildActivityShieldedReceiptGalleryCase(BuildContext context) {
  final message = wbStateKnob<ActivityReceiptMessage>(
    context,
    label: 'Message',
    options: ActivityReceiptMessage.values,
    labelBuilder: activityReceiptMessageLabel,
  );
  return shieldedReceiptFixture(
    status: wbStateKnob<ShieldedReceiptStatus>(
      context,
      label: 'Status',
      options: ShieldedReceiptStatus.values,
      initial: ShieldedReceiptStatus.completed,
      labelBuilder: activityShieldedReceiptStatusLabel,
    ),
    fee: wbBoolKnob(context, label: 'Network fee', initial: true),
    memo: message != ActivityReceiptMessage.none,
    memoExpanded: message == ActivityReceiptMessage.expanded,
  );
}

String activityShieldedReceiptStatusLabel(ShieldedReceiptStatus status) {
  return switch (status) {
    ShieldedReceiptStatus.inProgress => 'In progress',
    ShieldedReceiptStatus.completed => 'Completed',
    ShieldedReceiptStatus.failed => 'Failed',
  };
}

String activityReceiptStatusLabel(ReceivedReceiptStatus status) {
  return switch (status) {
    ReceivedReceiptStatus.completed => 'Completed',
    ReceivedReceiptStatus.inProgress => 'In progress',
    ReceivedReceiptStatus.failed => 'Failed',
  };
}

String activityReceiptFromLabel(ReceivedReceiptFromSource from) {
  return switch (from) {
    ReceivedReceiptFromSource.transparentAddress => 'Transparent address',
    ReceivedReceiptFromSource.contact => 'Contact',
    ReceivedReceiptFromSource.shieldedSender => 'Shielded sender',
    ReceivedReceiptFromSource.unknownSender => 'Unknown sender',
  };
}

String activityReceiptPoolLabel(ReceivedReceiptReceivingPool pool) {
  return switch (pool) {
    ReceivedReceiptReceivingPool.transparent => 'Transparent',
    ReceivedReceiptReceivingPool.shielded => 'Shielded',
  };
}

// --- Gift card detail ------------------------------------------------------

enum ActivityGiftCardKind { created, redeemed }

Widget buildActivityGiftCardDetailGalleryCase(BuildContext context) {
  final kind = wbStateKnob<ActivityGiftCardKind>(
    context,
    label: 'Kind',
    options: ActivityGiftCardKind.values,
    labelBuilder: activityGiftCardKindLabel,
  );
  final message = wbStateKnob<ActivityReceiptMessage>(
    context,
    label: 'Message',
    options: ActivityReceiptMessage.values,
    initial: ActivityReceiptMessage.collapsed,
    labelBuilder: activityReceiptMessageLabel,
  );
  final fiat = wbBoolKnob(context, label: 'Fiat value', initial: true);

  return giftCardActivityDetailFixture(
    context,
    kind: kind == ActivityGiftCardKind.created
        ? GiftCardActivityKind.created
        : GiftCardActivityKind.redeemed,
    artwork: wbStateKnob<PaymentLinkCardArtwork>(
      context,
      label: 'Artwork',
      options: PaymentLinkCardArtwork.values,
      initial: PaymentLinkCardArtwork.ruby,
      labelBuilder: activityGiftCardArtworkLabel,
    ),
    status: wbStateKnob<GiftCardActivityDetailStatus>(
      context,
      label: 'Status',
      options: GiftCardActivityDetailStatus.values,
      initial: GiftCardActivityDetailStatus.completed,
      labelBuilder: activityGiftCardStatusLabel,
    ),
    message: message == ActivityReceiptMessage.none
        ? null
        : 'Hope this makes your day a little brighter!',
    messageExpanded: message == ActivityReceiptMessage.expanded,
    supportingText: fiat ? r'$142.23' : null,
  );
}

String activityGiftCardStatusLabel(GiftCardActivityDetailStatus status) {
  return switch (status) {
    GiftCardActivityDetailStatus.inProgress => 'In progress',
    GiftCardActivityDetailStatus.completed => 'Completed',
    GiftCardActivityDetailStatus.failed => 'Failed',
  };
}

String activityGiftCardArtworkLabel(PaymentLinkCardArtwork artwork) =>
    artwork.semanticLabel;

String activityGiftCardKindLabel(ActivityGiftCardKind kind) {
  return switch (kind) {
    ActivityGiftCardKind.created => 'Created',
    ActivityGiftCardKind.redeemed => 'Redeemed',
  };
}

// --- Swap detail screen ----------------------------------------------------

String activitySwapDetailStatusLabel(SwapDetailStatus status) {
  return switch (status) {
    SwapDetailStatus.awaitingDeposit => 'Awaiting deposit',
    SwapDetailStatus.processing => 'Processing',
    SwapDetailStatus.complete => 'Complete',
    SwapDetailStatus.expired => 'Expired',
    SwapDetailStatus.failed => 'Failed',
  };
}

String activitySwapDetailModeLabel(SwapDetailMode mode) {
  return mode == SwapDetailMode.swap ? 'Swap' : 'Payment';
}

String activitySwapDetailIntentLabel(SwapDetailIntentCase intentCase) {
  return intentCase == SwapDetailIntentCase.present ? 'Present' : 'Missing';
}

Widget buildActivitySwapDetailScreenGalleryCase(BuildContext context) {
  return swapDetailScreenFixture(
    layout: wbLayoutKnob(context),
    status: wbStateKnob<SwapDetailStatus>(
      context,
      label: 'Status',
      options: SwapDetailStatus.values,
      initial: SwapDetailStatus.processing,
      labelBuilder: activitySwapDetailStatusLabel,
    ),
    mode: wbStateKnob<SwapDetailMode>(
      context,
      label: 'Mode',
      options: SwapDetailMode.values,
      labelBuilder: activitySwapDetailModeLabel,
    ),
    intentCase: wbStateKnob<SwapDetailIntentCase>(
      context,
      label: 'Intent',
      options: SwapDetailIntentCase.values,
      labelBuilder: activitySwapDetailIntentLabel,
    ),
  );
}

// --- Shielding message -----------------------------------------------------

String homeShieldMessageLabel(HomeShieldMessage message) {
  return switch (message) {
    HomeShieldMessage.noActiveAccount => 'No active account',
    HomeShieldMessage.passphraseUnavailable => 'No secret passphrase',
    HomeShieldMessage.syncRequired => 'Sync not finished',
    HomeShieldMessage.balanceTooSmall => 'Balance too small',
    HomeShieldMessage.broadcastFailed => "Couldn't broadcast",
    HomeShieldMessage.genericFailure => "Couldn't shield",
    HomeShieldMessage.queuedForRetry => 'Queued for retry',
    HomeShieldMessage.hardwareBroadcastUnknown => 'Confirmation timed out',
    HomeShieldMessage.hardwareStorageFailed => 'Not stored locally',
    HomeShieldMessage.hardwareStatusUncertain => 'Status uncertain',
  };
}

// --- Keystone shielding ----------------------------------------------------

/// The shield signing surface on both form factors, driven through its
/// preparation seam: preparation is the only thing that moves before the
/// device answers, and everything past the scan needs a real broadcast.
///
/// The two stage lists are separate enums — only the phone turns into the
/// signature scanner in place — so `Stage` is declared per layout.
Widget buildHomeKeystoneShieldGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  if (layout == WbLayout.mobile) {
    return homeKeystoneShieldMobileFixture(
      stage: wbStateKnob<HomeKeystoneShieldMobileStage>(
        context,
        label: 'Stage',
        options: HomeKeystoneShieldMobileStage.values,
        initial: HomeKeystoneShieldMobileStage.qrReady,
        labelBuilder: homeKeystoneShieldMobileStageLabel,
      ),
    );
  }
  return homeKeystoneShieldDesktopFixture(
    stage: wbStateKnob<HomeKeystoneShieldDesktopStage>(
      context,
      label: 'Stage',
      options: HomeKeystoneShieldDesktopStage.values,
      initial: HomeKeystoneShieldDesktopStage.qrReady,
      labelBuilder: homeKeystoneShieldDesktopStageLabel,
    ),
  );
}

String homeKeystoneShieldDesktopStageLabel(
  HomeKeystoneShieldDesktopStage stage,
) {
  return switch (stage) {
    HomeKeystoneShieldDesktopStage.preparing => 'Preparing',
    HomeKeystoneShieldDesktopStage.qrReady => 'QR ready',
    HomeKeystoneShieldDesktopStage.failed => 'Failed',
  };
}

String homeKeystoneShieldMobileStageLabel(HomeKeystoneShieldMobileStage stage) {
  return switch (stage) {
    HomeKeystoneShieldMobileStage.preparing => 'Preparing',
    HomeKeystoneShieldMobileStage.qrReady => 'QR ready',
    HomeKeystoneShieldMobileStage.scanning => 'Scanning signature',
    HomeKeystoneShieldMobileStage.failed => 'Failed',
  };
}

Widget buildHomeShieldMessageGalleryCase(BuildContext context) {
  return homeShieldMessageFixture(
    message: wbStateKnob<HomeShieldMessage>(
      context,
      label: 'Message',
      options: HomeShieldMessage.values,
      labelBuilder: homeShieldMessageLabel,
    ),
  );
}
