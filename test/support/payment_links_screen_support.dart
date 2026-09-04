import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_clipboard.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_qr_image_saver.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../fakes/fake_sync_notifier.dart';

/// Harness shared by the desktop and mobile Gift Card screen suites, which are
/// separate files because only the mobile one runs in the mobile token lane.
Future<void> loadPaymentLinksTestFonts() async {
  final loader = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
  await loader.load();
}

Future<void> pumpPaymentLinksScreen(
  WidgetTester tester, {
  FakePaymentLinkOperations? operations,
  FakePaymentLinkClipboard? clipboard,
  PaymentLinkHardwareSigningService? hardwareSigning,
  PaymentLinkQrImageSaver? qrImageSaver,
  AccountNotifier? accountNotifier,
  AppBootstrapState? bootstrap,
  BigInt? spendableBalance,
  FakeSyncNotifier? syncNotifier,
}) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final paymentLinkOperations = operations ?? FakePaymentLinkOperations();
  final paymentLinkClipboard = clipboard ?? FakePaymentLinkClipboard();
  final appBootstrap = bootstrap ?? paymentLinksBootstrap;
  final initialAccountUuid =
      appBootstrap.initialAccountState.activeAccountUuid ?? 'account-1';

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(appBootstrap),
        if (accountNotifier != null)
          accountProvider.overrideWith(() => accountNotifier),
        paymentLinkOperationsProvider.overrideWithValue(paymentLinkOperations),
        paymentLinkClipboardProvider.overrideWithValue(paymentLinkClipboard),
        if (qrImageSaver != null)
          paymentLinkQrImageSaverProvider.overrideWithValue(qrImageSaver),
        if (hardwareSigning != null)
          paymentLinkHardwareSigningServiceProvider.overrideWithValue(
            hardwareSigning,
          ),
        syncProvider.overrideWith(
          () =>
              syncNotifier ??
              FakeSyncNotifier(
                SyncState(
                  accountUuid: initialAccountUuid,
                  hasAccountScopedData: true,
                  isSyncComplete: true,
                  percentage: 1,
                  displayTargetPercentage: 1,
                  spendableBalance:
                      spendableBalance ?? BigInt.from(14223000000),
                  displaySpendableBalance:
                      spendableBalance ?? BigInt.from(14223000000),
                ),
              ),
        ),
        ironwoodHomeMigrationCtaProvider.overrideWith((ref) async {
          return const IronwoodHomeMigrationCtaState.hidden();
        }),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
        ironwoodPostMigrationStateProvider.overrideWith((ref) async {
          return const IronwoodPostMigrationState.unavailable();
        }),
        ironwoodMigrationAnnouncementProvider.overrideWith((ref) async {
          return const IronwoodMigrationAnnouncementState.hidden();
        }),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          FakeMigrationCoordinator.new,
        ),
      ],
      child: const ZcashWalletApp(),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    final hasDesktopScreen = find
        .byKey(const ValueKey('payment_links_desktop_screen'))
        .evaluate()
        .isNotEmpty;
    final hasMobileScreen = find
        .byKey(const ValueKey('payment_links_mobile_screen'))
        .evaluate()
        .isNotEmpty;
    if (hasDesktopScreen || hasMobileScreen) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 100));
}

const paymentLinksAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final paymentLinksBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: paymentLinksAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final homeBootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: paymentLinksAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const hardwareAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'hardware-account',
      name: 'Keystone',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'hardware-account',
  activeAddress: 'u1hardwareaddress',
);

final hardwareBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: hardwareAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const twoAccountHardwareState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'hardware-account',
      name: 'Keystone',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isHardware: true,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Savings',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'hardware-account',
  activeAddress: 'u1hardwareaddress',
);

final twoAccountHardwareBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: twoAccountHardwareState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

const twoAccountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Primary Vault',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
    AccountInfo(
      uuid: 'account-2',
      name: 'Savings',
      order: 1,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1accountsaddress',
);

final twoAccountBootstrap = AppBootstrapState(
  initialLocation: '/payment-links',
  initialAccountState: twoAccountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

final incomingLink = VizorPaymentLink(
  network: 'main',
  address: 'u1paymentlinkaddress',
  amountZatoshi: BigInt.from(445000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
  presentation: const PaymentLinkPresentation(
    artworkId: 'ruby',
    message: 'Congratulations!',
  ),
);

final secondIncomingLink = VizorPaymentLink(
  network: 'main',
  address: 'u1secondpaymentlinkaddress',
  amountZatoshi: BigInt.from(225000000),
  mnemonic: List.filled(24, 'legal').join(' '),
  birthdayHeight: 3000001,
  label: 'Second payment link',
  createdAt: DateTime.utc(2026, 8, 7),
  presentation: const PaymentLinkPresentation(
    artworkId: 'gift',
    message: 'A second gift!',
  ),
);

final sharedRecovery = PaymentLinkRecoveryRecord(
  link: incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.shared,
  updatedAt: DateTime.utc(2026, 8, 6),
  fundingTxids: 'funding-txid',
);

final fundedRecovery = PaymentLinkRecoveryRecord(
  link: incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.funded,
  updatedAt: DateTime.utc(2026, 8, 6),
  fundingTxids: 'funding-txid',
);

final otherAccountLink = VizorPaymentLink(
  network: 'main',
  address: 'u1otheraccountpaymentlinkaddress',
  amountZatoshi: BigInt.from(100000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 5),
);

final otherAccountRecovery = PaymentLinkRecoveryRecord(
  link: otherAccountLink,
  sourceAccountUuid: 'account-2',
  state: PaymentLinkRecoveryState.funded,
  updatedAt: DateTime.utc(2026, 8, 5),
  fundingTxids: 'funding-txid-2',
);

final unknownOriginRecovery = PaymentLinkRecoveryRecord(
  link: unknownOriginLink,
  sourceAccountUuid: '',
  state: PaymentLinkRecoveryState.funded,
  updatedAt: DateTime.utc(2026, 8, 4),
  fundingTxids: 'funding-txid-3',
);

final unknownOriginLink = VizorPaymentLink(
  network: 'main',
  address: 'u1unknownoriginpaymentlinkaddress',
  amountZatoshi: BigInt.from(200000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 4),
);

final draftRecovery = PaymentLinkRecoveryRecord(
  link: incomingLink,
  sourceAccountUuid: 'account-1',
  state: PaymentLinkRecoveryState.draft,
  updatedAt: DateTime.utc(2026, 8, 6),
);

class FakePaymentLinkOperations implements PaymentLinkOperations {
  FakePaymentLinkOperations({
    List<PaymentLinkRecoveryRecord> records = const [],
    List<PaymentLinkReceivedRecord> receivedRecords = const [],
    this.claimCompleter,
    this.claimCompleters = const {},
    this.createdLoadGate,
    this.receivedLoadGate,
    this.prepareClaimGates = const {},
    this.receivedLoadFailures = 0,
    this.prepareClaimFailures = 0,
    this.prepareClaimError,
    this.fundingMetadataSavedOnCreate = true,
    this.fundingBroadcastAcceptedOnCreate = true,
    this.fundingConfirmationCount = kPaymentLinkShareConfirmationTarget,
    this.claimable = true,
    this.waitingForFundingConfirmations = false,
    this.longSyncConfirmationRequired = false,
  }) : records = List.of(records),
       receivedRecords = List.of(receivedRecords);

  final Completer<PaymentLinkClaimResult>? claimCompleter;
  final Map<String, Completer<PaymentLinkClaimResult>> claimCompleters;
  final Completer<void>? createdLoadGate;
  final Completer<void>? receivedLoadGate;

  /// Gates the Nth `prepareClaim` call (1-based) so a test can act mid-await.
  final Map<int, Completer<void>> prepareClaimGates;
  int receivedLoadFailures;
  int prepareClaimFailures;
  final Object? prepareClaimError;
  final bool fundingMetadataSavedOnCreate;
  final bool fundingBroadcastAcceptedOnCreate;
  int fundingConfirmationCount;
  bool expireFundingOnInspect = false;
  bool claimable;
  bool waitingForFundingConfirmations;
  final bool longSyncConfirmationRequired;
  final List<PaymentLinkRecoveryRecord> records;
  final List<PaymentLinkReceivedRecord> receivedRecords;
  final Map<String, PaymentLinkReceivedStatus> receivedClaimStatuses = {};
  final List<BigInt> createdAmounts = [];
  final List<String> createdFromAccounts = [];
  final List<String?> createdArtworkIds = [];
  final List<String?> createdMessages = [];
  final List<String> quotedAccounts = [];
  final List<String> maxQuotedAccounts = [];
  final List<VizorPaymentLink> sharedLinks = [];
  final List<VizorPaymentLink> claimedLinks = [];
  final List<String> discardedClaimAddresses = [];
  final List<String> retainedClaimAddresses = [];
  final List<String> keptLinkAddresses = [];
  final List<String> forgottenLinkAddresses = [];
  final List<bool> allowLongSyncCalls = [];
  final List<VizorPaymentLink> preparedLinks = [];
  int createdLoadCalls = 0;
  int receivedLoadCalls = 0;
  int fundingMetadataRetries = 0;

  @override
  Future<PaymentLinkFundingQuote> quoteMaxFunding({
    required String sourceAccountUuid,
  }) async {
    maxQuotedAccounts.add(sourceAccountUuid);
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: BigInt.from(14222980000),
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    quotedAccounts.add(sourceAccountUuid);
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: BigInt.from(10000),
      claimFeeReserveZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    );
  }

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    createdArtworkIds.add(presentation?.artworkId);
    createdMessages.add(presentation?.message);
    final link = VizorPaymentLink(
      network: 'main',
      address: 'u1createdpaymentlinkaddress',
      amountZatoshi: amountZatoshi,
      mnemonic: List.filled(24, 'abandon').join(' '),
      birthdayHeight: 3000000,
      label: 'Payment link',
      createdAt: DateTime.utc(2026, 8, 6),
      presentation: presentation,
    );
    records.add(
      PaymentLinkRecoveryRecord(
        link: link,
        sourceAccountUuid: sourceAccountUuid,
        state: fundingMetadataSavedOnCreate
            ? PaymentLinkRecoveryState.funded
            : PaymentLinkRecoveryState.draft,
        updatedAt: DateTime.utc(2026, 8, 6),
        fundingTxids: fundingMetadataSavedOnCreate ? 'funding-txid' : null,
      ),
    );
    return PaymentLinkFundingResult(
      link: link,
      txids: 'funding-txid',
      fundingMetadataSaved: fundingMetadataSavedOnCreate,
      broadcastAccepted: fundingBroadcastAcceptedOnCreate,
    );
  }

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) async {
    fundingMetadataRetries += 1;
    final index = records.indexWhere(
      (record) => record.link.address == address,
    );
    records[index] = records[index].copyWith(
      state: PaymentLinkRecoveryState.funded,
      fundingTxids: fundingTxids,
      updatedAt: DateTime.utc(2026, 8, 6, 1),
    );
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async {
    createdLoadCalls += 1;
    await createdLoadGate?.future;
    return List.unmodifiable(records);
  }

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) async {
    sharedLinks.add(link);
    final index = records.indexWhere(
      (record) => record.link.address == link.address,
    );
    final updated = records[index].copyWith(
      state: PaymentLinkRecoveryState.shared,
      updatedAt: DateTime.utc(2026, 8, 6, 1),
    );
    records[index] = updated;
    return updated;
  }

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    final expiredAddresses = expireFundingOnInspect
        ? {
            for (final record in records)
              if (record.state == PaymentLinkRecoveryState.funded)
                record.link.address,
          }
        : const <String>{};
    this.records.removeWhere(
      (record) => expiredAddresses.contains(record.link.address),
    );
    return {
      for (final record in records)
        if (!expiredAddresses.contains(record.link.address))
          record.link.address: PaymentLinkFundingProgress(
            confirmationCount: fundingConfirmationCount,
          ),
    };
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async {
    receivedLoadCalls += 1;
    await receivedLoadGate?.future;
    if (receivedLoadFailures > 0) {
      receivedLoadFailures -= 1;
      throw StateError('transient Received load failure');
    }
    return List.unmodifiable(receivedRecords);
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async {
    for (var index = 0; index < receivedRecords.length; index++) {
      final record = receivedRecords[index];
      final status = receivedClaimStatuses[record.address] ?? record.status;
      receivedRecords[index] = switch (status) {
        PaymentLinkReceivedStatus.readyToClaim => record.copyWith(
          status: status,
          destinationAccountUuid: null,
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
        PaymentLinkReceivedStatus.submitting => record.copyWith(
          status: status,
          destinationAccountUuid: record.destinationAccountUuid ?? 'account-1',
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
        PaymentLinkReceivedStatus.receiving => record,
        PaymentLinkReceivedStatus.received => record.copyWith(
          status: status,
          claimLink: null,
          updatedAt: DateTime.utc(2026, 8, 6, 3),
        ),
      };
    }
    return List.unmodifiable(receivedRecords);
  }

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    preparedLinks.add(link);
    allowLongSyncCalls.add(allowLongSync);
    await prepareClaimGates[preparedLinks.length]?.future;
    final configuredError = prepareClaimError;
    if (configuredError != null) throw configuredError;
    if (prepareClaimFailures > 0) {
      prepareClaimFailures -= 1;
      throw StateError('transient claim preparation failure');
    }
    if (longSyncConfirmationRequired && !allowLongSync) {
      throw const PaymentLinkLongSyncConfirmationRequired();
    }
    return PaymentLinkClaimSession(
      link: link,
      destinationAddress: 'u1receiver',
      destinationAccountUuid: 'account-1',
      directory: Directory('/tmp/vizor-payment-link-test'),
      dbPath: '/tmp/vizor-payment-link-test/wallet.db',
      accountUuid: 'payment-link-account',
      totalZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      claimableZatoshi: claimable ? link.amountZatoshi : BigInt.zero,
      feeZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
      fundingConfirmationCount: fundingConfirmationCount,
      waitingForFundingConfirmations: waitingForFundingConfirmations,
    );
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    if (!receivedRecords.any(
      (record) => record.address == session.link.address,
    )) {
      receivedRecords.insert(
        0,
        PaymentLinkReceivedRecord.fromLink(
          session.link,
          updatedAt: DateTime.utc(2026, 8, 6),
        ),
      );
    }
    try {
      final result = await _claimLink(session.link);
      _replaceReceivedRecord(
        session.link.address,
        (record) => record.copyWith(
          status: PaymentLinkReceivedStatus.receiving,
          destinationAccountUuid: session.destinationAccountUuid,
          claimTxids: result.txids,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      );
      return result;
    } catch (_) {
      _replaceReceivedRecord(
        session.link.address,
        (record) => record.copyWith(
          status: PaymentLinkReceivedStatus.readyToClaim,
          destinationAccountUuid: null,
          claimTxids: null,
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {
    discardedClaimAddresses.add(session.link.address);
  }

  @override
  Future<void> forgetReceivedLink(VizorPaymentLink link) async {
    forgottenLinkAddresses.add(link.address);
    receivedRecords.removeWhere((record) => record.address == link.address);
  }

  @override
  Future<void> keepReceivedLink(VizorPaymentLink link) async {
    keptLinkAddresses.add(link.address);
    if (!receivedRecords.any((record) => record.address == link.address)) {
      receivedRecords.insert(
        0,
        PaymentLinkReceivedRecord.fromLink(
          link,
          updatedAt: DateTime.utc(2026, 8, 6),
        ),
      );
    }
  }

  @override
  Future<void> retainPendingClaim(PaymentLinkClaimSession session) async {
    retainedClaimAddresses.add(session.link.address);
    if (!receivedRecords.any(
      (record) => record.address == session.link.address,
    )) {
      receivedRecords.insert(
        0,
        PaymentLinkReceivedRecord.fromLink(
          session.link,
          updatedAt: DateTime.utc(2026, 8, 6),
        ),
      );
    }
  }

  Future<PaymentLinkClaimResult> _claimLink(VizorPaymentLink link) async {
    claimedLinks.add(link);
    return claimCompleters[link.address]?.future ??
        claimCompleter?.future ??
        broadcastedClaimResult;
  }

  void _replaceReceivedRecord(
    String address,
    PaymentLinkReceivedRecord Function(PaymentLinkReceivedRecord record) update,
  ) {
    final index = receivedRecords.indexWhere(
      (record) => record.address == address,
    );
    if (index >= 0) receivedRecords[index] = update(receivedRecords[index]);
  }
}

class SwitchablePaymentLinkAccountNotifier extends AccountNotifier {
  SwitchablePaymentLinkAccountNotifier([this.initialState = twoAccountState]);

  final AccountState initialState;

  @override
  AccountState build() => initialState;

  void setActiveAccount(String uuid) {
    final current = state.value ?? initialState;
    state = AsyncData(
      current.copyWith(
        activeAccountUuid: uuid,
        activeAddress: 'u1${uuid}address',
      ),
    );
  }
}

const broadcastedClaimResult = PaymentLinkClaimResult(
  txids: 'claim-txid',
  status: PaymentLinkClaimBroadcastStatus.broadcasted,
);

class FakePaymentLinkClipboard implements PaymentLinkClipboard {
  FakePaymentLinkClipboard({this.text, this.readCompleter});

  String? text;
  final Completer<String?>? readCompleter;
  final List<String> copiedSecrets = [];
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    text = '';
  }

  @override
  Future<void> copySecret(String text) async {
    copiedSecrets.add(text);
    this.text = text;
  }

  @override
  Future<String?> readText() => readCompleter?.future ?? Future.value(text);
}

class FakePaymentLinkQrImageSaver implements PaymentLinkQrImageSaver {
  final List<Uint8List> savedImages = [];

  @override
  Future<bool> savePng(Uint8List pngBytes) async {
    savedImages.add(Uint8List.fromList(pngBytes));
    return true;
  }
}

class FakePaymentLinkHardwareSigningService
    implements PaymentLinkHardwareSigningService {
  FakePaymentLinkHardwareSigningService({this.createCompleter});

  final Completer<PaymentLinkHardwarePcztDraft>? createCompleter;
  final createdAmounts = <BigInt>[];
  final createdFromAccounts = <String>[];
  final createdArtworkIds = <String?>[];
  final createdMessages = <String?>[];
  final discardedDrafts = <BigInt>[];

  PaymentLinkHardwarePcztDraft get draft => PaymentLinkHardwarePcztDraft(
    link: incomingLink,
    pcztBytes: const [1, 2, 3],
    needsSaplingParams: false,
    feeZatoshi: BigInt.from(10000),
    proposalId: BigInt.one,
    sendFlowId: 'test-payment-link-hardware',
  );

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) async {
    createdAmounts.add(amountZatoshi);
    createdFromAccounts.add(sourceAccountUuid);
    createdArtworkIds.add(presentation?.artworkId);
    createdMessages.add(presentation?.message);
    return createCompleter?.future ?? draft;
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required PaymentLinkHardwarePcztDraft draft,
  }) async => const ['ur:zcash-sign-batch/test'];

  @override
  Future<List<int>> decodeSigningResponse({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async => const [10, 11];

  @override
  Future<List<int>> addProofsForSigning({
    required PaymentLinkHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async => const [7, 8, 9];

  @override
  Future<void> discardPcztDraft({
    required PaymentLinkHardwarePcztDraft draft,
  }) async {
    discardedDrafts.add(draft.proposalId);
  }

  @override
  Future<PaymentLinkHardwareFundingResult> broadcastSignedPczt({
    required PaymentLinkHardwarePcztDraft draft,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
    void Function()? onSubmissionStarted,
  }) async {
    return const PaymentLinkHardwareFundingResult(
      txids: 'hardware-funding-txid',
      status: 'broadcasted',
      fundingMetadataSaved: true,
    );
  }
}

class FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

Rect globalCaretRect(RenderEditable editable, int offset) {
  final caretLocal = editable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  return editable.localToGlobal(caretLocal.topLeft) & caretLocal.size;
}

RenderEditable findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? found;
  root.visitChildren((child) {
    found ??= findRenderEditable(child);
  });
  return found!;
}
