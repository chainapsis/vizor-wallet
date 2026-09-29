// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/features/onboarding/mobile/passcode_widgets.dart';
import '../src/core/widgets/biometric_icon.dart';
import '../src/features/onboarding/mobile/mobile_passcode_layout.dart';
import '../src/services/biometric_unlock.dart';

enum PasscodePreviewState { create, confirm, enter, unlock, remove }

enum PasscodePreviewViewport {
  design(
    'Figma · 393 × 852',
    Size(393, 852),
    EdgeInsets.only(top: 55, bottom: 24),
  ),
  ipad(
    'iPad mini compatibility · 375 × 667',
    Size(375, 667),
    EdgeInsets.only(top: 20, bottom: 25),
  ),
  ipadPro13(
    'iPad Pro 13 compatibility · 390 × 844',
    Size(390, 844),
    EdgeInsets.only(top: 20, bottom: 25),
  ),
  small('Small phone · 320 × 568', Size(320, 568), EdgeInsets.only(top: 20));

  const PasscodePreviewViewport(this.label, this.size, this.padding);
  final String label;
  final Size size;
  final EdgeInsets padding;
}

Widget buildMobilePasscodeOptions(
  BuildContext context, {
  PasscodePreviewState initialState = PasscodePreviewState.create,
  List<PasscodePreviewState> states = const [
    PasscodePreviewState.create,
    PasscodePreviewState.confirm,
    PasscodePreviewState.enter,
    PasscodePreviewState.remove,
  ],
  BiometricKind biometricKind = BiometricKind.face,
  bool initialBiometric = false,
}) {
  if (WidgetbookState.maybeOf(context) == null) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: PasscodePreviewViewport.design.padding,
        viewPadding: PasscodePreviewViewport.design.padding,
      ),
      child: PasscodeLayoutPreview(
        state: initialState,
        biometric: initialBiometric,
        biometricKind: biometricKind,
      ),
    );
  }
  final viewport = context.knobs.object.dropdown(
    label: 'Viewport',
    options: PasscodePreviewViewport.values,
    initialOption: PasscodePreviewViewport.design,
    labelBuilder: (v) => v.label,
  );
  final state = context.knobs.object.dropdown(
    label: 'Screen',
    options: states,
    initialOption: initialState,
    labelBuilder: (s) => s.name,
  );
  final scale = context.knobs.object.dropdown<double>(
    label: 'Text scale',
    options: [1, 1.3, 1.5, 2, 3],
    initialOption: 1,
  );
  final biometric = context.knobs.boolean(
    label: 'Biometric footer',
    initialValue: initialBiometric,
  );
  final error = context.knobs.boolean(
    label: 'Error message',
    initialValue: false,
  );
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SingleChildScrollView(
      child: SizedBox.fromSize(
        size: viewport.size,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: viewport.size,
            padding: viewport.padding,
            viewPadding: viewport.padding,
            textScaler: TextScaler.linear(scale),
          ),
          child: ClipRect(
            child: PasscodeLayoutPreview(
              key: ValueKey(state),
              state: state,
              biometric: biometric,
              biometricKind: biometricKind,
              showError: error,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Interactive, in-memory visual fixture. Six digits never create, unlock,
/// remove, or reset a wallet.
class PasscodeLayoutPreview extends StatefulWidget {
  const PasscodeLayoutPreview({
    this.state = PasscodePreviewState.create,
    this.biometric = false,
    this.biometricKind = BiometricKind.face,
    this.showError = false,
    this.initialFilled = 0,
    super.key,
  });
  final PasscodePreviewState state;
  final bool biometric;
  final BiometricKind biometricKind;
  final bool showError;
  final int initialFilled;
  @override
  State<PasscodeLayoutPreview> createState() => _PasscodeLayoutPreviewState();
}

class _PasscodeLayoutPreviewState extends State<PasscodeLayoutPreview> {
  late int _filled = widget.initialFilled;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isUnlock = state == PasscodePreviewState.unlock;
    return MobilePasscodeLayout(
      title: switch (state) {
        PasscodePreviewState.create => 'Create Passcode',
        PasscodePreviewState.confirm => 'Confirm Passcode',
        PasscodePreviewState.unlock => 'Welcome Back',
        _ => 'Enter Passcode',
      },
      subtitle: switch (state) {
        PasscodePreviewState.create ||
        PasscodePreviewState.confirm => '6 digits length',
        PasscodePreviewState.unlock => 'Enter your passcode to open Vizor',
        PasscodePreviewState.remove =>
          'Enter your passcode to remove this account.',
        _ => 'Confirm your access',
      },
      navigation: isUnlock
          ? null
          : state == PasscodePreviewState.create
          ? MobileTopNav.steps(progress: 0.3, onBack: () {})
          : MobileTopNav.back(title: '', onBack: () {}),
      filled: _filled,
      error: widget.showError
          ? "Couldn't check your passcode. Please try again."
          : null,
      onDigit: (_) => setState(() => _filled = (_filled + 1).clamp(0, 6)),
      onBackspace: () => setState(() => _filled = (_filled - 1).clamp(0, 6)),
      onHelp: isUnlock ? () {} : null,
      footer: widget.biometric && state != PasscodePreviewState.remove
          ? PasscodeBiometricButton(
              wrapLabel: true,
              label: widget.biometricKind.signInLabel,
              icon: BiometricIcon(kind: widget.biometricKind, size: 16),
              onPressed: () {},
            )
          : null,
    );
  }
}

Widget _capture(BuildContext context, PasscodePreviewState state) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: PasscodePreviewViewport.design.padding,
    viewPadding: PasscodePreviewViewport.design.padding,
  ),
  child: PasscodeLayoutPreview(
    state: state,
    initialFilled: state == PasscodePreviewState.confirm ? 1 : 0,
  ),
);
Widget buildPasscodeCreateCapture(BuildContext context) =>
    _capture(context, PasscodePreviewState.create);
Widget buildPasscodeEnterCapture(BuildContext context) =>
    _capture(context, PasscodePreviewState.enter);
Widget buildPasscodeConfirmCapture(BuildContext context) =>
    _capture(context, PasscodePreviewState.confirm);

Widget buildPasscodeIpadCapture(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: PasscodePreviewViewport.ipad.padding,
    viewPadding: PasscodePreviewViewport.ipad.padding,
  ),
  child: const PasscodeLayoutPreview(
    state: PasscodePreviewState.enter,
    biometric: true,
  ),
);
Widget buildPasscodeSmallErrorCapture(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: PasscodePreviewViewport.small.padding,
    viewPadding: PasscodePreviewViewport.small.padding,
    textScaler: const TextScaler.linear(1.5),
  ),
  child: const PasscodeLayoutPreview(
    state: PasscodePreviewState.confirm,
    showError: true,
    biometric: true,
  ),
);
