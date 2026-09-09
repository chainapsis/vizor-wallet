import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/app_main_sidebar.dart';
import '../src/core/layout/app_pane_scroll_scaffold.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/features/address_book/models/address_book_contact.dart';
import '../src/features/address_book/providers/address_book_provider.dart';
import '../src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../src/features/send/models/send_prefill_args.dart';
import '../src/features/send/screens/send_screen.dart';
import '../src/features/send/screens/mobile/mobile_send_screen.dart';
import '../src/features/send/services/send_compose_dependencies.dart';
import '../src/features/send/services/send_proving_key_warmup.dart';
import '../src/features/send/widgets/send_recipient_resolver.dart';
import '../src/features/send/widgets/send_review_content_view.dart';
import '../src/features/send/widgets/send_review_layout.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/sync_provider.dart';
import '../src/providers/zec_price_change_provider.dart';
import '../src/rust/api/sync.dart' as rust_sync;

enum LedgerTransferScenario { send, ready }

const _recipient = 'u1exampleledgerrecipientforpreviewonly';
const _account = AccountInfo(
  uuid: 'ledger-preview',
  name: 'Daily spending',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  ledgerWalletName: 'My Ledger',
);
const _accounts = AccountState(
  accounts: [_account],
  activeAccountUuid: 'ledger-preview',
  activeAddress: 'u1previewownaddress',
);

/// Actual Send screens, with fixture dependencies and no native wallet calls.
class LedgerTransferPreview extends StatefulWidget {
  const LedgerTransferPreview({required this.scenario, super.key});
  final LedgerTransferScenario scenario;
  @override
  State<LedgerTransferPreview> createState() => _LedgerTransferPreviewState();
}

class _LedgerTransferPreviewState extends State<LedgerTransferPreview> {
  late final GoRouter _router;
  SendPrefillArgs? _review;
  bool _memoExpanded = false;
  bool get _mobile => kAppFormFactor == AppFormFactor.mobile;
  SendPrefillArgs get _prefill => SendPrefillArgs(
    id: 'widgetbook-${widget.scenario.name}',
    source: 'widgetbook',
    address: _recipient,
    amountText: widget.scenario == LedgerTransferScenario.send
        ? '2.00'
        : '1.24',
    memoText: 'For dinner',
  );

  void _openReview(SendPrefillArgs args) {
    _review = args;
    _router.push('/review');
  }

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/send',
      routes: [
        GoRoute(
          path: '/send',
          builder: (context, state) => _mobile
              ? MobileSendScreen(
                  initialRecipient: _prefill.address,
                  initialAddressType: 'unified',
                  initialAmount: _prefill.amountText,
                  initialMemo: _prefill.memoText,
                  initialContactLabel: 'Alice',
                  initialContactPictureId: 'pfp-02',
                  loadWalletDbPath: () async => '/preview/not-a-wallet',
                  validateAddress: _validateAddress,
                  estimateFee: _estimateFee,
                  openScanner: (_) async => null,
                  onReview: _openReview,
                )
              : SendScreen(prefill: _prefill, onReview: _openReview),
        ),
        GoRoute(path: '/review', builder: (_, _) => _reviewPage()),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  Widget _reviewPage() {
    final args = _review!;
    final content = StatefulBuilder(
      builder: (context, setReviewState) => SendReviewContentView(
        amountText: '${args.amountText} ZEC',
        feeText: '0.0001 ZEC',
        recipient: SendReviewContactRecipient(
          name: 'Alice',
          profilePictureId: 'pfp-02',
          address: args.address,
        ),
        memoText: args.memoText,
        memoExpanded: _memoExpanded,
        confirmLabel: 'Confirm with Ledger',
        confirmLeadingIconName: AppIcons.ledger,
        // The preview ends before device approval.
        onConfirm: null,
        onCancel: () => _router.pop(),
        onExpandMemo: () =>
            setReviewState(() => _memoExpanded = !_memoExpanded),
      ),
    );
    if (_mobile) {
      return Material(
        color: context.colors.background.window,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: content,
        ),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: content,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(
          AppBootstrapState(
            initialLocation: '/send',
            initialAccountState: _accounts,
            initialSyncSnapshot: AppSyncSnapshot.empty,
            network: kZcashDefaultNetworkName,
            rpcEndpointConfig: defaultRpcEndpointConfig(
              kZcashDefaultNetworkName,
            ),
            themeMode: ThemeMode.system,
            privacyModeEnabled: false,
            isPasswordConfigured: true,
            isUnlocked: true,
            passwordRotationRecoveryFailed: false,
          ),
        ),
        accountProvider.overrideWith(_PreviewAccountNotifier.new),
        syncProvider.overrideWith(_PreviewSyncNotifier.new),
        sendWalletDbPathProvider.overrideWithValue(
          () async => '/preview/not-a-wallet',
        ),
        sendProvingKeyWarmupProvider.overrideWithValue(() {}),
        sendAddressValidatorProvider.overrideWithValue(_validateAddress),
        sendFeeEstimatorProvider.overrideWithValue(_estimateFee),
        sendMaxEstimatorProvider.overrideWithValue(_estimateMax),
        ownAccountAddressesProvider.overrideWithValue(const AsyncData({})),
        addressBookRepositoryProvider.overrideWithValue(
          const _PreviewContacts(),
        ),
        zecLiveUsdUnitPriceProvider.overrideWithValue(40),
        zecHomeUsdUnitPriceProvider.overrideWithValue(40),
        ironwoodHomeMigrationCtaProvider.overrideWithValue(
          const AsyncData(IronwoodHomeMigrationCtaState.hidden()),
        ),
        ironwoodHomeMigrationPresentationProvider.overrideWithValue(
          const IronwoodHomeMigrationCtaState.hidden(),
        ),
        ironwoodPostMigrationStateProvider.overrideWithValue(
          const AsyncData(IronwoodPostMigrationState.inactive()),
        ),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          _PreviewMigrationCoordinator.new,
        ),
      ],
      child: Material(
        color: theme.colors.background.window,
        child: Center(
          child: SizedBox(
            width: _mobile ? 393 : 1160,
            height: _mobile ? 852 : 840,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Text(
                    'Preview · Example amounts · Device approval disabled',
                    style: AppTypography.labelSmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ),
                Expanded(
                  child: MaterialApp.router(
                    debugShowCheckedModeBanner: false,
                    routerConfig: _router,
                    builder: (_, child) => AppTheme(data: theme, child: child!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<rust_sync.AddressValidationResult> _validateAddress({
  required String address,
}) async => rust_sync.AddressValidationResult(
  isValid: address.startsWith('u1'),
  addressType: address.startsWith('u1') ? 'unified' : 'invalid',
);

Future<BigInt> _estimateFee({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  required BigInt amountZatoshi,
  String? memo,
}) async {
  if (amountZatoshi > BigInt.from(124000000)) {
    throw StateError('VIZOR_LEDGER_CAPACITY: preview input budget exceeded');
  }
  return BigInt.from(10000);
}

Future<rust_sync.SendMaxEstimateResult> _estimateMax({
  required String dbPath,
  required String network,
  required String accountUuid,
  required String toAddress,
  String? memo,
}) async => rust_sync.SendMaxEstimateResult(
  amountZatoshi: BigInt.from(124000000),
  feeZatoshi: BigInt.from(10000),
  needsSaplingParams: false,
);

class _PreviewAccountNotifier extends AccountNotifier {
  @override
  Future<AccountState> build() async => _accounts;
}

class _PreviewMigrationCoordinator extends IronwoodMigrationCoordinator {
  @override
  IronwoodMigrationCoordinatorState build() =>
      const IronwoodMigrationCoordinatorState();
}

class _PreviewSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: _account.uuid,
    hasAccountScopedData: true,
    spendableBalance: BigInt.from(250000000),
    totalBalance: BigInt.from(250000000),
    ironwoodBalance: BigInt.from(250000000),
    percentage: 1,
    isSyncComplete: true,
  );
  @override
  Future<void> waitForAuthoritativeSpendable({
    required String accountUuid,
    Duration timeout = const Duration(seconds: 30),
  }) async {}
}

class _PreviewContacts implements AddressBookRepository {
  const _PreviewContacts();
  @override
  Future<List<AddressBookContact>> loadContacts() async => [
    AddressBookContact(
      id: 'alice',
      label: 'Alice',
      network: AddressBookNetwork.zcash,
      address: _recipient,
      profilePictureId: 'pfp-02',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
  ];
  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {}
}
