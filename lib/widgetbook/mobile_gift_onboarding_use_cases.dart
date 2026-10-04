// ignore_for_file: depend_on_referenced_packages
// Preview boundaries are in memory; no wallet, network, storage or Rust calls.
import 'dart:async';
import '../src/features/payment_links/providers/gift_card_entry_price_provider.dart';
import '../src/features/payment_links/providers/gift_card_check_progress_provider.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../src/features/onboarding/mobile/mobile_passcode_screen.dart';
import '../src/core/navigation/mobile_onboarding_routes.dart';
import '../src/features/onboarding/mobile/mobile_import_screens.dart';
import '../src/features/onboarding/mobile/mobile_import_manual_screen.dart';
import '../src/features/onboarding/mobile/mobile_import_review_screen.dart';
import '../src/features/onboarding/mobile/mobile_import_birthday_screen.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';
import '../src/features/onboarding/mobile/mobile_keystone_screens.dart';
import '../src/features/onboarding/mobile/mobile_ledger_connect_screen.dart';
import '../src/features/onboarding/mobile/mobile_wallet_link_screens.dart';
import '../src/features/onboarding/shared/onboarding_flow_args.dart';
import '../src/features/payment_links/services/gift_claim_import_store.dart';
import '../src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import '../src/features/payment_links/widgets/gift_claim_failure_toast_listener.dart';
import '../src/core/widgets/app_toast.dart';
import '../src/features/payment_links/models/vizor_payment_link.dart';
import '../src/features/payment_links/widgets/payment_link_gift_card.dart';
import '../src/features/payment_links/widgets/mobile/payment_link_scan_sheet.dart';
import '../src/features/payment_links/services/payment_link_clipboard.dart';
import '../src/features/payment_links/providers/gift_claim_flow_provider.dart';
import '../src/features/payment_links/screens/gift_claim_screen.dart';
import '../src/features/payment_links/screens/gift_passcode_screen.dart';
import '../src/features/payment_links/screens/gift_customise_account_screen.dart';
import '../src/features/payment_links/screens/payment_links_screen.dart';
import '../src/features/payment_links/services/payment_link_recovery_store.dart';
import '../src/features/payment_links/services/payment_link_received_store.dart';
import '../src/features/payment_links/services/payment_link_service.dart';
import '../src/providers/account_provider.dart';
import '../src/core/profile_pictures.dart';
import '../src/app_bootstrap.dart';
import '../src/providers/app_security_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/biometric_unlock_provider.dart';
import '../src/services/biometric_unlock.dart';
import '../src/core/security/software_wallet_secret.dart';
import '../src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import '../src/features/activity/gift_card_activity_index.dart';
import '../src/rust/api/sync.dart' as rust_sync;
import 'screen_use_cases.dart';

Widget buildMobileGiftOnboardingEntry(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift');
Widget buildMobileGiftAddAccountEntry(BuildContext context) =>
    const _GiftPreview(
      initialLocation: '/gift?addAccount=true',
      addingAccount: true,
    );
Widget buildMobileGiftOnboardingPasscode(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift/passcode');
Widget buildMobileGiftOnboardingCustomise(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift/customise');
Widget buildMobileGiftOnboardingWalkthrough(BuildContext context) =>
    const _GiftPreview();
Widget buildMobileGiftOnboardingInspected(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift', inspected: true);
Widget buildMobileGiftAddAccountInspected(BuildContext context) =>
    const _GiftPreview(
      initialLocation: '/gift?addAccount=true',
      inspected: true,
      addingAccount: true,
    );
Widget buildMobileGiftOnboardingChecking(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift', checking: true);
Widget buildMobileGiftOnboardingFundingFound(BuildContext context) =>
    const _GiftPreview(
      initialLocation: '/gift',
      checking: true,
      fundingFound: true,
    );
Widget buildMobileGiftOnboardingLongSyncWarning(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift', longSyncWarning: true);

Widget buildMobileGiftOnboardingSubmissionError(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift', failCreation: true);
Widget buildMobileGiftOnboardingClaimFailure(BuildContext context) =>
    const _GiftPreview(initialLocation: '/gift/customise', failClaim: true);
Widget buildMobileGiftOnboardingStorageRecovery(BuildContext context) =>
    const _GiftPreview(
      initialLocation: '/gift/customise',
      recoverStorage: true,
    );
Widget buildMobileGiftOnboardingBiometrics(BuildContext context) =>
    const _GiftPreview(initialLocation: '/onboarding/biometrics');
Widget buildMobileGiftOnboardingImportAccounts(BuildContext context) =>
    const _GiftPreview(
      initialLocation: '/onboarding/set-passcode',
      walletLinkImport: true,
    );

final _walletLinkImportArgs = SetPasswordScreenArgs.importWalletLink(
  network: 'main',
  accounts: [
    for (var index = 0; index < 2; index++)
      LinkedWalletAccountImport(
        name: index == 0 ? 'Personal wallet' : 'Savings',
        birthdayHeight: 3000000,
        zip32AccountIndex: index,
        isHardware: false,
        isSeedAnchor: index == 0,
        profilePictureId: index == 0 ? 'pfp-01' : 'pfp-05',
        mnemonic: _importPhrase,
      ),
  ],
  contacts: const [],
  packageId: 'preview-package',
  completionToken: 'preview-completion',
  keyBytes: List.filled(32, 0),
);

final _link = VizorPaymentLink(
  network: 'main',
  address: 'u1previewgiftcard',
  amountZatoshi: BigInt.from(445000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 9, 1),
  presentation: PaymentLinkPresentation(
    artworkId: PaymentLinkCardArtwork.knightMagic.protocolId,
    message: 'Welcome to the Shielded World ;)',
  ),
);

const _importPhrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

String? _previewPhraseValidation(List<String> words) =>
    kMnemonicWordCounts.contains(words.length)
    ? null
    : 'Enter a complete secret passphrase.';

class _GiftPreview extends StatefulWidget {
  const _GiftPreview({
    this.initialLocation = '/welcome',
    this.checking = false,
    this.fundingFound = false,
    this.inspected = false,
    this.longSyncWarning = false,
    this.failCreation = false,
    this.failClaim = false,
    this.recoverStorage = false,
    this.walletLinkImport = false,
    this.addingAccount = false,
  });
  final String initialLocation;
  final bool checking;
  final bool fundingFound;
  final bool inspected;
  final bool longSyncWarning;
  final bool failCreation;
  final bool failClaim;
  final bool recoverStorage;
  final bool walletLinkImport;
  final bool addingAccount;
  @override
  State<_GiftPreview> createState() => _GiftPreviewState();
}

class _GiftPreviewState extends State<_GiftPreview> {
  final _storage = _MemoryGiftStorage();
  late final _accounts = _GiftPreviewAccounts(
    failCreation: widget.failCreation,
    recoverStorage: widget.recoverStorage,
    addingAccount: widget.addingAccount,
  );
  late final _router = GoRouter(
    initialLocation: widget.initialLocation,
    initialExtra: widget.walletLinkImport ? _walletLinkImportArgs : null,
    routes: [
      ...mobileOnboardingRoutes().whereType<GoRoute>().where(
        (route) => {
          '/onboarding/method',
          '/onboarding/hardware',
          if (!widget.walletLinkImport) '/onboarding/set-passcode',
          '/onboarding/customise-account',
          '/onboarding/biometrics',
        }.contains(route.path),
      ),
      if (widget.walletLinkImport)
        GoRoute(
          path: '/onboarding/set-passcode',
          builder: (_, state) => _importFrame(
            MobilePasscodeScreen(
              args:
                  mobileOnboardingPayload(state.extra)!
                      as SetPasswordScreenArgs,
              completeWalletLinkPackage:
                  ({
                    required packageId,
                    required completionToken,
                    required keyBytes,
                    required importedAccountCount,
                    required importedContactCount,
                  }) async {},
            ),
          ),
        ),
      GoRoute(
        path: '/import',
        builder: (_, _) => _importFrame(
          MobileImportScreen(
            readClipboardText: () async => _importPhrase,
            validatePastedWords: _previewPhraseValidation,
          ),
        ),
      ),
      GoRoute(
        path: '/import/manual',
        builder: (_, _) => _importFrame(
          MobileImportManualScreen(
            wordListOverride: _importPhrase.split(' ').toSet().toList(),
            mnemonicValidator: _previewPhraseValidation,
            screenshotStream: const Stream.empty(),
          ),
        ),
      ),
      GoRoute(
        path: '/import/review',
        builder: (_, state) => _importFrame(
          MobileImportReviewScreen(
            args:
                mobileOnboardingPayload(state.extra)
                    as ImportSecretPassphraseArgs,
            screenshotStream: const Stream.empty(),
          ),
        ),
      ),
      GoRoute(
        path: '/import/birthday',
        builder: (context, state) {
          final args =
              mobileOnboardingPayload(state.extra) as ImportBirthdayArgs;
          return _importFrame(
            Builder(
              builder: (context) => MobileImportBirthdayScreen(
                args: args,
                loadChainMetadata: false,
                onHeightConfirmed: (height) async {
                  context.pushOnboarding(
                    '/onboarding/set-passcode',
                    extra: SetPasswordScreenArgs.importWallet(
                      mnemonic: args.mnemonic,
                      bip39Passphrase: args.bip39Passphrase,
                      birthdayHeight: height,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      // Device import details have their own existing Widgetbook fixtures.
      // These read-only entry views never request a camera or connect a device.
      GoRoute(
        path: '/onboarding/keystone',
        builder: (_, _) => _importFrame(
          const IgnorePointer(child: MobileKeystoneIntroScreen()),
        ),
      ),
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) => _importFrame(
          const IgnorePointer(child: MobileLedgerConnectScreen()),
        ),
      ),
      GoRoute(
        path: '/onboarding/link-desktop',
        builder: (_, _) => _importFrame(
          const IgnorePointer(child: MobileWalletLinkIntroScreen()),
        ),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const MobileWelcomeScreen()),
      GoRoute(
        path: '/gift',
        builder: (_, state) => GiftClaimScreen(
          addingAccount: state.uri.queryParameters['addAccount'] == 'true',
        ),
      ),
      GoRoute(
        path: '/gift/passcode',
        builder: (_, _) => const GiftPasscodeScreen(),
      ),
      GoRoute(
        path: '/gift/customise',
        redirect: (context, _) =>
            ProviderScope.containerOf(
                  context,
                ).read(giftClaimFlowProvider)?.walletSetupInProgress ==
                true
            ? null
            : '/gift',
        pageBuilder: (context, state) {
          final setup = ProviderScope.containerOf(
            context,
          ).read(giftClaimFlowProvider)!;
          return NoTransitionPage(
            key: state.pageKey,
            child: GiftCustomiseAccountScreen(
              args: GiftCustomiseAccountArgs(
                passcode: setup.setupPasscode!,
                inspection: setup.inspection!,
              ),
              random: Random(1234),
            ),
          );
        },
      ),
      GoRoute(
        path: '/payment-links',
        builder: (_, state) => PaymentLinksScreen(
          initialReceivedCardAddress: state.uri.queryParameters['received'],
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const _GiftHomePreview()),
    ],
  );
  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 393,
      height: 852,
      child: ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          if (widget.fundingFound)
            giftCardCheckProgressProvider.overrideWith(
              _FundingFoundProgress.new,
            ),
          paymentLinkSetupJournalPendingProvider.overrideWithValue(
            () async => false,
          ),
          giftClaimImportStoreProvider.overrideWith(
            (ref) => GiftClaimImportStore(storage: _GiftPreviewImportStorage()),
          ),
          if (widget.walletLinkImport)
            giftClaimSetupReturnProvider.overrideWith(_ImportGiftReturn.new),
          if (widget.longSyncWarning)
            giftClaimFlowProvider.overrideWith(_LongSyncGiftFlow.new)
          else if (widget.checking)
            giftClaimFlowProvider.overrideWith(_CheckingGiftFlow.new)
          else if (widget.inspected ||
              widget.initialLocation.startsWith('/gift/'))
            giftClaimFlowProvider.overrideWith(
              () => _InspectedGiftFlow(
                setupPasscode: widget.initialLocation == '/gift/customise'
                    ? '123456'
                    : null,
              ),
            ),
          giftCardEntryPriceProvider.overrideWith((ref) async => 31.9618),
          accountProvider.overrideWith(() => _accounts),
          appSecurityProvider.overrideWith(_GiftPreviewSecurity.new),
          biometricUnlockProvider.overrideWith(_GiftPreviewBiometrics.new),
          syncProvider.overrideWith(_GiftPreviewSync.new),
          paymentLinkReceivedStoreProvider.overrideWith((ref) {
            return PaymentLinkReceivedStore(
              _storage,
              onRecordsChanged: () => ref
                  .read(paymentLinkLifecycleRevisionProvider.notifier)
                  .bump(),
            );
          }),
          paymentLinkOperationsProvider.overrideWith(
            (ref) => _GiftPreviewOperations(
              ref.watch(paymentLinkReceivedStoreProvider),
              failClaim: widget.failClaim,
            ),
          ),
          giftCardActivityIndexProvider.overrideWith((ref, uuid) async {
            ref.watch(paymentLinkLifecycleRevisionProvider);
            return GiftCardActivityIndex.forAccount(
              accountUuid: uuid,
              createdRecords: const [],
              receivedRecords: await ref
                  .watch(paymentLinkReceivedStoreProvider)
                  .load(),
            );
          }),
          paymentLinkClipboardProvider.overrideWithValue(
            _GiftPreviewClipboard(),
          ),
          paymentLinkScannerProvider.overrideWithValue(
            (_, {required networkName}) async => _link,
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.only(top: 55, bottom: 24),
          ),
          child: AppToastHost(
            child: GiftClaimFailureToastListener(
              router: _router,
              child: Router.withConfig(config: _router),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Simulates a mined receipt after Home first shows the persisted pending claim.
/// The real Activity index reads the same store throughout the walkthrough.
class _GiftHomePreview extends ConsumerStatefulWidget {
  const _GiftHomePreview();

  @override
  ConsumerState<_GiftHomePreview> createState() => _GiftHomePreviewState();
}

class _GiftHomePreviewState extends ConsumerState<_GiftHomePreview> {
  Timer? _confirmation;

  @override
  void initState() {
    super.initState();
    _confirmation = Timer(const Duration(seconds: 6), () async {
      final store = ref.read(paymentLinkReceivedStoreProvider);
      final record = await store.find(_link.address);
      if (!mounted || record?.status != PaymentLinkReceivedStatus.receiving) {
        return;
      }
      await store.markReceived(address: _link.address);
    });
  }

  @override
  void dispose() {
    _confirmation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildMobileGiftHomeReviewUseCase(
    context,
    account: ref.watch(accountProvider).value?.activeAccount,
  );
}

Widget _importFrame(Widget child) =>
    MobileOnboardingProgressFrame(child: child);

class _GiftPreviewAccounts extends AccountNotifier {
  _GiftPreviewAccounts({
    required this.failCreation,
    required this.recoverStorage,
    required this.addingAccount,
  });
  final bool failCreation;
  final bool recoverStorage;
  final bool addingAccount;
  VizorPaymentLink? _pendingGift;
  var _recoveryAttempts = 0;
  @override
  AccountState build() => addingAccount
      ? const AccountState(
          accounts: [
            AccountInfo(uuid: 'existing-account', name: 'Personal', order: 0),
          ],
          activeAccountUuid: 'existing-account',
          activeAddress: 'u1existing',
        )
      : const AccountState();

  @override
  Future<LinkedWalletAccountsImportResult> importLinkedWalletAccounts({
    required String network,
    required List<LinkedWalletAccountImport> accountsToImport,
  }) async {
    state = AsyncData(
      AccountState(
        accounts: [
          for (final (index, input) in accountsToImport.indexed)
            AccountInfo(
              uuid: 'gift-import-$index',
              name: input.name,
              order: index,
              profilePictureId:
                  input.profilePictureId ?? kDefaultProfilePictureId,
            ),
        ],
        activeAccountUuid: 'gift-import-0',
        activeAddress: 'u1preview',
      ),
    );
    return LinkedWalletAccountsImportResult(
      importedCount: accountsToImport.length,
      skippedDuplicateCount: 0,
    );
  }

  @override
  Future<void> switchAccount(String uuid) async {
    state = AsyncData(
      state.requireValue.copyWith(
        activeAccountUuid: uuid,
        activeAddress: 'u1preview',
      ),
    );
  }

  @override
  Future<void> clearPendingGiftAccountSetup({
    required String accountUuid,
  }) async {}

  @override
  Future<void> recoverPendingAccountMnemonic() async {
    if (_recoveryAttempts++ == 0) {
      throw StateError('Preview storage recovery failure');
    }
    await ref
        .read(paymentLinkReceivedStoreProvider)
        .saveReady(_pendingGift!, setupAccountUuid: 'gift-preview');
    _pendingGift = null;
  }

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async => const SoftwareWalletSecret(
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse '
        'access accident account accuse achieve acid acoustic acquire across act '
        'action actor actress actual',
  );

  @override
  Future<void> markBackedUp(String uuid) async => _complete(uuid, backup: true);

  @override
  Future<void> markGiftEducationComplete(String uuid) async =>
      _complete(uuid, backup: false);

  @override
  Future<void> snoozeBackupReminder(String uuid, {DateTime? now}) async {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        accounts: [
          for (final account in current.accounts)
            if (account.uuid == uuid && account.setupPending)
              account.copyWith(
                backupReminderSnoozeCount:
                    (account.backupReminderSnoozeCount + 1).clamp(1, 3),
                backupReminderSnoozedUntilUtc: (now ?? DateTime.now())
                    .toUtc()
                    .add(
                      backupReminderDelayForCount(
                        (account.backupReminderSnoozeCount + 1).clamp(1, 3),
                      ),
                    ),
              )
            else
              account,
        ],
      ),
    );
  }

  void _complete(String uuid, {required bool backup}) {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        accounts: [
          for (final account in current.accounts)
            account.uuid == uuid
                ? account.copyWith(
                    setupPending: backup ? false : null,
                    giftEducationPending: backup ? null : false,
                    clearBackupReminderSnooze: backup,
                  )
                : account,
        ],
      ),
    );
  }

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = kDefaultProfilePictureId,
    List<int> additionalAccountIndices = const [],
  }) async {
    state = AsyncData(
      AccountState(
        accounts: [
          AccountInfo(
            uuid: 'gift-preview',
            name: name ?? 'Imported wallet',
            profilePictureId: profilePictureId,
            order: 0,
          ),
        ],
        activeAccountUuid: 'gift-preview',
        activeAddress: 'u1preview',
      ),
    );
  }

  @override
  Future<String> createGiftClaimAccount({
    required String name,
    required String profilePictureId,
    required VizorPaymentLink link,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (failCreation) throw StateError('Preview wallet creation failure');
    state = AsyncData(
      AccountState(
        accounts: [
          ...state.requireValue.accounts,
          AccountInfo(
            uuid: 'gift-preview',
            name: name,
            profilePictureId: profilePictureId,
            order: state.requireValue.accounts.length,
            setupPending: true,
            giftEducationPending: true,
            birthdayHeight: link.birthdayHeight,
          ),
        ],
        activeAccountUuid: 'gift-preview',
        activeAddress: 'u1preview',
      ),
    );
    if (recoverStorage) {
      _pendingGift = link;
      throw GiftClaimAccountCreatedException(
        'gift-preview',
        StateError('Preview post-creation storage failure'),
      );
    }
    await ref
        .read(paymentLinkReceivedStoreProvider)
        .saveReady(link, setupAccountUuid: 'gift-preview');
    return 'gift-preview';
  }
}

class _ImportGiftReturn extends GiftClaimSetupReturnNotifier {
  @override
  GiftClaimSetupReturn build() => GiftClaimSetupReturn(
    link: _link,
    accountUuidsBeforeSetup: const {},
    inspection: _previewInspection(_link),
  );
}

class _GiftPreviewSecurity extends AppSecurityNotifier {
  String _passcode = '123456';
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);
  @override
  Future<void> preparePasswordSetup(String password) async {
    _passcode = password;
  }

  @override
  String requireSessionPasswordForNativeSecretUse() => _passcode;
  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();

  @override
  void commitPasswordSetup() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
  @override
  Future<void> rollbackPasswordSetup() async {}

  @override
  Future<bool> confirmPassword(String password) async => password == _passcode;
}

class _GiftPreviewSync extends SyncNotifier {
  @override
  Future<SyncState> build() async {
    ref.watch(paymentLinkLifecycleRevisionProvider);
    final uuid = ref.watch(
      accountProvider.select((state) => state.value?.activeAccountUuid),
    );
    final records = await ref.watch(paymentLinkReceivedStoreProvider).load();
    final received = records.where(
      (record) =>
          record.destinationAccountUuid == uuid &&
          record.status == PaymentLinkReceivedStatus.received,
    );
    final amount = received.fold<BigInt>(
      BigInt.zero,
      (total, record) => total + record.amountZatoshi,
    );
    return SyncState(
      accountUuid: uuid,
      hasAccountScopedData: uuid != null,
      isSyncComplete: true,
      percentage: 1,
      scannedHeight: 3428143,
      chainTipHeight: 3428143,
      orchardBalance: amount,
      spendableBalance: amount,
      totalBalance: amount,
      recentTransactions: [
        for (final record in received)
          rust_sync.TransactionInfo(
            txidHex: record.claimTxids!,
            minedHeight: BigInt.from(3428143),
            expiredUnmined: false,
            accountBalanceDelta: record.amountZatoshi.toInt(),
            fee: BigInt.zero,
            blockTime: BigInt.from(1788220800),
            isTransparent: false,
            txKind: 'received',
            displayAmount: record.amountZatoshi,
            displayPool: 'orchard',
            createdTime: BigInt.from(1788220800),
          ),
      ],
    );
  }

  @override
  bool needsPauseForWalletMutation() => false;

  @override
  Future<void> refreshAfterSend() async {}
}

class _GiftPreviewBiometrics extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => const BiometricUnlockState(
    availability: BiometricAvailability(
      supported: true,
      enrolled: true,
      kind: BiometricKind.face,
    ),
    enabled: false,
  );
  @override
  Future<void> enable(String passcode) async {
    final current = state.value ?? await future;
    state = AsyncData(current.copyWith(enabled: true));
  }

  @override
  Future<String?> readPasscode({required String reason}) async =>
      state.value?.enabled == true ? '123456' : null;
}

class _GiftPreviewClipboard implements PaymentLinkClipboard {
  @override
  Future<String?> readText() async => _link.toUri().toString();
  @override
  Future<void> clear() async {}
  @override
  Future<void> copySecret(String text) async {}
}

class _MemoryGiftStorage implements PaymentLinkReceivedStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}

class _GiftPreviewOperations implements PaymentLinkOperations {
  _GiftPreviewOperations(this.store, {this.failClaim = false});
  final bool failClaim;
  final PaymentLinkReceivedStore store;
  static const claimTxid =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async =>
      const [];
  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async => const {};
  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) => bindClaimDestination(
    _previewInspection(link),
    destinationAccountUuid: 'gift-preview',
  );
  @override
  Future<PaymentLinkClaimInspection> inspectClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return _previewInspection(link);
  }

  @override
  Future<PaymentLinkClaimSession> bindClaimDestination(
    PaymentLinkClaimInspection inspection, {
    required String destinationAccountUuid,
  }) async {
    if (failClaim) throw StateError('Preview claim failed.');
    return PaymentLinkClaimSession(
      link: inspection.link,
      destinationAddress: 'u1preview',
      destinationAccountUuid: destinationAccountUuid,
      directory: inspection.directory,
      dbPath: inspection.dbPath,
      accountUuid: inspection.accountUuid,
      totalZatoshi: inspection.totalZatoshi,
      claimableZatoshi: inspection.link.amountZatoshi,
      feeZatoshi: BigInt.from(10000),
      availability: PaymentLinkAvailability.available,
    );
  }

  @override
  Future<void> keepReceivedLink(
    VizorPaymentLink link, {
    String? setupAccountUuid,
  }) => store.saveReady(link, setupAccountUuid: setupAccountUuid);
  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    await store.markReceiving(
      address: session.link.address,
      destinationAccountUuid: session.destinationAccountUuid,
      claimTxids: claimTxid,
      claimSubmittedAt: DateTime.utc(2026, 9, 1),
      claimDestinationPool: 'orchard',
    );
    return PaymentLinkClaimResult(
      txids: claimTxid,
      status: PaymentLinkClaimBroadcastStatus.broadcasted,
    );
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() =>
      store.load();
  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records, {
    bool allowResubmit = true,
  }) async => records;
  @override
  Future<void> discardClaimInspection(
    PaymentLinkClaimInspection inspection,
  ) async {}
  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {}
  @override
  Future<void> retainPendingClaim(PaymentLinkClaimSession session) =>
      store.saveReady(
        session.link,
        setupAccountUuid: session.destinationAccountUuid,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CheckingGiftFlow extends GiftClaimFlowNotifier {
  @override
  GiftClaimFlowState build() =>
      GiftClaimFlowState(link: _link, phase: GiftClaimPhase.checking);
}

class _FundingFoundProgress extends GiftCardCheckProgressNotifier {
  @override
  Map<String, GiftCardCheckProgress> build() => {
    paymentLinkClaimWalletDirectoryName(_link): GiftCardCheckProgress(
      _link,
      rust_sync.ApiGiftCardCheckProgress(
        phase: 'checking',
        completed: BigInt.from(50),
        total: BigInt.from(100),
        fundingHeight: _link.birthdayHeight + 1,
        checkedHeight: _link.birthdayHeight + 50,
        totalZatoshi: _link.amountZatoshi + BigInt.from(10000),
        unspentZatoshi: _link.amountZatoshi + BigInt.from(10000),
        complete: false,
      ),
    ),
  };
}

class _LongSyncGiftFlow extends GiftClaimFlowNotifier {
  @override
  GiftClaimFlowState build() => GiftClaimFlowState(
    link: _link,
    phase: GiftClaimPhase.longSyncConfirmation,
  );
}

PaymentLinkClaimInspection _previewInspection(VizorPaymentLink link) =>
    PaymentLinkClaimInspection(
      link: link.withResolvedMetadata(
        address: _link.address,
        createdAt: _link.createdAt,
      ),
      directory: Directory.systemTemp,
      dbPath: 'preview',
      accountUuid: 'preview-card',
      totalZatoshi: link.amountZatoshi + BigInt.from(10000),
      claimableZatoshi: link.amountZatoshi,
      feeZatoshi: BigInt.from(10000),
      fundingConfirmationCount: 2,
      waitingForFundingConfirmations: false,
      availability: PaymentLinkAvailability.available,
    );

class _InspectedGiftFlow extends GiftClaimFlowNotifier {
  _InspectedGiftFlow({this.setupPasscode});
  final String? setupPasscode;

  @override
  GiftClaimFlowState build() => GiftClaimFlowState(
    link: _link,
    phase: GiftClaimPhase.inspected,
    inspection: _previewInspection(_link),
    setupPasscode: setupPasscode,
    walletSetupInProgress: setupPasscode != null,
  );
}

class _GiftPreviewImportStorage implements GiftClaimImportStorage {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async => _value = value;
  @override
  Future<void> delete() async => _value = null;
}
