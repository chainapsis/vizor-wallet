import 'package:flutter/widgets.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/activity/activity_row_mapper.dart';
import '../src/features/activity/widgets/activity_feed.dart';
import '../src/rust/api/sync.dart' as rust;

Widget activitySkeletonCapture(BuildContext context) =>
    activityPaginationCapture(context, loading: true);
Widget activityLoadedCapture(BuildContext context) =>
    activityPaginationCapture(context);
Widget activityAppendCapture(BuildContext context) =>
    activityPaginationCapture(context, appending: true);

/// Deterministic, local-only captures of the production Activity sliver.
Widget activityPaginationCapture(
  BuildContext context, {
  bool loading = false,
  bool appending = false,
}) {
  const mobile = kAppFormFactor == AppFormFactor.mobile;
  return ColoredBox(
    color: context.colors.background.window,
    child: Column(
      children: [
        if (mobile) MobileTopNav.back(title: 'Activity'),
        Expanded(
          child: Center(
            child: SizedBox(
              width: mobile ? null : 420,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(
                      left: mobile ? AppSpacing.xxs : 0,
                      right: mobile ? AppSpacing.xxs : 0,
                      top: mobile ? AppSpacing.s : 48 + AppSpacing.sm,
                    ),
                    sliver: ActivityFeedSliver(
                      showHeader: !mobile,
                      cardWidth: mobile ? null : 396,
                      isLoading: loading,
                      isLoadingMore: appending,
                      sections: loading
                          ? const []
                          : [
                              ActivityFeedSectionData(
                                title: 'This week',
                                rows: List.generate(
                                  5,
                                  (i) => buildTransactionActivityRow(
                                    context: context,
                                    transaction: rust.TransactionInfo(
                                      txidHex: 'capture-$i',
                                      minedHeight: BigInt.from(100 + i),
                                      expiredUnmined: false,
                                      accountBalanceDelta: 100000000,
                                      fee: BigInt.zero,
                                      feeState: rust
                                          .TransactionFeeState
                                          .notApplicable,
                                      detailsComplete: true,
                                      provisional: false,
                                      amountIncludesFee: false,
                                      blockTime: BigInt.from(
                                        1792756800 - i * 60,
                                      ),
                                      createdTime: BigInt.zero,
                                      isTransparent: false,
                                      txKind: 'received',
                                      displayAmount: BigInt.from(100000000),
                                      displayPool: 'shielded',
                                    ),
                                    privacyModeEnabled: false,
                                    onTap: () {},
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
        ),
      ],
    ),
  );
}
