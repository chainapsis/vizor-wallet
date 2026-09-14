// Pins the Scanning gallery: every case renders at its defaults against the
// camera / UR fakes, and every knob option reaches a different screen.

import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/gallery/scanner_gallery.dart';
import 'package:zcash_wallet/widgetbook/scanner_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_fake_scanner_platform.dart';

import 'support/wb_gallery_harness.dart';

// Real fonts are loaded: the Keystone card's 396px footer and the desktop
// sidebar overflow under the test-default font metrics, which would report as
// a render exception on every case.
void main() {
  setUpAll(_loadAppFonts);
  setUpAll(WbFakeUrScanRustApi.install);
  tearDown(WbFakeMobileScannerPlatform.reset);

  group('Keystone scanner card', () {
    testWidgets('renders the live feed at its defaults', (tester) async {
      await _pumpScanner(tester, buildScannerKeystoneCardGalleryCase);

      expect(tester.takeException(), isNull);
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);
      expect(find.text('Built-in camera (Default)'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the camera axis reaches every permission state', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneCardGalleryCase,
        label: kScannerCameraKnob,
        optionLabels: const [
          'Live feed',
          'Requesting access',
          'Access denied',
          'Camera unavailable',
        ],
      );
    });

    testWidgets('the denied camera offers the allow action', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCameraKnob: 'Access denied'},
      );

      expect(find.text("You've denied the Camera access"), findsOneWidget);
      expect(find.text('Allow camera'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the unavailable camera shows the host detail and retry', (
      tester,
    ) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCameraKnob: 'Camera unavailable'},
      );

      expect(find.text('Camera unavailable'), findsOneWidget);
      // The card's own prompt, plus the plugin's default error widget under
      // it, both name the host detail.
      expect(
        find.text('This camera is already in use by another app.'),
        findsWidgets,
      );
      expect(find.text('Try again'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the camera-list axis renames the footer control', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneCardGalleryCase,
        label: kScannerCameraListKnob,
        optionLabels: const ['None found', 'One camera', 'Two cameras'],
      );
    });

    testWidgets('one camera names it and two name the default', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCameraListKnob: 'One camera'},
      );
      expect(find.text('Back camera (Default)'), findsOneWidget);
      await disposeTree(tester);

      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCameraListKnob: 'Two cameras'},
      );
      expect(find.text('Built-in camera (Default)'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('the overlay axis opens each overlay', (tester) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneCardGalleryCase,
        label: kScannerCardOverlayKnob,
        optionLabels: const ['None', 'Camera picker', 'Trouble scanning'],
      );
    });

    testWidgets('the camera picker lists both cameras', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCardOverlayKnob: 'Camera picker'},
      );

      expect(find.text('External webcam'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the trouble-scanning overlay lists its tips', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCardOverlayKnob: 'Trouble scanning'},
      );

      // The popover repeats the disclosure title, which is how it is told
      // apart from the closed state.
      expect(find.text('Trouble scanning?'), findsNWidgets(2));

      await disposeTree(tester);
    });

    testWidgets('the scan axis reaches progress and decoding', (tester) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneCardGalleryCase,
        label: kScannerCardScanKnob,
        optionLabels: const [
          'Nothing scanned',
          'Reading a multi-part code',
          'Decoding the result',
        ],
      );
    });

    testWidgets('decoding draws the reading-accounts overlay', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCardScanKnob: 'Decoding the result'},
      );

      expect(find.text('Reading accounts...'), findsOneWidget);

      await disposeTree(tester);
    });

    // The harness remounts on every pump, so only an in-place rebuild proves
    // the knob-derived key: Widgetbook rebuilds the use case at the same
    // widget position, and a scanner seeded in `initState` would otherwise
    // keep showing the previous option.
    testWidgets('a camera change takes effect on an in-place rebuild', (
      tester,
    ) async {
      final camera = ValueNotifier(ScannerCameraCase.live);
      addTearDown(camera.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: Material(
              child: ValueListenableBuilder<ScannerCameraCase>(
                valueListenable: camera,
                builder: (_, value, _) =>
                    keystoneScannerCardFixture(camera: value),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump();
      }
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

      camera.value = ScannerCameraCase.denied;
      for (var i = 0; i < 12; i++) {
        await tester.pump();
      }

      expect(find.byKey(kWbFakeCameraViewKey), findsNothing);
      expect(find.text("You've denied the Camera access"), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the error knob prints the scan error under the card', (
      tester,
    ) async {
      await _pumpScanner(tester, buildScannerKeystoneCardGalleryCase);
      expect(
        find.text('Keep the QR code steady and fully visible.'),
        findsNothing,
      );
      await disposeTree(tester);

      await _pumpScanner(
        tester,
        buildScannerKeystoneCardGalleryCase,
        knobs: const {kScannerCardErrorKnob: 'true'},
      );
      expect(
        find.text('Keep the QR code steady and fully visible.'),
        findsOneWidget,
      );
      await disposeTree(tester);
    });
  });

  group('Keystone scan screen', () {
    testWidgets('renders the onboarding step at its defaults', (tester) async {
      await _pumpScanner(tester, buildScannerKeystoneOnboardingGalleryCase);

      expect(tester.takeException(), isNull);
      // The onboarding sidebar repeats the step label, so the title is two.
      expect(find.text('Scan QR Code'), findsNWidgets(2));
      expect(find.text('Prepare your Keystone wallet'), findsOneWidget);
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the camera axis reaches every permission state', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneOnboardingGalleryCase,
        label: kScannerCameraKnob,
        optionLabels: const [
          'Live feed',
          'Requesting access',
          'Access denied',
          'Camera unavailable',
        ],
      );
    });

    testWidgets('the scan axis reaches both error copies', (tester) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneOnboardingGalleryCase,
        label: kScannerScreenScanKnob,
        optionLabels: const [
          'Nothing scanned',
          'Reading a multi-part code',
          'Wrong code shown',
          'Code will not decode',
        ],
      );
    });

    testWidgets('a wrong code asks for the account QR', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneOnboardingGalleryCase,
        knobs: const {kScannerScreenScanKnob: 'Wrong code shown'},
      );

      expect(
        find.text('Open the Zcash account QR on Keystone, then scan again.'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('an undecodable accounts QR shows the accounts error', (
      tester,
    ) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneOnboardingGalleryCase,
        knobs: const {kScannerScreenScanKnob: 'Code will not decode'},
      );

      expect(
        find.text(
          'This QR code could not be decoded as a Keystone Zcash '
          'account.',
        ),
        findsOneWidget,
      );

      await disposeTree(tester);
    });
  });

  group('Send Keystone scan', () {
    testWidgets('renders the send scan screen at its defaults', (tester) async {
      await _pumpScanner(tester, buildScannerKeystoneSendGalleryCase);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Hold the QR code steady in front of your camera'),
        findsOneWidget,
      );
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the camera axis reaches every permission state', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneSendGalleryCase,
        label: kScannerCameraKnob,
        optionLabels: const [
          'Live feed',
          'Requesting access',
          'Access denied',
          'Camera unavailable',
        ],
      );
    });

    testWidgets('the scan axis reaches both error copies', (tester) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneSendGalleryCase,
        label: kScannerScreenScanKnob,
        optionLabels: const [
          'Nothing scanned',
          'Reading a multi-part code',
          'Wrong code shown',
          'Code will not decode',
        ],
      );
    });

    testWidgets('an undecodable signature QR shows the signature error', (
      tester,
    ) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneSendGalleryCase,
        knobs: const {kScannerScreenScanKnob: 'Code will not decode'},
      );

      expect(
        find.text(
          'This QR code could not be decoded as a Keystone '
          'transaction signature.',
        ),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('a wrong code names the response the flow asked for', (
      tester,
    ) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneSendGalleryCase,
        knobs: const {kScannerScreenScanKnob: 'Wrong code shown'},
      );
      expect(
        find.text(
          'Open the signed transaction QR on Keystone, then scan again.',
        ),
        findsOneWidget,
      );
      await disposeTree(tester);

      await _pumpScanner(
        tester,
        buildScannerKeystoneSendGalleryCase,
        knobs: const {
          kScannerScreenScanKnob: 'Wrong code shown',
          kScannerSendExpectedKnob: 'Signature result',
        },
      );
      expect(
        find.text('Open the signature result QR on Keystone, then scan again.'),
        findsOneWidget,
      );
      await disposeTree(tester);
    });

    testWidgets('an unreadable signature-result QR stays on the screen', (
      tester,
    ) async {
      // The signature result is not CBOR-decoded, so a complete UR would pop
      // the route; its undecodable QR is one the UR decoder rejects.
      await _pumpScanner(
        tester,
        buildScannerKeystoneSendGalleryCase,
        knobs: const {
          kScannerScreenScanKnob: 'Code will not decode',
          kScannerSendExpectedKnob: 'Signature result',
        },
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Keep the QR code steady and fully visible.'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('the expected-code axis swaps the wrong-code line', (
      tester,
    ) async {
      // Swept on a wrong code: the two arg shapes differ only in the UR type
      // they accept, so an idle scanner renders the same screen for both.
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneSendGalleryCase,
        label: kScannerSendExpectedKnob,
        optionLabels: const ['Signed transaction', 'Signature result'],
        otherKnobs: const {kScannerScreenScanKnob: 'Wrong code shown'},
      );
    });

    testWidgets('the sidebar axis clears the active selection', (tester) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneSendGalleryCase,
        label: kScannerSidebarKnob,
        optionLabels: const ['Send highlighted', 'No selection'],
      );
    });

    // The screen exists in one form factor only, so the single Playground case
    // registers its state axes and no `Layout` knob.
    testWidgets('registers its state axes without a layout knob', (
      tester,
    ) async {
      final state = await pumpUseCase(
        tester,
        buildScannerKeystoneSendGalleryCase,
      );

      expect(
        state.knobs.keys,
        containsAll(<String>[
          kScannerCameraKnob,
          kScannerScreenScanKnob,
          kScannerSendExpectedKnob,
          kScannerSidebarKnob,
        ]),
      );
      expect(state.knobs.keys, isNot(contains('Layout')));

      await disposeTree(tester);
    });
  });

  group('Voting Keystone scan', () {
    testWidgets('renders the voting scan screen at its defaults', (
      tester,
    ) async {
      await _pumpScanner(tester, buildScannerKeystoneVotingGalleryCase);

      expect(tester.takeException(), isNull);
      expect(find.text('Scan voting signature'), findsOneWidget);
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the camera axis reaches every permission state', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneVotingGalleryCase,
        label: kScannerCameraKnob,
        optionLabels: const [
          'Live feed',
          'Requesting access',
          'Access denied',
          'Camera unavailable',
        ],
      );
    });

    testWidgets('a wrong code asks for the signed voting QR', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerKeystoneVotingGalleryCase,
        knobs: const {kScannerScreenScanKnob: 'Wrong code shown'},
      );

      expect(
        find.text('Open the signed voting QR on Keystone, then scan again.'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    // Desktop-only screen: one Playground case, no `Layout` knob, and the scan
    // axis stays trimmed to the outcomes that do not pop the route.
    testWidgets('registers its state axes without a layout knob', (
      tester,
    ) async {
      final state = await pumpUseCase(
        tester,
        buildScannerKeystoneVotingGalleryCase,
      );

      expect(
        state.knobs.keys,
        containsAll(<String>[kScannerCameraKnob, kScannerScreenScanKnob]),
      );
      expect(state.knobs.keys, isNot(contains('Layout')));

      await disposeTree(tester);
    });

    testWidgets('the scan axis reaches its three offered outcomes', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerKeystoneVotingGalleryCase,
        label: kScannerScreenScanKnob,
        optionLabels: const [
          'Nothing scanned',
          'Reading a multi-part code',
          'Wrong code shown',
        ],
      );
    });
  });

  group('Migration Keystone scans', () {
    // Mobile-lane only: the case is `WbLaneOnly(mobile)` because the real card
    // falls back to its desktop geometry and overflows the phone frame under
    // the desktop token set. The desktop lane can only assert the notice; the
    // camera and signing-step options are exercised by running the mobile
    // widgetbook lane.
    testWidgets('shows the mobile-lane notice in the desktop lane', (
      tester,
    ) async {
      await _pumpScanner(tester, buildScannerMigrationGalleryCase);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('registers its camera and signing-step knobs', (tester) async {
      final state = await pumpUseCase(tester, buildScannerMigrationGalleryCase);

      expect(
        state.knobs.keys,
        containsAll(<String>[kScannerMigrationStepKnob, kScannerCameraKnob]),
      );

      await disposeTree(tester);
    });
  });

  group('QR scanner views', () {
    testWidgets('the plain view renders the feed at its defaults', (
      tester,
    ) async {
      await _pumpScanner(tester, buildScannerPlainViewGalleryCase);

      expect(tester.takeException(), isNull);
      expect(find.byKey(kWbFakeCameraViewKey), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the plain view camera axis reaches every state', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerPlainViewGalleryCase,
        label: kScannerCameraKnob,
        optionLabels: const [
          'Live feed',
          'Requesting access',
          'Access denied',
          'Camera unavailable',
        ],
      );
    });

    testWidgets('the preview box axis changes the scan window it derives', (
      tester,
    ) async {
      await _pumpScanner(
        tester,
        buildScannerPlainViewGalleryCase,
        knobs: const {kScannerViewFrameKnob: 'Square'},
      );
      final square = WbFakeMobileScannerPlatform.current!.lastScanWindow;
      await disposeTree(tester);

      await _pumpScanner(
        tester,
        buildScannerPlainViewGalleryCase,
        knobs: const {kScannerViewFrameKnob: 'Portrait'},
      );
      final portrait = WbFakeMobileScannerPlatform.current!.lastScanWindow;
      await disposeTree(tester);

      expect(square, isNotNull);
      expect(portrait, isNotNull);
      expect(square!.size, isNot(portrait!.size));
    });

    testWidgets('the preview box axis renders two different boxes', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerPlainViewGalleryCase,
        label: kScannerViewFrameKnob,
        optionLabels: const ['Square', 'Portrait'],
      );
    });

    testWidgets('the animated UR view opens on the denied camera', (
      tester,
    ) async {
      await _pumpScanner(tester, buildScannerAnimatedUrViewGalleryCase);

      expect(tester.takeException(), isNull);
      expect(find.byKey(kWbFakeCameraViewKey), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('the error-view axis swaps the plugin widget for the caller', (
      tester,
    ) async {
      await _expectOptionsRenderDistinctly(
        tester,
        buildScannerAnimatedUrViewGalleryCase,
        label: kScannerViewErrorKnob,
        optionLabels: const ['Scanner default', 'Caller supplied'],
      );
    });

    testWidgets('the caller error view names the failure', (tester) async {
      await _pumpScanner(
        tester,
        buildScannerAnimatedUrViewGalleryCase,
        knobs: const {kScannerViewErrorKnob: 'Caller supplied'},
      );

      expect(find.text('Camera error: permissionDenied'), findsOneWidget);

      await disposeTree(tester);
    });
  });
}

/// Pumps a scanner case and lets it settle.
///
/// The camera resolves a frame after mount and the fixtures' mount driver
/// retries its push / tap per frame, so one pump is never enough.
Future<void> _pumpScanner(
  WidgetTester tester,
  WidgetBuilder builder, {
  Map<String, String> knobs = const {},
}) async {
  await pumpUseCase(tester, builder, knobs: knobs);
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

/// The harness sweep with the extra frames a scanner needs.
Future<void> _expectOptionsRenderDistinctly(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await _pumpScanner(tester, builder, knobs: {...otherKnobs, label: option});
    expect(tester.takeException(), isNull, reason: '$label / $option');

    final fingerprint = await useCaseFingerprint(tester);
    final duplicate = seen[fingerprint];
    expect(
      duplicate,
      isNull,
      reason:
          "'$label' options '$duplicate' and '$option' render identically — "
          'the knob has a dead option or a duplicated dispatch.',
    );
    seen[fingerprint] = option;
    await disposeTree(tester);
  }
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Bold.ttf'));
  final geistMono = FontLoader('Geist Mono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), geistMono.load(), youngSerif.load()]);
}
