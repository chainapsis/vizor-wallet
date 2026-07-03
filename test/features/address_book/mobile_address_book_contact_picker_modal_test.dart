@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/mobile_text_field.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/address_book/widgets/address_book_contact_picker_modal.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('mobile contact picker keeps a stable list viewport', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(_harness([_contact(0)]));
    await tester.pumpAndSettle();

    expect(find.byType(MobileModalScaffold), findsOneWidget);
    expect(find.byType(MobileTextField), findsOneWidget);
    expect(tester.getSize(find.byType(MobileTextField)), const Size(329, 60));
    expect(find.text('Select contact'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('address_book_contact_picker_list_viewport')),
      ),
      const Size(329, 304),
    );

    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('address_book_contact_picker_scrollbar')),
    );
    expect(scrollbar.thumbVisibility, isFalse);
  });

  testWidgets('mobile contact picker scrolls long lists inside the viewport', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _harness([for (var index = 0; index < 8; index++) _contact(index)]),
    );
    await tester.pumpAndSettle();

    final viewport = find.byKey(
      const ValueKey('address_book_contact_picker_list_viewport'),
    );
    expect(tester.getSize(viewport), const Size(329, 304));

    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('address_book_contact_picker_scrollbar')),
    );
    final listView = tester.widget<ListView>(
      find.descendant(of: viewport, matching: find.byType(ListView)),
    );
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.controller, same(listView.controller));

    expect(find.text('Contact 0'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('address_book_contact_picker_list_gutter')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contact 7'), findsOneWidget);
  });
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _harness(List<AddressBookContact> contacts) {
  return ProviderScope(
    overrides: [
      addressBookRepositoryProvider.overrideWithValue(
        _FakeAddressBookRepository(contacts),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (_, navigator) =>
          AppTheme(data: AppThemeData.light, child: navigator!),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MobileModalCard(
            child: AddressBookContactPickerModal(
              title: 'Select contact',
              networks: const [AddressBookNetwork.ethereum],
              onSelected: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

AddressBookContact _contact(int index) {
  return AddressBookContact(
    id: 'contact-$index',
    label: 'Contact $index',
    network: AddressBookNetwork.ethereum,
    address: '0x000000000000000000000000000000000000000$index',
    profilePictureId: 'pfp-01',
    createdAtMs: index,
    updatedAtMs: index,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  const _FakeAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
