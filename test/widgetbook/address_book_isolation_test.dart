import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/pay/screens/pay_screen.dart';
import 'package:zcash_wallet/src/features/pay/screens/mobile/mobile_pay_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/pay_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/swap_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/support/wb_address_book_repository.dart';

import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Geist-$weight.ttf'));
    }
    await loader.load();
  });

  final cases = <String, (WidgetBuilder, Type, Type)>{
    'Pay': (buildPayScreenGalleryCase, PayScreen, MobilePayScreen),
    'Swap': (buildSwapScreenGalleryCase, SwapScreen, MobileSwapScreen),
    'Swap pinned mobile': (
      buildSwapPageGalleryCase,
      SwapScreen,
      MobileSwapScreen,
    ),
  };
  for (final entry in cases.entries) {
    for (final layout in WbLayout.values) {
      // The pinned mobile composer has a separate provider scope from the
      // interactive screen; its desktop counterpart is not a screen host.
      if (entry.key == 'Swap pinned mobile' && layout == WbLayout.desktop) {
        continue;
      }
      testWidgets(
        '${entry.key} ${layout.name} persists contacts only in its own preview',
        (tester) async {
          AddressBookRepository? previous;
          for (var mount = 0; mount < 2; mount++) {
            await pumpUseCase(
              tester,
              entry.value.$1,
              knobs: {'Layout': wbLayoutLabel(layout)},
            );
            await tester.pump();
            final scope = ProviderScope.containerOf(
              tester.element(
                find.byType(
                  layout == WbLayout.desktop ? entry.value.$2 : entry.value.$3,
                ),
              ),
              listen: false,
            );
            final repository = scope.read(addressBookRepositoryProvider);
            expect(repository, isA<WbAddressBookRepository>());
            expect(identical(repository, previous), isFalse);
            expect(
              (await repository.loadContacts()).any(
                (c) => c.label == 'Preview contact',
              ),
              isFalse,
            );
            // Exercise the inherited persistence method used by the screen's
            // save/remember callback, with no secure-storage plugin mocks.
            final saved = await scope
                .read(addressBookProvider.notifier)
                .addContact(
                  label: 'Preview contact',
                  network: AddressBookNetwork.ethereum,
                  address: '0x1111111111111111111111111111111111111111',
                  profilePictureId: 'default',
                );
            expect(
              (await repository.loadContacts()).map((c) => c.id),
              contains(saved.id),
            );
            expect(
              scope.read(addressBookProvider).value!.contacts.map((c) => c.id),
              contains(saved.id),
            );
            previous = repository;
            await disposeTree(tester);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }
}
