import 'package:flutter/widgets.dart';

import '../widgetbook/screen_use_cases.dart';

Widget buildMobileHomeTenTransactionsCapture(BuildContext context) =>
    buildMobileHomeRecentActivityReviewUseCase(context);

Widget buildMobileHomeTenSwapsCapture(BuildContext context) =>
    buildMobileHomeRecentActivityReviewUseCase(
      context,
      withSwapChildRows: true,
    );

Widget buildMobileHomeReportedCapture(BuildContext context) =>
    buildMobileHomeRecentActivityReviewUseCase(
      context,
      matchReportedScreenshot: true,
    );

Widget buildMobileHomeLongContentCapture(BuildContext context) =>
    buildMobileHomeRecentActivityReviewUseCase(context, withLongContent: true);
