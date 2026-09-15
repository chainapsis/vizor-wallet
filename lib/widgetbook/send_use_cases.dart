// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'dart:async';

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
import '../src/features/send/services/send_flow.dart'
    show kWrongNetworkAddressMessage;
import '../src/features/send/services/send_proving_key_warmup.dart';
import 'send_compose_view.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'support/wb_layout.dart';

// A long memo that exceeds the 512-byte cap, used to preview the over-limit
// error state.
const _longMemo =
    'Zcash is a privacy-focused cryptocurrency which features an encrypted '
    'ledger using zero-knowledge proofs. Launched in October 2016, Zcash was '
    'developed by cryptographers at Johns Hopkins University and MIT and '
    'derived its code from bitcoin.';

const _sampleUnifiedAddress = 'u112344123478129718 … 1238312779jkasdy';

/// Recipient the filled compose previews put in the "Send to" field.
const kSendComposeFixtureAddress = _sampleUnifiedAddress;

/// Memo over the 512-byte cap, with the counter and error the screen shows.
const kSendComposeFixtureLongMemo = _longMemo;
const kSendComposeFixtureMemoCounter = '-32/512';
const kSendComposeFixtureMemoError = 'Message is too long';

/// Amount-field error the composer shows when the spend exceeds the balance.
const kSendComposeFixtureAmountError = 'Insufficient shielded balance';

/// Parameterised desktop compose preview: the real [SendComposeView] on the
/// `_SendPageFrame` shell.
///
/// Every default mirrors `SendComposeView`'s own, so the builders below stay
/// one-line delegates whose renders are unchanged.
Widget sendComposeFixture({
  String recipientText = '',
  SendPoolRoute route = SendPoolRoute.unknown,
  String amountText = '',
  bool amountInputIsUsd = false,
  String? amountConversionText = r'$ 0',
  bool amountConversionLoading = false,
  bool amountFocused = false,
  String? amountError,
  SendMemoMode memoMode = SendMemoMode.prompt,
  String memoText = '',
  String memoCounter = '512/512',
  String? memoError,
  bool reviewEnabled = false,
}) {
  return _SendPageFrame(
    child: SendComposeView(
      recipientText: recipientText,
      route: route,
      amountText: amountText,
      amountInputIsUsd: amountInputIsUsd,
      amountConversionText: amountConversionText,
      amountConversionLoading: amountConversionLoading,
      amountFocused: amountFocused,
      amountError: amountError,
      memoMode: memoMode,
      memoText: memoText,
      memoCounter: memoCounter,
      memoError: memoError,
      reviewEnabled: reviewEnabled,
    ),
  );
}

/// Empty / default compose state — placeholders, collapsed memo card,
/// disabled Review. (Toggle the Widgetbook theme to see dark mode.)
Widget buildSendEmptyUseCase(BuildContext context) => sendComposeFixture();

/// Shielded recipient, amount entered, memo expanded, Review enabled.
Widget buildSendShieldedFilledUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '125.12',
    amountConversionText: r'$ 8,758.40',
    amountFocused: true,
    memoMode: SendMemoMode.expanded,
    reviewEnabled: true,
  );
}

/// Transparent recipient: memo hidden, Review enabled.
Widget buildSendTransparentUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToTransparent,
    amountText: '125.12',
    amountConversionText: r'$ 8,758.40',
    amountFocused: true,
    memoMode: SendMemoMode.transparentUnavailable,
    reviewEnabled: true,
  );
}

/// A contact-backed address is filled, but the picker affordance stays as
/// `Contacts ›`.
Widget buildSendContactSelectedUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '125.12',
    amountConversionText: r'$ 8,758.40',
    amountFocused: true,
    memoMode: SendMemoMode.expanded,
    reviewEnabled: true,
  );
}

Widget buildSendUsdInputUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '512.24',
    amountInputIsUsd: true,
    amountConversionText: '125.12 ZEC',
    amountFocused: true,
    memoMode: SendMemoMode.expanded,
    reviewEnabled: true,
  );
}

Widget buildSendNotEnoughUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '50,012.24',
    amountInputIsUsd: true,
    amountConversionText: '651.12 ZEC',
    amountFocused: true,
    amountError: 'Insufficient shielded balance',
    memoMode: SendMemoMode.expanded,
  );
}

/// Parameterised mobile send wizard preview: the real [MobileSendScreen]
/// behind deterministic provider overrides and injected Rust seams.
///
/// The builders below are one-line delegates onto it, each keeping the
/// arguments it already passed, so their renders are unchanged.
Widget mobileSendFixture({
  List<AddressBookContact> contacts = const [],
  Map<String, AccountInfo> ownAccountAddresses = const {},
  String? initialRecipient,
  String? initialAddressType,
  String? initialAmount,
  String? initialFiatAmount,
  MobileSendAmountInputMode initialAmountInputMode =
      MobileSendAmountInputMode.zec,
  String? initialAmountError,
  bool initialAmountReady = false,
  bool initialAmountStep = false,
  bool initialReview = false,
  BigInt? initialFeeZatoshi,
  bool refreshReviewFeeOnInit = false,
  bool useRouteSteps = false,
  String? initialMemo,
  String? initialContactLabel,
  String? initialContactPictureId,
  bool initialRecipientFocused = false,
  bool isPaymentRequest = false,
  String? paymentRequestLabel,
  BigInt? requestedAmountZatoshi,
  MobileSendFeeEstimator estimateFee = _widgetbookEstimateFee,
}) {
  return _MobileSendHarness(
    contacts: contacts,
    ownAccountAddresses: ownAccountAddresses,
    initialRecipient: initialRecipient,
    initialAddressType: initialAddressType,
    initialAmount: initialAmount,
    initialFiatAmount: initialFiatAmount,
    initialAmountInputMode: initialAmountInputMode,
    initialAmountError: initialAmountError,
    initialAmountReady: initialAmountReady,
    initialAmountStep: initialAmountStep,
    initialReview: initialReview,
    initialFeeZatoshi: initialFeeZatoshi,
    refreshReviewFeeOnInit: refreshReviewFeeOnInit,
    useRouteSteps: useRouteSteps,
    initialMemo: initialMemo,
    initialContactLabel: initialContactLabel,
    initialContactPictureId: initialContactPictureId,
    initialRecipientFocused: initialRecipientFocused,
    isPaymentRequest: isPaymentRequest,
    paymentRequestLabel: paymentRequestLabel,
    requestedAmountZatoshi: requestedAmountZatoshi,
    estimateFee: estimateFee,
  );
}

/// Recipient addresses the preview validator resolves to each address type.
const kMobileSendUnifiedAddress = _mobileShieldedAddress;
const kMobileSendSaplingAddress =
    'zs1saplingaddress00000000000000000000000000'
    '000000000000000000000000000q6d4x2';
const kMobileSendTransparentAddress = _mobileTransparentAddress;
const kMobileSendTexAddress = 'tex1s2rt77ggv6q989lr23rrx8mzva7gnzqsurw2jw';
const kMobileSendInvalidAddress = 'not-an-address';

/// Well-formed, but for another Zcash network — the validator answers
/// `wrongNetwork`, which is its own sentence under the field.
const kMobileSendWrongNetworkAddress =
    'utest1wrongnetwork0000000000000000000000000'
    '00000000000000000000000000000k64x';

/// Contacts the recipient step lists.
const kMobileSendPreviewContacts = _mobileSendContacts;

/// The own-account map `ownAccountAddressesProvider` hands the review step.
const kMobileSendOwnAccountAddresses = {
  _mobileShieldedAddress: _mobileSendOwnAccount,
};

// --- Mobile send wizard, per step -------------------------------------------

/// What the payer has typed into the recipient field, named by the branch the
/// address validator takes on it.
enum MobileSendRecipientAddressCase {
  empty,
  unified,
  sapling,
  transparent,
  tex,
  invalid,
  wrongNetwork,
}

/// The address each recipient case seeds; null leaves the field empty.
String? mobileSendRecipientAddressFor(MobileSendRecipientAddressCase address) {
  return switch (address) {
    MobileSendRecipientAddressCase.empty => null,
    MobileSendRecipientAddressCase.unified => kMobileSendUnifiedAddress,
    MobileSendRecipientAddressCase.sapling => kMobileSendSaplingAddress,
    MobileSendRecipientAddressCase.transparent => kMobileSendTransparentAddress,
    MobileSendRecipientAddressCase.tex => kMobileSendTexAddress,
    MobileSendRecipientAddressCase.invalid => kMobileSendInvalidAddress,
    MobileSendRecipientAddressCase.wrongNetwork =>
      kMobileSendWrongNetworkAddress,
  };
}

/// The wizard's recipient step.
Widget mobileSendRecipientFixture({
  MobileSendRecipientAddressCase address = MobileSendRecipientAddressCase.empty,
  bool listContacts = false,
  bool fieldFocused = false,
}) {
  return mobileSendFixture(
    contacts: listContacts ? kMobileSendPreviewContacts : const [],
    initialRecipient: mobileSendRecipientAddressFor(address),
    initialRecipientFocused: fieldFocused,
  );
}

/// How much the payer has entered on the amount step.
enum MobileSendAmountCase { empty, entered, notEnough }

/// The wizard's amount step.
///
/// The `/send/amount` route (`MobileSendAmountScreen`) forwards its args to
/// exactly these props plus `useRouteSteps` / `initialAmountStep`, which only
/// change where Back goes, so the route is seeded here rather than previewed
/// as a second, pixel-identical case.
Widget mobileSendAmountFixture({
  MobileSendAmountCase amount = MobileSendAmountCase.empty,
  MobileSendAmountInputMode unit = MobileSendAmountInputMode.zec,
}) {
  final usd = unit == MobileSendAmountInputMode.usd;
  return mobileSendFixture(
    initialRecipient: kMobileSendUnifiedAddress,
    initialAmount: switch (amount) {
      MobileSendAmountCase.empty => '',
      MobileSendAmountCase.entered => usd ? '12' : '24.312',
      MobileSendAmountCase.notEnough => '243.12',
    },
    initialFiatAmount: !usd
        ? null
        : switch (amount) {
            MobileSendAmountCase.empty => '',
            MobileSendAmountCase.entered => '120.12',
            MobileSendAmountCase.notEnough => '17018.40',
          },
    initialAmountInputMode: unit,
    initialAmountError: amount == MobileSendAmountCase.notEnough
        ? 'Not enough ZEC'
        : null,
    initialAmountReady: amount == MobileSendAmountCase.entered,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

/// Where the review step's fee estimate lands.
enum MobileSendReviewFeeCase {
  ready,
  refreshing,
  notEnough,
  syncing,
  unavailable,
}

/// Who the review step names as the recipient.
enum MobileSendReviewIdentityCase { address, contact, ownAccount }

/// Whether this send answers a ZIP-321 request, and whether the reviewed
/// amount is the one the request asked for.
enum MobileSendReviewRequestCase { none, matching, differentAmount }

/// Amount the review step is composed with, in ZEC and in zatoshi.
const _mobileSendReviewAmountText = '123.12';
final _mobileSendReviewAmountZatoshi = BigInt.from(12_312_000_000);

/// Fee estimator per review case: a fee for the ready row, a never-completing
/// call for the refreshing row, and the error strings the screen's own
/// branches match on (`insufficient`, `sync`, anything else).
MobileSendFeeEstimator _mobileSendReviewFeeEstimator(
  MobileSendReviewFeeCase fee,
) {
  return ({
    required String dbPath,
    required String network,
    required String accountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
  }) {
    return switch (fee) {
      MobileSendReviewFeeCase.ready => Future<BigInt>.value(BigInt.from(10000)),
      MobileSendReviewFeeCase.refreshing => Completer<BigInt>().future,
      MobileSendReviewFeeCase.notEnough => Future<BigInt>.error(
        Exception('InsufficientFunds'),
      ),
      MobileSendReviewFeeCase.syncing => Future<BigInt>.error(
        Exception('Wallet sync is still finishing'),
      ),
      MobileSendReviewFeeCase.unavailable => Future<BigInt>.error(
        Exception('Fee estimation failed'),
      ),
    };
  };
}

/// The wizard's review step.
///
/// Every case but [MobileSendReviewFeeCase.ready] re-estimates on init, which
/// is how the `/send/review` route (`MobileSendReviewScreen`) enters it —
/// `refreshReviewFeeOnInit` plus the draft args' fee.
Widget mobileSendReviewFixture({
  MobileSendReviewFeeCase fee = MobileSendReviewFeeCase.ready,
  MobileSendReviewIdentityCase identity = MobileSendReviewIdentityCase.contact,
  MobileSendReviewRequestCase request = MobileSendReviewRequestCase.none,
  bool memo = false,
}) {
  final refreshes = fee != MobileSendReviewFeeCase.ready;
  return mobileSendFixture(
    ownAccountAddresses: identity == MobileSendReviewIdentityCase.ownAccount
        ? kMobileSendOwnAccountAddresses
        : const {},
    initialRecipient: kMobileSendUnifiedAddress,
    initialAmount: _mobileSendReviewAmountText,
    initialReview: true,
    refreshReviewFeeOnInit: refreshes,
    useRouteSteps: refreshes,
    estimateFee: _mobileSendReviewFeeEstimator(fee),
    initialMemo: memo ? 'Zcash is a privacy-focused digital currency' : null,
    initialContactLabel: identity == MobileSendReviewIdentityCase.contact
        ? 'Contact label'
        : null,
    initialContactPictureId: identity == MobileSendReviewIdentityCase.contact
        ? 'pfp-02'
        : null,
    isPaymentRequest: request != MobileSendReviewRequestCase.none,
    paymentRequestLabel: request == MobileSendReviewRequestCase.none
        ? null
        : 'Blue Door Coffee',
    requestedAmountZatoshi: switch (request) {
      MobileSendReviewRequestCase.none => null,
      MobileSendReviewRequestCase.matching => _mobileSendReviewAmountZatoshi,
      MobileSendReviewRequestCase.differentAmount => BigInt.from(5_000_000),
    },
  );
}

Widget buildMobileSendRecipientEmptyUseCase(BuildContext context) {
  return mobileSendFixture();
}

Widget buildMobileSendRecipientFocusedUseCase(BuildContext context) {
  return mobileSendFixture(
    contacts: _mobileSendContacts,
    initialRecipientFocused: true,
  );
}

Widget buildMobileSendRecipientContactsUseCase(BuildContext context) {
  return mobileSendFixture(contacts: _mobileSendContacts);
}

Widget buildMobileSendRecipientFilledUseCase(BuildContext context) {
  return mobileSendFixture(initialRecipient: _mobileShieldedAddress);
}

Widget buildMobileSendAmountEmptyUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

/// Figma 4479:47503: resolve the recipient from data, without a route label.
Widget buildMobileSendAmountContactUseCase(BuildContext context) {
  return _mobileSendAmountCaptureFrame(
    context,
    const _MobileSendHarness(
      contacts: _mobileSendContacts,
      initialRecipient: _mobileShieldedAddress,
      initialAmount: '12',
    ),
  );
}

Widget buildMobileSendAmountOwnAccountUseCase(BuildContext context) {
  return _mobileSendAmountCaptureFrame(
    context,
    const _MobileSendHarness(
      ownAccountAddresses: {
        _mobileShieldedAddress: AccountInfo(
          uuid: 'savings',
          name: 'Savings',
          order: 1,
          profilePictureId: 'pfp-02',
        ),
      },
      initialRecipient: _mobileShieldedAddress,
      initialAmount: '12',
    ),
  );
}

Widget _mobileSendAmountCaptureFrame(BuildContext context, Widget child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(
      padding: const EdgeInsets.only(top: 55),
      viewPadding: const EdgeInsets.only(top: 55),
      viewInsets: const EdgeInsets.only(bottom: 318),
    ),
    child: child,
  );
}

Widget buildMobileSendAmountErrorUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '243.12',
    initialAmountError: 'Not enough ZEC',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendAmountReadyUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '24.312',
    initialAmountReady: true,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendAmountUsdUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '12',
    initialFiatAmount: '120.12',
    initialAmountInputMode: MobileSendAmountInputMode.usd,
    initialAmountReady: true,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendReviewDefaultUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '123.12',
    initialReview: true,
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

Widget buildMobileSendReviewWithMemoUseCase(BuildContext context) {
  return mobileSendFixture(
    initialRecipient: _mobileShieldedAddress,
    initialAmount: '123.12',
    initialReview: true,
    initialMemo: 'Zcash is a privacy-focused digital currency',
    initialContactLabel: 'Contact label',
    initialContactPictureId: 'pfp-02',
  );
}

/// Inline messages `resolveScannedZcashAddress` rejects a scan with; quoted
/// from `mobile_send_scan_screen.dart`, which is where the payer reads them.
const kMobileSendScanNotZcashMessage = "This QR code isn't a Zcash address.";
const kMobileSendScanWrongNetworkMessage = '$kWrongNetworkAddressMessage.';

/// The card `showMobileSendScanSheet` mounts, with the camera stubbed.
///
/// [error] replaces the caption once a scan has been rejected; the card only
/// renders it over a live camera.
Widget mobileSendQrScanFixture({
  required AddressQrCameraStatus status,
  String? error,
}) {
  return _MobileSendScanFrame(
    child: MobileAddressScanCardContent(
      key: const ValueKey('mobile_send_qr_scan_card'),
      status: status,
      cameraView: const _MobileSendScanCameraPreview(),
      error: error,
      onTorch: _noop,
      onClose: _noop,
      onRetry: _noop,
    ),
  );
}

Widget buildMobileSendQrScanUseCase(BuildContext context) {
  return mobileSendQrScanFixture(status: AddressQrCameraStatus.active);
}

Widget buildMobileSendQrScanLoadingUseCase(BuildContext context) {
  return mobileSendQrScanFixture(status: AddressQrCameraStatus.loading);
}

Widget buildMobileSendQrScanRequestingUseCase(BuildContext context) {
  return mobileSendQrScanFixture(status: AddressQrCameraStatus.requesting);
}

Widget buildMobileSendQrScanDeniedUseCase(BuildContext context) {
  return mobileSendQrScanFixture(status: AddressQrCameraStatus.denied);
}

/// Desktop window chrome (sidebar + pane + back link) wrapping the compose
/// view, mirroring `_SwapPageFrame` so Widgetbook previews use the same
/// surface the real screen lives in.
class _SendPageFrame extends StatelessWidget {
  const _SendPageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WbDesktopWindowBox(
      child: LayoutBuilder(
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
      ),
    );
  }
}

class _MobileSendHarness extends StatelessWidget {
  const _MobileSendHarness({
    this.contacts = const [],
    this.ownAccountAddresses = const {},
    this.initialRecipient,
    this.initialAddressType,
    this.initialAmount,
    this.initialFiatAmount,
    this.initialAmountInputMode = MobileSendAmountInputMode.zec,
    this.initialAmountError,
    this.initialAmountReady = false,
    this.initialAmountStep = false,
    this.initialReview = false,
    this.initialFeeZatoshi,
    this.refreshReviewFeeOnInit = false,
    this.useRouteSteps = false,
    this.initialMemo,
    this.initialContactLabel,
    this.initialContactPictureId,
    this.initialRecipientFocused = false,
    this.isPaymentRequest = false,
    this.paymentRequestLabel,
    this.requestedAmountZatoshi,
    this.estimateFee = _widgetbookEstimateFee,
  });

  final List<AddressBookContact> contacts;
  final Map<String, AccountInfo> ownAccountAddresses;
  final String? initialRecipient;
  final String? initialAddressType;
  final String? initialAmount;
  final String? initialFiatAmount;
  final MobileSendAmountInputMode initialAmountInputMode;
  final String? initialAmountError;
  final bool initialAmountReady;
  final bool initialAmountStep;
  final bool initialReview;
  final BigInt? initialFeeZatoshi;
  final bool refreshReviewFeeOnInit;
  final bool useRouteSteps;
  final String? initialMemo;
  final String? initialContactLabel;
  final String? initialContactPictureId;
  final bool initialRecipientFocused;
  final bool isPaymentRequest;
  final String? paymentRequestLabel;
  final BigInt? requestedAmountZatoshi;
  final MobileSendFeeEstimator estimateFee;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // Riverpod 3 retries a failed provider on a backoff timer; nothing here
      // is allowed to fail, and a preview must not leave one running.
      retry: (_, _) => null,
      overrides: [
        appBootstrapProvider.overrideWithValue(_mobileSendBootstrap),
        sendProvingKeyWarmupProvider.overrideWithValue(() {}),
        syncProvider.overrideWith(() => _WidgetbookSendSyncNotifier()),
        zecLiveUsdUnitPriceProvider.overrideWithValue(70),
        addressBookRepositoryProvider.overrideWithValue(
          _WidgetbookAddressBookRepository(contacts),
        ),
        // The real provider reads the wallet DB path and then Rust; seeded
        // here so the review step can name an own-account recipient.
        ownAccountAddressesProvider.overrideWith(
          (ref) async => ownAccountAddresses,
        ),
      ],
      child: WbScaleDownBox(
        size: const Size(393, 852),
        child: SizedBox(
          width: 393,
          height: 852,
          child: MobileSendScreen(
            useRouteSteps: useRouteSteps,
            initialRecipient: initialRecipient,
            initialAddressType: initialAddressType,
            initialAmount: initialAmount,
            initialFiatAmount: initialFiatAmount,
            initialAmountInputMode: initialAmountInputMode,
            initialAmountError: initialAmountError,
            initialAmountReady: initialAmountReady,
            initialAmountStep: initialAmountStep,
            initialReview: initialReview,
            initialFeeZatoshi: initialFeeZatoshi,
            refreshReviewFeeOnInit: refreshReviewFeeOnInit,
            initialMemo: initialMemo,
            initialContactLabel: initialContactLabel,
            initialContactPictureId: initialContactPictureId,
            initialRecipientFocused: initialRecipientFocused,
            isPaymentRequest: isPaymentRequest,
            paymentRequestLabel: paymentRequestLabel,
            requestedAmountZatoshi: requestedAmountZatoshi,
            loadWalletDbPath: () async => '/tmp/widgetbook-zcash-wallet.db',
            validateAddress: _widgetbookValidateAddress,
            estimateFee: estimateFee,
          ),
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
    return WbScaleDownBox(
      size: const Size(393, 852),
      child: SizedBox(
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

/// The second account the review step names when the recipient is the
/// wallet's own address.
const _mobileSendOwnAccount = AccountInfo(
  uuid: 'widgetbook-send-savings',
  name: 'Savings',
  order: 1,
  profilePictureId: 'pfp-05',
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

/// Preview stand-in for Rust address validation: the recipient's prefix picks
/// the address type, so a fixture selects a branch by the address it seeds.
Future<rust_sync.AddressValidationResult> _widgetbookValidateAddress({
  required String address,
  required String network,
}) async {
  const invalid = rust_sync.AddressValidationResult(
    isValid: false,
    addressType: '',
    wrongNetwork: false,
  );
  if (address.startsWith('utest1') || address.startsWith('ztestsapling')) {
    return const rust_sync.AddressValidationResult(
      isValid: false,
      addressType: '',
      wrongNetwork: true,
    );
  }
  final type = switch (address) {
    _ when address.startsWith('t1') => 'transparent',
    _ when address.startsWith('tex1') => 'tex',
    _ when address.startsWith('zs1') => 'sapling',
    _ when address.startsWith('u1') => 'unified',
    _ => null,
  };
  if (type == null) return invalid;
  return rust_sync.AddressValidationResult(
    isValid: true,
    addressType: type,
    wrongNetwork: false,
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
                    label: 'Pay',
                    iconName: AppIcons.paid,
                    onTap: () {},
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Vote',
                    iconName: AppIcons.vote,
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
        // AppBackLink now carries a 12px internal pill inset, so the toolbar
        // padding drops from md (24) to s (12) to keep the chevron at the
        // design position (pane + 24) instead of shifting it to pane + 36.
        padding: const EdgeInsets.only(
          left: AppSpacing.s,
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

Widget buildSendMemoTooLongUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '125.12',
    amountConversionText: r'$ 8,758.40',
    amountFocused: true,
    memoMode: SendMemoMode.expanded,
    memoText: _longMemo,
    memoCounter: '-32/512',
    memoError: 'Message is too long',
  );
}

Widget buildSendPriceLoadingUseCase(BuildContext context) {
  return sendComposeFixture(
    recipientText: _sampleUnifiedAddress,
    route: SendPoolRoute.shieldedToShielded,
    amountText: '125.12',
    amountConversionText: null,
    amountConversionLoading: true,
    amountFocused: true,
    memoMode: SendMemoMode.expanded,
    reviewEnabled: true,
  );
}
