import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../send/services/sapling_params.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_recovery_store.dart';

final paymentLinkServiceProvider = Provider<PaymentLinkService>((ref) {
  return PaymentLinkService(ref, ref.read(paymentLinkRecoveryStoreProvider));
});

class PaymentLinkClaimSession {
  const PaymentLinkClaimSession({
    required this.link,
    required this.purpose,
    required this.destinationAddress,
    required this.directory,
    required this.dbPath,
    required this.accountUuid,
    required this.totalZatoshi,
    required this.claimableZatoshi,
    required this.feeZatoshi,
  });

  final VizorPaymentLink link;
  final PaymentLinkSpendPurpose purpose;
  final String destinationAddress;
  final Directory directory;
  final String dbPath;
  final String accountUuid;
  final BigInt totalZatoshi;
  final BigInt claimableZatoshi;
  final BigInt feeZatoshi;

  bool get canClaim => claimableZatoshi > BigInt.zero;
}

enum PaymentLinkSpendPurpose { claim, reclaim }

class PaymentLinkService {
  PaymentLinkService(this._ref, this._recoveryStore);

  final Ref _ref;
  final PaymentLinkRecoveryStore _recoveryStore;

  Future<VizorPaymentLink> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    if (sourceAccountUuid.isEmpty) {
      throw StateError('No active account.');
    }
    if (amountZatoshi <= BigInt.zero) {
      throw ArgumentError.value(
        amountZatoshi,
        'amountZatoshi',
        'Payment link amount must be positive.',
      );
    }

    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final paymentAccount = await rust_wallet.previewNewSoftwareAccount(
      network: endpoint.networkName,
    );
    final ephemeralAddress = paymentAccount.unifiedAddress;
    if (ephemeralAddress.isEmpty) {
      throw StateError('Payment link account was created without an address.');
    }

    final birthdayHeight = await _ref
        .read(rpcEndpointFailoverProvider.notifier)
        .getLatestBlockHeight();
    final link = VizorPaymentLink(
      network: endpoint.networkName,
      address: ephemeralAddress,
      amountZatoshi: amountZatoshi,
      mnemonic: paymentAccount.mnemonic,
      birthdayHeight: birthdayHeight.toInt(),
      label: 'Payment link',
      createdAt: DateTime.now(),
    );

    await PaymentLinkFundingRecovery(_recoveryStore).fund(
      link: link,
      sourceAccountUuid: sourceAccountUuid,
      broadcast: () => _sendShielded(
        fromAccountUuid: sourceAccountUuid,
        toAddress: ephemeralAddress,
        amountZatoshi: amountZatoshi,
        memo: null,
      ),
    );

    unawaited(_ref.read(syncProvider.notifier).refreshAfterSend());
    return link;
  }

  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() {
    return _recoveryStore.load();
  }

  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) {
    return _recoveryStore.markShared(address: link.address);
  }

  Future<PaymentLinkRecoveryRecord> setCreatedLinkArchived(
    VizorPaymentLink link, {
    required bool archived,
  }) {
    return _recoveryStore.setArchived(
      address: link.address,
      archived: archived,
    );
  }

  Future<PaymentLinkClaimSession> prepareClaim(VizorPaymentLink link) async {
    final receiverState = _ref.read(accountProvider).value;
    final receiverAddress = receiverState?.activeAddress;
    if (receiverState?.activeAccountUuid == null ||
        receiverAddress == null ||
        receiverAddress.isEmpty) {
      throw StateError('No active receive account.');
    }
    return _prepareSpend(
      link: link,
      purpose: PaymentLinkSpendPurpose.claim,
      destinationAddress: receiverAddress,
    );
  }

  Future<PaymentLinkClaimSession> prepareCreatedLinkReclaim(
    PaymentLinkRecoveryRecord record,
  ) async {
    if (record.state == PaymentLinkRecoveryState.reclaiming) {
      throw StateError('Payment link reclaim is already in progress.');
    }
    final accountState = _ref.read(accountProvider).value;
    final sourceAccountExists =
        accountState?.accounts.any(
          (account) => account.uuid == record.sourceAccountUuid,
        ) ??
        false;
    if (!sourceAccountExists) {
      throw StateError('Payment link source account is no longer available.');
    }

    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (record.link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${record.link.network}, but this wallet is using '
        '${endpoint.networkName}.',
      );
    }
    final sourceAddress = await rust_wallet.getUnifiedAddress(
      dbPath: await getWalletDbPath(),
      network: endpoint.networkName,
      accountUuid: record.sourceAccountUuid,
    );
    return _prepareSpend(
      link: record.link,
      purpose: PaymentLinkSpendPurpose.reclaim,
      destinationAddress: sourceAddress,
    );
  }

  Future<PaymentLinkClaimSession> _prepareSpend({
    required VizorPaymentLink link,
    required PaymentLinkSpendPurpose purpose,
    required String destinationAddress,
  }) async {
    await _requireShieldedAddress(destinationAddress);
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    if (link.network != endpoint.networkName) {
      throw StateError(
        'Payment link is for ${link.network}, but this wallet is using '
        '${endpoint.networkName}.',
      );
    }

    final tempWallet = await _createTemporaryWalletDb();
    try {
      final imported = await rust_wallet.importWallet(
        mnemonic: link.mnemonic,
        bip39Passphrase: '',
        birthdayHeight: BigInt.from(link.birthdayHeight),
        network: endpoint.networkName,
        dbPath: tempWallet.dbPath,
        accountName: purpose == PaymentLinkSpendPurpose.claim
            ? 'Payment link claim'
            : 'Payment link reclaim',
      );
      if (imported.unifiedAddress != link.address) {
        throw const FormatException(
          'Payment link address does not match its recovery phrase.',
        );
      }

      await _runBlockingSync(dbPath: tempWallet.dbPath);
      final balance = await rust_sync.getBalance(
        dbPath: tempWallet.dbPath,
        network: endpoint.networkName,
        accountUuid: imported.accountUuid,
      );
      var claimableZatoshi = BigInt.zero;
      var feeZatoshi = BigInt.zero;
      try {
        final estimate = await rust_sync.estimateSendMaxMinConfirmations(
          dbPath: tempWallet.dbPath,
          network: endpoint.networkName,
          accountUuid: imported.accountUuid,
          toAddress: destinationAddress,
        );
        claimableZatoshi = estimate.amountZatoshi;
        feeZatoshi = estimate.feeZatoshi;
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (!message.contains('insufficient balance')) {
          rethrow;
        }
      }

      return PaymentLinkClaimSession(
        link: link,
        purpose: purpose,
        destinationAddress: destinationAddress,
        directory: tempWallet.directory,
        dbPath: tempWallet.dbPath,
        accountUuid: imported.accountUuid,
        totalZatoshi: balance.total,
        claimableZatoshi: claimableZatoshi,
        feeZatoshi: feeZatoshi,
      );
    } catch (_) {
      await _deleteTemporaryWalletDb(tempWallet.directory);
      rethrow;
    }
  }

  Future<String> claimPreparedLink(PaymentLinkClaimSession session) async {
    if (session.purpose != PaymentLinkSpendPurpose.claim) {
      throw ArgumentError('A reclaim session cannot be used as a claim.');
    }
    return _broadcastPreparedSpend(session);
  }

  Future<String> reclaimPreparedCreatedLink(
    PaymentLinkRecoveryRecord record,
    PaymentLinkClaimSession session,
  ) async {
    if (session.purpose != PaymentLinkSpendPurpose.reclaim ||
        session.link.address != record.link.address) {
      throw ArgumentError('Payment link reclaim session does not match.');
    }
    try {
      return await PaymentLinkReclaimRecovery(_recoveryStore).reclaim(
        address: record.link.address,
        broadcast: () =>
            _broadcastPreparedSpend(session, discardSession: false),
      );
    } finally {
      await discardClaimSession(session);
    }
  }

  Future<String> _broadcastPreparedSpend(
    PaymentLinkClaimSession session, {
    bool discardSession = true,
  }) async {
    try {
      if (!session.canClaim) {
        throw StateError('Payment link has no spendable shielded balance yet.');
      }
      final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
      if (session.link.network != endpoint.networkName) {
        throw StateError(
          'Payment link is for ${session.link.network}, but this wallet is '
          'using ${endpoint.networkName}.',
        );
      }
      final estimate = await rust_sync.estimateSendMaxMinConfirmations(
        dbPath: session.dbPath,
        network: endpoint.networkName,
        accountUuid: session.accountUuid,
        toAddress: session.destinationAddress,
      );
      if (estimate.amountZatoshi <= BigInt.zero) {
        throw StateError('Payment link has no spendable shielded balance yet.');
      }

      final txids = await _sendShielded(
        dbPath: session.dbPath,
        fromAccountUuid: session.accountUuid,
        toAddress: session.destinationAddress,
        amountZatoshi: estimate.amountZatoshi,
        memo: null,
        mnemonic: session.link.mnemonic,
        useMinConfirmations: true,
      );
      unawaited(_ref.read(syncProvider.notifier).refreshAfterSend());
      return txids;
    } finally {
      if (discardSession) {
        await discardClaimSession(session);
      }
    }
  }

  Future<String> claimLink(VizorPaymentLink link) async {
    final session = await prepareClaim(link);
    return claimPreparedLink(session);
  }

  Future<String> reclaimCreatedLink(PaymentLinkRecoveryRecord record) async {
    final session = await prepareCreatedLinkReclaim(record);
    return reclaimPreparedCreatedLink(record, session);
  }

  Future<void> discardClaimSession(PaymentLinkClaimSession session) =>
      _deleteTemporaryWalletDb(session.directory);

  Future<String> _sendShielded({
    String? dbPath,
    required String fromAccountUuid,
    required String toAddress,
    required BigInt amountZatoshi,
    String? memo,
    String? mnemonic,
    bool useMinConfirmations = false,
  }) async {
    await _requireShieldedAddress(toAddress);
    final walletDbPath = dbPath ?? await getWalletDbPath();
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    final sendFlowId = _newSendFlowId();
    final proposal = useMinConfirmations
        ? await rust_sync.proposeSendMinConfirmations(
            dbPath: walletDbPath,
            network: endpoint.networkName,
            accountUuid: fromAccountUuid,
            sendFlowId: sendFlowId,
            toAddress: toAddress,
            amountZatoshi: amountZatoshi,
            memo: memo,
          )
        : await rust_sync.proposeSend(
            dbPath: walletDbPath,
            network: endpoint.networkName,
            accountUuid: fromAccountUuid,
            sendFlowId: sendFlowId,
            toAddress: toAddress,
            amountZatoshi: amountZatoshi,
            memo: memo,
          );

    try {
      final result = await _executeProposal(
        dbPath: walletDbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        accountUuid: fromAccountUuid,
        proposalId: proposal.proposalId,
        sendFlowId: sendFlowId,
        needsSaplingParams: proposal.needsSaplingParams,
        mnemonic: mnemonic,
      );
      if (result.status != 'broadcasted') {
        throw StateError(result.message ?? 'Transaction was not broadcast.');
      }
      return result.txids;
    } catch (e) {
      try {
        await rust_sync.discardProposal(
          proposalId: proposal.proposalId,
          sendFlowId: sendFlowId,
        );
      } catch (discardError) {
        log('PaymentLinkService: discardProposal failed: $discardError');
      }
      rethrow;
    }
  }

  Future<rust_sync.ExecuteProposalResult> _executeProposal({
    required String dbPath,
    required String lightwalletdUrl,
    required String accountUuid,
    required BigInt proposalId,
    required String sendFlowId,
    required bool needsSaplingParams,
    String? mnemonic,
  }) async {
    var saplingParams = await loadSaplingParamsStatus();
    if (needsSaplingParams && !saplingParams.complete) {
      await downloadMissingSaplingParams(
        saplingParams,
        log: (message) => log('PaymentLinkService: $message'),
      );
      saplingParams = await loadSaplingParamsStatus();
    }

    if (Platform.isMacOS && mnemonic == null) {
      final password = _ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      return rust_sync.executeProposalWithMacosStoredMnemonic(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        password: password,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    }

    final mnemonicBytes = mnemonic == null
        ? await _ref
              .read(accountProvider.notifier)
              .getMnemonicBytesForAccount(accountUuid)
        : Uint8List.fromList(utf8.encode(mnemonic));
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw StateError('Mnemonic not found for payment link account.');
    }
    late final Future<rust_sync.ExecuteProposalResult> result;
    try {
      result = rust_sync.executeProposal(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
        mnemonicBytes: mnemonicBytes,
        spendParamsPath: needsSaplingParams ? saplingParams.spendPath : null,
        outputParamsPath: needsSaplingParams ? saplingParams.outputPath : null,
      );
    } finally {
      _zeroize(mnemonicBytes);
    }
    return result;
  }

  Future<void> _runBlockingSync({required String dbPath}) async {
    final endpoint = _ref.read(rpcEndpointFailoverProvider).current;
    await rust_sync.runFullSyncBlocking(
      dbPath: dbPath,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: endpoint.networkName,
      mode: 1,
    );
  }

  Future<({Directory directory, String dbPath})>
  _createTemporaryWalletDb() async {
    final supportDir = await getWalletSupportDirectory();
    final random = Random.secure();
    final suffix = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final separator = Platform.pathSeparator;
    final directory = Directory(
      '${supportDir.path}${separator}payment_link_claim_$suffix',
    );
    await directory.create(recursive: true);
    return (
      directory: directory,
      dbPath: '${directory.path}${separator}zcash_wallet.db',
    );
  }

  Future<void> _deleteTemporaryWalletDb(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e, st) {
      log(
        'PaymentLinkService: failed to delete temporary payment-link DB '
        '${directory.path}: $e\n$st',
      );
    }
  }

  Future<void> _requireShieldedAddress(String address) async {
    final validation = await rust_sync.validateAddress(address: address);
    if (!validation.isValid ||
        (validation.addressType != 'unified' &&
            validation.addressType != 'sapling')) {
      throw StateError('Payment links only support shielded addresses.');
    }
  }

  String _newSendFlowId() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  void _zeroize(Uint8List bytes) {
    bytes.fillRange(0, bytes.length, 0);
  }
}
