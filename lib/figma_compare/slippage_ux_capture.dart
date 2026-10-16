import 'package:flutter/widgets.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/swap/widgets/mobile/mobile_swap_slippage_stepper_modal.dart';
import '../src/features/swap/widgets/swap_slippage_modal.dart';
import '../widgetbook/pay_use_cases.dart';
import '../widgetbook/swap_use_cases.dart';

Widget buildSwapSlippageLowDesktopCapture(BuildContext context) =>
    _DesktopSlippageCapture(slippageBps: 50, context: context);

Widget buildSwapSlippageDefaultDesktopCapture(BuildContext context) =>
    _DesktopSlippageCapture(slippageBps: 200, context: context);

Widget buildPaySlippageLowDesktopCapture(BuildContext context) =>
    _DesktopSlippageCapture(
      slippageBps: 50,
      context: context,
      paymentMode: true,
    );

Widget buildPaySlippageDefaultDesktopCapture(BuildContext context) =>
    _DesktopSlippageCapture(
      slippageBps: 200,
      context: context,
      paymentMode: true,
    );

Widget buildSwapSlippageLowDesktopTextScale2Capture(BuildContext context) =>
    _DesktopSlippageCapture(
      slippageBps: 50,
      context: context,
      modalTextScale: 2,
    );

Widget buildSwapSlippageLowMobileCapture(BuildContext context) =>
    const _MobileSlippageCapture(slippageBps: 50);

Widget buildSwapSlippageDefaultMobileCapture(BuildContext context) =>
    const _MobileSlippageCapture(slippageBps: 200);

Widget buildPaySlippageLowMobileCapture(BuildContext context) =>
    const _MobileSlippageCapture(slippageBps: 50, paymentMode: true);

Widget buildPaySlippageDefaultMobileCapture(BuildContext context) =>
    const _MobileSlippageCapture(slippageBps: 200, paymentMode: true);

Widget buildSwapSlippageLowMobileTextScale2Capture(BuildContext context) =>
    _withTextScale(context, 2, const _MobileSlippageCapture(slippageBps: 50));

Widget buildPaySlippageLowMobileTextScale2Capture(BuildContext context) =>
    _withTextScale(
      context,
      2,
      const _MobileSlippageCapture(slippageBps: 50, paymentMode: true),
    );

Widget _withTextScale(BuildContext context, double scale, Widget child) =>
    MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    );

class _DesktopSlippageCapture extends StatelessWidget {
  const _DesktopSlippageCapture({
    required this.slippageBps,
    required this.context,
    this.modalTextScale,
    this.paymentMode = false,
  });

  final int slippageBps;
  final BuildContext context;
  final double? modalTextScale;
  final bool paymentMode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        paymentMode
            ? buildPayAmountValueUnfocusedUseCase(this.context)
            : buildSwapPageFigmaNode3UseCase(this.context),
        Padding(
          padding: EdgeInsets.only(
            left: appDesktopPaneLeftInset(kAppDesktopSidebarWidth),
            right: kAppDesktopShellMargin,
            top: kAppDesktopShellMargin,
            bottom: kAppDesktopShellMargin,
          ),
          child: Stack(
            children: [
              AppPaneModalOverlay(onDismiss: _noop, child: _modal(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modal(BuildContext context) {
    final modal = SwapSlippageModal(
      slippageBps: slippageBps,
      confidential: false,
      onConfidentialChanged: (_) {},
      paymentMode: paymentMode,
      onSubmitted: _ignoreBps,
      onCancel: _noop,
    );
    final scale = modalTextScale;
    return scale == null ? modal : _withTextScale(context, scale, modal);
  }
}

class _MobileSlippageCapture extends StatelessWidget {
  const _MobileSlippageCapture({
    required this.slippageBps,
    this.paymentMode = false,
  });

  final int slippageBps;
  final bool paymentMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => ColoredBox(
        color: colors.background.neutralScrim,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: MobileModalCard(
                child: MobileSwapSlippageStepperModal(
                  slippageBps: slippageBps,
                  confidential: false,
                  onConfidentialChanged: (_) {},
                  paymentMode: paymentMode,
                  onSubmitted: _ignoreBps,
                  onCancel: _noop,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _ignoreBps(int _) {}

void _noop() {}
