@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/screens/mobile/mobile_address_book_screen.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  setUp(() async {
    // No setUp body needed; viewport set per test via setSurfaceSize.
  });

  testWidgets('no-contacts state shows the illustration empty state', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(_harness(_FakeRepo()));
    await tester.pumpAndSettle();

    // Top nav title is present; the top-nav + is hidden when there are no
    // contacts (the centered CTA covers adding the first one).
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile_contacts_add')), findsNothing);

    // Empty state: headline + centered add button, no search field.
    expect(find.text('No contacts yet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_contacts_add_empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_contacts_search_field')),
      findsNothing,
    );
  });

  testWidgets('groups contacts by network with a search field', (tester) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness(
        _FakeRepo([
          _contact(id: 'mike', label: 'Mike'),
          _contact(
            id: 'sol',
            label: 'Solana Binance',
            address: '43123abc987def43123xyz',
            network: AddressBookNetwork.solana,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile_contacts_search_field')),
      findsOneWidget,
    );
    // Network group headers + contact labels.
    expect(find.text('Zcash'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Solana Binance'), findsOneWidget);
  });

  testWidgets('row menu exposes Send ZEC only for Zcash contacts', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness(
        _FakeRepo([
          _contact(id: 'mike', label: 'Mike'),
          _contact(
            id: 'sol',
            label: 'Solana Binance',
            address: '43123abc987def43123xyz',
            network: AddressBookNetwork.solana,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // Zcash contact: full menu including Send ZEC.
    await tester.tap(find.byKey(const ValueKey('mobile_contact_menu_mike')));
    await tester.pumpAndSettle();
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsOneWidget);
    expect(find.text('Edit contact'), findsOneWidget);
    expect(find.text('Remove contact'), findsOneWidget);
    final openMenuButton = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile_contact_menu_button_mike')),
    );
    expect(
      (openMenuButton.decoration as BoxDecoration).color,
      AppThemeData.light.colors.state.hover,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_contact_menu_card'))),
      const Size(173, 173),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_contact_menu_copy'))),
      const Size(165, 26),
    );

    // Dismiss the menu (tap the scrim).
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Solana contact: no Send ZEC (can't send from wallet).
    await tester.tap(find.byKey(const ValueKey('mobile_contact_menu_sol')));
    await tester.pumpAndSettle();
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Send ZEC'), findsNothing);
    expect(find.text('Edit contact'), findsOneWidget);
    expect(find.text('Remove contact'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_contact_menu_card'))),
      const Size(173, 139),
    );
  });

  testWidgets('remove contact sheet uses a short destructive action label', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness(_FakeRepo([_contact(id: 'mike', label: 'Mike')])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_contact_menu_mike')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove contact'));
    await tester.pumpAndSettle();

    expect(find.text('Remove contact?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_address_book_remove_confirm')),
        matching: find.text('Remove'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('non-matching search shows the empty-search state', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness(_FakeRepo([_contact(id: 'mike', label: 'Mike')])),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('mobile_contacts_search_field')),
      'zzzz',
    );
    await tester.pumpAndSettle();

    expect(find.text('No contacts were found'), findsOneWidget);
    expect(find.text('Mike'), findsNothing);
    // The search field stays visible above the empty result.
    expect(
      find.byKey(const ValueKey('mobile_contacts_search_field')),
      findsOneWidget,
    );
  });

  testWidgets('the + button opens the add-contact sheet', (tester) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness(_FakeRepo([_contact(id: 'mike', label: 'Mike')])),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_contacts_add')));
    await tester.pumpAndSettle();

    // The add sheet shows its network/name/address fields and a save button.
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_address_book_save')),
      findsOneWidget,
    );
    // The address field carries a QR scan affordance.
    expect(find.bySemanticsLabel('Scan address QR'), findsOneWidget);
  });

  testWidgets('save enables only with a label and a valid address', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(_harness(_FakeRepo()));
    await tester.pumpAndSettle();

    // No contacts yet → open the add sheet from the empty-state CTA.
    await tester.tap(find.byKey(const ValueKey('mobile_contacts_add_empty')));
    await tester.pumpAndSettle();

    AppButton save() => tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_address_book_save')),
    );

    // Empty form → disabled, and no clear (×) on an empty field.
    expect(save().onPressed, isNull);
    expect(find.bySemanticsLabel('Clear address'), findsNothing);

    // Label only → still disabled.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_address_book_label')),
      'Alice',
    );
    await tester.pump();
    expect(save().onPressed, isNull);

    // Invalid Zcash address → disabled, format error shown, and a clear (×)
    // appears now that the focused field has text.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_address_book_address')),
      'foo',
    );
    await tester.pumpAndSettle();
    expect(save().onPressed, isNull);
    expect(find.text('Invalid Zcash address'), findsOneWidget);
    expect(find.bySemanticsLabel('Clear address'), findsOneWidget);

    // Switch to Ethereum and enter a valid EVM address → enabled.
    await tester.tap(find.byKey(const ValueKey('mobile_address_book_network')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ethereum'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_address_book_address')),
      '0x1234567890abcdef1234567890abcdef12345678',
    );
    await tester.pump();
    expect(save().onPressed, isNotNull);
  });
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _harness(AddressBookRepository repo) {
  final router = GoRouter(
    initialLocation: '/settings/address-book',
    routes: [
      GoRoute(
        path: '/settings/address-book',
        builder: (_, _) => const MobileAddressBookScreen(),
      ),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
    ],
  );

  return ProviderScope(
    overrides: [addressBookRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AddressBookContact _contact({
  required String id,
  required String label,
  String address = 'u1234512345abcdef67890zyxwv',
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

class _FakeRepo implements AddressBookRepository {
  _FakeRepo([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts = [...contacts];
  }
}
