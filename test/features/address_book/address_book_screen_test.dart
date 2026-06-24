import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_pane_scroll_scaffold.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_back_link.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/screens/address_book_screen.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('does not show a loading spinner while contacts load', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _DelayedAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts yet'), findsOneWidget);

    repo.complete(const []);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No contacts yet'), findsOneWidget);
  });

  testWidgets('renders empty state and creates a contact from the form', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    expect(find.text('No contacts yet'), findsOneWidget);
    // The no-contacts state drops the page title; the serif empty headline
    // takes that role.
    expect(find.text('Contacts'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      'u1alice',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('u1alice'), findsOneWidget);
    expect(find.text('No contacts yet'), findsNothing);
    expect(find.text('Contacts'), findsOneWidget);
  });

  testWidgets('empty-state add button is a compact users-icon pill', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    final addButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    // Updated design: compact secondary pill, h 36 / min-w 96, no shadow.
    expect(addButton.variant, AppButtonVariant.secondary);
    expect(addButton.size, AppButtonSize.medium);
    expect(addButton.height, 36);
    expect(addButton.minWidth, 96);
    // The no-contacts empty state leads with the users icon (not the default
    // plus-circle the floating button uses).
    final leading = addButton.leading;
    expect(leading, isA<AppIcon>());
    expect((leading! as AppIcon).name, AppIcons.users);
  });

  testWidgets('floating add button is flat and leads with the add icon', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    final addButton = tester.widget<AppButton>(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    expect(addButton.variant, AppButtonVariant.secondary);
    expect(addButton.size, AppButtonSize.medium);
    expect(addButton.height, 36);
    // The floating slot now renders the flat button directly — no min-width
    // stretch and the default plus-circle icon.
    expect(addButton.minWidth, 96);
    final leading = addButton.leading;
    expect(leading, isA<AppIcon>());
    expect((leading! as AppIcon).name, AppIcons.addNew);
  });

  testWidgets('creates a Zcash contact for a TEX address without warning', (
    tester,
  ) async {
    const texAddress = 'tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte';
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Exchange',
    );
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      texAddress,
    );
    await tester.pump();

    expect(find.text('Invalid Zcash address'), findsNothing);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('address_book_contact_submit_button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(repo.contacts.single.network, AddressBookNetwork.zcash);
    expect(repo.contacts.single.address, texAddress);
  });

  testWidgets('warns about a malformed address but still allows saving', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Eve',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'ethereu',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      '0xnope',
    );
    await tester.pump();

    expect(find.text("Invalid EVM address"), findsOneWidget);
    // Soft warning: the save button stays enabled.
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('address_book_contact_submit_button')),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(repo.contacts.single.address, '0xnope');
  });

  testWidgets('warns about a bare NEAR top-level name but allows saving', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Ali',
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'near',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NEAR'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      'alice',
    );
    await tester.pump();

    // Warning severity: surfaced, but rendered as advisory and saveable.
    expect(
      find.text(
        'NEAR accounts usually end in .near — double-check this address',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('address_book_contact_submit_button')),
          )
          .onPressed,
      isNotNull,
    );

    // A dotted account clears the warning.
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_address_field')),
      'alice.near',
    );
    await tester.pump();
    expect(
      find.text(
        'NEAR accounts usually end in .near — double-check this address',
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_submit_button')),
    );
    await tester.pumpAndSettle();

    expect(repo.contacts, hasLength(1));
    expect(repo.contacts.single.address, 'alice.near');
  });

  testWidgets('edit contact label x clears the draft label', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit contact'));
    await tester.pumpAndSettle();

    // The label caption is now shown in edit mode too (was add-only before).
    expect(find.text('Address label'), findsOneWidget);

    final labelFieldFinder = find.descendant(
      of: find.byKey(const ValueKey('address_book_contact_label_field')),
      matching: find.byType(TextField),
    );
    TextField labelField() => tester.widget<TextField>(labelFieldFinder);

    expect(labelField().controller?.text, 'Mike');

    // In edit mode the primary action reads "Update".
    final submitFinder = find.byKey(
      const ValueKey('address_book_contact_submit_button'),
    );
    expect(
      find.descendant(of: submitFinder, matching: find.text('Update')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Clear contact label'));
    await tester.pumpAndSettle();

    expect(labelField().controller?.text, isEmpty);
    // An empty label is invalid, so the submit action is disabled.
    expect(tester.widget<AppButton>(submitFinder).onPressed, isNull);
  });

  testWidgets('filters contacts into the empty search state', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    // Updated design: the contacts search field is the compact 256-wide
    // variant, narrower than the 352-wide group cards.
    final searchField = find.byKey(const ValueKey('address_book_search_field'));
    expect(searchField, findsOneWidget);
    expect(tester.getSize(searchField).width, 256);

    await tester.enterText(searchField, 'nothing');
    await tester.pumpAndSettle();

    expect(find.text('No contacts were found'), findsOneWidget);
    expect(find.text('Try to modify your search'), findsOneWidget);
    expect(find.text('Mike'), findsNothing);
  });

  testWidgets('avatar picker requires a changed selection before update', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Change contact picture'));
    await tester.pumpAndSettle();

    // Picker is titled "Select contact picture" with an "Update" action.
    expect(find.text('Select contact picture'), findsOneWidget);

    final updateFinder = find.byKey(
      const ValueKey('address_book_avatar_update_button'),
    );
    expect(
      find.descendant(of: updateFinder, matching: find.text('Update')),
      findsOneWidget,
    );
    AppButton updateButton() => tester.widget<AppButton>(updateFinder);

    expect(updateButton().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('address_book_avatar_pfp-02')));
    await tester.pumpAndSettle();

    expect(updateButton().onPressed, isNotNull);
  });

  testWidgets('network selector shows empty state when search has no matches', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'Value',
    );
    await tester.pumpAndSettle();

    expect(find.text('No networks found'), findsOneWidget);
    expect(find.text('Zcash'), findsNothing);
    // With no matching rows the list collapses to the empty result, so the
    // scrollbar surface is gone entirely.
    expect(
      find.byKey(const ValueKey('address_book_network_scrollbar')),
      findsNothing,
    );
  });

  testWidgets('network selector shows a visible scrollbar when overflowing', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();

    // The full (unfiltered) network list overflows the modal's fixed list
    // viewport, so the redesign keeps its scrollbar thumb visible to signal
    // there is more content below the clean cut.
    final scrollbarFinder = find.byKey(
      const ValueKey('address_book_network_scrollbar'),
    );
    expect(scrollbarFinder, findsOneWidget);
    expect(
      tester.widget<RawScrollbar>(scrollbarFinder).thumbVisibility,
      isTrue,
      reason: 'overflowing network list must show its scrollbar thumb',
    );

    // Narrow the list to a single match: it no longer overflows, so the
    // always-on thumb is suppressed (no full-length dummy thumb).
    await tester.enterText(
      find.byKey(const ValueKey('address_book_network_search_field')),
      'zcash',
    );
    await tester.pumpAndSettle();

    expect(scrollbarFinder, findsOneWidget);
    expect(
      tester.widget<RawScrollbar>(scrollbarFinder).thumbVisibility,
      isFalse,
      reason: 'a short network list should not force a persistent thumb',
    );
  });

  testWidgets('network selector cancel hugs its label width', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('address_book_network_selector_button')),
    );
    await tester.pumpAndSettle();

    // The redesigned modal trades the full-width cancel for a compact ghost
    // button hugging its label (min width 196, not the old 280 stretch).
    final cancelButton = tester.widget<AppButton>(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(AppButton)),
    );
    expect(cancelButton.variant, AppButtonVariant.ghost);
    expect(cancelButton.minWidth, 196);
  });

  testWidgets('opens address scanner as an in-pane modal', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository();

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_add_contact_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      'Alice',
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Scan address QR'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('address_scan_modal')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      findsNothing,
    );
    expect(find.text('scan route'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('address_scan_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('address_scan_modal')), findsNothing);
    expect(
      find.byKey(const ValueKey('address_book_contact_label_field')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('sends Zcash contacts with a send prefill', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);
    SendPrefillArgs? sentPrefill;

    await tester.pumpWidget(
      _addressBookHarness(
        repo,
        onSendRoute: (prefill) => sentPrefill = prefill,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();

    // The redesigned context menu lists actions top-to-bottom as:
    // Copy address, Send ZEC (Zcash only), Edit contact, Remove contact.
    expect(
      _menuItemOrder(tester, const [
        'Copy address',
        'Send ZEC',
        'Edit contact',
        'Remove contact',
      ]),
      isTrue,
      reason: 'context menu items are out of order',
    );

    await tester.tap(find.text('Send ZEC'));
    await tester.pumpAndSettle();

    expect(sentPrefill?.source, 'address-book');
    expect(sentPrefill?.address, 'u1mike');
    expect(sentPrefill?.label, 'Mike');
    expect(find.text('send route'), findsOneWidget);
  });

  testWidgets('remove contact modal uses a short destructive action label', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove contact'));
    await tester.pumpAndSettle();

    expect(find.text('Remove contact'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('address_book_remove_confirm_button')),
        matching: find.text('Remove'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('omits send action for non-Zcash contacts', (tester) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(
        id: 'solana',
        label: 'Solana Contact',
        address: '43123',
        network: AddressBookNetwork.solana,
      ),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_solana')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit contact'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsNothing);
  });

  testWidgets('dismisses contact menu from outside the address list', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('address_book_contact_menu_mike')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit contact'), findsOneWidget);

    await tester.tapAt(const Offset(80, 120));
    await tester.pumpAndSettle();

    expect(find.text('Edit contact'), findsNothing);
    expect(find.text('Copy address'), findsNothing);
  });

  testWidgets('renders the back link inside the pinned pane toolbar band', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final repo = _FakeAddressBookRepository([
      _contact(id: 'mike', label: 'Mike', address: 'u1mike'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    // The redesign moved the back link out of hand-rolled pane content and into
    // the shared AppPaneToolbar. Exactly one back link exists and it lives
    // inside the toolbar (no pane-content copy lingers).
    final backLink = find.byType(AppBackLink);
    expect(backLink, findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppPaneToolbar), matching: backLink),
      findsOneWidget,
    );

    // It sits in the pinned 48px band at the top of the pane (not the window:
    // the desktop shell sidebar offsets the pane horizontally), left-aligned
    // against the toolbar, and above the 'Contacts' title.
    final backRect = tester.getRect(backLink);
    final toolbarRect = tester.getRect(find.byType(AppPaneToolbar));
    expect(backRect.top, lessThan(AppPaneScrollScaffold.toolbarHeight));
    expect(
      backRect.bottom,
      lessThanOrEqualTo(AppPaneScrollScaffold.toolbarHeight + 1),
    );
    // Chevron hugs the pane/toolbar left edge (small toolbar + back-link
    // inset), not floated into the middle of the band.
    expect(backRect.left - toolbarRect.left, lessThan(24));
    expect(backRect.top, lessThan(tester.getTopLeft(find.text('Contacts')).dy));
  });

  testWidgets('keeps the last group card clear of the floating add button', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    // Enough contacts to overflow the 720px viewport so the pane must scroll
    // and the bottom reserve under the floating button becomes load-bearing.
    final repo = _FakeAddressBookRepository([
      for (var i = 0; i < 18; i++)
        _contact(id: 'c$i', label: 'Contact $i', address: 'u1contact$i'),
    ]);

    await tester.pumpWidget(_addressBookHarness(repo));
    await tester.pumpAndSettle();

    // The contacts list is now a non-scrolling Column; the single scroll
    // surface is AppPaneScrollScaffold's SingleChildScrollView.
    final scrollView = find.byKey(AppPaneScrollScaffold.scrollViewKey);
    expect(scrollView, findsOneWidget);

    // Drive the pane's own scroll surface to the bottom (drag up). The list
    // overflows the viewport, so this exercises the measured bottom reserve.
    await tester.drag(scrollView, const Offset(0, -2000));
    await tester.pumpAndSettle();

    // Guard against a vacuous assertion: the pane must have actually scrolled,
    // which proves the list overflowed the viewport in the first place.
    final scrollableState = tester.state<ScrollableState>(
      find.descendant(of: scrollView, matching: find.byType(Scrollable)).first,
    );
    expect(scrollableState.position.pixels, greaterThan(0));

    // The floating add button is a Stack sibling pinned to the pane bottom; the
    // scaffold's measured bottom reserve must let the last row scroll clear of
    // it instead of being permanently covered.
    final floatingButton = find.byKey(
      const ValueKey('address_book_add_contact_button'),
    );
    expect(floatingButton, findsOneWidget);
    final lastRow = find.byKey(const ValueKey('address_book_contact_row_c17'));
    expect(lastRow, findsOneWidget);
    final lastRowBottom = tester.getRect(lastRow).bottom;
    final floatingButtonTop = tester.getRect(floatingButton).top;
    expect(lastRowBottom, lessThanOrEqualTo(floatingButtonTop + 0.5));
  });
}

/// Returns true when [labels] appear top-to-bottom in the given vertical
/// order on screen. Each label must resolve to exactly one widget.
bool _menuItemOrder(WidgetTester tester, List<String> labels) {
  double? previousTop;
  for (final label in labels) {
    final finder = find.text(label);
    if (finder.evaluate().length != 1) return false;
    final top = tester.getTopLeft(finder).dy;
    if (previousTop != null && top <= previousTop) return false;
    previousTop = top;
  }
  return true;
}

Widget _addressBookHarness(
  AddressBookRepository repo, {
  ValueChanged<SendPrefillArgs?>? onSendRoute,
}) {
  final router = GoRouter(
    initialLocation: '/address-book',
    routes: [
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const AddressBookScreen(),
      ),
      GoRoute(
        path: '/send',
        builder: (_, state) {
          final prefill = state.extra is SendPrefillArgs
              ? state.extra as SendPrefillArgs
              : null;
          onSendRoute?.call(prefill);
          return const Text('send route');
        },
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive')),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/about', builder: (_, _) => const Text('about')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      accountProvider.overrideWith(() => _FakeAccountNotifier(_accountState)),
      addressBookRepositoryProvider.overrideWithValue(repo),
      syncProvider.overrideWith(() => _FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

AddressBookContact _contact({
  required String id,
  required String label,
  String address = 'u1address',
  AddressBookNetwork network = AddressBookNetwork.zcash,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: network,
    address: address,
    profilePictureId: kDefaultProfilePictureId,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

final _accountState = const AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1activeaddress',
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/address-book',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
  }
}

class _DelayedAddressBookRepository implements AddressBookRepository {
  final _loadCompleter = Completer<List<AddressBookContact>>();
  var contacts = <AddressBookContact>[];

  void complete(List<AddressBookContact> contacts) {
    this.contacts = [...contacts];
    _loadCompleter.complete(this.contacts);
  }

  @override
  Future<List<AddressBookContact>> loadContacts() => _loadCompleter.future;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
