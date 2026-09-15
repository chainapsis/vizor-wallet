import 'dart:typed_data';

import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/features/receive/services/request_qr_export.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_pane_modal_overlay.dart';
import 'package:zcash_wallet/src/core/layout/app_main_sidebar.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/mobile/receive_request_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_address_widgets.dart';
import 'package:zcash_wallet/src/features/receive/widgets/receive_desktop_preview.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/receive_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/request_amount_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Lane-agnostic: the layout knob is driven by explicit query params, never by
// the compiled lane, so both test lanes exercise the same combinations. The
// exception is the desktop `ReceiveScreen`, which the gallery gates with
// `WbLaneOnly` because its fixed-coordinate pane overflows the mobile tokens.
final _desktopLane = wbLayoutMatchesLane(WbLayout.desktop);

/// The `Layout` knob values the folded screen case dispatches on.
final _desktopLaneKnob = {'Layout': wbLayoutLabel(WbLayout.desktop)};
final _mobileLane = {'Layout': wbLayoutLabel(WbLayout.mobile)};

void main() {
  testWidgets('every receive gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(receiveGalleryNodes).toList();
    expect(useCases.length, 14);

    for (final useCase in useCases) {
      await _pumpSettled(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('the screen covers both layouts with their own address axes', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    // The two panes resolve a load into different outcomes, so `Address` is a
    // per-layout knob rather than one shared option list.
    final desktop = await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: _desktopLaneKnob,
    );
    expect(
      _addressOptions(desktop),
      ReceiveAddressCase.values.map(receiveAddressCaseLabel).toList(),
    );

    final mobile = await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: _mobileLane,
    );
    expect(mobile.knobs.keys, containsAll(<String>['Layout', 'Pool']));
    expect(
      _addressOptions(mobile),
      ReceiveMobileAddressCase.values
          .map(receiveMobileAddressCaseLabel)
          .toList(),
    );
    await disposeTree(tester);
  });

  testWidgets(
    'the real receive screen carries a request through result and back',
    (tester) async {
      if (!_desktopLane) return;
      await _pumpSettled(
        tester,
        buildReceiveScreenGalleryCase,
        knobs: _desktopLaneKnob,
      );
      await tester.tap(find.byKey(const ValueKey('receive_request_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('request_amount_field')),
          matching: find.byType(EditableText),
        ),
        '0.5',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('request_copy_link_button')),
        findsOneWidget,
      );
      final fixtureScope = ProviderScope.containerOf(
        tester.element(find.byType(ReceiveScreen)),
        listen: false,
      );
      expect(
        await fixtureScope.read(requestQrSaveLocationPickerProvider)(
          suggestedName: 'fixture.png',
        ),
        isNull,
      );
      // Exercise the real screen's save callback with already-encoded bytes;
      // QR rasterization is independent of the platform/filesystem boundary.
      await tester
          .widget<RequestQrExportButton>(
            find.byKey(const ValueKey('request_save_qr_button')),
          )
          .onBytes!(Uint8List.fromList([137, 80, 78, 71]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('QR image saved'), findsNothing);
      expect(
        find.textContaining("We couldn't save the QR image"),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('request_modal_back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('request_amount_field')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the desktop screen covers both pools and every address outcome',
    (tester) async {
      if (!_desktopLane) return;
      await _expectOptionsRenderDistinctly(
        tester,
        buildReceiveScreenGalleryCase,
        label: 'Pool',
        optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
        otherKnobs: {
          ..._desktopLaneKnob,
          'Address': receiveAddressCaseLabel(ReceiveAddressCase.loaded),
        },
      );
      await _expectOptionsRenderDistinctly(
        tester,
        buildReceiveScreenGalleryCase,
        label: 'Address',
        optionLabels: ReceiveAddressCase.values
            .map(receiveAddressCaseLabel)
            .toList(),
        otherKnobs: {
          ..._desktopLaneKnob,
          'Pool': receivePoolCaseLabel(ReceivePoolCase.shielded),
        },
      );
    },
  );

  testWidgets('the desktop screen renders the real receive widgets', (
    tester,
  ) async {
    if (!_desktopLane) return;
    // The point of this case: the production screen, not the preview mock.
    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: _desktopLaneKnob,
    );
    expect(find.byType(ReceiveScreen), findsOneWidget);
    expect(find.byType(ReceiveTabs), findsOneWidget);
    expect(find.byType(ReceiveDesktopPreview), findsNothing);
    expect(_addressLine(tester).address, kReceiveScreenShieldedAddress);

    // The transparent option goes through the real tab callback, so the pane
    // has to end up on the transparent address, not merely on another tab.
    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        ..._desktopLaneKnob,
        'Pool': receivePoolCaseLabel(ReceivePoolCase.transparent),
      },
    );
    expect(_addressLine(tester).address, kReceiveScreenTransparentAddress);

    // Empty and Failed differ by more than pixels: one leaves the pane with
    // no address at all, the other keeps the address and adds the error line.
    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        ..._desktopLaneKnob,
        'Address': receiveAddressCaseLabel(ReceiveAddressCase.empty),
      },
    );
    expect(_addressLine(tester).address, isEmpty);

    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        ..._desktopLaneKnob,
        'Address': receiveAddressCaseLabel(ReceiveAddressCase.failed),
      },
    );
    expect(_addressLine(tester).address, kReceiveScreenShieldedAddress);
    // The pane prints the thrown object, so the preview stand-in is what
    // reaches the error line.
    expect(find.textContaining('Preview: address load failed'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('the mobile screen covers both pools and both address outcomes', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveScreenGalleryCase,
      label: 'Pool',
      optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
      otherKnobs: {
        ..._mobileLane,
        'Address': receiveMobileAddressCaseLabel(
          ReceiveMobileAddressCase.loaded,
        ),
      },
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveScreenGalleryCase,
      label: 'Address',
      optionLabels: ReceiveMobileAddressCase.values
          .map(receiveMobileAddressCaseLabel)
          .toList(),
      otherKnobs: {
        ..._mobileLane,
        'Pool': receivePoolCaseLabel(ReceivePoolCase.shielded),
      },
    );
  });

  testWidgets('the mobile screen carries a request through result and back', (
    tester,
  ) async {
    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        ..._mobileLane,
        'Address': receiveMobileAddressCaseLabel(
          ReceiveMobileAddressCase.loaded,
        ),
      },
    );
    await tester.tap(find.byKey(const ValueKey('mobile_receive_request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('request_amount_input')),
      '0.5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('request_create_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('request_copy_link_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('request_sheet_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('request_amount_input')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('the mobile screen share action stays inside Widgetbook', (
    tester,
  ) async {
    final shareCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        shareCalls.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        null,
      ),
    );

    await _pumpSettled(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        ..._mobileLane,
        'Address': receiveMobileAddressCaseLabel(
          ReceiveMobileAddressCase.loaded,
        ),
      },
    );
    await tester.tap(find.byKey(const ValueKey('mobile_receive_share')));
    await tester.pump();

    expect(shareCalls, isEmpty);
    await disposeTree(tester);
  });

  testWidgets('the address info sheet covers both address types', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveAddressInfoGalleryCase,
      label: 'Type',
      optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
    );
  });

  testWidgets('the copy button covers both address types and disabled', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveCopyAddressButtonGalleryCase,
      label: 'Type',
      optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveCopyAddressButtonGalleryCase,
      label: kReceiveCopyEnabledKnob,
      optionLabels: const ['true', 'false'],
    );

    // The label follows the pool, and the slot is the screen's own 230x44.
    await _pumpSettled(
      tester,
      buildReceiveCopyAddressButtonGalleryCase,
      knobs: {'Type': receivePoolCaseLabel(ReceivePoolCase.transparent)},
    );
    expect(find.text('Copy transparent address'), findsOneWidget);
    expect(_copyAddressButton(tester).enabled, isTrue);
    expect(
      tester.getSize(find.byType(ReceiveCopyAddressButton)),
      const Size(230, 44),
    );

    await _pumpSettled(
      tester,
      buildReceiveCopyAddressButtonGalleryCase,
      knobs: {kReceiveCopyEnabledKnob: 'false'},
    );
    expect(find.text('Copy shielded address'), findsOneWidget);
    expect(_copyAddressButton(tester).enabled, isFalse);
    await disposeTree(tester);
  });

  testWidgets('the tabs cover both selections and both call sites', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveTabsGalleryCase,
      label: 'Selected',
      optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
      otherKnobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveTabsGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      otherKnobs: {
        'Selected': receivePoolCaseLabel(ReceivePoolCase.transparent),
      },
    );

    // The desktop argument set is the one nothing else renders today.
    await _pumpSettled(
      tester,
      buildReceiveTabsGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(_tabs(tester).alwaysDarkSelected, isFalse);
    expect(tester.getSize(find.byType(ReceiveTabs)), const Size(256, 36));

    await _pumpSettled(
      tester,
      buildReceiveTabsGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(_tabs(tester).alwaysDarkSelected, isTrue);
    expect(tester.getSize(find.byType(ReceiveTabs)), const Size(320, 44));

    // Tapping moves the live selection, as it does on screen.
    await tester.tap(
      find.byKey(const ValueKey('receive_address_type_tab_transparent')),
    );
    await tester.pumpAndSettle();
    expect(_tabs(tester).selectedType, ReceiveAddressType.transparent);
    await disposeTree(tester);
  });

  testWidgets('the QR surface covers both pools, both sizes and no address', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveQrSurfaceGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveQrSurfaceGalleryCase,
      label: 'Address',
      optionLabels: ReceiveComponentAddressCase.values
          .map(receiveComponentAddressCaseLabel)
          .toList(),
    );

    // Pool by props rather than by pixels: the bitmap rasterises off the test
    // clock, so the address it encodes is the reliable signal.
    for (final pool in ReceivePoolCase.values) {
      await _pumpSettled(
        tester,
        buildReceiveQrSurfaceGalleryCase,
        knobs: {'Type': receivePoolCaseLabel(pool)},
      );
      final shielded = pool == ReceivePoolCase.shielded;
      final surface = tester.widget<ReceiveQrSurface>(
        find.byType(ReceiveQrSurface),
      );
      expect(
        surface.type,
        shielded ? ReceiveAddressType.shielded : ReceiveAddressType.transparent,
      );
      expect(
        surface.address,
        shielded
            ? kReceiveScreenShieldedAddress
            : kReceiveScreenTransparentAddress,
      );
    }

    // Desktop is the 230 code with the 48 badge; mobile is the larger frame.
    await _pumpSettled(
      tester,
      buildReceiveQrSurfaceGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(tester.getSize(find.byType(ReceiveQrSurface)), const Size(262, 278));
    expect(
      tester.widget<ReceiveQrSurface>(find.byType(ReceiveQrSurface)).badgeSize,
      48,
    );

    await _pumpSettled(
      tester,
      buildReceiveQrSurfaceGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(tester.getSize(find.byType(ReceiveQrSurface)), const Size(292, 308));

    // Nothing to encode is the copy, not an empty frame.
    await _pumpSettled(
      tester,
      buildReceiveQrSurfaceGalleryCase,
      knobs: {
        'Address': receiveComponentAddressCaseLabel(
          ReceiveComponentAddressCase.empty,
        ),
      },
    );
    expect(
      find.textContaining("We couldn't load your address"),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('the renew button covers idle and renewing', (tester) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRenewButtonGalleryCase,
      label: 'State',
      optionLabels: ReceiveRenewCase.values.map(receiveRenewCaseLabel).toList(),
    );

    // The spinner is the state both screens only reach by tapping.
    await _pumpSettled(
      tester,
      buildReceiveRenewButtonGalleryCase,
      knobs: {'State': receiveRenewCaseLabel(ReceiveRenewCase.renewing)},
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(ReceiveRenewButton)), const Size(48, 48));

    await _pumpSettled(
      tester,
      buildReceiveRenewButtonGalleryCase,
      knobs: {'State': receiveRenewCaseLabel(ReceiveRenewCase.idle)},
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('the address line covers both pools, both styles and empty', (
    tester,
  ) async {
    // Pool by the address it compacts: the two lines differ only in their
    // text, and the test font draws every glyph as the same box.
    for (final pool in ReceivePoolCase.values) {
      await _pumpSettled(
        tester,
        buildReceiveAddressLineGalleryCase,
        knobs: {'Type': receivePoolCaseLabel(pool)},
      );
      expect(
        _addressLine(tester).address,
        pool == ReceivePoolCase.shielded
            ? kReceiveScreenShieldedAddress
            : kReceiveScreenTransparentAddress,
        reason: pool.name,
      );
      expect(
        find.textContaining(
          pool == ReceivePoolCase.shielded ? 'u1tvg2412a23k' : 't1aWwWwqk3jYG',
          findRichText: true,
        ),
        findsOneWidget,
        reason: pool.name,
      );
    }

    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveAddressLineGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveAddressLineGalleryCase,
      label: 'Address',
      optionLabels: ReceiveComponentAddressCase.values
          .map(receiveComponentAddressCaseLabel)
          .toList(),
    );

    // Each layout keeps its own call site's styling rather than a third mix.
    await _pumpSettled(
      tester,
      buildReceiveAddressLineGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(_addressLine(tester).secondaryTint, isFalse);
    expect(_addressLine(tester).scaleToFit, isFalse);

    await _pumpSettled(
      tester,
      buildReceiveAddressLineGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(_addressLine(tester).secondaryTint, isTrue);
    expect(_addressLine(tester).scaleToFit, isTrue);

    await _pumpSettled(
      tester,
      buildReceiveAddressLineGalleryCase,
      knobs: {
        'Address': receiveComponentAddressCaseLabel(
          ReceiveComponentAddressCase.empty,
        ),
      },
    );
    expect(_addressLine(tester).address, isEmpty);
    expect(
      find.textContaining("Address couldn't be loaded", findRichText: true),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  testWidgets('the live request sheet covers both pools and price states', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestSheetGalleryCase,
      label: 'Pool',
      optionLabels: ReceivePoolCase.values.map(receivePoolCaseLabel).toList(),
      otherKnobs: {
        'Price': receiveRequestPriceCaseLabel(ReceiveRequestPriceCase.live),
      },
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestSheetGalleryCase,
      label: 'Price',
      optionLabels: ReceiveRequestPriceCase.values
          .map(receiveRequestPriceCaseLabel)
          .toList(),
      otherKnobs: {'Pool': receivePoolCaseLabel(ReceivePoolCase.shielded)},
    );
  });

  testWidgets('the live request sheet is the stateful widget, not a snapshot', (
    tester,
  ) async {
    await _pumpSettled(tester, buildReceiveRequestSheetGalleryCase);
    expect(find.byType(ReceiveRequestSheet), findsOneWidget);

    // Typing an amount has to move the live draft, which is what separates
    // this case from the presentational Compose case.
    await tester.enterText(find.byType(EditableText).first, '0.5');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('35.00'), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('request compose covers every state in both layouts', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await _expectOptionsRenderDistinctly(
        tester,
        buildReceiveRequestComposeGalleryCase,
        label: 'Request',
        optionLabels: kReceiveRequestComposeCases
            .map(receiveRequestFixtureLabel)
            .toList(),
        // With the editor collapsed the desktop card shows a message state
        // and an amount-only state identically, which is the product's own
        // behaviour rather than a dead option.
        otherKnobs: {
          'Layout': wbLayoutLabel(layout),
          kReceiveRequestMessageExpandedKnob: 'true',
        },
      );
    }

    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestComposeGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('request result covers every state in both layouts', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await _expectOptionsRenderDistinctly(
        tester,
        buildReceiveRequestResultGalleryCase,
        label: 'Request',
        optionLabels: kReceiveRequestResultCases
            .map(receiveRequestFixtureLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestResultGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
  });

  testWidgets('request delegates keep their per-state fixture flags', (
    tester,
  ) async {
    // `messageExpanded` and the inert unit toggle are the only two flags the
    // helper extraction could drop, and each belongs to one state only.
    await _pumpSettled(tester, buildRequestModalStepOneMessageUseCase);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('request_message_field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('request_add_message_card')),
      findsNothing,
    );

    await _pumpSettled(tester, buildRequestModalStepOnePriceUnavailableUseCase);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('request_amount_price_loading')),
      findsOneWidget,
    );
    final toggle = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('request_amount_mode_toggle')),
    );
    expect(toggle.onTap, isNull);

    // The dense result fixture is the one with its own address and message.
    await _pumpSettled(tester, buildRequestModalStepTwoDenseUseCase);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('request_copy_link_button')),
      findsWidgets,
    );

    await disposeTree(tester);
  });

  testWidgets('the compose step opens and closes the message editor', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await _expectOptionsRenderDistinctly(
        tester,
        buildReceiveRequestComposeGalleryCase,
        label: kReceiveRequestMessageExpandedKnob,
        optionLabels: const ['false', 'true'],
        otherKnobs: {
          'Layout': wbLayoutLabel(layout),
          'Request': receiveRequestFixtureLabel(
            ReceiveRequestFixture.amountAndMessage,
          ),
        },
      );
    }

    await _pumpSettled(
      tester,
      buildReceiveRequestComposeGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Request': receiveRequestFixtureLabel(
          ReceiveRequestFixture.amountAndMessage,
        ),
        kReceiveRequestMessageExpandedKnob: 'true',
      },
    );
    expect(find.byKey(const ValueKey('request_message_field')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('the compose step can show the amount field focused', (
    tester,
  ) async {
    // Desktop only: the knob drives the real field's focus ring, which the
    // mobile sheet has no field to show, so mobile registers no such knob.
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestComposeGalleryCase,
      label: kReceiveRequestAmountFocusedKnob,
      optionLabels: const ['false', 'true'],
      otherKnobs: _desktopLaneKnob,
    );

    final mobile = await _pumpSettled(
      tester,
      buildReceiveRequestComposeGalleryCase,
      knobs: _mobileLane,
    );
    expect(
      mobile.knobs.keys,
      isNot(contains(kReceiveRequestAmountFocusedKnob)),
    );

    final desktop = await _pumpSettled(
      tester,
      buildReceiveRequestComposeGalleryCase,
      knobs: {..._desktopLaneKnob, kReceiveRequestAmountFocusedKnob: 'true'},
    );
    expect(desktop.knobs.keys, contains(kReceiveRequestAmountFocusedKnob));
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('request_amount_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    await disposeTree(tester);
  });

  testWidgets('both request steps can sit on the live receive pane', (
    tester,
  ) async {
    for (final builder in <WidgetBuilder>[
      buildReceiveRequestComposeGalleryCase,
      buildReceiveRequestResultGalleryCase,
    ]) {
      for (final layout in WbLayout.values) {
        await _expectOptionsRenderDistinctly(
          tester,
          builder,
          label: 'Background',
          optionLabels: ReceiveRequestBackgroundCase.values
              .map(receiveRequestBackgroundCaseLabel)
              .toList(),
          otherKnobs: {'Layout': wbLayoutLabel(layout)},
        );
      }
    }

    // The pane option is the real screen, not a painted stand-in, and the
    // scrim stops at the pane so the sidebar beside it stays uncovered.
    await _pumpSettled(
      tester,
      buildReceiveRequestComposeGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.desktop),
        'Background': receiveRequestBackgroundCaseLabel(
          ReceiveRequestBackgroundCase.receivePane,
        ),
      },
    );
    expect(find.byKey(const ValueKey('request_amount_field')), findsOneWidget);
    if (_desktopLane) {
      expect(find.byType(ReceiveScreen), findsOneWidget);
      final sidebar = tester.getRect(find.byType(AppMainSidebar));
      final scrim = tester.getRect(find.byType(AppPaneModalOverlay));
      expect(scrim.left, greaterThanOrEqualTo(sidebar.right));
    }
    await disposeTree(tester);
  });

  testWidgets('the result step pins the no-amount and the dense request', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      await _pumpSettled(
        tester,
        buildReceiveRequestResultGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(layout),
          'Request': receiveRequestFixtureLabel(ReceiveRequestFixture.empty),
        },
      );
      // Before an amount the code is the bare address: scannable, but there is
      // nothing to summarise and no link to copy.
      expect(find.byKey(const ValueKey('request_qr_surface')), findsOneWidget);
      expect(find.byKey(const ValueKey('request_summary_row')), findsNothing);
      expect(_copyLinkButton(tester).onPressed, isNull);

      await _pumpSettled(
        tester,
        buildReceiveRequestResultGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(layout),
          'Request': receiveRequestFixtureLabel(
            ReceiveRequestFixture.denseMessage,
          ),
        },
      );
      expect(find.byKey(const ValueKey('request_summary_row')), findsOneWidget);
      expect(_copyLinkButton(tester).onPressed, isNotNull);
    }
    await disposeTree(tester);
  });

  testWidgets('the QR surface covers every payload and both sides', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestQrSurfaceGalleryCase,
      label: 'Data',
      optionLabels: ReceiveRequestQrDataCase.values
          .map(receiveRequestQrDataCaseLabel)
          .toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestQrSurfaceGalleryCase,
      label: 'Size',
      optionLabels: RequestQrPreviewSize.values
          .map(receiveRequestQrSizeLabel)
          .toList(),
    );

    // Nothing to encode is a placeholder, not an empty frame.
    await _pumpSettled(
      tester,
      buildReceiveRequestQrSurfaceGalleryCase,
      knobs: {
        'Data': receiveRequestQrDataCaseLabel(ReceiveRequestQrDataCase.empty),
      },
    );
    expect(find.text('QR unavailable'), findsOneWidget);

    // The dense payload grows past the side the mobile sheet asks for.
    await _pumpSettled(
      tester,
      buildReceiveRequestQrSurfaceGalleryCase,
      knobs: {
        'Data': receiveRequestQrDataCaseLabel(
          ReceiveRequestQrDataCase.denseMessage,
        ),
        'Size': receiveRequestQrSizeLabel(RequestQrPreviewSize.mobileSheet),
      },
    );
    final dense = tester.getSize(
      find.byKey(const ValueKey('request_qr_surface')),
    );
    expect(dense.width, greaterThan(kRequestSheetQrSize));
    await disposeTree(tester);
  });

  testWidgets('the QR export button covers both call sites and disabled', (
    tester,
  ) async {
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestQrExportGalleryCase,
      label: 'Action',
      optionLabels: RequestQrExportAction.values
          .map(receiveRequestExportActionLabel)
          .toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestQrExportGalleryCase,
      label: kReceiveRequestExportEnabledKnob,
      optionLabels: const ['true', 'false'],
    );

    await _pumpSettled(
      tester,
      buildReceiveRequestQrExportGalleryCase,
      knobs: {
        'Action': receiveRequestExportActionLabel(
          RequestQrExportAction.shareRequest,
        ),
      },
    );
    expect(find.text('Share request'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton)).onPressed,
      isNotNull,
    );

    await _pumpSettled(
      tester,
      buildReceiveRequestQrExportGalleryCase,
      knobs: {kReceiveRequestExportEnabledKnob: 'false'},
    );
    expect(find.text('Save QR image'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
    await disposeTree(tester);
  });

  testWidgets('the amount rows cover every row, unit and error', (
    tester,
  ) async {
    for (final row in RequestAmountRowCase.values) {
      final state = await _pumpSettled(
        tester,
        buildReceiveRequestAmountRowsGalleryCase,
        knobs: {'Row': receiveRequestRowLabel(row)},
      );
      expect(
        state.knobs.keys.contains('Unit'),
        row == RequestAmountRowCase.amountField,
        reason: row.name,
      );
      expect(
        state.knobs.keys.contains('Error'),
        row == RequestAmountRowCase.amountError,
        reason: row.name,
      );
    }
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestAmountRowsGalleryCase,
      label: 'Row',
      optionLabels: RequestAmountRowCase.values
          .map(receiveRequestRowLabel)
          .toList(),
    );
    await _expectOptionsRenderDistinctly(
      tester,
      buildReceiveRequestAmountRowsGalleryCase,
      label: 'Unit',
      optionLabels: ReceiveRequestUnitCase.values
          .map(receiveRequestUnitLabel)
          .toList(),
      otherKnobs: {
        'Row': receiveRequestRowLabel(RequestAmountRowCase.amountField),
      },
    );

    // USD entry is the dollar prefix, not a relabelled ZEC field.
    await _pumpSettled(
      tester,
      buildReceiveRequestAmountRowsGalleryCase,
      knobs: {
        'Row': receiveRequestRowLabel(RequestAmountRowCase.amountField),
        'Unit': receiveRequestUnitLabel(ReceiveRequestUnitCase.usd),
      },
    );
    expect(find.text(r'$'), findsWidgets);
    expect(find.text('ZEC'), findsNothing);

    for (final error in ReceiveRequestErrorCase.values) {
      await _pumpSettled(
        tester,
        buildReceiveRequestAmountRowsGalleryCase,
        knobs: {
          'Row': receiveRequestRowLabel(RequestAmountRowCase.amountError),
          'Error': receiveRequestErrorLabel(error),
        },
      );
      expect(
        find.text(switch (error) {
          ReceiveRequestErrorCase.decimals => kRequestAmountDecimalsError,
          ReceiveRequestErrorCase.overSupply => kRequestAmountSupplyError,
          ReceiveRequestErrorCase.notANumber => kRequestAmountFormatError,
        }),
        findsOneWidget,
        reason: error.name,
      );
    }
    await disposeTree(tester);
  });
}

/// The option labels the mounted case registered its `Address` knob with.
List<String> _addressOptions(WidgetbookState state) =>
    (state.knobs['Address']!.fields.single.toJson()['values'] as List)
        .cast<String>();

/// The copy action on whichever result step is mounted.
AppButton _copyLinkButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('request_copy_link_button')),
);

/// The copy action on whichever component case is mounted.
ReceiveCopyAddressButton _copyAddressButton(WidgetTester tester) => tester
    .widget<ReceiveCopyAddressButton>(find.byType(ReceiveCopyAddressButton));

/// The mounted tabs, whose props are what the two call sites differ in.
ReceiveTabs _tabs(WidgetTester tester) =>
    tester.widget<ReceiveTabs>(find.byType(ReceiveTabs));

/// The address line renders its address as `RichText` spans, so the widget's
/// own field is what a test can read.
ReceiveAddressLine _addressLine(WidgetTester tester) =>
    tester.widget<ReceiveAddressLine>(find.byType(ReceiveAddressLine).first);

/// Pumps a use case and lets the async seams settle.
///
/// The receive screens load their addresses through a provider and the QR
/// surfaces rasterise off the fake clock, so a plain pump would compare a
/// mid-transition frame rather than a state; `runAsync` is what lets that real
/// async work finish before the next pump.
Future<WidgetbookState> _pumpSettled(
  WidgetTester tester,
  WidgetBuilder builder, {
  Map<String, String> knobs = const {},
}) async {
  final state = await pumpUseCase(tester, builder, knobs: knobs);
  for (var i = 0; i < 2; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  return state;
}

/// [expectKnobOptionsRenderDistinctly] with the settle pumps above.
Future<void> _expectOptionsRenderDistinctly(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await _pumpSettled(tester, builder, knobs: {...otherKnobs, label: option});
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
  }
  await disposeTree(tester);
}
