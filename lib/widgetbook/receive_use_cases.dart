// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/receive/widgets/receive_desktop_preview.dart';

Widget buildReceiveDesktopShieldedUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.shielded,
  );
}

Widget buildReceiveDesktopTransparentUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.transparent,
  );
}

Widget buildReceiveDesktopShieldedModalUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.shieldedModal,
  );
}

Widget buildReceiveDesktopTransparentModalUseCase(BuildContext context) {
  return const _ReceiveDesktopHarness(
    state: ReceiveDesktopPreviewState.transparentModal,
  );
}

class _ReceiveDesktopHarness extends StatelessWidget {
  const _ReceiveDesktopHarness({required this.state});

  final ReceiveDesktopPreviewState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.window,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : ReceiveDesktopPreview.size.width;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : ReceiveDesktopPreview.size.height;
          final contentWidth = math.max(320.0, maxWidth);
          final contentHeight = math.max(240.0, maxHeight);
          final scale = math.min(
            contentWidth / ReceiveDesktopPreview.size.width,
            contentHeight / ReceiveDesktopPreview.size.height,
          );

          return Center(
            child: SizedBox(
              width: ReceiveDesktopPreview.size.width * scale,
              height: ReceiveDesktopPreview.size.height * scale,
              child: FittedBox(
                fit: BoxFit.contain,
                child: ReceiveDesktopPreview(state: state),
              ),
            ),
          );
        },
      ),
    );
  }
}
