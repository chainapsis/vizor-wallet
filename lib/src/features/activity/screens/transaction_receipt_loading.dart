import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../payment_links/services/payment_link_transaction_matching.dart';
import '../gift_card_activity_index.dart';
import '../public_details_load.dart';
import '../transaction_completeness.dart';
import '../widgets/public_details_lookup_dialog.dart';

/// Loads the Activity rows of one transaction, `txidHex` as
/// [rust_sync.TransactionInfo.txidHex], not the account's whole history;
/// injectable so previews and widget tests can avoid the Rust FFI.
typedef ActivityTxHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(
      String accountUuid,
      String txidHex,
    );

/// Loads one transaction's detail; injectable for previews and widget tests.
typedef ActivityTxDetailLoader =
    Future<rust_sync.TransactionDetail?> Function(
      String accountUuid,
      rust_sync.TransactionInfo transaction,
    );

/// Asks the next sync to look a transaction's transparent details up first;
/// injectable for widget tests.
typedef TransparentDetailsPrioritizer = Future<void> Function(String txidHex);

/// Loads one transaction's full details from the server after the user
/// confirmed; injectable for widget tests.
typedef TransparentDetailsPublicLookup =
    Future<void> Function(rust_sync.TransactionInfo transaction);

/// Asks the user before a public lookup; injectable for widget tests.
typedef PublicLookupConfirmation = Future<bool> Function(BuildContext context);

/// What a receipt screen opens on. The tapped row passes its
/// [initialTransaction] so the screen renders at once; the screen then
/// refreshes itself from the wallet database.
abstract interface class TransactionReceiptArgs {
  String get txidHex;
  String? get txKind;
  rust_sync.TransactionInfo? get initialTransaction;
  rust_sync.TransactionDetail? get initialDetail;

  /// Account that supplied the row and its metadata. Absent for direct links.
  String? get sourceAccountUuid;

  /// Set when the tapped row already resolved this transaction as a Gift
  /// Card.
  GiftCardActivityMetadata? get giftCard;
}

/// A desktop or mobile receipt of one transaction, with the test seams its
/// [TransactionReceiptLoading] state reads.
abstract class TransactionReceiptScreen extends ConsumerStatefulWidget {
  const TransactionReceiptScreen({
    super.key,
    this.historyLoader,
    this.detailLoader,
    this.transparentDetailsPrioritizer,
    this.transparentDetailsPublicLookup,
    this.publicLookupConfirmation = confirmPublicDetailsLookup,
  });

  TransactionReceiptArgs get receiptArgs;

  /// Test seam — production reads the wallet DB through Rust.
  @visibleForTesting
  final ActivityTxHistoryLoader? historyLoader;

  /// Test seam — production reads the wallet DB through Rust.
  @visibleForTesting
  final ActivityTxDetailLoader? detailLoader;

  /// Test seam — production asks Rust.
  @visibleForTesting
  final TransparentDetailsPrioritizer? transparentDetailsPrioritizer;

  /// Test seam — production asks Rust.
  @visibleForTesting
  final TransparentDetailsPublicLookup? transparentDetailsPublicLookup;

  /// Test seam — production shows [PublicDetailsLookupDialog].
  final PublicLookupConfirmation publicLookupConfirmation;
}

/// Loads and refreshes what a receipt screen shows, for desktop and mobile
/// alike: the transaction's Activity row and its detail, read for that one
/// transaction only; the follow-up
/// that re-reads the detail while its transparent details are on the way;
/// and the public lookup the receipt offers.
///
/// Every load bumps a generation, and a result is shown only while its
/// generation and account are still current, so a superseded or another
/// account's read is never shown. Screens render from the getters here and
/// call [listenForReceiptRefresh] at the top of `build`.
mixin TransactionReceiptLoading<W extends TransactionReceiptScreen>
    on ConsumerState<W> {
  rust_sync.TransactionInfo? _transaction;
  rust_sync.TransactionDetail? _detail;
  bool _isLoading = false;
  // A null detail can mean pending, unavailable, or failed. Keep the read
  // state separate, and show placeholders only without a matching cached detail.
  bool _detailsPending = true;
  String? _error;
  String? _activeAccountUuid;
  String? _argsAccountUuid;
  int _loadGeneration = 0;
  Timer? _transparentDetailsPoll;
  bool _transparentDetailsPollInFlight = false;
  bool _transparentDetailsPrioritized = false;
  String? _publicLookupText;
  bool _publicLookupRunning = false;
  // The detail read a load started for the shown row before its row read
  // returned, while it runs: a load that supersedes it shares it.
  ({
    String accountUuid,
    rust_sync.TransactionInfo row,
    Future<rust_sync.TransactionDetail?> read,
  })?
  _earlyDetailRead;

  /// The Activity row shown, or `null` until one loads.
  rust_sync.TransactionInfo? get receiptTransaction => _transaction;

  /// The last detail read, which may belong to a row no longer shown; see
  /// [matchingReceiptDetailFor].
  rust_sync.TransactionDetail? get receiptDetail => _detail;

  /// Whether no row is shown yet because one is loading.
  bool get receiptLoading => _isLoading;

  /// Why the last load failed, if it did.
  String? get receiptError => _error;

  /// The account the shown receipt was loaded for.
  String? get receiptAccountUuid => _activeAccountUuid;

  /// The account the route's row and metadata came from.
  String? get receiptArgsAccountUuid => _argsAccountUuid;

  String? get publicLookupText => _publicLookupText;

  /// Whether the shown row's detail is still loading with no cached detail to
  /// show meanwhile.
  bool get receiptDetailsLoading =>
      _detailsPending && matchingReceiptDetailFor(_transaction) == null;

  /// Called once after the first frame, before the first load.
  @protected
  void onReceiptFirstFrame() {}

  /// Clears what the screen keeps of the previous account's receipt; called
  /// inside the `setState` of a load whose account changed.
  @protected
  void onReceiptAccountChanged() {}

  @override
  void initState() {
    super.initState();
    final args = widget.receiptArgs;
    _transaction = args.initialTransaction;
    _detail = args.initialDetail;
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _argsAccountUuid = args.sourceAccountUuid ?? _activeAccountUuid;
    if (_argsAccountUuid != _activeAccountUuid) {
      _transaction = null;
      _detail = null;
    }
    _isLoading = _transaction == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      onReceiptFirstFrame();
      unawaited(loadReceipt());
    });
  }

  @override
  void dispose() {
    _transparentDetailsPoll?.cancel();
    super.dispose();
  }

  /// Reloads the receipt when the account changes, when the shown row changes
  /// among the recent transactions, when sync completes again, and when a
  /// follow-up finishes after completion. Call at the top of `build`.
  void listenForReceiptRefresh() {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) unawaited(loadReceipt());
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      // Enhancement can change older rows outside the ten recent transactions,
      // and the deferred account refresh and ephemeral address checks report
      // completion again after scanning already completed.
      final syncCompleted =
          next.value?.isSyncComplete == true &&
          (previous?.value?.isSyncComplete != true ||
              previous?.value?.lastSyncCompletedAt !=
                  next.value?.lastSyncCompletedAt);
      if (_recentTxSignature(previous?.value) !=
              _recentTxSignature(next.value) ||
          syncCompleted) {
        unawaited(loadReceipt());
      }
    });
    // So can recovery and detail follow-ups that finish after completion.
    ref.listen<int>(syncFollowupProvider, (_, _) {
      unawaited(loadReceipt());
    });
  }

  bool _loadIsCurrent(int generation, String? accountUuid) =>
      mounted &&
      generation == _loadGeneration &&
      accountUuid == ref.read(accountProvider).value?.activeAccountUuid;

  /// Loads the shown row's Activity rows and detail, and publishes each as it
  /// arrives. A receipt opened from a row already shows that row; while it
  /// has no detail for it, the detail is read at once, alongside the row read
  /// rather than after it, so the skeleton waits on that one read. A
  /// provisional row's detail is shown only once the row read confirms its
  /// role.
  Future<void> loadReceipt() async {
    final generation = ++_loadGeneration;
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final accountChanged = accountUuid != _activeAccountUuid;
    _activeAccountUuid = accountUuid;
    setState(() {
      // A refresh while a public load runs keeps its state; the load
      // refreshes again when it finishes.
      if (!_publicLookupRunning || accountChanged) _publicLookupText = null;
      if (accountChanged) {
        _transaction = null;
        _detail = null;
        onReceiptAccountChanged();
      }
      _isLoading = _transaction == null;
      _detailsPending = true;
      _error = null;
    });
    if (accountUuid == null) {
      setState(() {
        _isLoading = false;
        _detailsPending = false;
        _error = 'No active account.';
      });
      return;
    }

    // The row already shown, from the tapped row or the last load.
    final shown = _transaction;
    Future<rust_sync.TransactionDetail?>? shownDetail;
    if (shown != null && matchingReceiptDetailFor(shown) == null) {
      final read = _readShownDetail(accountUuid, shown);
      shownDetail = read;
      // A provisional row's role can still change with the row read
      // ([_findTransaction]); its detail would then show for a moment and
      // give way to the new role's skeleton. It waits for the row read.
      if (!shown.provisional) {
        unawaited(_publishShownDetail(read, shown, generation, accountUuid));
      }
    }
    try {
      final txs = await _loadHistory(accountUuid);
      if (!_loadIsCurrent(generation, accountUuid)) return;
      final tx = _findTransaction(txs);
      if (tx == null) {
        setState(() {
          _error = _transaction == null
              ? 'Transaction could not be loaded.'
              : 'Latest transaction status could not be refreshed.';
          _isLoading = false;
          _detailsPending = false;
        });
        return;
      }
      // The detail already asked for answers for this row unless the
      // transaction's role changed meanwhile.
      final sameRow = shown != null && _isSameRow(shown, tx);
      // Publish the status without waiting for addresses, outputs, or memo.
      // A detail that still fits the row (a receive that became mined) stays
      // shown while its new read runs: [receiptDetailsLoading] shows the
      // skeleton only when no shown detail fits.
      setState(() {
        _transaction = tx;
        _detail = matchingReceiptDetailFor(tx);
        if (!sameRow) _detailsPending = true;
        _isLoading = false;
        _error = null;
      });
      final detail = sameRow && shownDetail != null
          ? await shownDetail
          : await _loadDetail(accountUuid, tx);
      if (!_loadIsCurrent(generation, accountUuid)) return;
      setState(() {
        _detail = detail ?? _detail;
        _detailsPending = false;
      });
      _followTransparentDetails();
    } catch (e, st) {
      if (!_loadIsCurrent(generation, accountUuid)) return;
      log('TransactionReceipt: transaction load failed: $e\n$st');
      setState(() {
        _error = _transaction == null
            ? 'Transaction could not be loaded.'
            : 'Latest transaction status could not be refreshed.';
        _isLoading = false;
        _detailsPending = false;
      });
    }
  }

  /// The detail of [shown], sharing a read an earlier load started for the
  /// same row that is still running.
  Future<rust_sync.TransactionDetail?> _readShownDetail(
    String accountUuid,
    rust_sync.TransactionInfo shown,
  ) {
    final running = _earlyDetailRead;
    if (running != null &&
        running.accountUuid == accountUuid &&
        _isSameRow(running.row, shown)) {
      return running.read;
    }
    final read = _loadDetail(accountUuid, shown);
    _earlyDetailRead = (accountUuid: accountUuid, row: shown, read: read);
    unawaited(
      read.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (identical(_earlyDetailRead?.read, read)) _earlyDetailRead = null;
      }),
    );
    return read;
  }

  /// Publishes the detail read for the [shown] row as soon as it arrives,
  /// while the row read is still running: it ends the skeleton. The full load
  /// publishes it again, and reports a failure.
  Future<void> _publishShownDetail(
    Future<rust_sync.TransactionDetail?> pending,
    rust_sync.TransactionInfo shown,
    int generation,
    String accountUuid,
  ) async {
    final rust_sync.TransactionDetail? detail;
    try {
      detail = await pending;
    } catch (_) {
      return;
    }
    final current = _transaction;
    if (!_loadIsCurrent(generation, accountUuid) ||
        !_detailsPending ||
        current == null ||
        !_isSameRow(shown, current)) {
      return;
    }
    setState(() {
      _detail = detail ?? _detail;
      _detailsPending = false;
    });
  }

  /// Whether a detail read for [a] answers for [b]: the same transaction in
  /// the same Activity role.
  bool _isSameRow(rust_sync.TransactionInfo a, rust_sync.TransactionInfo b) =>
      receiptTxidsMatch(a.txidHex, b.txidHex) && a.txKind == b.txKind;

  /// The receipt transaction's Activity rows. A Gift Card's txid may be in
  /// either byte order, so its rows are looked up in the other order too.
  Future<List<rust_sync.TransactionInfo>> _loadHistory(
    String accountUuid,
  ) async {
    final txidHex = widget.receiptArgs.txidHex;
    final rows = await _loadRows(accountUuid, txidHex);
    if (rows.isNotEmpty || widget.receiptArgs.giftCard == null) return rows;
    final otherOrder = paymentLinkTxidInOtherByteOrder(txidHex);
    return otherOrder == null ? rows : _loadRows(accountUuid, otherOrder);
  }

  Future<List<rust_sync.TransactionInfo>> _loadRows(
    String accountUuid,
    String txidHex,
  ) async {
    final loader = widget.historyLoader;
    if (loader != null) return loader(accountUuid, txidHex);
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    return rust_sync.getTransactionRows(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      txidHex: txidHex,
    );
  }

  Future<rust_sync.TransactionDetail?> _loadDetail(
    String accountUuid,
    rust_sync.TransactionInfo transaction,
  ) async {
    final loader = widget.detailLoader;
    if (loader != null) return loader(accountUuid, transaction);
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    return rust_sync.getTransactionDetail(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      txidHex: transaction.txidHex,
      txKind: transaction.txKind,
    );
  }

  /// The last detail read when it belongs to [tx], the same transaction and
  /// Activity role; `null` otherwise.
  rust_sync.TransactionDetail? matchingReceiptDetailFor(
    rust_sync.TransactionInfo? tx,
  ) {
    final detail = _detail;
    if (tx == null ||
        detail == null ||
        !receiptTxidsMatch(detail.txidHex, tx.txidHex) ||
        !_txKindMatches(detail.txKind, tx.txKind)) {
      return null;
    }
    return detail;
  }

  /// While the shown transaction's transparent details may still arrive,
  /// asks the next sync to look them up first (once) and re-reads the detail
  /// until they do.
  void _followTransparentDetails() {
    final detail = matchingReceiptDetailFor(_transaction);
    if (!transparentDetailsAwaited(
      detail,
      privateQueriesEnabled: ref.read(enhancePirProvider),
    )) {
      _transparentDetailsPoll?.cancel();
      _transparentDetailsPoll = null;
      return;
    }
    if (!_transparentDetailsPrioritized) {
      _transparentDetailsPrioritized = true;
      unawaited(_prioritizeTransparentDetails(detail!.txidHex));
    }
    _transparentDetailsPoll ??= Timer.periodic(
      kTransparentDetailsPollInterval,
      (_) => unawaited(_pollTransparentDetails()),
    );
  }

  Future<void> _prioritizeTransparentDetails(String txidHex) async {
    try {
      final prioritizer = widget.transparentDetailsPrioritizer;
      if (prioritizer != null) return await prioritizer(txidHex);
      rust_sync.prioritizeTransparentDetails(
        dbPath: await getWalletDbPath(),
        txidHex: txidHex,
      );
    } catch (e) {
      log('TransactionReceipt: prioritize failed: $e');
    }
  }

  Future<void> _pollTransparentDetails() async {
    // Full receipt loads supersede polls through the same generation guard.
    // Do not start a second read while either refresh is still running.
    if (_detailsPending || _transparentDetailsPollInFlight) return;
    final generation = _loadGeneration;
    final tx = _transaction;
    final accountUuid = _activeAccountUuid;
    if (tx == null || accountUuid == null) return;
    _transparentDetailsPollInFlight = true;
    try {
      final detail = await _loadDetail(accountUuid, tx);
      if (!_loadIsCurrent(generation, accountUuid) || detail == null) {
        return;
      }
      setState(() => _detail = detail);
      _followTransparentDetails();
    } catch (e) {
      log('TransactionReceipt: transparent details refresh failed: $e');
    } finally {
      _transparentDetailsPollInFlight = false;
    }
  }

  /// Loads [tx]'s full details from the server once the user confirms, then
  /// refreshes the receipt. Nothing here runs without that confirmation, and a
  /// refresh while it runs neither drops its result nor offers it again.
  Future<void> runPublicLookup(rust_sync.TransactionInfo tx) async {
    // One load at a time: a tap while one runs asks nothing.
    if (_publicLookupRunning) return;
    _publicLookupRunning = true;
    final accountUuid = _activeAccountUuid;
    var loaded = false;
    try {
      if (!await widget.publicLookupConfirmation(context) || !mounted) return;
      setState(() => _publicLookupText = kLoadDetailsPubliclyLoadingText);
      final lookup = widget.transparentDetailsPublicLookup;
      if (lookup != null) {
        await lookup(tx);
      } else {
        await loadTransactionDetailsPublicly(
          ref.read,
          accountUuid: accountUuid,
          txidHex: tx.txidHex,
        );
      }
      loaded = true;
    } catch (e) {
      log('TransactionReceipt: public details lookup failed');
      if (mounted && _activeAccountUuid == accountUuid) {
        setState(() => _publicLookupText = kLoadDetailsPubliclyFailedText);
      }
    } finally {
      _publicLookupRunning = false;
    }
    // A full refresh supersedes any read that started before the store.
    if (loaded && mounted && _activeAccountUuid == accountUuid) {
      await loadReceipt();
    }
  }

  /// The Activity role the receipt shows: the loaded row's, else the route's.
  String? get _shownTxKind =>
      _transaction?.txKind ??
      widget.receiptArgs.initialTransaction?.txKind ??
      widget.receiptArgs.txKind;

  /// The row of the receipt's transaction in its shown role. A provisional
  /// row whose role changed follows its successor, when the transaction has a
  /// single row.
  rust_sync.TransactionInfo? _findTransaction(
    Iterable<rust_sync.TransactionInfo> transactions,
  ) {
    final txidHex = widget.receiptArgs.txidHex;
    final txKind = _shownTxKind;
    if (txKind == null) {
      for (final tx in transactions) {
        if (receiptTxidsMatch(txidHex, tx.txidHex)) return tx;
      }
      return null;
    }
    for (final tx in transactions) {
      if (receiptTxidsMatch(txidHex, tx.txidHex) &&
          _txKindMatches(txKind, tx.txKind)) {
        return tx;
      }
    }
    final shown = _transaction ?? widget.receiptArgs.initialTransaction;
    if (shown?.provisional ?? false) {
      return provisionalRoleSuccessor(
        transactions,
        (other) => receiptTxidsMatch(txidHex, other),
      );
    }
    return null;
  }

  /// What a refresh compares of the shown row among the recent transactions.
  String _recentTxSignature(SyncState? sync) {
    final txKind = _shownTxKind;
    for (final tx in sync?.recentTransactions ?? const []) {
      if (receiptTxidsMatch(widget.receiptArgs.txidHex, tx.txidHex) &&
          (txKind == null || _txKindMatches(txKind, tx.txKind))) {
        return [
          tx.txidHex,
          tx.minedHeight,
          tx.expiredUnmined,
          tx.txKind,
          tx.displayAmount,
          tx.fee,
          tx.activityPool,
          transactionCompletenessSignature(tx),
        ].join(':');
      }
    }
    return '';
  }

  /// Whether two txids name the receipt's transaction. A Gift Card's may be
  /// in either byte order.
  bool receiptTxidsMatch(String first, String second) {
    if (widget.receiptArgs.giftCard != null) {
      return paymentLinkTxidsMatch(first, second);
    }
    return first.toLowerCase() == second.toLowerCase();
  }

  bool _txKindMatches(String expected, String actual) {
    if (expected == actual) return true;
    return (expected == 'receiving' && actual == 'received') ||
        (expected == 'received' && actual == 'receiving');
  }
}
