import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart' show ObjectDropdownField;
import 'package:zcash_wallet/src/core/widgets/app_profile_picture_picker_modal.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/widgets/address_book_network_icon.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart';
import 'package:zcash_wallet/widgetbook/address_book_use_cases.dart';
import 'package:zcash_wallet/widgetbook/address_scan_use_cases.dart';
import 'package:zcash_wallet/widgetbook/gallery/address_book_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Mostly lane-agnostic: the layout knob is driven by explicit query params, so
// both lanes exercise the same combinations. The exceptions are the real
// AddressBookScreen desktop branch, the row menu and the desktop scan modal,
// which are `WbLaneOnly(desktop)` - their assertions are scoped to the compiled
// desktop lane.
void main() {
  testWidgets('every address book gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(addressBookGalleryNodes).toList();
    expect(useCases.length, 10);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('the static snapshot covers every list state in both layouts', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAddressBookScreenGalleryCase,
      label: 'State',
      optionLabels: addressBookScreenLoadOptions(
        AddressBookScreenPreview.snapshot,
      ).map(addressBookScreenLoadLabel).toList(),
      otherKnobs: {
        ..._snapshotKnobs(WbLayout.desktop),
        addressBookRowMenuKnobLabel: 'false',
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAddressBookScreenGalleryCase,
      label: 'State',
      optionLabels: mobileAddressBookLoadOptions
          .map(mobileAddressBookLoadLabel)
          .toList(),
      otherKnobs: _snapshotKnobs(WbLayout.mobile),
    );

    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAddressBookScreenGalleryCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      otherKnobs: {
        addressBookScreenPreviewKnobLabel: addressBookScreenPreviewLabel(
          AddressBookScreenPreview.snapshot,
        ),
        addressBookRowMenuKnobLabel: 'false',
      },
    );
  });

  testWidgets('Preview swaps the live screen for the static snapshot', (
    tester,
  ) async {
    Future<void> sweep(WbLayout layout) => expectKnobOptionsRenderDistinctly(
      tester,
      buildAddressBookScreenGalleryCase,
      label: addressBookScreenPreviewKnobLabel,
      optionLabels: AddressBookScreenPreview.values
          .map(addressBookScreenPreviewLabel)
          .toList(),
      otherKnobs: {'Layout': wbLayoutLabel(layout)},
    );

    await sweep(WbLayout.mobile);
    // The live desktop branch is the lane notice off the desktop lane.
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      await sweep(WbLayout.desktop);
    }
  });

  testWidgets('row menu knob opens the desktop snapshot context menu', (
    tester,
  ) async {
    // The menu is an OverlayEntry above the capture boundary, so it is
    // asserted by its items rather than by a render fingerprint.
    await pumpUseCase(
      tester,
      buildAddressBookScreenGalleryCase,
      knobs: {
        ..._snapshotKnobs(WbLayout.desktop),
        'State': addressBookScreenLoadLabel(AddressBookScreenLoad.contacts),
        addressBookRowMenuKnobLabel: 'true',
      },
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Edit contact'), findsOneWidget);

    await pumpUseCase(
      tester,
      buildAddressBookScreenGalleryCase,
      knobs: {
        ..._snapshotKnobs(WbLayout.desktop),
        'State': addressBookScreenLoadLabel(AddressBookScreenLoad.contacts),
        addressBookRowMenuKnobLabel: 'false',
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Copy address'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('modal playground covers every modal distinctly', (tester) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildAddressBookModalsGalleryCase,
      label: 'Modal',
      optionLabels: AddressBookModalCase.values
          .map(addressBookModalCaseLabel)
          .toList(),
    );
  });

  testWidgets('contact picker keeps its stub repository contacts', (
    tester,
  ) async {
    await pumpUseCase(tester, buildAddressBookContactPickerGalleryCase);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('USDC recipients'), findsOneWidget);
    await disposeTree(tester);
  });

  // --- Address book screen (real AddressBookScreen) -------------------------

  testWidgets('the screen playground registers each layout\'s own knobs', (
    tester,
  ) async {
    // Lane-agnostic: knobs are registered before `WbLaneOnly` decides whether
    // the desktop branch renders or shows the lane notice.
    Future<Set<String>> knobsOf(Map<String, String> knobs) async {
      final state = await pumpUseCase(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs,
      );
      await tester.pumpAndSettle();
      return state.knobs.keys.toSet();
    }

    expect(await knobsOf({'Layout': wbLayoutLabel(WbLayout.desktop)}), {
      'Layout',
      addressBookScreenPreviewKnobLabel,
      'State',
      'Networks',
      'Modal',
      'Draft',
      'Avatar',
      addressBookScreenSubmitFailsKnobLabel,
    });
    expect(await knobsOf({'Layout': wbLayoutLabel(WbLayout.mobile)}), {
      'Layout',
      addressBookScreenPreviewKnobLabel,
      'State',
      'Sheet',
      'Network',
      'Draft',
    });

    // The snapshots only vary on the list state, plus the desktop row menu
    // where there is a row to open it on.
    expect(await knobsOf(_snapshotKnobs(WbLayout.desktop)), {
      'Layout',
      addressBookScreenPreviewKnobLabel,
      'State',
      addressBookRowMenuKnobLabel,
    });
    expect(
      await knobsOf({
        ..._snapshotKnobs(WbLayout.desktop),
        'State': addressBookScreenLoadLabel(AddressBookScreenLoad.noContacts),
      }),
      {'Layout', addressBookScreenPreviewKnobLabel, 'State'},
    );
    expect(await knobsOf(_snapshotKnobs(WbLayout.mobile)), {
      'Layout',
      addressBookScreenPreviewKnobLabel,
      'State',
    });
    await disposeTree(tester);
  });

  testWidgets('the desktop Modal knob offers only what each State can open', (
    tester,
  ) async {
    // Lane-agnostic: the options are registered before `WbLaneOnly` decides
    // whether the desktop branch renders.
    const formModals = [
      AddressBookScreenModal.none,
      AddressBookScreenModal.addContact,
      AddressBookScreenModal.avatarPicker,
      AddressBookScreenModal.networkSelector,
    ];
    const expected = <AddressBookScreenLoad, List<AddressBookScreenModal>>{
      AddressBookScreenLoad.contacts: AddressBookScreenModal.values,
      AddressBookScreenLoad.noContacts: formModals,
      AddressBookScreenLoad.noSearchResults: formModals,
      AddressBookScreenLoad.loading: formModals,
      AddressBookScreenLoad.failed: [AddressBookScreenModal.none],
    };
    expect(expected.keys, containsAll(AddressBookScreenLoad.values));

    for (final entry in expected.entries) {
      final state = await pumpUseCase(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: {
          'Layout': wbLayoutLabel(WbLayout.desktop),
          'State': addressBookScreenLoadLabel(entry.key),
        },
      );
      await tester.pumpAndSettle();
      final field =
          state.knobs['Modal']!.fields.single
              as ObjectDropdownField<AddressBookScreenModal>;
      expect(field.values, entry.value, reason: '${entry.key}');
      expect(addressBookScreenModalOptions(entry.key), entry.value);

      // The error pane has no form or submit, so their knobs are not offered.
      final formKnobs = {
        'Draft',
        'Avatar',
        addressBookScreenSubmitFailsKnobLabel,
      };
      if (entry.key == AddressBookScreenLoad.failed) {
        expect(
          state.knobs.keys.toSet().intersection(formKnobs),
          isEmpty,
          reason: '${entry.key}',
        );
      } else {
        expect(
          state.knobs.keys,
          containsAll(formKnobs),
          reason: '${entry.key}',
        );
      }
    }

    // The empty states keep the add button, so the add form opens over them.
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      for (final load in [
        AddressBookScreenLoad.noContacts,
        AddressBookScreenLoad.noSearchResults,
        AddressBookScreenLoad.loading,
      ]) {
        await _pumpSettled(
          tester,
          buildAddressBookScreenGalleryCase,
          knobs: _desktopScreenKnobs(
            load: load,
            modal: AddressBookScreenModal.addContact,
          ),
        );
        expect(find.text('Address label'), findsOneWidget, reason: '$load');
      }
    }
    await disposeTree(tester);
  });

  group('address book screen > Desktop layout', () {
    testWidgets('every State option renders its own pane', (tester) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      Future<void> pumpState(AddressBookScreenLoad load) => _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: _desktopScreenKnobs(load: load),
      );

      await pumpState(AddressBookScreenLoad.contacts);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);

      await pumpState(AddressBookScreenLoad.noContacts);
      expect(find.text('No contacts yet'), findsOneWidget);

      await pumpState(AddressBookScreenLoad.noSearchResults);
      expect(find.text('No contacts were found'), findsOneWidget);

      await pumpState(AddressBookScreenLoad.failed);
      expect(
        find.textContaining("Couldn't load your contacts."),
        findsOneWidget,
      );

      // Loading has no pane of its own by design — it keeps the previous data
      // (none here) and never shows a spinner, so it is asserted by that
      // absence rather than by a distinct render.
      await pumpState(AddressBookScreenLoad.loading);
      expect(find.text('No contacts yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('Networks options group the list differently', (tester) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: _desktopScreenKnobs(
          contacts: AddressBookScreenContacts.zcashOnly,
        ),
      );
      expect(find.text('Zcash'), findsOneWidget);
      expect(find.text('Solana'), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: _desktopScreenKnobs(
          contacts: AddressBookScreenContacts.mixedNetworks,
        ),
      );
      expect(find.text('Solana'), findsOneWidget);
      expect(find.text('Bitcoin'), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: _desktopScreenKnobs(
          contacts: AddressBookScreenContacts.allNetworks,
        ),
      );
      expect(find.text('Bitcoin'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('Modal None keeps the pane the State knob picked', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      // The folded default: the modal axis starts closed, which is the render
      // the desktop use case had before the modals case merged into it.
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: _desktopScreenKnobs(),
      );
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Address label'), findsNothing);
      await disposeTree(tester);
    });
  });

  group('address book screen > Desktop modals', () {
    Map<String, String> knobs({
      AddressBookScreenModal modal = AddressBookScreenModal.addContact,
      AddressBookScreenDraft draft = AddressBookScreenDraft.unchanged,
      AddressBookScreenAvatar avatar = AddressBookScreenAvatar.defaultPicture,
      bool submitFails = false,
    }) {
      return _desktopScreenKnobs(
        modal: modal,
        draft: draft,
        avatar: avatar,
        submitFails: submitFails,
      );
    }

    testWidgets('every Modal option opens its production modal', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.addContact),
      );
      expect(find.text('Address label'), findsOneWidget);
      expect(find.text('Update'), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.editContact),
      );
      expect(find.text('Update'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.avatarPicker),
      );
      expect(find.text('Select contact picture'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.networkSelector),
      );
      expect(find.text('Select network'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.removeContact),
      );
      expect(find.text('Remove contact'), findsOneWidget);
      expect(
        find.text('Mike will be removed from your contacts.'),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('every Draft option reaches its own validation tier', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      Future<void> pumpDraft(AddressBookScreenDraft draft) => _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.editContact, draft: draft),
      );

      await pumpDraft(AddressBookScreenDraft.unchanged);
      expect(find.text('Use 1-20 characters'), findsNothing);
      expect(find.text('Invalid Zcash address'), findsNothing);

      await pumpDraft(AddressBookScreenDraft.labelTooLong);
      expect(find.text('Use 1-20 characters'), findsOneWidget);

      await pumpDraft(AddressBookScreenDraft.invalidAddress);
      expect(find.text('Invalid Zcash address'), findsOneWidget);

      await pumpDraft(AddressBookScreenDraft.addressAdvisory);
      expect(
        find.text(
          'NEAR accounts usually end in .near — double-check this address',
        ),
        findsOneWidget,
      );

      await disposeTree(tester);
    });

    testWidgets('every Avatar option lands on the draft profile picture', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      Future<String> pumpAvatar(AddressBookScreenAvatar avatar) async {
        await _pumpSettled(
          tester,
          buildAddressBookScreenGalleryCase,
          knobs: knobs(
            modal: AddressBookScreenModal.avatarPicker,
            avatar: avatar,
          ),
        );
        return tester
            .widget<AppProfilePicturePickerModal>(
              find.byType(AppProfilePicturePickerModal),
            )
            .currentProfilePictureId;
      }

      expect(
        await pumpAvatar(AddressBookScreenAvatar.defaultPicture),
        'pfp-01',
      );
      expect(await pumpAvatar(AddressBookScreenAvatar.pfp08), 'pfp-08');
      expect(await pumpAvatar(AddressBookScreenAvatar.lastOption), 'pfp-15');

      await disposeTree(tester);
    });

    testWidgets('Submit fails surfaces the save and remove errors', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(
          modal: AddressBookScreenModal.editContact,
          submitFails: true,
        ),
      );
      expect(find.text("Couldn't save contact. Try again."), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(
          modal: AddressBookScreenModal.removeContact,
          submitFails: true,
        ),
      );
      expect(find.text("Couldn't remove contact. Try again."), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: knobs(modal: AddressBookScreenModal.editContact),
      );
      expect(find.text("Couldn't save contact. Try again."), findsNothing);

      await disposeTree(tester);
    });
  });

  group('contact row menu > Playground', () {
    testWidgets('the menu knob opens the production context menu', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      // The menu is an OverlayEntry above the capture boundary, so it is
      // asserted by its items rather than by a render fingerprint.
      await _pumpSettled(
        tester,
        buildAddressBookRowMenuGalleryCase,
        knobs: {
          'Network': addressBookRowMenuNetworkLabel(
            AddressBookRowMenuNetwork.zcash,
          ),
          addressBookScreenMenuOpenKnobLabel: 'true',
        },
      );
      expect(find.text('Copy address'), findsOneWidget);
      expect(find.text('Edit contact'), findsOneWidget);
      expect(find.text('Remove contact'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookRowMenuGalleryCase,
        knobs: {
          'Network': addressBookRowMenuNetworkLabel(
            AddressBookRowMenuNetwork.zcash,
          ),
          addressBookScreenMenuOpenKnobLabel: 'false',
        },
      );
      expect(find.text('Copy address'), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('Send ZEC is offered only for a Zcash contact', (tester) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await _pumpSettled(
        tester,
        buildAddressBookRowMenuGalleryCase,
        knobs: {
          'Network': addressBookRowMenuNetworkLabel(
            AddressBookRowMenuNetwork.zcash,
          ),
          addressBookScreenMenuOpenKnobLabel: 'true',
        },
      );
      expect(find.text('Send ZEC'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookRowMenuGalleryCase,
        knobs: {
          'Network': addressBookRowMenuNetworkLabel(
            AddressBookRowMenuNetwork.otherNetwork,
          ),
          addressBookScreenMenuOpenKnobLabel: 'true',
        },
      );
      expect(find.text('Copy address'), findsOneWidget);
      expect(find.text('Send ZEC'), findsNothing);

      await disposeTree(tester);
    });
  });

  // --- Contact picker -------------------------------------------------------

  group('contact picker > Playground', () {
    Map<String, String> pickerKnobs({
      AddressBookPickerContacts contacts = AddressBookPickerContacts.results,
      AddressBookPickerAsync async = AddressBookPickerAsync.loaded,
      AddressBookPickerNetworks networks = AddressBookPickerNetworks.single,
      AddressBookPickerQuery query = AddressBookPickerQuery.empty,
    }) {
      return {
        'Contacts': addressBookPickerContactsLabel(contacts),
        'Load': addressBookPickerAsyncLabel(async),
        'Networks': addressBookPickerNetworksLabel(networks),
        'Search': addressBookPickerQueryLabel(query),
      };
    }

    testWidgets('Contacts and Load reach the list, empty and error copy', (
      tester,
    ) async {
      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(),
      );
      expect(find.text('Mike'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(contacts: AddressBookPickerContacts.noResults),
      );
      expect(find.text('No saved USDC recipients'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(async: AddressBookPickerAsync.failed),
      );
      expect(find.text("Couldn't load contacts. Try again."), findsOneWidget);

      // Not `_pumpSettled`: the loader icon animates forever.
      await pumpUseCase(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(async: AddressBookPickerAsync.loading),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.text('Mike'), findsNothing);
      expect(find.text("Couldn't load contacts. Try again."), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('Networks adds the per-row badge only when there are several', (
      tester,
    ) async {
      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(),
      );
      expect(find.byType(AddressBookNetworkIcon), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(networks: AddressBookPickerNetworks.multiple),
      );
      // Two Ethereum contacts plus the Zcash one, each badged.
      expect(find.byType(AddressBookNetworkIcon), findsNWidgets(3));

      await disposeTree(tester);
    });

    testWidgets('Search seeds the query and filters the list', (tester) async {
      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(),
      );
      expect(find.text('John'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookContactPickerGalleryCase,
        knobs: pickerKnobs(query: AddressBookPickerQuery.typed),
      );
      expect(find.text(addressBookPickerTypedQuery), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('John'), findsNothing);

      await disposeTree(tester);
    });
  });

  // --- Address book screen > Mobile -----------------------------------------

  group('address book screen > Mobile layout', () {
    Map<String, String> mobileKnobs({
      MobileAddressBookLoad load = MobileAddressBookLoad.contacts,
      MobileAddressBookOverlay overlay = MobileAddressBookOverlay.none,
      MobileAddressBookNetwork network = MobileAddressBookNetwork.zcash,
      MobileAddressBookDraft draft = MobileAddressBookDraft.asOpened,
    }) {
      return _mobileScreenKnobs(
        load: load,
        overlay: overlay,
        network: network,
        draft: draft,
      );
    }

    testWidgets('every State option renders its own screen', (tester) async {
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(),
      );
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('Mike'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(load: MobileAddressBookLoad.noContacts),
      );
      expect(find.text('No contacts yet'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(load: MobileAddressBookLoad.noSearchResults),
      );
      expect(find.text('No contacts were found'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('loading and error fall back to the no-contacts screen', (
      tester,
    ) async {
      // Not knob options: the screen reads `.value ?? AddressBookState()`, so
      // neither has a surface of its own. Asserted here so the gap is visible.
      for (final load in [
        MobileAddressBookLoad.loading,
        MobileAddressBookLoad.failed,
      ]) {
        await pumpUseCase(
          tester,
          (_) => mobileAddressBookScreenFixture(load: load),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$load');
        expect(find.text('No contacts yet'), findsOneWidget, reason: '$load');
      }
      await disposeTree(tester);
    });

    testWidgets('every Sheet option opens its production sheet', (
      tester,
    ) async {
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(),
      );
      expect(find.text('Add contact'), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(overlay: MobileAddressBookOverlay.addContact),
      );
      expect(find.text('Add contact'), findsWidgets);
      expect(find.text('Select network'), findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(overlay: MobileAddressBookOverlay.networkPicker),
      );
      expect(find.text('Select network'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);

      await disposeTree(tester);
    });

    testWidgets('the add sheet opens from the empty state too', (tester) async {
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(
          load: MobileAddressBookLoad.noContacts,
          overlay: MobileAddressBookOverlay.addContact,
        ),
      );
      expect(find.text('Add a name'), findsOneWidget);
      await disposeTree(tester);
    });

    testWidgets('Network picks the draft network through the picker', (
      tester,
    ) async {
      // The contacts list behind the sheet carries network names too, so the
      // assertion reads the sheet's own network field.
      AddressBookNetwork fieldNetwork() => tester
          .widget<AddressBookNetworkIcon>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile_address_book_network')),
              matching: find.byType(AddressBookNetworkIcon),
            ),
          )
          .network;

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(overlay: MobileAddressBookOverlay.addContact),
      );
      expect(fieldNetwork(), AddressBookNetwork.zcash);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(
          overlay: MobileAddressBookOverlay.addContact,
          network: MobileAddressBookNetwork.solana,
        ),
      );
      expect(fieldNetwork(), AddressBookNetwork.solana);

      await disposeTree(tester);
    });

    testWidgets('every Draft option changes the add sheet', (tester) async {
      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(overlay: MobileAddressBookOverlay.addContact),
      );
      expect(find.text('Invalid Zcash address'), findsNothing);
      expect(_clearNameButton, findsNothing);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(
          overlay: MobileAddressBookOverlay.addContact,
          draft: MobileAddressBookDraft.invalidAddress,
        ),
      );
      expect(find.text('Invalid Zcash address'), findsOneWidget);

      await _pumpSettled(
        tester,
        buildAddressBookScreenGalleryCase,
        knobs: mobileKnobs(
          overlay: MobileAddressBookOverlay.addContact,
          draft: MobileAddressBookDraft.typing,
        ),
      );
      expect(_clearNameButton, findsOneWidget);

      await disposeTree(tester);
    });
  });

  // --- Network icon ---------------------------------------------------------

  group('network icon', () {
    testWidgets('every Network option renders that network', (tester) async {
      // Not a render sweep: several networks deliberately share one asset
      // (Abstract reuses the Ethereum image), so identical pixels are correct.
      for (final network in AddressBookNetwork.values) {
        await pumpUseCase(
          tester,
          buildAddressBookNetworkIconGalleryCase,
          knobs: {'Network': network.label},
        );
        expect(tester.takeException(), isNull, reason: network.label);
        expect(
          tester
              .widget<AddressBookNetworkIcon>(
                find.byType(AddressBookNetworkIcon),
              )
              .network,
          network,
        );
      }
      await disposeTree(tester);
    });

    testWidgets('every Size option renders its call-site size', (tester) async {
      for (final size in AddressBookNetworkIconSize.values) {
        await pumpUseCase(
          tester,
          buildAddressBookNetworkIconGalleryCase,
          knobs: {'Size': addressBookNetworkIconSizeLabel(size)},
        );
        expect(
          tester
              .widget<AddressBookNetworkIcon>(
                find.byType(AddressBookNetworkIcon),
              )
              .size,
          addressBookNetworkIconSizeValue(size),
        );
      }
      await disposeTree(tester);
    });

    testWidgets('All networks shows one icon per network', (tester) async {
      await pumpUseCase(tester, buildAddressBookNetworkIconGridUseCase);
      expect(tester.takeException(), isNull);
      expect(
        find.byType(AddressBookNetworkIcon),
        findsNWidgets(AddressBookNetwork.values.length),
      );
      await disposeTree(tester);
    });
  });

  // --- Contact name inline --------------------------------------------------

  testWidgets('contact name inline covers both axes distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildContactNameInlineGalleryCase,
      label: 'Address',
      optionLabels: ContactNameInlineAddress.values
          .map(contactNameInlineAddressLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildContactNameInlineGalleryCase,
      label: 'Name',
      optionLabels: ContactNameInlineName.values
          .map(contactNameInlineNameLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildContactNameInlineGalleryCase,
      knobs: {
        'Address': contactNameInlineAddressLabel(
          ContactNameInlineAddress.compactAddress,
        ),
      },
    );
    expect(
      find.text('$kContactNameInlineShortName (0x0cd7…7181)'),
      findsOneWidget,
    );
    await disposeTree(tester);
  });

  // --- Address scan ---------------------------------------------------------

  testWidgets('the address scan playground registers each layout\'s knobs', (
    tester,
  ) async {
    // Lane-agnostic: the modal's knobs are registered before `WbLaneOnly`.
    final desktop = await pumpUseCase(
      tester,
      buildAddressScanGalleryCase,
      knobs: _desktopScan,
    );
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'Camera',
      'Scanned code',
      'Camera picker',
    });

    final mobile = await pumpUseCase(
      tester,
      buildAddressScanGalleryCase,
      knobs: _mobileScan,
    );
    expect(mobile.knobs.keys.toSet(), {
      'Layout',
      'Camera',
      'Caption',
      'Flow',
      'Permission chrome',
      'Height',
      addressScanCardCloseKnobLabel,
    });
    await disposeTree(tester);
  });

  testWidgets('the address scan Layout knob swaps modal and card', (
    tester,
  ) async {
    await pumpUseCase(tester, buildAddressScanGalleryCase, knobs: _mobileScan);
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileAddressScanCardContent), findsOneWidget);

    await pumpUseCase(tester, buildAddressScanGalleryCase, knobs: _desktopScan);
    expect(tester.takeException(), isNull);
    expect(find.byType(MobileAddressScanCardContent), findsNothing);
    expect(
      find.byKey(const ValueKey('wb_lane_only_notice')),
      wbCompiledLaneLayout == WbLayout.desktop ? findsNothing : findsOneWidget,
    );
    await disposeTree(tester);
  });

  group('address scan > Desktop modal', () {
    testWidgets('every Camera option renders a different modal', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      // Not `expectKnobOptionsRenderDistinctly`: 'No camera' surfaces a real
      // production defect — the hardcoded fallback description wraps to three
      // lines and overflows the fixed 220px viewport by 12px. The state is
      // real, so the option stays and the overflow is asserted, not hidden.
      final seen = <String, String>{};
      for (final camera in AddressScanModalCamera.values) {
        final label = addressScanModalCameraLabel(camera);
        await pumpUseCase(
          tester,
          buildAddressScanGalleryCase,
          knobs: {..._desktopScan, 'Camera': label},
        );
        _expectDesktopModalOverflow(
          tester,
          overflows: camera == AddressScanModalCamera.unavailable,
          reason: label,
        );

        final fingerprint = await useCaseFingerprint(tester);
        expect(seen[fingerprint], isNull, reason: label);
        seen[fingerprint] = label;
      }
      await disposeTree(tester);
    });

    testWidgets('the device message replaces the generic no-camera copy', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: {
          ..._desktopScan,
          'Camera': addressScanModalCameraLabel(
            AddressScanModalCamera.unavailableDetail,
          ),
        },
      );
      expect(find.text(kAddressScanDeviceMessage), findsOneWidget);
      _expectDesktopModalOverflow(tester, overflows: false);
      await disposeTree(tester);
    });

    testWidgets('Scanned code puts the rejection under the viewport', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: _desktopScan,
      );
      expect(find.text(kAddressScanNoAddressError), findsNothing);

      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: {
          ..._desktopScan,
          'Scanned code': addressScanModalErrorLabel(
            AddressScanModalError.noAddress,
          ),
        },
      );
      expect(find.text(kAddressScanNoAddressError), findsOneWidget);
      // A second real production defect this case surfaces: with the camera
      // footer up, the error line squeezes the fixed 276px camera box and the
      // desktop modal overflows by 16px.
      _expectDesktopModalOverflow(tester, overflows: true);
      await disposeTree(tester);
    });

    testWidgets('Camera picker arms the footer, and only while scanning', (
      tester,
    ) async {
      if (wbCompiledLaneLayout != WbLayout.desktop) return;
      // The footer's enabled state is a tap target, not copy, so it is read
      // off the detector rather than from a render fingerprint.
      bool? footerEnabled() {
        final footer = find.byKey(const ValueKey('address_scan_camera_footer'));
        if (footer.evaluate().isEmpty) return null;
        return tester
                .widget<GestureDetector>(
                  find
                      .ancestor(
                        of: footer,
                        matching: find.byType(GestureDetector),
                      )
                      .first,
                )
                .onTap !=
            null;
      }

      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: _desktopScan,
      );
      expect(footerEnabled(), isTrue);

      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: {
          ..._desktopScan,
          'Camera picker': addressScanModalPickerLabel(
            AddressScanModalPicker.singleCamera,
          ),
        },
      );
      expect(footerEnabled(), isFalse);

      // Hidden entirely once there is nothing to pick a camera for.
      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: {
          ..._desktopScan,
          'Camera': addressScanModalCameraLabel(
            AddressScanModalCamera.unavailableDetail,
          ),
        },
      );
      expect(footerEnabled(), isNull);
      _expectDesktopModalOverflow(tester, overflows: false);
      await disposeTree(tester);
    });
  });

  group('address scan > Mobile scan card', () {
    testWidgets('every Camera option renders a different card', (tester) async {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildAddressScanGalleryCase,
        label: 'Camera',
        optionLabels: AddressScanCardCamera.values
            .map(addressScanCardCameraLabel)
            .toList(),
        otherKnobs: _mobileScan,
      );
    });

    testWidgets('Caption swaps the idle prompt for each rejection', (
      tester,
    ) async {
      for (final error in AddressScanCardError.values) {
        await pumpUseCase(
          tester,
          buildAddressScanGalleryCase,
          knobs: {..._mobileScan, 'Caption': addressScanCardErrorLabel(error)},
        );
        expect(tester.takeException(), isNull, reason: error.name);
        final expected =
            addressScanCardErrorMessage(error) ??
            addressScanCardCaption(AddressScanCardCopy.sendAndSwap);
        expect(find.text(expected), findsOneWidget, reason: error.name);
      }
      await disposeTree(tester);
    });

    testWidgets('Flow carries each call site\'s own copy', (tester) async {
      for (final copy in AddressScanCardCopy.values) {
        await pumpUseCase(
          tester,
          buildAddressScanGalleryCase,
          knobs: {..._mobileScan, 'Flow': addressScanCardCopyLabel(copy)},
        );
        expect(find.text(addressScanCardCaption(copy)), findsOneWidget);

        await pumpUseCase(
          tester,
          buildAddressScanGalleryCase,
          knobs: {
            ..._mobileScan,
            'Flow': addressScanCardCopyLabel(copy),
            'Camera': addressScanCardCameraLabel(
              AddressScanCardCamera.requesting,
            ),
          },
        );
        expect(
          find.text(addressScanCardPermissionTitle(copy)),
          findsOneWidget,
          reason: copy.name,
        );
      }
      await disposeTree(tester);
    });

    testWidgets('Permission chrome swaps the card behind the camera', (
      tester,
    ) async {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildAddressScanGalleryCase,
        label: 'Permission chrome',
        optionLabels: AddressScanCardChrome.values
            .map(addressScanCardChromeLabel)
            .toList(),
        // The chrome only exists while the camera is covered.
        otherKnobs: {
          ..._mobileScan,
          'Camera': addressScanCardCameraLabel(AddressScanCardCamera.denied),
        },
      );
    });

    testWidgets('Height picks the in-page camera box', (tester) async {
      double cardHeight() => tester
          .getSize(find.byType(MobileAddressScanCardContent).first)
          .height;

      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: _mobileScan,
      );
      final modalHeight = cardHeight();

      await pumpUseCase(
        tester,
        buildAddressScanGalleryCase,
        knobs: {
          ..._mobileScan,
          'Height': addressScanCardHeightLabel(AddressScanCardHeight.inPage),
        },
      );
      expect(cardHeight(), kAddressScanInPageCameraHeight);
      expect(modalHeight, isNot(kAddressScanInPageCameraHeight));
      await disposeTree(tester);
    });

    testWidgets('Close enabled dims the close glyph', (tester) async {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildAddressScanGalleryCase,
        label: addressScanCardCloseKnobLabel,
        optionLabels: const ['true', 'false'],
        otherKnobs: _mobileScan,
      );
    });
  });

  group('camera error overlay', () {
    testWidgets('every Camera option renders distinctly', (tester) async {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildMobileScanCameraErrorOverlayGalleryCase,
        label: 'Camera',
        optionLabels: MobileScanOverlayError.values
            .map(mobileScanOverlayErrorLabel)
            .toList(),
      );
    });

    testWidgets('only a denied camera offers the settings trip', (
      tester,
    ) async {
      final settings = find.byKey(
        const ValueKey('mobile_scan_open_settings_button'),
      );

      await pumpUseCase(tester, buildMobileScanCameraErrorOverlayGalleryCase);
      expect(find.text(kMobileScanPermissionDeniedMessage), findsOneWidget);
      expect(settings, findsOneWidget);

      await pumpUseCase(
        tester,
        buildMobileScanCameraErrorOverlayGalleryCase,
        knobs: {
          'Camera': mobileScanOverlayErrorLabel(
            MobileScanOverlayError.unavailable,
          ),
        },
      );
      expect(find.text(kMobileScanUnavailableMessage), findsOneWidget);
      expect(settings, findsNothing);

      await pumpUseCase(
        tester,
        buildMobileScanCameraErrorOverlayGalleryCase,
        knobs: {
          'Camera': mobileScanOverlayErrorLabel(MobileScanOverlayError.none),
        },
      );
      expect(find.text(kMobileScanUnavailableMessage), findsNothing);
      expect(settings, findsNothing);
      await disposeTree(tester);
    });
  });

  testWidgets('every viewfinder bracket geometry renders distinctly', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildMobileScanViewfinderGalleryCase,
      label: 'Brackets',
      optionLabels: MobileScanViewfinderVariant.values
          .map(mobileScanViewfinderVariantLabel)
          .toList(),
    );

    await pumpUseCase(
      tester,
      buildMobileScanViewfinderGalleryCase,
      knobs: {
        'Brackets': mobileScanViewfinderVariantLabel(
          MobileScanViewfinderVariant.allThree,
        ),
      },
    );
    expect(
      find.byType(MobileScanViewfinderCorners),
      findsNWidgets(kMobileScanViewfinderGeometry.length),
    );
    await disposeTree(tester);
  });
}

/// The scan modal's fixed 312×440 geometry — and the two overflows it has — is
/// the desktop branch; the mobile lane renders the hug-content branch with its
/// own metrics, so those assertions are scoped to the compiled lane.
void _expectDesktopModalOverflow(
  WidgetTester tester, {
  required bool overflows,
  String? reason,
}) {
  final exception = tester.takeException();
  if (wbCompiledLaneLayout != WbLayout.desktop) return;
  expect(exception, overflows ? isFlutterError : isNull, reason: reason);
}

final Map<String, String> _desktopScan = {
  'Layout': wbLayoutLabel(WbLayout.desktop),
};
final Map<String, String> _mobileScan = {
  'Layout': wbLayoutLabel(WbLayout.mobile),
};

/// The screen playground's static snapshot for [layout].
Map<String, String> _snapshotKnobs(WbLayout layout) => {
  'Layout': wbLayoutLabel(layout),
  addressBookScreenPreviewKnobLabel: addressBookScreenPreviewLabel(
    AddressBookScreenPreview.snapshot,
  ),
};

/// The screen playground's desktop knob set at its defaults, so a test names
/// only the axis it sweeps and the folded case still gets the whole set.
Map<String, String> _desktopScreenKnobs({
  AddressBookScreenLoad load = AddressBookScreenLoad.contacts,
  AddressBookScreenContacts contacts = AddressBookScreenContacts.zcashOnly,
  AddressBookScreenModal modal = AddressBookScreenModal.none,
  AddressBookScreenDraft draft = AddressBookScreenDraft.unchanged,
  AddressBookScreenAvatar avatar = AddressBookScreenAvatar.defaultPicture,
  bool submitFails = false,
}) {
  return {
    'Layout': wbLayoutLabel(WbLayout.desktop),
    addressBookScreenPreviewKnobLabel: addressBookScreenPreviewLabel(
      AddressBookScreenPreview.live,
    ),
    'State': addressBookScreenLoadLabel(load),
    'Networks': addressBookScreenContactsLabel(contacts),
    'Modal': addressBookScreenModalLabel(modal),
    'Draft': addressBookScreenDraftLabel(draft),
    'Avatar': addressBookScreenAvatarLabel(avatar),
    addressBookScreenSubmitFailsKnobLabel: '$submitFails',
  };
}

/// The same for the mobile branch, whose axes are sheets rather than modals.
Map<String, String> _mobileScreenKnobs({
  MobileAddressBookLoad load = MobileAddressBookLoad.contacts,
  MobileAddressBookOverlay overlay = MobileAddressBookOverlay.none,
  MobileAddressBookNetwork network = MobileAddressBookNetwork.zcash,
  MobileAddressBookDraft draft = MobileAddressBookDraft.asOpened,
}) {
  return {
    'Layout': wbLayoutLabel(WbLayout.mobile),
    addressBookScreenPreviewKnobLabel: addressBookScreenPreviewLabel(
      AddressBookScreenPreview.live,
    ),
    'State': mobileAddressBookLoadLabel(load),
    'Sheet': mobileAddressBookOverlayLabel(overlay),
    'Network': mobileAddressBookNetworkLabel(network),
    'Draft': mobileAddressBookDraftLabel(draft),
  };
}

/// The edit sheet's name clear (x), which only appears with text and focus.
final Finder _clearNameButton = find.bySemanticsLabel('Clear name');

/// The screen fixtures resolve their provider and replay their driver steps
/// over several frames, so every assertion pumps to a settled tree.
Future<void> _pumpSettled(
  WidgetTester tester,
  WidgetBuilder builder, {
  Map<String, String> knobs = const {},
}) async {
  await pumpUseCase(tester, builder, knobs: knobs);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$knobs');
}
