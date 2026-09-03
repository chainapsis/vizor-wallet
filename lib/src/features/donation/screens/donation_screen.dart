import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../../send/services/send_amount_conversion.dart';
import '../../send/services/send_flow.dart';
import '../../send/services/send_proving_key_warmup.dart';
import '../donation_config.dart';
import '../widgets/donation_views.dart';

class DonationScreen extends ConsumerStatefulWidget {
  const DonationScreen({super.key});

  @override
  ConsumerState<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends ConsumerState<DonationScreen> {
  final _controller = TextEditingController();
  DonationAmountMode _mode = DonationAmountMode.zec;
  String _zecText = '';
  String _usdText = '';
  String? _selectedPreset;
  String? _amountError;
  String? _globalError;
  bool _submitting = false;
  int _validationSequence = 0;
  Timer? _validationTimer;

  @override
  void initState() {
    super.initState();
    try {
      ref.read(sendProvingKeyWarmupProvider).call();
    } catch (error) {
      log('Donation: Orchard proving-key warmup failed to start: $error');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _isUsd => _mode == DonationAmountMode.usd;

  BigInt? _amountZatoshi(double? price) => _isUsd
      ? sendZatoshiFromUsdText(_usdText, price)
      : parseZecAmount(_zecText);

  void _setVisibleText(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _handleAmountChanged(String value) {
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    setState(() {
      _selectedPreset = null;
      _globalError = null;
      if (_isUsd) {
        _usdText = value.trim();
        final zatoshi = sendZatoshiFromUsdText(_usdText, price);
        _zecText = zatoshi == null
            ? ''
            : ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
      } else {
        _zecText = value.trim();
      }
    });
    _scheduleValidation();
  }

  void _selectPreset(String value) {
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    setState(() {
      _selectedPreset = value;
      _globalError = null;
      if (_isUsd) {
        _usdText = value;
        final zatoshi = sendZatoshiFromUsdText(value, price);
        _zecText = zatoshi == null
            ? ''
            : ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
      } else {
        _zecText = value;
      }
    });
    _setVisibleText(value);
    _scheduleValidation(immediate: true);
  }

  void _toggleMode() {
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    if (!_isUsd && price == null) return;
    setState(() {
      _selectedPreset = null;
      _amountError = null;
      _globalError = null;
      if (_isUsd) {
        final zatoshi = sendZatoshiFromUsdText(_usdText, price);
        _zecText = zatoshi == null
            ? ''
            : ZecAmount.fromZatoshi(zatoshi).pretty().amountText;
        _mode = DonationAmountMode.zec;
      } else {
        final zatoshi = parseZecAmount(_zecText);
        _usdText = zatoshi == null
            ? ''
            : sendSendableUsdInputTextForZatoshi(zatoshi, price!);
        _mode = DonationAmountMode.usd;
      }
    });
    _setVisibleText(_isUsd ? _usdText : _zecText);
    _scheduleValidation();
  }

  void _scheduleValidation({bool immediate = false}) {
    _validationTimer?.cancel();
    final sequence = ++_validationSequence;
    if (immediate) {
      unawaited(_validateAmount(sequence));
    } else {
      _validationTimer = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_validateAmount(sequence)),
      );
    }
  }

  Future<void> _validateAmount(int sequence) async {
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    final amount = _amountZatoshi(price);
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    final scoped = (ref.read(syncProvider).value ?? SyncState())
        .scopedToAccount(activeAccountUuid);
    final migration = ref.read(ironwoodHomeMigrationCtaProvider).value;
    final migrationInProgress =
        migration?.mode == IronwoodHomeMigrationCtaMode.resume;
    final available = migrationInProgress
        ? scoped.displayIronwoodBalance
        : scoped.displaySpendableBalance;

    String? localError;
    if (_controller.text.trim().isNotEmpty && amount == null) {
      localError = 'Invalid amount';
    } else if (amount != null && amount > available) {
      localError = 'Insufficient shielded balance';
    }
    if (!mounted || sequence != _validationSequence) return;
    setState(() => _amountError = localError);
    if (localError != null ||
        amount == null ||
        amount <= BigInt.zero ||
        activeAccountUuid == null ||
        scoped.isUsingCompletedSpendableSnapshot) {
      return;
    }

    try {
      final fee = await ref
          .read(syncProvider.notifier)
          .runWithAuthoritativeSpendable<BigInt?>(
            accountUuid: activeAccountUuid,
            operation: () async {
              if (!mounted || sequence != _validationSequence) return null;
              final endpoint = ref.read(rpcEndpointProvider);
              return rust_sync.estimateFee(
                dbPath: await getWalletDbPath(),
                network: endpoint.networkName,
                accountUuid: activeAccountUuid,
                toAddress: kVizorDonationAddress,
                amountZatoshi: amount,
                memo: null,
              );
            },
          );
      if (!mounted || sequence != _validationSequence || fee == null) return;
      setState(() {
        _amountError = amount + fee > available
            ? 'Insufficient shielded balance including fee'
            : null;
      });
    } catch (error) {
      if (!mounted || sequence != _validationSequence) return;
      if (error.toString().toLowerCase().contains('insufficient')) {
        setState(() {
          _amountError = 'Insufficient shielded balance including fee';
        });
      } else {
        log('Donation: fee estimation failed (non-blocking): $error');
      }
    }
  }

  Future<void> _openReview() async {
    final price = ref.read(zecLiveUsdUnitPriceProvider);
    final amount = _amountZatoshi(price);
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (amount == null || amount <= BigInt.zero || accountUuid == null) return;

    setState(() {
      _submitting = true;
      _globalError = null;
    });
    final flowId = newSendFlowId();
    BigInt? proposalId;
    var openedReview = false;
    try {
      final args = await proposeSendTransfer(
        ref: ref,
        accountUuid: accountUuid,
        sendFlowId: flowId,
        address: kVizorDonationAddress,
        addressType: 'unified',
        amountZatoshi: amount,
        flowKind: SendFlowKind.donation,
      );
      proposalId = args.proposalId;
      if (!mounted) return;
      setState(() => _submitting = false);
      openedReview = true;
      await context.push('/send/review', extra: args);
    } catch (error) {
      log('Donation: proposal failed: $error');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _globalError = friendlyProposeSendError(error.toString());
      });
    } finally {
      if (proposalId != null && !openedReview) {
        await discardSendProposal(
          proposalId: proposalId,
          sendFlowId: flowId,
          logContext: 'Donation(review not opened)',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final scoped = ref.watch(
      syncProvider.select(
        (value) => (value.value ?? SyncState()).scopedToAccount(accountUuid),
      ),
    );
    final migration = ref.watch(ironwoodHomeMigrationCtaProvider).value;
    final available = migration?.mode == IronwoodHomeMigrationCtaMode.resume
        ? scoped.displayIronwoodBalance
        : scoped.displaySpendableBalance;
    final price = ref.watch(zecLiveUsdUnitPriceProvider);
    final amount = _amountZatoshi(price);
    final conversionText = _isUsd
        ? '${amount == null ? '0' : ZecAmount.fromZatoshi(amount).pretty().amountText} ZEC'
        : amount == null || amount <= BigInt.zero || price == null
        ? r'$ 0'
        : r'$ ' + sendUsdDisplayTextForZatoshi(amount, price);
    final canContinue =
        !_submitting &&
        _amountError == null &&
        amount != null &&
        amount > BigInt.zero &&
        amount <= available &&
        accountUuid != null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(backLinkMinWidth: 60),
            Expanded(
              child: DonationComposeView(
                controller: _controller,
                mode: _mode,
                conversionText: conversionText,
                selectedPreset: _selectedPreset,
                errorText: _amountError ?? _globalError,
                isSubmitting: _submitting,
                onAmountChanged: _handleAmountChanged,
                onToggleMode: _isUsd || price != null ? _toggleMode : null,
                onPresetSelected: _selectPreset,
                onContinue: canContinue ? () => unawaited(_openReview()) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
