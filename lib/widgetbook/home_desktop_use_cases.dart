// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/home/widgets/home_desktop_preview.dart';

Widget buildHomeDesktopImportingUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.importing);
}

Widget buildHomeDesktopNoBalanceUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.noBalance);
}

Widget buildHomeDesktopNoActivityUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.noActivity);
}

Widget buildHomeDesktopDefaultUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.activity);
}

Widget buildHomeDesktopKeystoneUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.keystone);
}

Widget buildHomeDesktopAccountsUseCase(BuildContext context) {
  return const _HomeDesktopHarness(state: HomeDesktopPreviewState.accounts);
}

Widget buildHomeDesktopAccountsScrollUseCase(BuildContext context) {
  return const _HomeDesktopHarness(
    state: HomeDesktopPreviewState.accounts,
    accountCount: 8,
  );
}

Widget buildHomeDesktopPasswordRecoveryNoticeUseCase(BuildContext context) {
  return const _HomeDesktopHarness(
    state: HomeDesktopPreviewState.activity,
    notice: HomeDesktopPreviewNotice.passwordRecovery,
  );
}

Widget buildHomeDesktopShieldQueuedNoticeUseCase(BuildContext context) {
  return const _HomeDesktopHarness(
    state: HomeDesktopPreviewState.activity,
    notice: HomeDesktopPreviewNotice.shieldQueued,
  );
}

Widget buildHomeDesktopSyncFailureNoticeUseCase(BuildContext context) {
  return const _HomeDesktopHarness(
    state: HomeDesktopPreviewState.activity,
    notice: HomeDesktopPreviewNotice.syncFailure,
  );
}

class _HomeDesktopHarness extends StatelessWidget {
  const _HomeDesktopHarness({
    required this.state,
    this.notice = HomeDesktopPreviewNotice.none,
    this.accountCount = 4,
  });

  final HomeDesktopPreviewState state;
  final HomeDesktopPreviewNotice notice;
  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.window,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : HomeDesktopPreview.size.width;
          final maxHeight =
              constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : HomeDesktopPreview.size.height;
          final contentWidth = math.max(320.0, maxWidth);
          final contentHeight = math.max(240.0, maxHeight);
          final scale = math.min(
            contentWidth / HomeDesktopPreview.size.width,
            contentHeight / HomeDesktopPreview.size.height,
          );

          return Center(
            child: SizedBox(
              width: HomeDesktopPreview.size.width * scale,
              height: HomeDesktopPreview.size.height * scale,
              child: FittedBox(
                fit: BoxFit.contain,
                child: HomeDesktopPreview(
                  state: state,
                  notice: notice,
                  accountCount: accountCount,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
