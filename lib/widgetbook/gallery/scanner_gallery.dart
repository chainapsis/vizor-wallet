// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../scanner_use_cases.dart';
import '../support/wb_state.dart';

/// The Scanning gallery: the camera-owning surfaces that have no other home.
///
/// One component per host, because the hosts are different screens rather than
/// form factors of one surface: the shared card, the two desktop Keystone scan
/// screens whose flows register no scan entry, and the two bare scanner views
/// the rest of the app embeds.
///
/// Two more scanning surfaces are built here but registered by the flow that
/// already owns the screen, so neither appears twice (one surface, one entry):
/// [buildScannerKeystoneOnboardingGalleryCase] belongs to
/// `Screens > Keystone > Scan`, and [buildScannerMigrationGalleryCase] is the
/// `Scanning` option on the migration Keystone-sign `Stage` knob.
///
/// No component here takes a `Layout` knob: each is one widget class with one
/// form factor, so there is no desktop/mobile pair to fold.
///
/// All of them render against the camera and UR-decode fakes in
/// `support/wb_fake_scanner_platform.dart`, so no preview opens the host's
/// real camera.
final List<WidgetbookNode> scannerGalleryNodes = [
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Keystone scanner card',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildScannerKeystoneCardGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'QR scanner views',
        useCases: [
          WidgetbookUseCase(
            name: 'Plain QR',
            builder: buildScannerPlainViewGalleryCase,
          ),
          WidgetbookUseCase(
            name: 'Animated UR',
            builder: buildScannerAnimatedUrViewGalleryCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Send Keystone scan',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildScannerKeystoneSendGalleryCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Voting Keystone scan',
        useCases: [
          WidgetbookUseCase(
            name: 'Playground',
            builder: buildScannerKeystoneVotingGalleryCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Shared knobs -----------------------------------------------------------

const String kScannerCameraKnob = 'Camera';
const String kScannerCameraListKnob = 'Cameras found';
const String kScannerCardOverlayKnob = 'Overlay';
const String kScannerCardScanKnob = 'Scan';
const String kScannerScreenScanKnob = 'Scan';
const String kScannerCardErrorKnob = 'Scan error';
const String kScannerSidebarKnob = 'Sidebar';
const String kScannerSendExpectedKnob = 'Expected code';
const String kScannerMigrationStepKnob = 'Signing step';
const String kScannerViewFrameKnob = 'Preview box';
const String kScannerViewErrorKnob = 'Error view';

ScannerCameraCase _cameraKnob(BuildContext context) {
  return wbStateKnob<ScannerCameraCase>(
    context,
    label: kScannerCameraKnob,
    options: ScannerCameraCase.values,
    labelBuilder: scannerCameraCaseLabel,
  );
}

String scannerCameraCaseLabel(ScannerCameraCase camera) {
  return switch (camera) {
    ScannerCameraCase.live => 'Live feed',
    ScannerCameraCase.requesting => 'Requesting access',
    ScannerCameraCase.denied => 'Access denied',
    ScannerCameraCase.unavailable => 'Camera unavailable',
  };
}

String scannerCameraListCaseLabel(ScannerCameraListCase cameras) {
  return switch (cameras) {
    ScannerCameraListCase.noneFound => 'None found',
    ScannerCameraListCase.one => 'One camera',
    ScannerCameraListCase.two => 'Two cameras',
  };
}

String scannerCardOverlayCaseLabel(ScannerCardOverlayCase overlay) {
  return switch (overlay) {
    ScannerCardOverlayCase.none => 'None',
    ScannerCardOverlayCase.cameraPicker => 'Camera picker',
    ScannerCardOverlayCase.troubleScanning => 'Trouble scanning',
  };
}

String scannerCardScanCaseLabel(ScannerCardScanCase scan) {
  return switch (scan) {
    ScannerCardScanCase.waiting => 'Nothing scanned',
    ScannerCardScanCase.readingCode => 'Reading a multi-part code',
    ScannerCardScanCase.decoding => 'Decoding the result',
  };
}

String scannerScreenScanCaseLabel(ScannerScreenScanCase scan) {
  return switch (scan) {
    ScannerScreenScanCase.waiting => 'Nothing scanned',
    ScannerScreenScanCase.readingCode => 'Reading a multi-part code',
    ScannerScreenScanCase.wrongCode => 'Wrong code shown',
    ScannerScreenScanCase.unreadable => 'Code will not decode',
  };
}

ScannerScreenScanCase _screenScanKnob(
  BuildContext context, {
  List<ScannerScreenScanCase> options = ScannerScreenScanCase.values,
}) {
  return wbStateKnob<ScannerScreenScanCase>(
    context,
    label: kScannerScreenScanKnob,
    options: options,
    labelBuilder: scannerScreenScanCaseLabel,
  );
}

// --- Keystone scanner card --------------------------------------------------

Widget buildScannerKeystoneCardGalleryCase(BuildContext context) {
  final camera = _cameraKnob(context);
  final cameras = wbStateKnob<ScannerCameraListCase>(
    context,
    label: kScannerCameraListKnob,
    options: ScannerCameraListCase.values,
    labelBuilder: scannerCameraListCaseLabel,
    // Two cameras is the default so the picker axis has something to open;
    // one camera hides the control on desktop.
    initial: ScannerCameraListCase.two,
  );
  final overlay = wbStateKnob<ScannerCardOverlayCase>(
    context,
    label: kScannerCardOverlayKnob,
    options: ScannerCardOverlayCase.values,
    labelBuilder: scannerCardOverlayCaseLabel,
  );
  final scan = wbStateKnob<ScannerCardScanCase>(
    context,
    label: kScannerCardScanKnob,
    options: ScannerCardScanCase.values,
    labelBuilder: scannerCardScanCaseLabel,
  );
  final showError = wbBoolKnob(context, label: kScannerCardErrorKnob);

  return keystoneScannerCardFixture(
    camera: camera,
    cameras: cameras,
    overlay: overlay,
    scan: scan,
    showError: showError,
  );
}

// --- Keystone scan screens --------------------------------------------------

/// The Keystone onboarding scan step, desktop half. Registered by the
/// onboarding gallery's existing `Scan` component, not here.
Widget buildScannerKeystoneOnboardingGalleryCase(BuildContext context) {
  return keystoneOnboardingScanScreenFixture(
    camera: _cameraKnob(context),
    scan: _screenScanKnob(context),
  );
}

/// Whether the sidebar still highlights the flow the scan belongs to — the one
/// `KeystoneSendScanArgs` field the screen renders.
enum ScannerSidebarCase { highlighted, suppressed }

String scannerSidebarCaseLabel(ScannerSidebarCase sidebar) {
  return switch (sidebar) {
    ScannerSidebarCase.highlighted => 'Send highlighted',
    ScannerSidebarCase.suppressed => 'No selection',
  };
}

String scannerSendExpectedCaseLabel(ScannerSendExpectedCase expected) {
  return switch (expected) {
    ScannerSendExpectedCase.signedTransaction => 'Signed transaction',
    ScannerSendExpectedCase.signatureResult => 'Signature result',
  };
}

Widget buildScannerKeystoneSendGalleryCase(BuildContext context) {
  final camera = _cameraKnob(context);
  final scan = _screenScanKnob(context);
  final expected = wbStateKnob<ScannerSendExpectedCase>(
    context,
    label: kScannerSendExpectedKnob,
    options: ScannerSendExpectedCase.values,
    labelBuilder: scannerSendExpectedCaseLabel,
  );
  final sidebar = wbStateKnob<ScannerSidebarCase>(
    context,
    label: kScannerSidebarKnob,
    options: ScannerSidebarCase.values,
    labelBuilder: scannerSidebarCaseLabel,
  );
  return keystoneSendScanScreenFixture(
    camera: camera,
    scan: scan,
    expected: expected,
    suppressSidebarSelection: sidebar == ScannerSidebarCase.suppressed,
  );
}

Widget buildScannerKeystoneVotingGalleryCase(BuildContext context) {
  return keystoneVotingScanScreenFixture(
    camera: _cameraKnob(context),
    // A decoded voting signature pops the route, so the completing outcome is
    // not an option here.
    scan: _screenScanKnob(
      context,
      options: const [
        ScannerScreenScanCase.waiting,
        ScannerScreenScanCase.readingCode,
        ScannerScreenScanCase.wrongCode,
      ],
    ),
  );
}

// --- Ironwood migration Keystone scans --------------------------------------

String scannerMigrationStepCaseLabel(ScannerMigrationStepCase step) {
  return switch (step) {
    ScannerMigrationStepCase.combined => 'Combined sign',
    ScannerMigrationStepCase.immediate => 'Immediate sign',
  };
}

/// The migration signing screens on their scanning stage. Mobile only: the
/// desktop signing screens swap the scanner for a static placeholder as soon
/// as a preview request is set (`keystone_signing.dart:1813`). Registered on
/// the migration gallery's Keystone-sign stage knob, which already owns these
/// screens, so it is not a component here.
///
/// [step] pins the signing screen for a caller that already names it — the
/// migration components do — instead of registering a redundant knob.
Widget buildScannerMigrationGalleryCase(
  BuildContext context, {
  ScannerMigrationStepCase? step,
}) {
  final signStep =
      step ??
      wbStateKnob<ScannerMigrationStepCase>(
        context,
        label: kScannerMigrationStepKnob,
        options: ScannerMigrationStepCase.values,
        labelBuilder: scannerMigrationStepCaseLabel,
      );
  final camera = _cameraKnob(context);
  final scan = _screenScanKnob(
    context,
    options: const [
      ScannerScreenScanCase.waiting,
      ScannerScreenScanCase.readingCode,
      ScannerScreenScanCase.wrongCode,
    ],
  );
  return migrationKeystoneScanFixture(
    step: signStep,
    camera: camera,
    scan: scan,
  );
}

// --- Bare scanner views -----------------------------------------------------

String scannerViewFrameCaseLabel(ScannerViewFrameCase frame) {
  return switch (frame) {
    ScannerViewFrameCase.square => 'Square',
    ScannerViewFrameCase.portrait => 'Portrait',
  };
}

String scannerViewErrorCaseLabel(ScannerViewErrorCase error) {
  return switch (error) {
    ScannerViewErrorCase.pluginDefault => 'Scanner default',
    ScannerViewErrorCase.callerBuilder => 'Caller supplied',
  };
}

Widget buildScannerPlainViewGalleryCase(BuildContext context) {
  final camera = _cameraKnob(context);
  final frame = wbStateKnob<ScannerViewFrameCase>(
    context,
    label: kScannerViewFrameKnob,
    options: ScannerViewFrameCase.values,
    labelBuilder: scannerViewFrameCaseLabel,
  );
  return plainQrScannerViewFixture(camera: camera, frame: frame);
}

Widget buildScannerAnimatedUrViewGalleryCase(BuildContext context) {
  // Opens on the denied camera: `errorBuilder` is the axis this case exists
  // for, and it only draws anything once the camera has failed.
  final camera = wbStateKnob<ScannerCameraCase>(
    context,
    label: kScannerCameraKnob,
    options: ScannerCameraCase.values,
    labelBuilder: scannerCameraCaseLabel,
    initial: ScannerCameraCase.denied,
  );
  final error = wbStateKnob<ScannerViewErrorCase>(
    context,
    label: kScannerViewErrorKnob,
    options: ScannerViewErrorCase.values,
    labelBuilder: scannerViewErrorCaseLabel,
  );
  return animatedUrScannerViewFixture(camera: camera, error: error);
}
