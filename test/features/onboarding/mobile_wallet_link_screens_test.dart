@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/address_book/models/address_book_contact.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/providers/mobile_wallet_link_provider.dart';

class _WalletLinkController extends MobileWalletLinkController {
  _WalletLinkController(this.initialState);

  final MobileWalletLinkState initialState;

  @override
  MobileWalletLinkState build() => initialState;
}

Widget _app(Widget child, {required MobileWalletLinkState state}) {
  return ProviderScope(
    overrides: [
      mobileWalletLinkControllerProvider.overrideWith(
        () => _WalletLinkController(state),
      ),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: child,
    ),
  );
}

MobileWalletLinkState _state({
  required bool submitting,
  bool contacts = false,
}) {
  const account = WalletLinkTransferAccount(
    uuid: 'software-account',
    name: 'Desktop account',
    order: 0,
    isHardware: false,
    isSeedAnchor: true,
    hardwareKind: null,
    profilePictureId: null,
    birthdayHeight: 120000,
    zip32AccountIndex: 0,
    ufvk: null,
    seedFingerprint: null,
    mnemonic: 'abandon ability able about above absent absorb abstract',
  );
  const contact = AddressBookContact(
    id: 'contact-1',
    label: 'Desktop contact',
    network: AddressBookNetwork.zcash,
    address: 'u1desktopcontactaddress',
    profilePictureId: 'profile_1',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
  final payload = WalletLinkTransferPayload(
    version: 1,
    exportedAt: DateTime.utc(2026, 7, 8),
    network: 'main',
    activeAccountUuid: account.uuid,
    accounts: const [account],
    contacts: contacts ? const [contact] : const [],
  );
  return MobileWalletLinkState(
    payload: payload,
    packageId: '550e8400-e29b-41d4-a716-446655440000',
    completionToken: 'completion-token',
    keyBytes: List<int>.filled(32, 1),
    selectedAccountUuids: const {'software-account'},
    selectedContactIds: contacts ? const {'contact-1'} : const {},
    submitting: submitting,
  );
}

bool _hasIcon(WidgetTester tester, String name) {
  return tester
      .widgetList<AppIcon>(find.byType(AppIcon))
      .any((icon) => icon.name == name);
}

bool _canPop(WidgetTester tester) {
  return tester.widget<PopScope<dynamic>>(find.byType(PopScope)).canPop;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1000)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('account selection shows importing progress while submitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectAccountsScreen(),
        state: _state(submitting: true),
      ),
    );
    await tester.pump();

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('Link 1 account'), findsNothing);
    expect(_hasIcon(tester, AppIcons.loader), isTrue);
    expect(_hasIcon(tester, AppIcons.chevronBackward), isFalse);
    expect(_canPop(tester), isFalse);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();

    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });

  testWidgets('contact selection shows importing progress while submitting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileWalletLinkSelectContactsScreen(),
        state: _state(submitting: true, contacts: true),
      ),
    );
    await tester.pump();

    expect(find.text('Importing...'), findsOneWidget);
    expect(find.text('Import 1 contact'), findsNothing);
    expect(_hasIcon(tester, AppIcons.loader), isTrue);
    expect(_hasIcon(tester, AppIcons.chevronBackward), isFalse);
    expect(_canPop(tester), isFalse);

    await tester.tap(find.text('Deselect all'));
    await tester.pump();

    expect(find.text('Deselect all'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);
  });
}
