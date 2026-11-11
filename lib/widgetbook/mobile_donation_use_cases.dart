// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'package:flutter/material.dart' show Scaffold, ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/formatting/zec_amount.dart';
import '../src/core/layout/mobile/mobile_bottom_safe_area.dart';
import '../src/core/layout/mobile/mobile_top_nav.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/features/donation/donation_config.dart';
import '../src/features/donation/widgets/donation_views.dart';
import '../src/features/donation/widgets/mobile/mobile_donation_views.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../src/features/send/screens/mobile/mobile_send_status_screen.dart';
import '../src/features/send/services/send_flow.dart';
import '../src/features/send/services/send_amount_conversion.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';

Widget buildMobileDonationEmptyUseCase(BuildContext context) =>
    const _Compose();
Widget buildMobileDonationAmountUseCase(BuildContext context) =>
    const _Compose(amount: '0.02');
Widget buildMobileDonationUsdUseCase(BuildContext context) =>
    const _Compose(amount: '15', usd: true);
Widget buildMobileDonationInsufficientUseCase(BuildContext context) =>
    const _Compose(amount: '1', insufficient: true);
Widget buildMobileDonationReviewUseCase(BuildContext context) => _data(
  MobileSendScreen(
    flowKind: SendFlowKind.donation,
    initialReview: true,
    initialAmountReady: true,
    initialRecipient: kVizorDonationAddress,
    initialAddressType: 'unified',
    initialAmount: '0.02',
    initialFeeZatoshi: BigInt.from(10000),
    loadWalletDbPath: () async => '/capture/wallet.db',
  ),
);
Widget buildMobileDonationSendingUseCase(BuildContext context) => _status(null);
Widget buildMobileDonationSuccessUseCase(BuildContext context) =>
    _status(SendBroadcastPhase.succeeded);
Widget buildMobileDonationPendingUseCase(BuildContext context) =>
    _status(SendBroadcastPhase.pendingBroadcast);
Widget buildMobileDonationFailureUseCase(BuildContext context) =>
    _status(SendBroadcastPhase.failed);

Widget buildMobileDonationReviewLargeTextUseCase(BuildContext context) =>
    MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: Builder(builder: buildMobileDonationReviewUseCase),
    );
Widget buildMobileDonationSuccessLargeTextUseCase(BuildContext context) =>
    MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(2)),
      child: Builder(builder: buildMobileDonationSuccessUseCase),
    );

Widget _status(SendBroadcastPhase? phase) => _data(
  MobileSendStatusScreen(
    args: SendReviewArgs(
      proposalId: BigInt.one,
      sendFlowId: 'donation-capture',
      proposalAccountUuid: 'donation-capture-account',
      address: kVizorDonationAddress,
      addressType: 'unified',
      amountZatoshi: BigInt.from(2000000),
      feeZatoshi: BigInt.from(10000),
      needsSaplingParams: false,
      flowKind: SendFlowKind.donation,
    ),
    broadcastRunner:
        ({
          required ref,
          required l10n,
          required args,
          keystone,
          ledger,
          required confirmSaplingParamsDownload,
          shouldAbort,
        }) => phase == null
        ? Completer<SendBroadcastOutcome>().future
        : Future.value(
            SendBroadcastOutcome(phase: phase, proposalConsumed: true),
          ),
  ),
);

class _Compose extends StatefulWidget {
  const _Compose({
    this.amount = '',
    this.usd = false,
    this.insufficient = false,
  });
  final String amount;
  final bool usd;
  final bool insufficient;
  @override
  State<_Compose> createState() => _ComposeState();
}

class _ComposeState extends State<_Compose> {
  late final controller = TextEditingController(text: widget.amount);
  String get _conversionText {
    final amount = widget.usd
        ? sendZatoshiFromUsdText(controller.text, 800)
        : parseZecAmount(controller.text);
    if (widget.usd) {
      return '${ZecAmount.fromZatoshi(amount ?? BigInt.zero).pretty().amountText} ZEC';
    }
    return amount == null
        ? r'$ 0'
        : '\$ ${sendUsdDisplayTextForZatoshi(amount, 800)}';
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.s),
          MobileTopNav.back(title: 'Support Vizor', onBack: () {}),
          Expanded(
            child: MobileBottomSafeArea(
              bottomPadding: AppSpacing.md,
              child: MobileDonationComposeView(
                controller: controller,
                mode: widget.usd
                    ? DonationAmountMode.usd
                    : DonationAmountMode.zec,
                conversionText: _conversionText,
                balanceText: '0.42 ZEC',
                selectedPreset: widget.amount,
                errorText: widget.insufficient
                    ? 'Insufficient shielded balance including fee'
                    : null,
                onAmountChanged: (_) => setState(() {}),
                onToggleMode: () {},
                onPresetSelected: (_) {},
                onContinue: widget.amount.isEmpty || widget.insufficient
                    ? null
                    : () {},
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _data(Widget child) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(
      AppBootstrapState(
        initialLocation: '/donation',
        initialAccountState: const AccountState(
          accounts: [
            AccountInfo(
              uuid: 'donation-capture-account',
              name: 'Account 1',
              order: 0,
            ),
          ],
          activeAccountUuid: 'donation-capture-account',
        ),
        initialSyncSnapshot: AppSyncSnapshot.empty,
        network: 'main',
        rpcEndpointConfig: defaultRpcEndpointConfig('main'),
        themeMode: ThemeMode.system,
        privacyModeEnabled: false,
        isPasswordConfigured: true,
        isUnlocked: true,
        passwordRotationRecoveryFailed: false,
      ),
    ),
    sendProvingKeyWarmupProvider.overrideWithValue(() {}),
    syncProvider.overrideWith(_CaptureSync.new),
    zecLiveUsdUnitPriceProvider.overrideWithValue(800),
    addressBookRepositoryProvider.overrideWithValue(const _EmptyContacts()),
    ownAccountAddressesProvider.overrideWith((ref) async => const {}),
  ],
  child: child,
);

class _CaptureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'donation-capture-account',
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(42000000),
    displaySpendableBalance: BigInt.from(42000000),
  );
  @override
  Future<void> refreshAfterSend() async {}
  @override
  Future<void> refreshAfterProposalRelease(String accountUuid) async {}
}

class _EmptyContacts implements AddressBookRepository {
  const _EmptyContacts();
  @override
  Future<List<AddressBookContact>> loadContacts() async => const [];
  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
