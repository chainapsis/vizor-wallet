// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/address_scan/widgets/address_qr_scan_modal.dart';
import '../src/features/address_scan/widgets/mobile_address_scan_card.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../src/features/send/widgets/send_compose_view.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;

// A long memo that exceeds the 512-byte cap, used to preview the over-limit
// error state.
const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin.';

const _sampleUnifiedAddress = 'u112344123478129718 … 1238312779jkasdy';

/// Empty / default compose state — placeholders, collapsed memo card,
/// disabled Review. (Toggle the Widgetbook theme to see dark mode.)
Widget buildSendEmptyUseCase(BuildContext context) {
  return const _SendPageFrame(child: SendComposeView());
}

/// Shielded → Shielded, amount entered, memo expanded, Review enabled.
Widget buildSendShieldedFilledUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      reviewEnabled: true,
    ),
  );
}

/// Shielded → Shielded with a memo over the 512-byte limit: destructive
/// tone, "Message is too long", Review disabled.
Widget buildSendMemoTooLongUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      memoText: _longMemo,
      memoCounter: '-32/512',
      memoError: 'Message is too long',
    ),
  );
}

/// Transparent recipient: grey "Shielded → Transparent" route, memo hidden,
/// Review enabled.
Widget buildSendTransparentUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToTransparent,
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.transparentUnavailable,
      reviewEnabled: true,
    ),
  );
}

/// A contact was picked: the "Send to" link reflects the contact name
/// ("Mike ›") instead of "Contacts ›".
Widget buildSendContactSelectedUseCase(BuildContext context) {
  return const _SendPageFrame(
    child: SendComposeView(
      recipientText: _sampleUnifiedAddress,
      route: SendPoolRoute.shieldedToShielded,
      contactName: 'Mike',
      amountText: '125.12',
      amountFocused: true,
      memoMode: SendMemoMode.expanded,
      reviewEnabled: true,
    ),
  );
}

Widget buildMobileSendRecipientEmptyUseCase(BuildContext context) {
  return const _MobileSendHarness();
}

Widget buildMobileSendRecipientFocusedUseCase(BuildContext context) {
  return const _MobileSendHarness(
    contacts: _mobileSendContacts,
    initialRecipientFocused: true,
  );
}

Widget buildMobileSendRecipientContactsUseCase(BuildContext context) {
  return const _MobileSendHarness(contacts: _mobileSendContacts);
}

Widget buildMobileSendRecipientFilledUseCase(BuildContext context) {
  return const _MobileSendHarness(initialRecipient: _mobileShieldedAddress);
}

Widget buildMobileSendAmountEmptyUseCase(BuildContext context) {
  return const _MobileSendHarness(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendAmountErrorUseCase(BuildContext context) {
  return const _MobileSendHarness(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '243.12',
    initialAmountError: 'Not enough ZEC',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendAmountReadyUseCase(BuildContext context) {
  return const _MobileSendHarness(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '24.312',
    initialAmountReady: true,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendReviewDefaultUseCase(BuildContext context) {
  return const _MobileSendHarness(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '123.12',
    initialReview: true,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendReviewWithMemoUseCase(BuildContext context) {
  return const _MobileSendHarness(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '123.12',
    initialReview: true,
    initialMemo: 'Zcash is a privacy-focused digital currency',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendQrScanUseCase(BuildContext context) {
  return const _MobileSendScanFrame(
    child: MobileAddressScanCardContent(
      key: ValueKey('mobile_send_qr_scan_card'),
      status: AddressQrCameraStatus.active,
      cameraView: _MobileSendScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSendQrScanLoadingUseCase(BuildContext context) {
  return const _MobileSendScanFrame(
    child: MobileAddressScanCardContent(
      key: ValueKey('mobile_send_qr_scan_card'),
      status: AddressQrCameraStatus.loading,
      cameraView: _MobileSendScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSendQrScanRequestingUseCase(BuildContext context) {
  return const _MobileSendScanFrame(
    child: MobileAddressScanCardContent(
      key: ValueKey('mobile_send_qr_scan_card'),
      status: AddressQrCameraStatus.requesting,
      cameraView: _MobileSendScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSendQrScanDeniedUseCase(BuildContext context) {
  return const _MobileSendScanFrame(
    child: MobileAddressScanCardContent(
      key: ValueKey('mobile_send_qr_scan_card'),
      status: AddressQrCameraStatus.denied,
      cameraView: _MobileSendScanCameraPreview(),
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

/// Desktop window chrome (sidebar + pane + back link) wrapping the compose
/// view, mirroring `_SwapPageFrame` so Widgetbook previews use the same
/// surface the real screen lives in.
class _SendPageFrame extends StatelessWidget {
  const _SendPageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1080.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;

        return SizedBox(
          width: width,
          height: height,
          child: AppDesktopShell(
            sidebar: const _PreviewSendSidebar(),
            pane: AppDesktopPane(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PreviewSendPaneToolbar(),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileSendHarness extends StatelessWidget {
  const _MobileSendHarness({
    this.contacts = const [],
    this.initialRecipient,
    this.initialAmount,
    this.initialAmountError,
    this.initialAmountReady = false,
    this.initialReview = false,
    this.initialMemo,
    this.initialContactLabel,
    this.initialContactPictureId,
    this.initialRecipientFocused = false,
  });

  final List<AddressBookContact> contacts;
  final String? initialRecipient;
  final String? initialAmount;
  final String? initialAmountError;
  final bool initialAmountReady;
  final bool initialReview;
  final String? initialMemo;
  final String? initialContactLabel;
  final String? initialContactPictureId;
  final bool initialRecipientFocused;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_mobileSendBootstrap),
        syncProvider.overrideWith(() => _WidgetbookSendSyncNotifier()),
        zecMarketDataSourceProvider.overrideWithValue(
          const _WidgetbookSendMarketDataSource(),
        ),
        addressBookRepositoryProvider.overrideWithValue(
          _WidgetbookAddressBookRepository(contacts),
        ),
      ],
      child: SizedBox(
        width: 393,
        height: 852,
        child: MobileSendScreen(
          initialRecipient: initialRecipient,
          initialAmount: initialAmount,
          initialAmountError: initialAmountError,
          initialAmountReady: initialAmountReady,
          initialReview: initialReview,
          initialMemo: initialMemo,
          initialContactLabel: initialContactLabel,
          initialContactPictureId: initialContactPictureId,
          initialRecipientFocused: initialRecipientFocused,
          loadWalletDbPath: () async => '/tmp/widgetbook-zcash-wallet.db',
          validateAddress: _widgetbookValidateAddress,
          estimateFee: _widgetbookEstimateFee,
        ),
      ),
    );
  }
}

class _MobileSendScanFrame extends StatelessWidget {
  const _MobileSendScanFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 393,
      height: 852,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          viewPadding: EdgeInsets.only(top: 55),
        ),
        child: ColoredBox(
          color: colors.background.neutralScrim,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                MobileModalCard(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileSendScanCameraPreview extends StatelessWidget {
  const _MobileSendScanCameraPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF111515)),
      child: Center(
        child: SizedBox(
          width: 320,
          height: 320,
          child: PrettyQrView.data(
            data: 'zcash:u1examplezcashaddressforpreviewonly',
            decoration: const PrettyQrDecoration(
              quietZone: PrettyQrQuietZone.zero,
              shape: PrettyQrSmoothSymbol(
                roundFactor: 0,
                color: Color(0xFFEFEDEA),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _noop() {}

const _mobileShieldedAddress =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';

const _mobileTransparentAddress = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

const _mobileSendAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'widgetbook-send',
      name: 'Account1',
      order: 0,
      profilePictureId: 'pfp-01',
    ),
  ],
  activeAccountUuid: 'widgetbook-send',
  activeAddress: _mobileShieldedAddress,
);

final _mobileSendBootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: _mobileSendAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const _mobileSendContacts = [
  AddressBookContact(
    id: 'contact-label-1',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileShieldedAddress,
    profilePictureId: 'pfp-02',
    createdAtMs: 1,
    updatedAtMs: 1,
  ),
  AddressBookContact(
    id: 'contact-label-2',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileTransparentAddress,
    profilePictureId: 'pfp-03',
    createdAtMs: 2,
    updatedAtMs: 2,
  ),
  AddressBookContact(
    id: 'contact-label-3',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileShieldedAddress,
    profilePictureId: 'pfp-04',
    createdAtMs: 3,
    updatedAtMs: 3,
  ),
  AddressBookContact(
    id: 'contact-label-4',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileShieldedAddress,
    profilePictureId: 'pfp-05',
    createdAtMs: 4,
    updatedAtMs: 4,
  ),
  AddressBookContact(
    id: 'contact-label-5',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileShieldedAddress,
    profilePictureId: 'pfp-06',
    createdAtMs: 5,
    updatedAtMs: 5,
  ),
  AddressBookContact(
    id: 'contact-label-6',
    label: 'Contact label',
    network: AddressBookNetwork.zcash,
    address: _mobileShieldedAddress,
    profilePictureId: 'pfp-07',
    createdAtMs: 6,
    updatedAtMs: 6,
  ),
];

Future<rust_sync.AddressValidationResult> _widgetbookValidateAddress({
  required String address,
}) async {
  if (address.startsWith('t1')) {
    return const rust_sync.AddressValidationResult(
      isValid: true,
      addressType: 'transparent',
    );
  }
  return const rust_sync.AddressValidationResult(
    isValid: true,
    addressType: 'unified',
  );
}

Future<BigInt> _widgetbookEstimateFee({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async {
  return BigInt.from(10000);
}

class _WidgetbookSendSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _mobileSendAccountState.activeAccountUuid,
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(14312120000),
    totalBalance: BigInt.from(14312120000),
    percentage: 1,
    displayPercentage: 1,
  );
}

class _WidgetbookAddressBookRepository implements AddressBookRepository {
  const _WidgetbookAddressBookRepository(this.contacts);

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => contacts;

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}

class _WidgetbookSendMarketDataSource implements ZecMarketDataSource {
  const _WidgetbookSendMarketDataSource();

  @override
  Future<ZecMarketData?> fetchMarketData() async {
    return const ZecMarketData(usdPrice: 70);
  }
}

/// Preview sidebar with Home active — mirrors the live desktop nav so the
/// Send page renders in a realistic shell.
class _PreviewSendSidebar extends StatelessWidget {
  const _PreviewSendSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopSidebarSurface(
      glass: true,
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Username',
                    iconName: AppIcons.user,
                    leadingGap: AppSpacing.xs,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Home',
                    iconName: AppIcons.home,
                    active: true,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Swap',
                    iconName: AppIcons.swapArrows,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 34,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: -AppSpacing.md,
                          top: 1,
                          bottom: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.sync.lightSuccess,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(AppRadii.full),
                              ),
                            ),
                            child: const SizedBox(width: 5),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '34% Syncing...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.sync.textSyncing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSendPaneToolbar extends StatelessWidget {
  const _PreviewSendPaneToolbar();

  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.md,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppBackLink(
            key: const ValueKey('send_preview_pane_back_button'),
            label: 'Home',
            minWidth: 60,
            onTap: () {},
          ),
        ),
      ),
    );
  }
}
