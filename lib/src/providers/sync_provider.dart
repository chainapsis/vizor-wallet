import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, protected;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../core/config/rpc_endpoint_config.dart';
import '../core/layout/app_process_work_policy.dart';
import '../core/lifecycle/app_shutdown_signal.dart';
import '../core/storage/wallet_paths.dart';
import '../core/storage/wallet_balance_cache.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/one_time_ivk.dart' as rust_swap;
import 'account_provider.dart';
import 'public_details_loads_provider.dart';
import 'pending_activity_evidence_provider.dart';
import 'enhance_pir_provider.dart';
import 'app_security_provider.dart';
import 'chain_upgrade_provider.dart';
import 'network_privacy_provider.dart'
    show excludeTransparentRecoveryCompanionsFromBackup;
import 'rpc_endpoint_failover_provider.dart';
import 'sync_failure.dart';
import 'wallet_balance_cache_provider.dart';

const kSyncPhasePreflight = 'preflight';
const kSyncPhaseSetup = 'setup';
const kSyncPhaseActiveUtxo = 'active_utxo';
const kSyncPhaseChainPrepare = 'chain_prepare';

bool isSyncPreparationPhase(String phase) =>
    phase == kSyncPhasePreflight ||
    phase == kSyncPhaseSetup ||
    phase == kSyncPhaseActiveUtxo ||
    phase == kSyncPhaseChainPrepare;

bool shouldPauseSyncForPrivateStatusCoverage({
  required SyncFailure? failure,
  required bool privateQueriesEnabled,
}) =>
    privateQueriesEnabled &&
    failure?.kind == SyncFailureKind.privateStatusCoverage;

/// Authoritative progress of additional scan work after the main queue drains.
class SyncCheckingProgress {
  const SyncCheckingProgress({
    required this.cycle,
    required this.percentage,
    required this.displayTargetPercentage,
  });

  final int cycle;
  final double percentage;
  final double displayTargetPercentage;
}

class SyncProgressEvent {
  final int scannedHeight;
  final int chainTipHeight;
  final double percentage;
  final double displayTargetPercentage;
  final int displayTargetBlocks;
  final SyncCheckingProgress? checking;

  /// Wallet-wide pending scan work. Null until Rust enumerates this attempt's
  /// queue; zero means the queue is known to be empty.
  final int? remainingScanBlocks;

  /// Inclusive start of the earliest pending range, regardless of priority.
  /// Null when the queue is unknown or empty.
  final int? pendingScanStartHeight;
  final bool isSyncing;
  final bool isComplete;
  final bool hasNewTx;
  final int phaseCompletedUnits;
  final int phaseTotalUnits;

  /// Current sync phase from Rust, including preparation phases.
  final String phase;

  const SyncProgressEvent({
    required this.scannedHeight,
    required this.chainTipHeight,
    required this.percentage,
    required this.displayTargetPercentage,
    required this.displayTargetBlocks,
    this.checking,
    this.remainingScanBlocks,
    this.pendingScanStartHeight,
    required this.isSyncing,
    required this.isComplete,
    required this.hasNewTx,
    this.phaseCompletedUnits = 0,
    this.phaseTotalUnits = 0,
    this.phase = '',
  });
}

enum SpendableBalanceFreshness { authoritative, lastCompletedSync }

class SyncState {
  /// Account UUID that owns the balance, shield status, and recent transaction
  /// fields below. Sync progress itself is wallet-wide.
  final String? accountUuid;

  /// True after balance fields have been loaded for [accountUuid].
  final bool hasBalanceData;

  /// Previous accepted balance restored from disk; its display fields carry
  /// amounts, while spendable pool fields remain empty until a live read.
  final bool hasCachedBalance;
  bool get hasDisplayBalance => hasBalanceData || hasCachedBalance;

  /// An actual initial scan keeps its importing presentation. A cache miss
  /// before scan work is known only leaves the balance card unloaded.
  bool get isImportingAccount =>
      !hasDisplayBalance && (remainingScanBlocks ?? 0) > 0 && failure == null;

  /// True after recent transaction history has been loaded for [accountUuid].
  final bool hasRecentTransactionsData;
  final bool hasRecentTransactionsError;

  /// True only after both balance and history have been loaded for
  /// [accountUuid]. Consumers requiring both use this; Home balance and activity
  /// surfaces use their independent availability flags.
  bool get hasAccountScopedData => hasBalanceData && hasRecentTransactionsData;
  final bool isSyncing;
  final bool isBackgroundMode;

  /// True only after bootstrap confirms a fully scanned wallet or the current
  /// sync run emits its successful completion event. Unlike height equality,
  /// this cannot be set by the final non-complete scan progress event.
  final bool isSyncComplete;
  bool get isChecking => checking != null && !isSyncComplete;

  final double percentage;
  final double displayTargetPercentage;
  final int displayTargetBlocks;
  final SyncCheckingProgress? checking;

  /// Wallet-wide pending scan work. Null until Rust enumerates this attempt's
  /// queue; zero means the queue is known to be empty.
  final int? remainingScanBlocks;

  /// Inclusive start of the earliest pending range, regardless of priority.
  /// Null when the queue is unknown or empty.
  final int? pendingScanStartHeight;
  final int phaseCompletedUnits;
  final int phaseTotalUnits;
  final int scannedHeight;
  final int chainTipHeight;
  final BigInt transparentBalance;
  final BigInt saplingBalance;
  final BigInt orchardBalance;
  final BigInt ironwoodBalance;
  final BigInt orchardLockedBalance;
  final BigInt transparentPendingBalance;

  /// Transparent funds a pending spend holds. Like the other transparent
  /// amounts, it is zero without current authority, and part of
  /// [totalBalance] only with it.
  final BigInt transparentLockedBalance;

  /// Whether the transparent balances are current. When they are not, they
  /// are zero because nothing is spendable, and [transparentLastKnownBalance]
  /// holds the informational prior amount, if any.
  final rust_sync.TransparentBalanceAuthority transparentAuthority;

  /// Prior transparent total, present only when [transparentAuthority] is
  /// `lastKnown` or `stopped`. It never authorizes a spend.
  final BigInt? transparentLastKnownBalance;

  /// Why private recovery stopped, present only when [transparentAuthority]
  /// is `stopped`.
  final rust_sync.TransparentStopReason? transparentStop;

  /// Whether the wallet durably requires private transparent authority. A
  /// current amount then lasts only while the private ledger covers the chain
  /// tip, so it is not carried into a new sync as current.
  final bool transparentPrivate;
  final BigInt saplingPendingBalance;
  final BigInt orchardPendingBalance;
  final BigInt ironwoodPendingBalance;
  final bool canShieldTransparentBalance;
  final BigInt shieldTransparentFee;
  final BigInt shieldTransparentAmount;

  /// Spendable shielded balance. Use for "available to send".
  final BigInt spendableBalance;

  /// Stable value shown while a previously-complete wallet catches up to a
  /// newly-polled chain tip. This never includes value that was pending in the
  /// last completed snapshot.
  final BigInt displaySpendableBalance;

  /// Stable Ironwood spendable value shown while a previously-complete wallet
  /// catches up. Active migration surfaces must use this instead of the
  /// aggregate display balance so Orchard funds are never presented as
  /// migration-sendable.
  final BigInt displayIronwoodBalance;

  /// Stable pending Ironwood value used by migration holdings surfaces while
  /// an incremental sync is reconciling pool balances.
  final BigInt displayIronwoodPendingBalance;

  /// Stable Orchard spendable and pending values used by migration progress
  /// surfaces while an incremental sync reconciles pool balances.
  final BigInt displayOrchardBalance;
  final BigInt displayOrchardPendingBalance;
  final BigInt displayOrchardLockedBalance;

  /// Stable Orchard holdings shown by migration surfaces.
  BigInt get displayOrchardHoldingsBalance =>
      displayOrchardBalance +
      displayOrchardPendingBalance +
      displayOrchardLockedBalance;

  /// Stable total-holdings value for account-level balance surfaces.
  final BigInt displayTotalBalance;

  /// Stable shielded holdings, including pending value, for Home while an
  /// incremental sync is reconciling individual pool balances.
  final BigInt displayShieldedBalance;

  /// Whether [displaySpendableBalance] is the current Rust value or the last
  /// completed sync snapshot. Rust remains authoritative for proposals.
  final SpendableBalanceFreshness displaySpendableFreshness;

  /// Sum of spendable + locked + pending balances across all pools.
  /// Use for "total holdings".
  final BigInt totalBalance;

  /// Structured sync failure used by UI to choose copy and recovery action.
  final SyncFailure? failure;

  /// Raw sync error retained for compatibility with existing failure checks.
  final String? error;
  final List<rust_sync.TransactionInfo> recentTransactions;
  final DateTime? lastSyncStartedAt;
  final DateTime? lastSyncCompletedAt;
  final DateTime? lastSyncFailedAt;

  /// Current preparation, download, or scan phase. The Sidebar keeps its
  /// existing percentage copy and uses this only to estimate display progress.
  final String phase;

  /// Amount waiting for confirmations (e.g. change from a recently sent tx).
  BigInt get pendingBalance =>
      transparentPendingBalance +
      saplingPendingBalance +
      orchardPendingBalance +
      ironwoodPendingBalance;

  bool get isSyncedToTip =>
      isSyncComplete &&
      failure == null &&
      error == null &&
      !isSyncing &&
      !isBackgroundMode &&
      chainTipHeight > 0 &&
      scannedHeight >= chainTipHeight;

  bool get isUsingCompletedSpendableSnapshot =>
      displaySpendableFreshness == SpendableBalanceFreshness.lastCompletedSync;

  /// Whether this state's spendable balance may end a check as "not enough".
  ///
  /// Read on an *account-scoped* state ([scopedToAccount]): the wallet-wide
  /// sync fields survive [withoutAccountScopedData], so a state carrying no
  /// balance for the account still reports `isSyncedToTip` with a zero
  /// spendable. [hasBalanceData] is what separates "scanned to the tip and
  /// this is the balance" from "scanned to the tip and this account's balance
  /// was never fetched" — without it the predicate fails open on a zero, which
  /// is the VZR-42 shape (a shortfall announced against a balance nobody read).
  bool get hasSettledSpendableBalance =>
      hasBalanceData && isSyncedToTip && !isUsingCompletedSpendableSnapshot;

  static bool shouldPreserveCompletedSpendable(SyncState? previous) {
    if (previous?.isUsingCompletedSpendableSnapshot ?? false) return true;
    return (previous?.hasBalanceData ?? false) &&
        (previous?.isSyncComplete ?? false) &&
        (previous?.displaySpendableFreshness ??
                SpendableBalanceFreshness.authoritative) ==
            SpendableBalanceFreshness.authoritative &&
        (previous?.chainTipHeight ?? 0) > 0 &&
        (previous?.scannedHeight ?? 0) >= (previous?.chainTipHeight ?? 0);
  }

  static ({BigInt balance, SpendableBalanceFreshness freshness})
  resolveSpendableDisplay({
    required SyncState? previous,
    required BigInt authoritativeSpendable,
    required bool hasAuthoritativeBalance,
    required bool syncComplete,
    bool releaseSnapshotOnAuthoritativeBalance = false,
  }) {
    // Persisted and in-memory snapshots share the same release conditions.
    // A live read during scanning updates actual balances, not this display.
    if (previous?.isUsingCompletedSpendableSnapshot ?? false) {
      final canReleaseSnapshot =
          hasAuthoritativeBalance &&
          (syncComplete || releaseSnapshotOnAuthoritativeBalance);
      if (!canReleaseSnapshot) {
        return (
          balance: previous!.displaySpendableBalance,
          freshness: SpendableBalanceFreshness.lastCompletedSync,
        );
      }
    }

    return (
      balance: authoritativeSpendable,
      freshness: SpendableBalanceFreshness.authoritative,
    );
  }

  static ({BigInt balance, SpendableBalanceFreshness freshness})
  preserveSpendableDisplay(SyncState? previous) {
    return (
      balance:
          previous?.displaySpendableBalance ??
          previous?.spendableBalance ??
          BigInt.zero,
      freshness:
          previous?.displaySpendableFreshness ??
          SpendableBalanceFreshness.authoritative,
    );
  }

  static bool shouldClearUnavailableRestoredSnapshot({
    required SyncState? previous,
    required bool hasAuthoritativeBalance,
    required bool clearRestoredSnapshotIfUnavailable,
  }) {
    return clearRestoredSnapshotIfUnavailable &&
        !(previous?.hasCachedBalance ?? false) &&
        !hasAuthoritativeBalance &&
        (previous?.isUsingCompletedSpendableSnapshot ?? false);
  }

  SyncState withCachedBalance(CachedWalletBalance cached) {
    final balance = cached.balance;
    return copyWith(
      hasCachedBalance: true,
      displaySpendableFreshness: SpendableBalanceFreshness.lastCompletedSync,
      displaySpendableBalance: balance.spendable,
      displayIronwoodBalance: balance.ironwood,
      displayIronwoodPendingBalance: balance.ironwoodPending,
      displayOrchardBalance: balance.orchard,
      displayOrchardPendingBalance: balance.orchardPending,
      displayOrchardLockedBalance: balance.orchardLocked,
      displayShieldedBalance:
          balance.sapling +
          balance.orchard +
          balance.ironwood +
          balance.saplingPending +
          balance.orchardPending +
          balance.ironwoodPending,
      displayTotalBalance: balance.total,
      // A persisted transparent amount never restores current authority.
      transparentAuthority: balance.transparentStop != null
          ? rust_sync.TransparentBalanceAuthority.stopped
          : rust_sync.TransparentBalanceAuthority.lastKnown,
      transparentLastKnownBalance:
          balance.transparentAuthority ==
              rust_sync.TransparentBalanceAuthority.current
          ? balance.transparent +
                balance.transparentPending +
                balance.transparentLocked
          : balance.transparentLastKnown,
      transparentStop: balance.transparentStop,
      transparentPrivate: balance.transparentPrivate,
    );
  }

  SyncState withSyncActivityStopped() {
    return copyWith(isSyncing: false, isBackgroundMode: false, phase: '');
  }

  /// Merges account data fetched by an older progress handler without
  /// replacing newer wallet-wide progress metadata.
  SyncState withFetchedAccountData({
    rust_sync.WalletBalance? balance,
    List<rust_sync.TransactionInfo>? fetchedRecentTransactions,
    bool? canShieldTransparentBalance,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
    required bool syncComplete,
    bool releaseSnapshotOnAuthoritativeBalance = false,
  }) {
    assert(
      balance == null ||
          balance.availability == rust_sync.WalletBalanceAvailability.available,
    );
    final hasAuthoritativeBalance = balance != null;
    final nextSpendableBalance = balance?.spendable ?? spendableBalance;
    final spendableDisplay = resolveSpendableDisplay(
      previous: this,
      authoritativeSpendable: nextSpendableBalance,
      hasAuthoritativeBalance: hasAuthoritativeBalance,
      syncComplete: syncComplete,
      releaseSnapshotOnAuthoritativeBalance:
          releaseSnapshotOnAuthoritativeBalance,
    );
    final preservePoolDisplay =
        spendableDisplay.freshness ==
        SpendableBalanceFreshness.lastCompletedSync;

    return copyWith(
      hasBalanceData: hasAuthoritativeBalance || hasBalanceData,
      hasCachedBalance: !hasAuthoritativeBalance && hasCachedBalance,
      hasRecentTransactionsData:
          fetchedRecentTransactions != null || hasRecentTransactionsData,
      hasRecentTransactionsError:
          fetchedRecentTransactions == null && hasRecentTransactionsError,
      transparentBalance: balance?.transparent,
      saplingBalance: balance?.sapling,
      orchardBalance: balance?.orchard,
      ironwoodBalance: balance?.ironwood,
      orchardLockedBalance: balance?.orchardLocked,
      transparentPendingBalance: balance?.transparentPending,
      transparentLockedBalance: balance?.transparentLocked,
      transparentAuthority: balance?.transparentAuthority,
      transparentLastKnownBalance: balance?.transparentLastKnown,
      transparentStop: balance?.transparentStop,
      transparentPrivate: balance?.transparentPrivate,
      saplingPendingBalance: balance?.saplingPending,
      orchardPendingBalance: balance?.orchardPending,
      ironwoodPendingBalance: balance?.ironwoodPending,
      canShieldTransparentBalance: hasAuthoritativeBalance
          ? canShieldTransparentBalance ?? this.canShieldTransparentBalance
          : this.canShieldTransparentBalance,
      shieldTransparentFee: hasAuthoritativeBalance
          ? shieldTransparentFee ?? this.shieldTransparentFee
          : this.shieldTransparentFee,
      shieldTransparentAmount: hasAuthoritativeBalance
          ? shieldTransparentAmount ?? this.shieldTransparentAmount
          : this.shieldTransparentAmount,
      spendableBalance: nextSpendableBalance,
      displaySpendableBalance: spendableDisplay.balance,
      displayIronwoodBalance: preservePoolDisplay
          ? displayIronwoodBalance
          : balance?.ironwood,
      displayIronwoodPendingBalance: preservePoolDisplay
          ? displayIronwoodPendingBalance
          : balance?.ironwoodPending,
      displayOrchardBalance: preservePoolDisplay
          ? displayOrchardBalance
          : balance?.orchard,
      displayOrchardPendingBalance: preservePoolDisplay
          ? displayOrchardPendingBalance
          : balance?.orchardPending,
      displayOrchardLockedBalance: preservePoolDisplay
          ? displayOrchardLockedBalance
          : balance?.orchardLocked,
      displaySpendableFreshness: spendableDisplay.freshness,
      totalBalance: balance?.total,
      displayTotalBalance: preservePoolDisplay
          ? displayTotalBalance
          : balance?.total,
      displayShieldedBalance: preservePoolDisplay
          ? displayShieldedBalance
          : balance == null
          ? null
          : balance.sapling +
                balance.orchard +
                balance.ironwood +
                balance.saplingPending +
                balance.orchardPending +
                balance.ironwoodPending,
      recentTransactions: fetchedRecentTransactions,
    );
  }

  SyncState({
    this.accountUuid,
    bool hasAccountScopedData = false,
    bool? hasBalanceData,
    this.hasCachedBalance = false,
    bool? hasRecentTransactionsData,
    this.hasRecentTransactionsError = false,
    this.isSyncing = false,
    this.isBackgroundMode = false,
    this.isSyncComplete = false,
    this.percentage = 0,
    double? displayTargetPercentage,
    this.displayTargetBlocks = 0,
    this.checking,
    this.remainingScanBlocks,
    this.pendingScanStartHeight,
    this.phaseCompletedUnits = 0,
    this.phaseTotalUnits = 0,
    this.scannedHeight = 0,
    this.chainTipHeight = 0,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? ironwoodBalance,
    BigInt? orchardLockedBalance,
    BigInt? transparentPendingBalance,
    BigInt? transparentLockedBalance,
    rust_sync.TransparentBalanceAuthority? transparentAuthority,
    this.transparentLastKnownBalance,
    this.transparentStop,
    bool? transparentPrivate,
    BigInt? saplingPendingBalance,
    BigInt? orchardPendingBalance,
    BigInt? ironwoodPendingBalance,
    this.canShieldTransparentBalance = false,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
    BigInt? spendableBalance,
    BigInt? displaySpendableBalance,
    BigInt? displayIronwoodBalance,
    BigInt? displayIronwoodPendingBalance,
    BigInt? displayOrchardBalance,
    BigInt? displayOrchardPendingBalance,
    BigInt? displayOrchardLockedBalance,
    this.displaySpendableFreshness = SpendableBalanceFreshness.authoritative,
    BigInt? totalBalance,
    BigInt? displayTotalBalance,
    BigInt? displayShieldedBalance,
    this.failure,
    this.error,
    this.recentTransactions = const [],
    this.lastSyncStartedAt,
    this.lastSyncCompletedAt,
    this.lastSyncFailedAt,
    this.phase = '',
  }) : hasBalanceData = hasBalanceData ?? hasAccountScopedData,
       hasRecentTransactionsData =
           hasRecentTransactionsData ?? hasAccountScopedData,
       displayTargetPercentage = displayTargetPercentage ?? percentage,
       transparentBalance = transparentBalance ?? BigInt.zero,
       saplingBalance = saplingBalance ?? BigInt.zero,
       orchardBalance = orchardBalance ?? BigInt.zero,
       ironwoodBalance = ironwoodBalance ?? BigInt.zero,
       orchardLockedBalance = orchardLockedBalance ?? BigInt.zero,
       transparentPendingBalance = transparentPendingBalance ?? BigInt.zero,
       transparentLockedBalance = transparentLockedBalance ?? BigInt.zero,
       transparentAuthority =
           transparentAuthority ??
           rust_sync.TransparentBalanceAuthority.current,
       transparentPrivate = transparentPrivate ?? false,
       saplingPendingBalance = saplingPendingBalance ?? BigInt.zero,
       orchardPendingBalance = orchardPendingBalance ?? BigInt.zero,
       ironwoodPendingBalance = ironwoodPendingBalance ?? BigInt.zero,
       shieldTransparentFee = shieldTransparentFee ?? BigInt.zero,
       shieldTransparentAmount = shieldTransparentAmount ?? BigInt.zero,
       spendableBalance = spendableBalance ?? BigInt.zero,
       displaySpendableBalance =
           displaySpendableBalance ?? spendableBalance ?? BigInt.zero,
       displayIronwoodBalance =
           displayIronwoodBalance ?? ironwoodBalance ?? BigInt.zero,
       displayIronwoodPendingBalance =
           displayIronwoodPendingBalance ??
           ironwoodPendingBalance ??
           BigInt.zero,
       displayOrchardBalance =
           displayOrchardBalance ?? orchardBalance ?? BigInt.zero,
       displayOrchardPendingBalance =
           displayOrchardPendingBalance ?? orchardPendingBalance ?? BigInt.zero,
       displayOrchardLockedBalance =
           displayOrchardLockedBalance ?? orchardLockedBalance ?? BigInt.zero,
       displayTotalBalance = displayTotalBalance ?? totalBalance ?? BigInt.zero,
       displayShieldedBalance =
           displayShieldedBalance ??
           (saplingBalance ?? BigInt.zero) +
               (orchardBalance ?? BigInt.zero) +
               (ironwoodBalance ?? BigInt.zero) +
               (saplingPendingBalance ?? BigInt.zero) +
               (orchardPendingBalance ?? BigInt.zero) +
               (ironwoodPendingBalance ?? BigInt.zero),
       totalBalance = totalBalance ?? BigInt.zero;

  SyncState copyWith({
    String? accountUuid,
    bool? hasAccountScopedData,
    bool? hasBalanceData,
    bool? hasCachedBalance,
    bool? hasRecentTransactionsData,
    bool? hasRecentTransactionsError,
    bool? isSyncing,
    bool? isBackgroundMode,
    bool? isSyncComplete,
    double? percentage,
    double? displayTargetPercentage,
    int? displayTargetBlocks,
    SyncCheckingProgress? checking,
    bool clearChecking = false,
    int? remainingScanBlocks,
    int? pendingScanStartHeight,
    bool clearPendingScanWork = false,
    int? phaseCompletedUnits,
    int? phaseTotalUnits,
    int? scannedHeight,
    int? chainTipHeight,
    BigInt? transparentBalance,
    BigInt? saplingBalance,
    BigInt? orchardBalance,
    BigInt? ironwoodBalance,
    BigInt? orchardLockedBalance,
    BigInt? transparentPendingBalance,
    BigInt? transparentLockedBalance,
    rust_sync.TransparentBalanceAuthority? transparentAuthority,
    BigInt? transparentLastKnownBalance,
    rust_sync.TransparentStopReason? transparentStop,
    bool? transparentPrivate,
    BigInt? saplingPendingBalance,
    BigInt? orchardPendingBalance,
    BigInt? ironwoodPendingBalance,
    bool? canShieldTransparentBalance,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
    BigInt? spendableBalance,
    BigInt? displaySpendableBalance,
    BigInt? displayIronwoodBalance,
    BigInt? displayIronwoodPendingBalance,
    BigInt? displayOrchardBalance,
    BigInt? displayOrchardPendingBalance,
    BigInt? displayOrchardLockedBalance,
    SpendableBalanceFreshness? displaySpendableFreshness,
    BigInt? totalBalance,
    BigInt? displayTotalBalance,
    BigInt? displayShieldedBalance,
    SyncFailure? failure,
    bool clearFailure = false,
    String? error,
    bool clearError = false,
    List<rust_sync.TransactionInfo>? recentTransactions,
    DateTime? lastSyncStartedAt,
    DateTime? lastSyncCompletedAt,
    DateTime? lastSyncFailedAt,
    String? phase,
  }) {
    return SyncState(
      accountUuid: accountUuid ?? this.accountUuid,
      hasBalanceData:
          hasBalanceData ?? hasAccountScopedData ?? this.hasBalanceData,
      hasCachedBalance: hasCachedBalance ?? this.hasCachedBalance,
      hasRecentTransactionsError:
          hasRecentTransactionsError ?? this.hasRecentTransactionsError,
      hasRecentTransactionsData:
          hasRecentTransactionsData ??
          hasAccountScopedData ??
          this.hasRecentTransactionsData,
      isSyncing: isSyncing ?? this.isSyncing,
      isBackgroundMode: isBackgroundMode ?? this.isBackgroundMode,
      isSyncComplete: isSyncComplete ?? this.isSyncComplete,
      percentage: percentage ?? this.percentage,
      displayTargetPercentage:
          displayTargetPercentage ?? this.displayTargetPercentage,
      displayTargetBlocks: displayTargetBlocks ?? this.displayTargetBlocks,
      checking: clearChecking ? null : checking ?? this.checking,
      remainingScanBlocks:
          remainingScanBlocks ??
          (clearPendingScanWork ? null : this.remainingScanBlocks),
      pendingScanStartHeight:
          pendingScanStartHeight ??
          (clearPendingScanWork ? null : this.pendingScanStartHeight),
      phaseCompletedUnits: phaseCompletedUnits ?? this.phaseCompletedUnits,
      phaseTotalUnits: phaseTotalUnits ?? this.phaseTotalUnits,
      scannedHeight: scannedHeight ?? this.scannedHeight,
      chainTipHeight: chainTipHeight ?? this.chainTipHeight,
      transparentBalance: transparentBalance ?? this.transparentBalance,
      saplingBalance: saplingBalance ?? this.saplingBalance,
      orchardBalance: orchardBalance ?? this.orchardBalance,
      ironwoodBalance: ironwoodBalance ?? this.ironwoodBalance,
      orchardLockedBalance: orchardLockedBalance ?? this.orchardLockedBalance,
      transparentPendingBalance:
          transparentPendingBalance ?? this.transparentPendingBalance,
      transparentLockedBalance:
          transparentLockedBalance ?? this.transparentLockedBalance,
      transparentAuthority: transparentAuthority ?? this.transparentAuthority,
      // The last-known amount and stop reason travel with their authority: a
      // new authority replaces them, including with none.
      transparentLastKnownBalance: transparentAuthority != null
          ? transparentLastKnownBalance
          : this.transparentLastKnownBalance,
      transparentStop: transparentAuthority != null
          ? transparentStop
          : this.transparentStop,
      transparentPrivate: transparentPrivate ?? this.transparentPrivate,
      saplingPendingBalance:
          saplingPendingBalance ?? this.saplingPendingBalance,
      orchardPendingBalance:
          orchardPendingBalance ?? this.orchardPendingBalance,
      ironwoodPendingBalance:
          ironwoodPendingBalance ?? this.ironwoodPendingBalance,
      canShieldTransparentBalance:
          canShieldTransparentBalance ?? this.canShieldTransparentBalance,
      shieldTransparentFee: shieldTransparentFee ?? this.shieldTransparentFee,
      shieldTransparentAmount:
          shieldTransparentAmount ?? this.shieldTransparentAmount,
      spendableBalance: spendableBalance ?? this.spendableBalance,
      displaySpendableBalance:
          displaySpendableBalance ?? this.displaySpendableBalance,
      displayIronwoodBalance:
          displayIronwoodBalance ?? this.displayIronwoodBalance,
      displayIronwoodPendingBalance:
          displayIronwoodPendingBalance ?? this.displayIronwoodPendingBalance,
      displayOrchardBalance:
          displayOrchardBalance ?? this.displayOrchardBalance,
      displayOrchardPendingBalance:
          displayOrchardPendingBalance ?? this.displayOrchardPendingBalance,
      displayOrchardLockedBalance:
          displayOrchardLockedBalance ?? this.displayOrchardLockedBalance,
      displaySpendableFreshness:
          displaySpendableFreshness ?? this.displaySpendableFreshness,
      totalBalance: totalBalance ?? this.totalBalance,
      displayTotalBalance: displayTotalBalance ?? this.displayTotalBalance,
      displayShieldedBalance:
          displayShieldedBalance ?? this.displayShieldedBalance,
      failure: clearFailure ? null : failure ?? this.failure,
      error: clearError ? null : error ?? this.error,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      lastSyncStartedAt: lastSyncStartedAt ?? this.lastSyncStartedAt,
      lastSyncCompletedAt: lastSyncCompletedAt ?? this.lastSyncCompletedAt,
      lastSyncFailedAt: lastSyncFailedAt ?? this.lastSyncFailedAt,
      phase: phase ?? this.phase,
    );
  }

  bool belongsToAccount(String? accountUuid) {
    return accountUuid != null && this.accountUuid == accountUuid;
  }

  bool hasDataForAccount(String? accountUuid) {
    return belongsToAccount(accountUuid) && hasAccountScopedData;
  }

  SyncState scopedToAccount(String? accountUuid) {
    if (belongsToAccount(accountUuid)) return this;
    return withoutAccountScopedData(accountUuid: accountUuid);
  }

  /// This state carried to a point where its transparent amount may be stale:
  /// a `current` amount becomes `lastKnown`, with nothing spendable, no
  /// Shield action, and no share of the totals, until a balance read reports
  /// Rust's authority again.
  /// Every path that shows a state not read from Rust just now goes through
  /// this rule; a fresh read never does.
  ///
  /// A privately read amount is current only while the private ledger covers
  /// the tip, so it goes stale when [crossesTip]: the tip actually moved
  /// since the read, at a sync start, during a sync, or for a cache. A
  /// publicly read amount goes stale when [privatePolicyMayApply]: the wallet
  /// may be private now, because Rust applied a private policy or because
  /// private queries are on.
  ///
  /// Either goes stale when [policyChanged]: Rust applied a new policy
  /// generation since the read, so the authority it reported no longer holds.
  SyncState carryingTransparentAuthority({
    required bool privatePolicyMayApply,
    required bool crossesTip,
    bool policyChanged = false,
  }) {
    final stale =
        transparentAuthority == rust_sync.TransparentBalanceAuthority.current &&
        (policyChanged ||
            (transparentPrivate ? crossesTip : privatePolicyMayApply));
    if (!stale) return this;
    // The totals drop the demoted amount too, as a read without transparent
    // authority would report them.
    final demoted =
        transparentBalance +
        transparentPendingBalance +
        transparentLockedBalance;
    final remaining = totalBalance - demoted;
    final total = remaining < BigInt.zero ? BigInt.zero : remaining;
    return copyWith(
      transparentBalance: BigInt.zero,
      transparentPendingBalance: BigInt.zero,
      transparentLockedBalance: BigInt.zero,
      transparentAuthority: rust_sync.TransparentBalanceAuthority.lastKnown,
      transparentLastKnownBalance: demoted,
      canShieldTransparentBalance: false,
      totalBalance: total,
      displayTotalBalance: total,
    );
  }

  /// This state under a transparent policy Rust just applied, before any
  /// fresh read: whether the wallet reads transparent funds privately follows
  /// the policy at once, and a public policy stops no account, so a stop
  /// reason read under a private one goes with it. Amounts are left to
  /// [carryingTransparentAuthority].
  SyncState underTransparentPolicy({required bool private}) {
    final stop = private ? transparentStop : null;
    if (transparentPrivate == private && transparentStop == stop) return this;
    return copyWith(
      transparentPrivate: private,
      // The stop reason travels with its authority, which stays.
      transparentAuthority: transparentAuthority,
      transparentLastKnownBalance: transparentLastKnownBalance,
      transparentStop: stop,
    );
  }

  /// This state's account-scoped data, carrying [current]'s wallet-wide
  /// sync fields.
  ///
  /// The inverse of [withoutAccountScopedData]: that keeps the sync
  /// fields and drops the account data, this keeps the account data and
  /// takes fresh sync fields. Used when restoring a previously-seen
  /// account on switch — the balances are that account's last known
  /// values, but sync progress must stay wallet-current or the progress
  /// indicator would jump backwards to whatever it was when the account
  /// was last active.
  ///
  /// Keep the field list here in step with [withoutAccountScopedData].
  SyncState withGlobalSyncFieldsFrom(SyncState current) {
    return copyWith(
      isSyncing: current.isSyncing,
      isBackgroundMode: current.isBackgroundMode,
      isSyncComplete: current.isSyncComplete,
      percentage: current.percentage,
      displayTargetPercentage: current.displayTargetPercentage,
      displayTargetBlocks: current.displayTargetBlocks,
      checking: current.checking,
      clearChecking: current.checking == null,
      remainingScanBlocks: current.remainingScanBlocks,
      pendingScanStartHeight: current.pendingScanStartHeight,
      clearPendingScanWork: true,
      phaseCompletedUnits: current.phaseCompletedUnits,
      phaseTotalUnits: current.phaseTotalUnits,
      scannedHeight: current.scannedHeight,
      chainTipHeight: current.chainTipHeight,
      failure: current.failure,
      clearFailure: current.failure == null,
      error: current.error,
      clearError: current.error == null,
      lastSyncStartedAt: current.lastSyncStartedAt,
      lastSyncCompletedAt: current.lastSyncCompletedAt,
      lastSyncFailedAt: current.lastSyncFailedAt,
      phase: current.phase,
    );
  }

  SyncState withoutAccountScopedData({String? accountUuid}) {
    return SyncState(
      accountUuid: accountUuid,
      hasBalanceData: false,
      hasRecentTransactionsData: false,
      isSyncing: isSyncing,
      isBackgroundMode: isBackgroundMode,
      isSyncComplete: isSyncComplete,
      percentage: percentage,
      displayTargetPercentage: displayTargetPercentage,
      displayTargetBlocks: displayTargetBlocks,
      checking: checking,
      remainingScanBlocks: remainingScanBlocks,
      pendingScanStartHeight: pendingScanStartHeight,
      phaseCompletedUnits: phaseCompletedUnits,
      phaseTotalUnits: phaseTotalUnits,
      scannedHeight: scannedHeight,
      chainTipHeight: chainTipHeight,
      failure: failure,
      error: error,
      lastSyncStartedAt: lastSyncStartedAt,
      lastSyncCompletedAt: lastSyncCompletedAt,
      lastSyncFailedAt: lastSyncFailedAt,
      phase: phase,
    );
  }
}

class WalletMutationSyncPause {
  final bool hadActiveSync;
  final bool hadPolling;
  final bool hadMempoolObserver;

  /// The wallet reset epoch when this pause was taken. A reset that exits
  /// while this pause is held advances the epoch, and the snapshot above then
  /// describes a wallet that no longer exists.
  final int resetEpoch;

  const WalletMutationSyncPause({
    required this.hadActiveSync,
    required this.hadPolling,
    required this.hadMempoolObserver,
    this.resetEpoch = 0,
  });

  bool get hadWorkToPause => hadActiveSync || hadPolling || hadMempoolObserver;
}

@visibleForTesting
bool shouldStartSyncForPolledTip(
  SyncState? current,
  int latestTipHeight, {
  bool hasActiveRecovery = false,
}) {
  return hasActiveRecovery ||
      !(current?.isSyncComplete ?? false) ||
      latestTipHeight > (current?.chainTipHeight ?? 0);
}

/// Retryable recovery obligations: payload queries, rediscovery jobs, and
/// private status lookups that a Status PIR failure deferred. Suspended work
/// is not retryable and is excluded.
@visibleForTesting
int recoveryRestartUnits(rust_sync.EnhanceRecoveryStatus recovery) =>
    recovery.queries + recovery.rediscovery + recovery.status;

/// Public transparent-service deadlines have their own rate limit in Rust.
/// They must not wait behind the unrelated payload/status backoff.
@visibleForTesting
bool shouldRestartRecovery(
  rust_sync.EnhanceRecoveryStatus recovery,
  RecoveryRestartGate gate,
) =>
    recovery.transparentRetryDue ||
    gate.shouldRestart(recoveryRestartUnits(recovery));

@visibleForTesting
const kRecoveryRestartInitialBackoff = Duration(seconds: 30);
@visibleForTesting
const kRecoveryRestartMaxBackoff = Duration(minutes: 10);

/// Rate-limits sync restarts that exist only to retry private recovery.
///
/// Durable PIR obligations stay pending for as long as the work cannot
/// progress — the service has no usable snapshot, its anchor is not scanned
/// yet, or a rediscovery job cannot be reconstructed. A bare "work remains"
/// check therefore turns every 10-second poll into a full foreground sync at
/// an unchanged tip, re-running tip validation, transparent-UTXO refresh, and
/// the 100-block rediscovery cover download for work that will fail again.
///
/// The gate treats an attempt as actionable only once its deadline passes,
/// and doubles the wait after every attempt, up to a cap. When a restart
/// happens depends only on what the private services already see: the
/// schedule starts over at the base interval on a new chain tip, an app
/// resume, a settings change or a lock ([reset]), never because the
/// outstanding count moved. A count that drops because a reply was good, or
/// stays because a reply was bad, must not make the next request sooner or
/// later, or the service could tell its answers apart by the wallet's timing.
///
/// Syncs driven by a new chain tip or an incomplete previous sync are
/// unaffected: those run recovery anyway, and they coincide with the newly
/// scanned blocks that can make a stuck job resolvable.
@visibleForTesting
class RecoveryRestartGate {
  RecoveryRestartGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime? _retryAt;
  Duration _backoff = kRecoveryRestartInitialBackoff;

  /// Starts the schedule over at the base interval. Call only on events the
  /// services see anyway: a new chain tip, an app resume, a settings change
  /// or a lock.
  void reset() {
    _retryAt = null;
    _backoff = kRecoveryRestartInitialBackoff;
  }

  /// [outstanding] is the durable query + rediscovery obligation count.
  /// Suspended work is excluded by the caller: it is not retryable, so it
  /// must never schedule network work of its own. The count only decides
  /// whether there is anything to restart for; it never moves the schedule.
  bool shouldRestart(int outstanding) {
    if (outstanding <= 0) return false;
    final at = _now();
    final deadline = _retryAt;
    if (deadline != null && at.isBefore(deadline)) return false;
    if (deadline != null) _backoff = _doubledBackoff(_backoff);
    _retryAt = at.add(_backoff);
    return true;
  }

  static Duration _doubledBackoff(Duration current) {
    final doubled = current * 2;
    return doubled > kRecoveryRestartMaxBackoff
        ? kRecoveryRestartMaxBackoff
        : doubled;
  }
}

/// Native resume retires the lease and prevents late callbacks from pausing
/// managers. A stalled channel must therefore fail within the deadline.
@visibleForTesting
Future<void> waitForRecoveryQuiescence(
  Future<void> quiescence, {
  Duration timeout = const Duration(seconds: 120),
}) => quiescence.timeout(timeout);

/// Whether a restart must abort because Rust network tasks are still running.
///
/// Only a route change has to: starting Tor while a direct channel is still up
/// would leak, so that caller fails loudly and keeps the old route. A restart
/// that leaves the transport alone (endpoint change, post-broadcast refresh)
/// starts anyway — aborting there would leave the wallet with neither sync nor
/// polling for the rest of the session.
@visibleForTesting
bool shouldAbortRestartForBusyNetwork({
  required bool quiescent,
  required bool changesTransport,
}) => !quiescent && changesTransport;

@visibleForTesting
bool shouldRestartSyncForMigrationEntry({
  required bool hasAttachedSync,
  required bool activeSyncStartedInForeground,
  required int activeSyncForegroundEpoch,
  required int currentForegroundEpoch,
}) {
  return hasAttachedSync &&
      (!activeSyncStartedInForeground ||
          activeSyncForegroundEpoch != currentForegroundEpoch);
}

class SyncNotifier extends AsyncNotifier<SyncState> {
  SyncNotifier({
    Future<String> Function()? walletDbPathResolver,
    Future<String?> Function()? existingWalletDbPathResolver,
    IronwoodMigrationBackgroundLifecycle? recoveryLifecycle,
    Duration recoveryTransitionTimeout = const Duration(seconds: 120),
    Future<void> Function(String dbPath)? excludeCompanionsFromBackup,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _walletDbPathResolver = walletDbPathResolver ?? getWalletDbPath,
       _existingWalletDbPathResolver =
           existingWalletDbPathResolver ?? getExistingWalletDbPath,
       _recoveryLifecycle =
           recoveryLifecycle ?? IronwoodMigrationBackgroundLifecycle.instance,
       _recoveryTransitionTimeout = recoveryTransitionTimeout,
       _excludeCompanionsFromBackup =
           excludeCompanionsFromBackup ??
           excludeTransparentRecoveryCompanionsFromBackup;

  final IronwoodMigrationBackgroundLifecycle _recoveryLifecycle;
  final Duration _recoveryTransitionTimeout;

  /// The clock the swap recovery retry deadlines read.
  final DateTime Function() _now;

  final Future<void> Function(String dbPath) _excludeCompanionsFromBackup;

  /// Whether the wallet's transparent policy may be private now even though
  /// a carried state was read public: Rust last applied `PrivateRequired`, or
  /// private queries are on for supported mainnet.
  bool get _privatePolicyMayApply =>
      _appliedTransparentPolicy?.mode ==
          rust_sync.ApiTransparentLedgerMode.privateRequired ||
      ref.read(enhancePirProvider);

  /// The durable transparent policy Rust last reported applying, at startup
  /// or from the private queries toggle; `null` until one is reported.
  rust_sync.ApiAppliedTransparentPolicy? _appliedTransparentPolicy;

  @visibleForTesting
  rust_sync.ApiAppliedTransparentPolicy? get appliedTransparentPolicy =>
      _appliedTransparentPolicy;

  /// Adopts a policy Rust just applied, mode and generation. Whether the
  /// wallet reads transparent funds privately follows the mode at once, in
  /// the visible state and the account-switch cache, so Settings never shows
  /// the previous policy until a fresh read, which may wait for the network.
  /// A new generation also demotes every carried transparent amount right
  /// away: each was read under a policy that no longer holds. It also
  /// restarts a foreground sync, so fresh reads replace them: once the
  /// wallet mutation that applied it exits when one is in progress, as for
  /// the private queries toggle, and now otherwise. `null`, nothing applied,
  /// changes nothing.
  void adoptAppliedTransparentPolicy(
    rust_sync.ApiAppliedTransparentPolicy? applied,
  ) {
    if (applied == null) return;
    final previous = _appliedTransparentPolicy;
    _appliedTransparentPolicy = applied;
    final private =
        applied.mode == rust_sync.ApiTransparentLedgerMode.privateRequired;
    _adoptTransparentPrivacy(private);
    ref.read(walletTransparentPrivateProvider.notifier).update(private);
    if (previous != null && previous.generation == applied.generation) return;
    _demoteCarriedTransparentAuthority();
    if (_requiresUnlock || !_isInForeground) return;
    if (_walletMutationPauseCount > 0) {
      _pendingMutationRestartSync = true;
      return;
    }
    startSync();
  }

  void _adoptTransparentPrivacy(bool private) {
    for (final entry in _lastKnownByAccount.entries.toList()) {
      _lastKnownByAccount[entry.key] = entry.value.underTransparentPolicy(
        private: private,
      );
    }
    final current = state.value;
    if (current == null) return;
    final adopted = current.underTransparentPolicy(private: private);
    if (!identical(adopted, current)) state = AsyncData(adopted);
  }

  void _demoteCarriedTransparentAuthority() {
    SyncState demote(SyncState carried) => carried.carryingTransparentAuthority(
      privatePolicyMayApply: _privatePolicyMayApply,
      crossesTip: false,
      policyChanged: true,
    );
    for (final entry in _lastKnownByAccount.entries.toList()) {
      _lastKnownByAccount[entry.key] = demote(entry.value);
    }
    final current = state.value;
    if (current != null) state = AsyncData(demote(current));
  }

  /// A foreground start requested while this notifier's own sync stream
  /// still holds the Rust guard, its post-sync follow-ups included. Started
  /// once that stream ends; repeats coalesce into one.
  _QueuedSyncStart? _queuedSyncStart;

  @visibleForTesting
  ({bool forced, int? latestTipHeight})? get queuedSyncStartForTesting {
    final queued = _queuedSyncStart;
    return queued == null
        ? null
        : (forced: queued.forced, latestTipHeight: queued.latestTipHeight);
  }

  void _queueSyncStart({required bool forced, int? latestTipHeight}) {
    final previous = _queuedSyncStart;
    final tips = [?previous?.latestTipHeight, ?latestTipHeight];
    _queuedSyncStart = _QueuedSyncStart(
      // A forced request upgrades a plain one; nothing downgrades it.
      forced: forced || (previous?.forced ?? false),
      latestTipHeight: tips.isEmpty ? null : tips.reduce(math.max),
    );
    log(
      'Sync: a sync still holds the Rust guard; '
      '${forced ? 'forced ' : ''}start queued until it ends',
    );
  }

  /// Starts the request queued behind the sync whose stream just ended. A
  /// request the app can no longer run, as after it moved to the background,
  /// is dropped: a foreground start must not run there.
  void _startQueuedSync() {
    final queued = _queuedSyncStart;
    _queuedSyncStart = null;
    if (queued == null || !ref.mounted) return;
    if (!canRunAppProcessWork(isInForeground: _isInForeground)) {
      log('Sync: dropping the queued start; the app is in the background');
      return;
    }
    log('Sync: starting the queued ${queued.forced ? 'forced ' : ''}sync');
    if (queued.forced) {
      // The highest tip any coalesced request observed carries over.
      unawaited(startSyncAnyway(latestTipHeight: queued.latestTipHeight));
    } else {
      startSync(latestTipHeight: queued.latestTipHeight);
    }
  }

  static const _authoritativeBalanceRecoveryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 250),
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final Future<String> Function() _walletDbPathResolver;

  /// Resolves the recorded wallet path without assigning one, or null after a
  /// reset (see [getExistingWalletDbPath]).
  final Future<String?> Function() _existingWalletDbPathResolver;

  /// The running chain of automatic rounds, the manual check or a filter step.
  /// Rust admits one at a time, so whatever is owed meanwhile waits for it.
  Future<void>? _swapRecovery;
  int _swapRecoveryGeneration = 0;
  int _swapRecoveryTransitions = 0;

  /// How long an owed request is held after one, two, three and more rounds
  /// in a row that failed, waited or hit the chain limit. A single bad Tor
  /// circuit often fails one round in isolation, so the first two retry soon,
  /// and only a longer outage backs off to the cap.
  static const _swapRecoveryRetryDelays = <Duration>[
    Duration(seconds: 10),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  /// Rounds chained in a row before the rest is held, so a round that keeps
  /// reporting more can't spin.
  static const _swapRecoveryChainLimit = 16;

  /// Requests for a round so far (see [_oweSwapRecovery]).
  int _swapRecoveryRequested = 0;

  /// The newest request a finished round served. A round serves only the
  /// requests made before it started, so one that finishes can't clear work
  /// owed after that.
  int _swapRecoveryServed = 0;

  /// Rounds in a row that left the request held (see
  /// [_swapRecoveryRetryDelays]).
  int _swapRecoveryHolds = 0;

  /// Until this time the owed request waits (see [_holdSwapRecovery]). Tip
  /// checks and completed syncs run it after. A new request ends the hold.
  DateTime? _swapRecoveryHeldUntil;

  /// Whether a completed sync ends the hold early, as it does for a wait on
  /// sync, a newer publication or a server, but not for a failure.
  bool _swapRecoveryHoldEndsOnSync = false;

  /// Completed syncs so far, so a round that waited for sync can tell that
  /// one completed while it ran.
  int _swapRecoverySyncs = 0;

  /// The scanned height the last completed sync reported, so a filter step
  /// follows only one that moved it.
  int? _swapFilterScanned;

  /// Completes when the round or filter step in flight ends, with a round's
  /// failure or null (see [awaitSwapRecovery]).
  Completer<Object?> _swapRecoveryRoundEnd = Completer<Object?>();

  /// Whether a round that reached the wallet ended without its Activity and
  /// balance refresh, because it was cancelled or the wallet could not be
  /// read then. It may have committed results that no later round reports, so
  /// the next round's end, resume, unlock or Pause refreshes once wallet
  /// reads are safe. Any follow-up refresh clears it, and a wallet reset
  /// drops it.
  bool _swapRecoveryRefreshOwed = false;

  /// Whether the wallet reported a round due (see [_checkSwapRecoveryWork]) or
  /// a filter step owes one. Unlike a request it ends no hold, so a failed
  /// round keeps its retry delay. It becomes a request only while no round
  /// runs, so a running chain applies its own hold first.
  bool _swapRecoveryWorkDue = false;

  /// Owes a receiver round, numbered so a round already running can't clear
  /// it, and ends any hold, since each request is a new reason to look. With
  /// `run`, the round starts once the wallet is at the tip (see
  /// [_runOwedSwapRecovery]). Without it, the next tip check or completed sync
  /// starts it.
  void _oweSwapRecovery({bool run = true}) {
    _swapRecoveryRequested++;
    _swapRecoveryHolds = 0;
    _swapRecoveryHeldUntil = null;
    if (run) _runOwedSwapRecovery();
  }

  /// Starts the owed round, unless it is held, once the wallet is at the tip:
  /// `synced` right after a completed sync, which also ends a hold for a wait,
  /// `atTip` after a tip check found nothing to scan or a completed sync's
  /// work check found new work, and otherwise when the last sync completed and
  /// none runs.
  void _runOwedSwapRecovery({bool synced = false, bool atTip = false}) {
    if (synced && _swapRecoveryHoldEndsOnSync) _swapRecoveryHeldUntil = null;
    if (_swapRecoveryWorkDue && _swapRecovery == null) {
      _swapRecoveryWorkDue = false;
      _swapRecoveryRequested++;
    }
    if (_swapRecoveryRequested == _swapRecoveryServed || _swapRecoveryHeld) {
      return;
    }
    if (!synced &&
        !atTip &&
        (_isSyncing || !(state.value?.isSyncComplete ?? false))) {
      return;
    }
    _startSwapRecovery();
  }

  /// Starts a chain of receiver rounds without occupying the ordinary sync
  /// lifecycle.
  void _startSwapRecovery() {
    if (_swapRecoverySlotFree) {
      _swapRecovery = _driveSwapRecovery(_swapRecoveryGeneration);
    }
  }

  /// Whether receiver work may take the slot (see [_swapRecovery]) now.
  bool get _swapRecoverySlotFree =>
      _swapRecovery == null &&
      _swapRecoveryTransitions == 0 &&
      !_requiresUnlock &&
      _walletMutationPauseCount == 0 &&
      canRunAppProcessWork(isInForeground: _isInForeground) &&
      _getActiveAccountUuid() != null;

  /// Starts a filter step when no round is owed or running, and reports
  /// whether it did.
  bool _startSwapFilterStep() {
    if (_swapRecoveryRequested != _swapRecoveryServed ||
        _swapRecoveryWorkDue ||
        !_swapRecoverySlotFree) {
      return false;
    }
    _swapRecovery = _driveSwapFilterStep(_swapRecoveryGeneration);
    return true;
  }

  /// Runs one filter step in the round's slot, so what cancels a round cancels
  /// it. Its `needsRound`, which a failed filter request also reports, owes a
  /// round as due work does, without ending a hold, and so does a step that
  /// fails unless it was cancelled.
  /// Then it starts what was owed meanwhile and, unless cancelled, checks
  /// whether a round is due, as a filter hit makes one.
  Future<void> _driveSwapFilterStep(int generation) async {
    try {
      final step = await _trackedWalletCall(
        _existingWalletDbPathResolver,
        (path) async => generation != _swapRecoveryGeneration
            ? null
            : await rust_swap.runSwapFilterStep(
                dbPath: path,
                networkName: _endpointConfig.networkName,
              ),
      );
      if ((step?.needsRound ?? false) &&
          generation == _swapRecoveryGeneration) {
        _swapRecoveryWorkDue = true;
      }
    } catch (error) {
      log('Swap filter step failed, owing a round: $error');
      if (generation == _swapRecoveryGeneration) _swapRecoveryWorkDue = true;
    } finally {
      _swapRecovery = null;
    }
    if (!ref.mounted) return;
    final current = generation == _swapRecoveryGeneration;
    // A step that wasn't cancelled followed a completed sync, at the tip.
    _runOwedSwapRecovery(atTip: current);
    // A waiter that joined the step waits for the round it owed, if one
    // started, and otherwise ends as when a round could not start.
    if (_swapRecovery == null) {
      final ended = _swapRecoveryRoundEnd;
      _swapRecoveryRoundEnd = Completer<Object?>();
      ended.complete(null);
    }
    if (current) unawaited(_checkSwapRecoveryWork());
  }

  /// Runs automatic rounds while Rust reports more work it can run now, or a
  /// round waited for sync that completed while it ran, up to
  /// [_swapRecoveryChainLimit], then settles the last one (see
  /// [_settleSwapRecovery]).
  Future<void> _driveSwapRecovery(int generation) async {
    var requested = _swapRecoveryRequested;
    rust_swap.SwapRecoveryRound? round;
    var failed = false;
    try {
      for (var rounds = 1; ; rounds++) {
        requested = _swapRecoveryRequested;
        final syncs = _swapRecoverySyncs;
        try {
          round = await _runSwapRecovery(generation);
        } catch (error) {
          log('Swap recovery remains pending: $error');
          failed = true;
          break;
        }
        if (!ref.mounted || generation != _swapRecoveryGeneration) break;
        if (round == null) break;
        final synced =
            round.wait == rust_swap.SwapRecoveryWait.sync_ &&
            _swapRecoverySyncs != syncs;
        if ((round.more || synced) && rounds < _swapRecoveryChainLimit) {
          continue;
        }
        break;
      }
    } finally {
      _swapRecovery = null;
    }
    if (ref.mounted) {
      _settleSwapRecovery(generation, requested, round, failed: failed);
    }
  }

  /// Applies the outcome of the round started under `generation`. A round that
  /// finishes without waiting serves the requests made before it started
  /// (`requested`). Otherwise the request is held (see [_holdSwapRecovery]). A
  /// request made during the round, or one a cancelled round leaves, runs
  /// next. New work seen during the round waits for that outcome.
  void _settleSwapRecovery(
    int generation,
    int requested,
    rust_swap.SwapRecoveryRound? round, {
    required bool failed,
  }) {
    if (generation != _swapRecoveryGeneration ||
        (_swapRecoveryRequested > requested && !failed)) {
      _runOwedSwapRecovery();
    } else if (failed) {
      _holdSwapRecovery(endsOnSync: false);
    } else if (round != null) {
      final wait = round.wait;
      if (round.more || wait == rust_swap.SwapRecoveryWait.backoff) {
        _holdSwapRecovery(endsOnSync: false);
      } else if (wait != null) {
        _holdSwapRecovery(endsOnSync: true);
      } else {
        _swapRecoveryServed = math.max(_swapRecoveryServed, requested);
        _swapRecoveryHolds = 0;
      }
    }
    if (_swapRecoveryWorkDue) _runOwedSwapRecovery();
  }

  /// Holds the owed request for the next of [_swapRecoveryRetryDelays]. With
  /// `endsOnSync`, a completed sync ends the hold early.
  void _holdSwapRecovery({required bool endsOnSync}) {
    final delays = _swapRecoveryRetryDelays;
    final delay = delays[math.min(_swapRecoveryHolds, delays.length - 1)];
    _swapRecoveryHolds++;
    _swapRecoveryHeldUntil = _now().add(delay);
    _swapRecoveryHoldEndsOnSync = endsOnSync;
  }

  /// Whether the owed request is still held.
  bool get _swapRecoveryHeld {
    final until = _swapRecoveryHeldUntil;
    return until != null && _now().isBefore(until);
  }

  /// Reads the wallet's recovery work (see [swapRecoveryStatus]), or null when
  /// it can't be read.
  Future<rust_swap.SwapRecoveryStatus?> _swapRecoveryWork() async {
    try {
      return await swapRecoveryStatus();
    } catch (error) {
      log('Swap recovery work not read: $error');
      return null;
    }
  }

  /// After a completed sync or a filter step, owes a round (see
  /// [_swapRecoveryWorkDue]) when the wallet reports one due
  /// (`SwapRecoveryStatus.roundDue`), as after a filter hit, a funding memo sync
  /// learned, or filters that fell behind the scanned tip. A read that a
  /// wallet reset overtook describes the old wallet and is dropped.
  Future<void> _checkSwapRecoveryWork() async {
    final epoch = _walletResetEpoch;
    final work = await _swapRecoveryWork();
    if (work == null || !ref.mounted || epoch != _walletResetEpoch) return;
    if (!work.roundDue) return;
    _swapRecoveryWorkDue = true;
    _runOwedSwapRecovery(atTip: true);
  }

  /// Starts sync when found payments wait for it, or a rescan it queued, to
  /// admit them, as a failed round may leave them.
  Future<void> _syncIfAwaitingAdmission() async {
    if ((await _swapRecoveryWork())?.awaitingAdmission ?? false) startSync();
  }

  /// Runs one round, automatic or `manual`, with the display refresh it needs,
  /// then ends it for [awaitSwapRecovery] and the history check. It returns
  /// what the round did, or null when an automatic one could not start or was
  /// cancelled. Either throws its failure, and a cancelled manual check throws
  /// a [StateError].
  Future<rust_swap.SwapRecoveryRound?> _runSwapRecovery(
    int generation, {
    bool manual = false,
  }) async {
    Object? failure;
    try {
      final path = await _getDbPath();
      if (!ref.mounted ||
          generation != _swapRecoveryGeneration ||
          _requiresUnlock ||
          _walletMutationPauseCount > 0 ||
          !canRunAppProcessWork(isInForeground: _isInForeground)) {
        if (manual) throw StateError('Swap history check was cancelled.');
        return null;
      }
      final network = _endpointConfig.networkName;
      final rust_swap.SwapRecoveryRound? round;
      try {
        round = await _trackedWalletCall(
          () async => path,
          (path) => manual
              ? rust_swap.checkSwapHistory(dbPath: path, networkName: network)
              : rust_swap.runSwapRecovery(dbPath: path, networkName: network),
        );
      } catch (error) {
        // A cancelled round's error says nothing about the receiver service.
        if (generation != _swapRecoveryGeneration) {
          _swapRecoveryRefreshOwed = true;
          if (manual) throw StateError('Swap history check was cancelled.');
          return null;
        }
        // A round can commit results and then fail (see
        // `SwapRecoveryRound.changed`), such as a payment that now waits for
        // sync to admit it.
        await _refreshAfterSwapRecovery();
        await _syncIfAwaitingAdmission();
        rethrow;
      }
      if (round == null) return null;
      if (round.rescan) startSync();
      if (round.changed || _swapRecoveryRefreshOwed) {
        await _refreshAfterSwapRecovery();
      }
      return round;
    } catch (error) {
      failure = error;
      rethrow;
    } finally {
      final ended = _swapRecoveryRoundEnd;
      _swapRecoveryRoundEnd = Completer<Object?>();
      ended.complete(failure);
      // Any round can resume or finish a saved history check.
      if (ref.mounted) ref.read(swapRecoveryRoundsProvider.notifier).ended();
    }
  }

  /// Reloads Activity and the balance after a receiver round. While the
  /// wallet is locked or being changed, it owes the refresh instead (see
  /// [_swapRecoveryRefreshOwed]).
  Future<void> _refreshAfterSwapRecovery() async {
    if (ref.mounted && !_requiresUnlock && _walletMutationPauseCount == 0) {
      await _onSyncFollowupUpdated();
    } else {
      _swapRecoveryRefreshOwed = true;
    }
  }

  /// Runs the refresh an earlier round skipped, if one is owed.
  Future<void> _refreshOwedSwapRecovery() async {
    if (_swapRecoveryRefreshOwed) await _refreshAfterSwapRecovery();
  }

  /// Owes a receiver round, as choosing a private query server or NEAR
  /// promising ZEC does. It runs once the wallet is at the tip.
  void requestSwapRecovery() => _oweSwapRecovery();

  /// Continues durable receiver work right away, without waiting for the tip,
  /// a hold or a block sync.
  void continueSwapRecovery() {
    _oweSwapRecovery(run: false);
    _startSwapRecovery();
  }

  /// Like [continueSwapRecovery], for a watched history check polling saved
  /// work on a timer, but it waits out a hold, and a running round already
  /// serves the check, so the poll joins it instead of owing another.
  void pollSwapRecovery() {
    if (_swapRecovery != null || _swapRecoveryHeld) return;
    _swapRecoveryRequested++;
    _startSwapRecovery();
  }

  /// Runs receiver rounds until the active account has nothing left that
  /// holds back issuance (see `getSwapAccountReadiness`), a round fails, or
  /// no further round runs because the rest waits. Returns the failure, or
  /// null when the rounds succeeded, were cancelled or could not start.
  Future<Object?> awaitSwapRecovery() async {
    continueSwapRecovery();
    for (var rounds = 0; rounds < _swapRecoveryChainLimit; rounds++) {
      if (_swapRecovery == null) return null;
      final generation = _swapRecoveryGeneration;
      final failure = await _swapRecoveryRoundEnd.future;
      // A cancelled round's failure says nothing about the account.
      if (generation != _swapRecoveryGeneration) return null;
      if (failure != null) return failure;
      if (await _activeSwapAccountReady()) return null;
    }
    return null;
  }

  /// Whether the active account has nothing left that holds back issuance. An
  /// unreadable state ends the wait, and issuance then says what is missing.
  Future<bool> _activeSwapAccountReady() async {
    final account = _getActiveAccountUuid();
    if (account == null || _requiresUnlock) return true;
    try {
      final readiness = await _trackedWalletCall(
        _existingWalletDbPathResolver,
        (path) => rust_swap.getSwapAccountReadiness(
          dbPath: path,
          networkName: _endpointConfig.networkName,
          accountUuid: account,
        ),
      );
      return readiness == null ||
          !(readiness.seedWalk ||
              readiness.lookups ||
              readiness.awaitingAdmission);
    } catch (error) {
      log('Swap account readiness not read: $error');
      return true;
    }
  }

  /// Starts or resumes explicit history recovery of every enrolled address.
  Future<void> checkSwapHistory() async {
    if (_swapRecoveryTransitions > 0) {
      throw StateError('A swap history transition is already running.');
    }
    _swapRecoveryTransitions++;
    final generation = _swapRecoveryGeneration + 1;
    int? requested;
    rust_swap.SwapRecoveryRound? round;
    var failed = false;
    try {
      await _stopSwapRecovery();
      if (!ref.mounted ||
          generation != _swapRecoveryGeneration ||
          _requiresUnlock ||
          _walletMutationPauseCount > 0) {
        throw StateError('Swap history check was cancelled.');
      }
      // An explicit trigger, so it ends any hold. Its request, owed while the
      // transition keeps automatic rounds out, carries on what the check
      // leaves, such as jobs a failed check saved.
      _oweSwapRecovery(run: false);
      requested = _swapRecoveryRequested;
      final work = _runSwapRecovery(generation, manual: true);
      _swapRecovery = work;
      try {
        round = await work;
      } catch (_) {
        failed = true;
        rethrow;
      } finally {
        _swapRecovery = null;
      }
    } finally {
      _swapRecoveryTransitions--;
      if (ref.mounted && requested != null) {
        // More work it can run now starts the automatic chain at once.
        if (round?.more ?? false) {
          _runOwedSwapRecovery();
        } else {
          _settleSwapRecovery(generation, requested, round, failed: failed);
        }
      }
    }
  }

  /// Cancels the running round's network work and invalidates a worker still
  /// resolving its wallet path, without waiting for it.
  void _cancelSwapRecoveryRound() {
    ++_swapRecoveryGeneration;
    rust_swap.cancelSwapRecovery();
  }

  /// Cancels network work and invalidates a worker still resolving its wallet path.
  Future<void> _stopSwapRecovery() async {
    _cancelSwapRecoveryRound();
    try {
      await _swapRecovery;
    } catch (_) {
      // The initiating manual caller receives its error. Draining must still allow
      // locking, wallet mutations and durable cancellation to finish.
    }
  }

  /// Pauses the manual job without erasing its durable cursor.
  Future<void> cancelSwapHistory() async {
    _swapRecoveryTransitions++;
    try {
      await _stopSwapRecovery();
      try {
        await _trackedWalletCall(
          _getDbPath,
          (path) => rust_swap.cancelSwapHistory(
            dbPath: path,
            networkName: _endpointConfig.networkName,
          ),
        );
      } finally {
        await _refreshOwedSwapRecovery();
      }
    } finally {
      _swapRecoveryTransitions--;
    }
  }

  bool _isSyncing = false;
  bool _recoverySettingTransition = false;
  final RecoveryRestartGate _recoveryRestartGate = RecoveryRestartGate();
  int _walletMutationPauseCount = 0;
  bool _pendingMutationRestartSync = false;
  // Advanced by every opt-out pause exit (a wallet reset). Pauses taken before
  // it cannot restart sync: their snapshots describe the deleted wallet.
  int _walletResetEpoch = 0;
  bool _pendingMutationRestartPolling = false;
  int _recoveryStatusReadCount = 0;
  Completer<void>? _recoveryStatusReadsDrained;
  bool _isInForeground = true;
  int _foregroundEpoch = 0;
  int _activeSyncForegroundEpoch = 0;
  bool _activeSyncStartedInForeground = true;
  int _lastLoggedHeight = 0;
  SyncProgressEvent? _lastForegroundSyncProgress;
  Future<void>? _lastForegroundProgressHandling;
  Future<void>? _foregroundSyncRecovery;
  int _syncGen = 0; // incremented by stopSync to invalidate pending startSync
  String? _cachedDbPath;
  StreamSubscription? _syncSub;
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;
  bool _pollCheckInFlight = false;
  bool _resumeTipCheckPending = false;
  int _sensitiveStateEpoch = 0;
  int _progressEventVersion = 0;
  int _balanceReadVersion = 0;
  int _authoritativeBalanceVersion = 0;
  Future<void>? _authoritativeBalanceRecovery;
  int _authoritativeSpendableOperationCount = 0;
  bool _syncStartDeferred = false;
  int? _deferredSyncLatestTipHeight;
  // Mempool observer subscription. Started in `startSync` and
  // cancelled in `stopSync`, so its lifetime matches the
  // foreground-sync lifetime even though the Rust side manages
  // the two cancel flags independently. A dedicated generation
  // counter isn't needed because the observer keeps running until
  // we explicitly cancel it — the Rust `MEMPOOL_CANCEL` flag is
  // what actually stops it, and `_mempoolSub` is just the Dart
  // side of the corresponding stream.
  StreamSubscription? _mempoolSub;
  int _mempoolEvidenceEpoch = 0;
  bool _mempoolRefreshInFlight = false;
  bool _mempoolRefreshQueued = false;
  // Coalesce balance/history refreshes through `_requestBalanceRefresh`.
  // Mid-flight requests queue one trailing pass so callers don't adopt a
  // stale in-flight result.
  /// Last known account-scoped state per account, used only when
  /// switching accounts.
  ///
  /// ## Why
  ///
  /// Switching used to clear account-scoped state and leave the screen
  /// empty until the refresh landed. Tracing the switch showed the new
  /// screen painting in ~20ms and then sitting blank for 370-970ms —
  /// 95% of the switch was an empty screen, with no dropped frames.
  /// Restoring the target account's last known values makes that first
  /// frame carry data instead.
  ///
  /// ## Refresh sequence on switch
  ///
  /// 1. `accountProvider` publishes the new active account.
  /// 2. `_clearAccountScopedStateFor` stores the outgoing account's
  ///    state here, then emits either the incoming account's stored
  ///    state (if present) or, as before, blank account-scoped state.
  ///    The first painted frame reflects this — ~20ms after the tap.
  /// 3. The switch's `refreshAfterSend` — which ran before this cache
  ///    existed and is unchanged — reads balance and history and emits
  ///    authoritative values, typically 0.9-1.6s later.
  ///
  /// Step 3 is not triggered by this cache and fetches nothing extra;
  /// the cache only changes what is displayed while it is in flight.
  ///
  /// ## Lifetime and clearing
  ///
  /// In memory, per `SyncNotifier` instance, never persisted. Written
  /// only when switching away from an account, and only when that
  /// account's data was complete (`hasAccountScopedData`). Read only
  /// when switching to an account. Cleared wholesale by
  /// `clearSensitiveStateForLock`, so lock, sign-out, and the password
  /// recovery flows drop it along with the rest of the sensitive state.
  ///
  /// Not cleared on account deletion, import, or network change. A
  /// stale entry for a removed account is unreachable — entries are
  /// keyed by uuid and only read for the account being switched to, and
  /// a removed account cannot be switched to — but pruning it would be
  /// tidier.
  ///
  /// ## What bounds staleness
  ///
  /// * Restored values are overwritten by the refresh already in flight
  ///   for that switch, typically within a second. If Rust cannot provide
  ///   an authoritative balance, the switch refresh clears the restored
  ///   balance fields while retaining independently refreshed history.
  /// * Only wallet-wide sync fields are taken from the live state via
  ///   `withGlobalSyncFieldsFrom`, so sync progress cannot regress to
  ///   whatever it was when the account was last active.
  /// * `displaySpendableFreshness` is forced to `lastCompletedSync`, so
  ///   consumers that distinguish authoritative balances (the mobile
  ///   send screen's max-amount quoting) treat it as a snapshot.
  /// * Entries are keyed by uuid and only read for the incoming
  ///   account, so one account's figures cannot appear under another.
  /// * Spending is unaffected: `propose_send` re-derives inputs from the
  ///   wallet DB, so a stale display cannot produce an invalid spend.
  ///
  /// ## Where staleness can still be observed
  ///
  /// This bounds staleness; it does not eliminate it. A thrown refresh
  /// failure leaves the restored figures in place until a later refresh
  /// succeeds. An unavailable balance is handled differently: the
  /// account-switch refresh returns balance surfaces to their blank state
  /// while still committing any transaction history it fetched.
  ///
  /// Only the mobile send screen currently reads
  /// `displaySpendableFreshness`; desktop surfaces render a restored
  /// balance identically to a fresh one. Wiring desktop to that flag is
  /// the natural follow-up.
  final Map<String, SyncState> _lastKnownByAccount = {};
  bool _balanceRefreshInFlight = false;
  bool _balanceRefreshQueued = false;
  bool _balanceRefreshQueuedReleaseSnapshot = false;
  bool _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable = false;
  bool _balanceRefreshQueuedRequireAuthoritativeBalance = false;
  Future<void>? _balanceRefreshChain;

  @override
  Future<SyncState> build() async {
    final bootstrap = ref.watch(appBootstrapProvider);
    // Publish whether the active account's transparent balance reads
    // privately, so Settings can offer to lower a durably private wallet
    // without depending on this notifier.
    listenSelf((_, next) {
      final private = next.value?.transparentPrivate ?? false;
      scheduleMicrotask(() {
        if (!ref.mounted) return;
        ref.read(walletTransparentPrivateProvider.notifier).update(private);
      });
    });
    unawaited(ref.read(chainUpgradeStatusProvider.future));
    final shutdown = ref.read(appShutdownSignalProvider);
    shutdown.addListener(_stopForAppExit);
    ref.onDispose(() => shutdown.removeListener(_stopForAppExit));
    _lifecycleListener = AppLifecycleListener(
      onResume: _handleAppResume,
      onHide: _handleAppHide,
    );

    ref.onDispose(() {
      ++_syncGen;
      ++_progressEventVersion;
      ++_balanceReadVersion;
      _isSyncing = false;
      _syncStartDeferred = false;
      _deferredSyncLatestTipHeight = null;
      rust_sync.cancelFullSync();
      _cancelSwapRecoveryRound();
      _syncSub?.cancel();
      _mempoolSub?.cancel();
      // Cancel the Rust-side observer too; cancelling the Dart
      // subscription alone leaves the tonic stream task alive
      // until the Rust isolate pool tears it down.
      rust_sync.stopMempoolObserver();
      _lifecycleListener?.dispose();
      _pollTimer?.cancel();
    });

    // Auto-start sync on account changes.
    // Uses ref.listen (not ref.watch) to avoid rebuilding SyncNotifier on every
    // account state change (switch, rename), which would cancel active sync and
    // reset UI state.
    //
    // Two cases:
    // 1. First account created (0→1): start sync + polling.
    // 2. Additional account added (N→N+1): start sync to rescan from new
    //    account's birthday height. Rust sync loop picks up new ranges via
    //    suggest_scan_ranges() even mid-sync; _isSyncing guard prevents duplicates.
    ref.listen(accountProvider, (prev, next) {
      final prevCount = prev?.value?.accounts.length ?? 0;
      final nextCount = next.value?.accounts.length ?? 0;
      final prevAccountUuid = prev?.value?.activeAccountUuid;
      final nextAccountUuid = next.value?.activeAccountUuid;
      if (nextCount < prevCount) {
        ref.read(pendingActivityEvidenceProvider.notifier).clear();
      }
      if (prevAccountUuid != nextAccountUuid) {
        // This only changes the order of transparent refreshes that Rust has
        // not started yet. The current bounded request group keeps running.
        rust_sync.setActiveSyncAccount(accountUuid: nextAccountUuid);
        _clearAccountScopedStateFor(nextAccountUuid);
      }
      if (nextCount > prevCount) {
        startSync();
        _startPolling();
      }
    });

    // Initial check: if accounts already exist at build time
    final accountState = ref.read(accountProvider).value;
    if (accountState != null && accountState.hasAccounts) {
      Future(() {
        unawaited(_startInitialSync());
      });
    }

    final initial = bootstrap.initialSyncSnapshot;
    final initialAccountUuid = accountState?.activeAccountUuid;
    final initialBelongsToActiveAccount =
        initial.accountUuid != null &&
        initial.accountUuid == initialAccountUuid &&
        initial.hasAccountScopedData;
    var initialState = SyncState(
      accountUuid: initialAccountUuid,
      hasAccountScopedData: initialBelongsToActiveAccount,
      isSyncing: false,
      isBackgroundMode: false,
      isSyncComplete: initialBelongsToActiveAccount && initial.isSyncComplete,
      percentage: initial.percentage,
      scannedHeight: initial.scannedHeight,
      chainTipHeight: initial.chainTipHeight,
      transparentBalance: initialBelongsToActiveAccount
          ? initial.transparentBalance
          : BigInt.zero,
      saplingBalance: initialBelongsToActiveAccount
          ? initial.saplingBalance
          : BigInt.zero,
      orchardBalance: initialBelongsToActiveAccount
          ? initial.orchardBalance
          : BigInt.zero,
      ironwoodBalance: initialBelongsToActiveAccount
          ? initial.ironwoodBalance
          : BigInt.zero,
      orchardLockedBalance: initialBelongsToActiveAccount
          ? initial.orchardLockedBalance
          : BigInt.zero,
      transparentPendingBalance: initialBelongsToActiveAccount
          ? initial.transparentPendingBalance
          : BigInt.zero,
      transparentLockedBalance: initialBelongsToActiveAccount
          ? initial.transparentLockedBalance
          : BigInt.zero,
      transparentAuthority: initialBelongsToActiveAccount
          ? initial.transparentAuthority
          : rust_sync.TransparentBalanceAuthority.current,
      transparentLastKnownBalance: initialBelongsToActiveAccount
          ? initial.transparentLastKnownBalance
          : null,
      transparentStop: initialBelongsToActiveAccount
          ? initial.transparentStop
          : null,
      transparentPrivate:
          initialBelongsToActiveAccount && initial.transparentPrivate,
      saplingPendingBalance: initialBelongsToActiveAccount
          ? initial.saplingPendingBalance
          : BigInt.zero,
      orchardPendingBalance: initialBelongsToActiveAccount
          ? initial.orchardPendingBalance
          : BigInt.zero,
      ironwoodPendingBalance: initialBelongsToActiveAccount
          ? initial.ironwoodPendingBalance
          : BigInt.zero,
      canShieldTransparentBalance: initialBelongsToActiveAccount
          ? initial.canShieldTransparentBalance
          : false,
      shieldTransparentFee: initialBelongsToActiveAccount
          ? initial.shieldTransparentFee
          : BigInt.zero,
      shieldTransparentAmount: initialBelongsToActiveAccount
          ? initial.shieldTransparentAmount
          : BigInt.zero,
      spendableBalance: initialBelongsToActiveAccount
          ? initial.spendableBalance
          : BigInt.zero,
      displaySpendableBalance: initialBelongsToActiveAccount
          ? initial.spendableBalance
          : BigInt.zero,
      totalBalance: initialBelongsToActiveAccount
          ? initial.totalBalance
          : BigInt.zero,
      recentTransactions: initialBelongsToActiveAccount
          ? initial.recentTransactions
          : const [],
      phase: '',
    );
    if (initial.accountUuid == initialAccountUuid &&
        initial.cachedBalance != null &&
        !_requiresUnlock) {
      initialState = initialState.withCachedBalance(initial.cachedBalance!);
    }
    // Startup may raise or lower the policy after the snapshot was read; the
    // tip has not moved since. See [SyncState.carryingTransparentAuthority].
    final startupApplied = ref
        .read(transparentPolicyStartupProvider)
        .appliedPolicy;
    _appliedTransparentPolicy ??= startupApplied;
    if (!initialBelongsToActiveAccount) return initialState;
    // The snapshot's policy flag and stop reason describe the policy before
    // reconciliation, which may have completed an interrupted opt-out.
    final reconciled = startupApplied == null
        ? initialState
        : initialState.underTransparentPolicy(
            private:
                startupApplied.mode ==
                rust_sync.ApiTransparentLedgerMode.privateRequired,
          );
    return reconciled.carryingTransparentAuthority(
      privatePolicyMayApply: _privatePolicyMayApply,
      crossesTip: false,
      // Bootstrap has no policy generation. Reconciliation may find a
      // generation another connection changed after the snapshot read, even
      // when it makes no change itself.
      policyChanged: startupApplied != null,
    );
  }

  SyncState? _previousScopedState(SyncState? prev, String? accountUuid) {
    if (accountUuid == null || prev?.accountUuid != accountUuid) {
      return null;
    }
    return prev;
  }

  /// Re-point account-scoped state at [accountUuid] during a switch.
  ///
  /// Bumping `_balanceReadVersion` first is what makes restoring safe:
  /// any refresh still in flight for the outgoing account is discarded
  /// on commit, so it cannot land on top of the incoming account's
  /// restored values. See `_lastKnownByAccount` for the full sequence.
  void _clearAccountScopedStateFor(String? accountUuid) {
    ++_balanceReadVersion;
    _authoritativeBalanceRecovery = null;
    // Rounds do the active account's work first (Rust reads the account
    // `setActiveSyncAccount` named), so an automatic round restarts with the
    // incoming account. A history check spans every account and keeps running.
    if (_swapRecovery != null && _swapRecoveryTransitions == 0) {
      _cancelSwapRecoveryRound();
    }
    _oweSwapRecovery();
    final prev = state.value;
    if (prev == null) return;

    // Remember the account being left so switching back can paint
    // immediately instead of blanking. Only complete states are stored,
    // so a half-loaded account is never restored later.
    final previousAccountUuid = prev.accountUuid;
    if (previousAccountUuid != null && prev.hasAccountScopedData) {
      _lastKnownByAccount[previousAccountUuid] = prev;
    }

    final restored = accountUuid == null
        ? null
        : _lastKnownByAccount[accountUuid];
    if (restored != null) {
      // Paint this account's last known values immediately, carrying the
      // live sync fields so progress cannot regress, and flagged as a
      // snapshot rather than authoritative. The switch's own refresh
      // replaces them shortly.
      // The cache predates any tip the other account's syncs moved, and any
      // policy raised since; see [SyncState.carryingTransparentAuthority].
      state = AsyncData(
        restored
            .carryingTransparentAuthority(
              privatePolicyMayApply: _privatePolicyMayApply,
              crossesTip: restored.chainTipHeight != prev.chainTipHeight,
            )
            .withGlobalSyncFieldsFrom(prev)
            .copyWith(
              displaySpendableFreshness:
                  SpendableBalanceFreshness.lastCompletedSync,
            ),
      );
      return;
    }

    state = AsyncData(prev.withoutAccountScopedData(accountUuid: accountUuid));
  }

  // ======================== Sync Control ========================

  Future<void> _startInitialSync() async {
    final epoch = _sensitiveStateEpoch;
    final staleSyncRunning = _syncSub == null && rust_sync.isSyncRunning();
    final staleMempoolRunning =
        _mempoolSub == null && rust_sync.isMempoolObserverRunning();

    if (staleSyncRunning || staleMempoolRunning) {
      if (staleSyncRunning) {
        log('Sync: cancelling stale Rust sync before startup');
        rust_sync.cancelFullSync();
      }
      if (staleMempoolRunning) {
        log('Mempool: stopping stale observer before startup');
        rust_sync.stopMempoolObserver();
      }

      var waited = 0;
      while ((rust_sync.isSyncRunning() ||
              rust_sync.isMempoolObserverRunning()) &&
          waited < 30000) {
        await Future.delayed(const Duration(milliseconds: 100));
        waited += 100;
      }
      if (rust_sync.isSyncRunning()) {
        log(
          'Sync: timed out waiting for stale Rust sync to stop after 30s; '
          'startup sync will rely on running-guard recovery',
        );
      }
      if (rust_sync.isMempoolObserverRunning()) {
        log(
          'Mempool: timed out waiting for stale observer to stop after 30s; '
          'startup observer will rely on running-guard recovery',
        );
      }
    }

    if (epoch != _sensitiveStateEpoch || _requiresUnlock) {
      log('Sync: skipping initial sync after lock transition');
      return;
    }
    startSync();
    refreshHomeInBackground();
    _startPolling();
  }

  bool get _isShuttingDown =>
      ref.read(appShutdownSignalProvider).isShuttingDown;

  /// Quiesce scan/poll work without waiting on network I/O or cancelling durable
  /// sends. Generation changes also reject preflight completions already queued.
  void _stopForAppExit() {
    _resumeTipCheckPending = false;
    _queuedSyncStart = null;
    ++_syncGen;
    ++_sensitiveStateEpoch;
    ++_progressEventVersion;
    ++_balanceReadVersion;
    _syncStartDeferred = false;
    _deferredSyncLatestTipHeight = null;
    _isSyncing = false;
    _stopPolling();
    _cancelSwapRecoveryRound();
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
  }

  /// Fire-and-forget: sets up FRB stream and returns immediately.
  /// Stream events update state via _onSyncProgress. Completion handled by _onSyncDone.
  void startSync({int? latestTipHeight}) {
    if (_isShuttingDown) return;
    if (_privateStatusCoverageNeedsSettings()) {
      _stopPolling();
      log(
        'Sync: private status coverage needs a Settings decision; '
        'automatic restart paused',
      );
      return;
    }
    // A wallet mutation owns the DB: account deletion, a reset, or the
    // recovery toggle. Hand the start to whichever pause exits last; a reset
    // that opts out discards it.
    if (_walletMutationPauseCount > 0) {
      _pendingMutationRestartSync = true;
      return;
    }
    if (_recoverySettingTransition) return;
    if (_requiresUnlock) {
      log('Sync: locked, skipping foreground sync start');
      return;
    }
    if (_authoritativeSpendableOperationCount > 0) {
      _syncStartDeferred = true;
      if (latestTipHeight != null) {
        _deferredSyncLatestTipHeight = math.max(
          _deferredSyncLatestTipHeight ?? 0,
          latestTipHeight,
        );
      }
      log(
        'Sync: deferring foreground sync while an authoritative spendable '
        'operation is active',
      );
      return;
    }
    if (_syncSub != null) {
      // This notifier's sync still holds the Rust guard, if only for its
      // post-sync follow-ups: start again once its stream ends.
      _queueSyncStart(forced: false, latestTipHeight: latestTipHeight);
      return;
    }
    if (_isSyncing || rust_sync.isSyncRunning()) {
      // Preflight of a start about to run, or a sync this notifier does not
      // own (native background preparation). Never start a second one.
      log('Sync: already running, skipping');
      return;
    }
    _queuedSyncStart = null;
    ++_progressEventVersion;
    ++_balanceReadVersion;
    _authoritativeBalanceRecovery = null;
    _isSyncing = true;
    _activeSyncForegroundEpoch = _foregroundEpoch;
    _activeSyncStartedInForeground = _isInForeground;
    _lastLoggedHeight = 0;
    _lastForegroundSyncProgress = null;
    _lastForegroundProgressHandling = null;
    final gen = ++_syncGen;
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    final startedAt = DateTime.now();
    final previousScannedHeight = prev?.scannedHeight ?? 0;
    final previousChainTipHeight = prev?.chainTipHeight ?? 0;
    final nextChainTipHeight = latestTipHeight == null
        ? previousChainTipHeight
        : math.max(previousChainTipHeight, latestTipHeight);
    final canPreserveCompletedSpendable =
        SyncState.shouldPreserveCompletedSpendable(scopedPrev);
    // A privately read amount goes stale only when the known tip actually
    // moved; a later move during the sync demotes it when its progress
    // reports the new tip. See [SyncState.carryingTransparentAuthority].
    final carried = scopedPrev?.carryingTransparentAuthority(
      privatePolicyMayApply: _privatePolicyMayApply,
      crossesTip: nextChainTipHeight != previousChainTipHeight,
    );
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasCachedBalance: scopedPrev?.hasCachedBalance ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        hasRecentTransactionsError:
            scopedPrev?.hasRecentTransactionsError ?? false,
        isSyncing: true,
        isBackgroundMode: false,
        isSyncComplete: false,
        percentage: 0.0,
        scannedHeight: previousScannedHeight,
        chainTipHeight: nextChainTipHeight,
        transparentBalance: carried?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        ironwoodBalance: scopedPrev?.ironwoodBalance,
        orchardLockedBalance: scopedPrev?.orchardLockedBalance,
        transparentPendingBalance: carried?.transparentPendingBalance,
        transparentLockedBalance: carried?.transparentLockedBalance,
        transparentAuthority: carried?.transparentAuthority,
        transparentLastKnownBalance: carried?.transparentLastKnownBalance,
        transparentStop: carried?.transparentStop,
        transparentPrivate: scopedPrev?.transparentPrivate,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        ironwoodPendingBalance: scopedPrev?.ironwoodPendingBalance,
        canShieldTransparentBalance:
            carried?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        displaySpendableBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displaySpendableBalance
            : scopedPrev?.spendableBalance,
        displayIronwoodBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayIronwoodBalance
            : scopedPrev?.ironwoodBalance,
        displayIronwoodPendingBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayIronwoodPendingBalance
            : scopedPrev?.ironwoodPendingBalance,
        displayOrchardBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayOrchardBalance
            : scopedPrev?.orchardBalance,
        displayOrchardPendingBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayOrchardPendingBalance
            : scopedPrev?.orchardPendingBalance,
        displayOrchardLockedBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayOrchardLockedBalance
            : scopedPrev?.orchardLockedBalance,
        displaySpendableFreshness: canPreserveCompletedSpendable
            ? SpendableBalanceFreshness.lastCompletedSync
            : SpendableBalanceFreshness.authoritative,
        totalBalance: carried?.totalBalance,
        displayTotalBalance: canPreserveCompletedSpendable
            ? carried?.displayTotalBalance
            : carried?.totalBalance,
        displayShieldedBalance: canPreserveCompletedSpendable
            ? scopedPrev?.displayShieldedBalance
            : scopedPrev == null
            ? null
            : scopedPrev.saplingBalance +
                  scopedPrev.orchardBalance +
                  scopedPrev.ironwoodBalance +
                  scopedPrev.saplingPendingBalance +
                  scopedPrev.orchardPendingBalance +
                  scopedPrev.ironwoodPendingBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: startedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: kSyncPhasePreflight,
      ),
    );

    _getDbPath()
        .then((dbPath) async {
          if (gen != _syncGen) return; // stopSync was called, abort
          // Only Rust's sync writes companions, and a wallet created or
          // replaced since launch has a directory nothing has marked yet.
          await _keepCompanionsOutOfBackups(dbPath);
          if (gen != _syncGen) return;
          try {
            final tip = await ref
                .read(rpcEndpointFailoverProvider.notifier)
                .getLatestBlockHeight();
            await ref
                .read(chainUpgradeStatusProvider.notifier)
                .refreshAtTip(tip);
          } catch (e) {
            if (gen != _syncGen) return;
            log('Sync: endpoint preflight failed: $e');
            _isSyncing = false;
            _recordSyncFailure(e);
            return;
          }

          // The preflight can wait out a Tor bootstrap; a lock or transport
          // change meanwhile has moved the generation and drained Rust work.
          if (gen != _syncGen) {
            log('Sync: preflight finished after stop; not starting');
            return;
          }
          final endpoint = _endpointConfig;
          log('Sync: starting foreground sync via ${endpoint.hostPort}');
          final readyState = state.value;
          if (readyState != null) {
            state = AsyncData(
              readyState.copyWith(
                phase: kSyncPhaseSetup,
                phaseCompletedUnits: 0,
                phaseTotalUnits: 0,
              ),
            );
          }
          // Fire up the mempool observer alongside the scan loop.
          // It has its own Rust cancel flag (MEMPOOL_CANCEL) and runs
          // on a separate tokio runtime, so it can accept events while
          // the scan loop is still catching up on old blocks.
          _startMempoolObserver(dbPath, endpoint);
          // Seed the shared priority synchronously before the asynchronous Rust
          // sync task starts. Later account switches update the same target.
          rust_sync.setActiveSyncAccount(accountUuid: _getActiveAccountUuid());
          final stream = rust_sync.startFullSync(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            mode: 1,
          );
          _syncSub = stream.listen(
            (event) {
              if (!ref.mounted || gen != _syncGen) return;
              if (event.kind == rust_sync.ApiSyncEventKind.followupUpdated) {
                unawaited(_onSyncFollowupUpdated());
                return;
              }
              final progress = SyncProgressEvent(
                scannedHeight: event.scannedHeight.toInt(),
                chainTipHeight: event.chainTipHeight.toInt(),
                percentage: event.percentage,
                displayTargetPercentage: event.displayTargetPercentage,
                displayTargetBlocks: event.displayTargetBlocks.toInt(),
                checking: event.checking == null
                    ? null
                    : SyncCheckingProgress(
                        cycle: event.checking!.cycle,
                        percentage: event.checking!.percentage,
                        displayTargetPercentage:
                            event.checking!.displayTargetPercentage,
                      ),
                remainingScanBlocks: event.remainingScanBlocks?.toInt(),
                pendingScanStartHeight: event.pendingScanStartHeight?.toInt(),
                isSyncing: event.isSyncing,
                isComplete: event.kind == rust_sync.ApiSyncEventKind.completed,
                hasNewTx: event.hasNewTx,
                phaseCompletedUnits: event.phaseCompletedUnits.toInt(),
                phaseTotalUnits: event.phaseTotalUnits.toInt(),
                phase: event.phase,
              );
              _lastForegroundSyncProgress = progress;
              final handling = _onSyncProgress(progress);
              _lastForegroundProgressHandling = handling;
              // Started after the handling is recorded, so the round's refresh
              // waits for this completion's reads. A batch before completion
              // leaves blocks the receiver may already publish unscanned, so an
              // owed round waits for completion.
              if (progress.isComplete && ref.mounted && !_requiresUnlock) {
                _swapRecoverySyncs++;
                _runOwedSwapRecovery(synced: true);
                final moved =
                    progress.scannedHeight > (_swapFilterScanned ?? -1);
                _swapFilterScanned = progress.scannedHeight;
                // A step checks for new work itself once it ends.
                if (!(moved && _startSwapFilterStep())) {
                  unawaited(_checkSwapRecoveryWork());
                }
              }
              unawaited(
                handling.catchError((Object error, StackTrace stackTrace) {
                  log(
                    'SyncNotifier: foreground progress handling failed: $error',
                  );
                }),
              );
            },
            onDone: () async {
              if (!ref.mounted || gen != _syncGen) {
                log('Sync: ignoring stale stream end');
                return;
              }
              log('Sync: stream ended');
              // `_syncSub` stays set until cleanup is done below, so a start
              // requested meanwhile is still queued behind this stream rather
              // than dropped as "already running".
              // Normal completion (isComplete=true) is handled inside
              // _onSyncProgress, which clears _isSyncing and starts
              // polling. But the stream can also end WITHOUT an
              // isComplete event when Rust exits because cancellation or a
              // sync-owner handoff changed DESIRED_SYNC_MODE. In that case
              // _isSyncing is still true and the mempool observer is
              // still running, both of which block future startSync()
              // calls. Clean up only when no final event arrived; otherwise
              // its async handler owns final cleanup.
              if (_isSyncing) {
                final lastProgress = _lastForegroundSyncProgress;
                if (lastProgress?.isComplete ?? false) {
                  log('Sync: final completion event is still being applied');
                  try {
                    await _lastForegroundProgressHandling;
                  } catch (_) {
                    // The listener logs the original error. Fall through to
                    // cleanup without promoting height equality to complete.
                  }
                  if (gen != _syncGen) return;
                }
                if (_isSyncing) {
                  ++_progressEventVersion;
                  _isSyncing = false;
                  log(
                    'Sync: stream ended without applied isComplete, '
                    'cleaning up',
                  );
                  _stopMempoolObserver();
                  final previousState = state.value;
                  if (previousState != null) {
                    state = AsyncData(previousState.withSyncActivityStopped());
                  }
                }
              }
              _syncSub = null;
              // Rust released its guard before closing the stream.
              _startQueuedSync();
            },
            onError: (e) {
              if (!ref.mounted || gen != _syncGen) return;
              log('Sync: stream error: $e');
              // Error recovery owns the next start, and the stream no longer
              // owns a sync to queue behind.
              _queuedSyncStart = null;
              _syncSub = null;
              ++_progressEventVersion;
              _isSyncing = false;
              // Sync died mid-stream: tear the mempool observer down
              // at the same time so a failed sync session can't leak
              // a lightwalletd stream that keeps firing
              // `_refreshBalance()` callbacks with no owning sync.
              _stopMempoolObserver();
              _trackForegroundSyncRecovery(
                _recoverSyncOnFallbackOrRecordFailure(
                  e,
                  gen,
                  endpoint: endpoint,
                ),
              );
            },
          );
        })
        .catchError((e, st) {
          if (gen != _syncGen) return;
          log('SyncNotifier: ERROR: $e\n$st');
          ++_progressEventVersion;
          _isSyncing = false;
          // Sync setup threw before the stream was ever attached.
          // We may have already started the mempool observer
          // (happens on the main success path just before
          // `startFullSync`), so always call
          // `_stopMempoolObserver()` here; it is idempotent when
          // nothing is running.
          _stopMempoolObserver();
          _trackForegroundSyncRecovery(
            _recoverSyncOnFallbackOrRecordFailure(e, gen),
          );
        });
  }

  void _trackForegroundSyncRecovery(Future<void> recovery) {
    _foregroundSyncRecovery = recovery;
    unawaited(
      recovery.whenComplete(() {
        if (identical(_foregroundSyncRecovery, recovery)) {
          _foregroundSyncRecovery = null;
        }
      }),
    );
  }

  /// Starts (or joins) one foreground sync and resolves only after its
  /// successful completion event has been applied to [state].
  ///
  /// Migration entry screens use this instead of observing [SyncState.isSyncing]
  /// directly. That lets the route show a one-time entry/resume syncing surface
  /// without turning later polling syncs into full-screen transitions.
  ///
  /// On iOS, `applicationWillEnterForeground` first asks native denomination
  /// preparation to hand its sync ownership back. If that native operation is
  /// still unwinding, wait for the shared Rust sync lane before attaching the
  /// Dart foreground stream.
  Future<SyncState> synchronizeForMigrationEntry() async {
    if (_requiresUnlock) {
      throw StateError('Wallet is locked.');
    }

    // This method is called only from a visible migration entry surface. Mark
    // foreground eagerly because AppLifecycleListener callback ordering is not
    // guaranteed across the status screen and this provider.
    _isInForeground = true;
    if (shouldRestartSyncForMigrationEntry(
      hasAttachedSync: _isSyncing || _syncSub != null,
      activeSyncStartedInForeground: _activeSyncStartedInForeground,
      activeSyncForegroundEpoch: _activeSyncForegroundEpoch,
      currentForegroundEpoch: _foregroundEpoch,
    )) {
      await restartSync();
      if (!_isSyncing) {
        throw StateError('Unable to restart wallet sync after app resume.');
      }
    }

    if (!_isSyncing && _syncSub == null) {
      const handoffPollInterval = Duration(milliseconds: 100);
      const handoffTimeout = Duration(minutes: 2);
      final handoffDeadline = DateTime.now().add(handoffTimeout);
      while (rust_sync.isSyncRunning()) {
        if (!ref.mounted || _requiresUnlock) {
          throw StateError('Wallet sync was interrupted.');
        }
        if (DateTime.now().isAfter(handoffDeadline)) {
          throw StateError(
            'Background migration preparation is still finishing. Try again.',
          );
        }
        await Future<void>.delayed(handoffPollInterval);
      }

      startSync();
      if (!_isSyncing) {
        if (_syncStartDeferred) {
          throw StateError(
            'Wallet sync is waiting for another wallet operation to finish.',
          );
        }
        throw StateError('Unable to start wallet sync.');
      }
    }

    var observedGeneration = _syncGen;
    const completionPollInterval = Duration(milliseconds: 50);
    while (true) {
      if (!ref.mounted || _requiresUnlock) {
        throw StateError('Wallet sync was interrupted.');
      }

      if (_syncGen != observedGeneration) {
        // Endpoint fallback starts a replacement foreground run. Treat it as
        // the same entry sync rather than completing the entry surface early.
        if (_isSyncing) {
          observedGeneration = _syncGen;
        } else {
          throw StateError('Wallet sync was interrupted.');
        }
      }

      final current = state.value;
      if (!_isSyncing) {
        final recovery = _foregroundSyncRecovery;
        if (recovery != null) {
          await recovery;
          continue;
        }
        if (current?.isSyncComplete == true &&
            current?.failure == null &&
            current?.error == null) {
          return current!;
        }
        final message =
            current?.failure?.rawMessage ??
            current?.error ??
            'Wallet sync ended before completion.';
        throw StateError(message);
      }

      await Future<void>.delayed(completionPollInterval);
    }
  }

  Future<void> _recoverSyncOnFallbackOrRecordFailure(
    Object error,
    int gen, {
    RpcEndpointConfig? endpoint,
  }) async {
    final switched = await ref
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          error,
          endpoint: endpoint,
          operation: 'foreground sync',
        );
    if (gen != _syncGen || _requiresUnlock) return;
    if (switched) {
      log('Sync: retrying foreground sync with fallback endpoint');
      final current = state.value;
      startSync(latestTipHeight: current?.chainTipHeight);
      _startPolling();
      return;
    }
    _recordSyncFailure(error);
  }

  void _recordSyncFailure(Object error) {
    ++_progressEventVersion;
    final failure = classifySyncFailure(error);
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    final spendableDisplay = SyncState.preserveSpendableDisplay(scopedPrev);
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasCachedBalance: scopedPrev?.hasCachedBalance ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        hasRecentTransactionsError:
            scopedPrev?.hasRecentTransactionsError ?? false,
        failure: failure,
        error: failure.rawMessage,
        isSyncComplete: false,
        transparentBalance: scopedPrev?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        ironwoodBalance: scopedPrev?.ironwoodBalance,
        orchardLockedBalance: scopedPrev?.orchardLockedBalance,
        transparentPendingBalance: scopedPrev?.transparentPendingBalance,
        transparentLockedBalance: scopedPrev?.transparentLockedBalance,
        transparentAuthority: scopedPrev?.transparentAuthority,
        transparentLastKnownBalance: scopedPrev?.transparentLastKnownBalance,
        transparentStop: scopedPrev?.transparentStop,
        transparentPrivate: scopedPrev?.transparentPrivate,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        ironwoodPendingBalance: scopedPrev?.ironwoodPendingBalance,
        canShieldTransparentBalance:
            scopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        displaySpendableBalance: spendableDisplay.balance,
        displayIronwoodBalance: scopedPrev?.displayIronwoodBalance,
        displayIronwoodPendingBalance:
            scopedPrev?.displayIronwoodPendingBalance,
        displayOrchardBalance: scopedPrev?.displayOrchardBalance,
        displayOrchardPendingBalance: scopedPrev?.displayOrchardPendingBalance,
        displayOrchardLockedBalance: scopedPrev?.displayOrchardLockedBalance,
        displaySpendableFreshness: spendableDisplay.freshness,
        totalBalance: scopedPrev?.totalBalance,
        displayTotalBalance: scopedPrev?.displayTotalBalance,
        displayShieldedBalance: scopedPrev?.displayShieldedBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: prev?.lastSyncStartedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: DateTime.now(),
      ),
    );
    _startPolling();
  }

  /// Recovery path for cases like unlock-after-sign-out where a previous
  /// sync has already been cancelled, but Rust is still unwinding.
  Future<void> startSyncAnyway({int? latestTipHeight}) async {
    if (_isShuttingDown) return;
    if (_requiresUnlock) {
      log('Sync: locked, skipping forced foreground sync start');
      return;
    }
    if (_syncSub != null) {
      _queueSyncStart(forced: true, latestTipHeight: latestTipHeight);
      return;
    }
    if (_isSyncing) {
      log('Sync: foreground sync already attached, skipping forced start');
      return;
    }

    final rustRunning = rust_sync.isSyncRunning();
    final cancelRequested = rust_sync.isSyncCancelRequested();
    final staleMempoolRunning =
        _mempoolSub == null && rust_sync.isMempoolObserverRunning();
    if (staleMempoolRunning) {
      log(
        'Mempool: stale observer still running, stopping before foreground restart',
      );
      rust_sync.stopMempoolObserver();
    }
    if ((rustRunning && cancelRequested) || staleMempoolRunning) {
      log(
        'Sync: cancelled Rust tasks still running, waiting before foreground '
        'restart',
      );
      final stopped = await _waitForRustTasksToStop(
        timeoutMs: 5000,
        onSyncTimeout:
            'SyncNotifier: startSyncAnyway timed out waiting for cancelled '
            'Rust sync to stop after 5s; keeping polling active for retry',
        onMempoolTimeout:
            'SyncNotifier: startSyncAnyway timed out waiting for mempool '
            'observer to stop after 5s; keeping polling active for retry',
      );
      if (!stopped) {
        _startPolling();
        return;
      }
    } else if (rustRunning) {
      log('Sync: already running, skipping forced foreground restart');
      return;
    }

    startSync(latestTipHeight: latestTipHeight);
    _startPolling();
  }

  void stopSync() {
    _resumeTipCheckPending = false;
    _queuedSyncStart = null;
    _syncStartDeferred = false;
    _deferredSyncLatestTipHeight = null;
    ++_syncGen; // invalidate pending startSync callbacks
    ++_progressEventVersion;
    ++_balanceReadVersion;
    rust_sync.cancelFullSync();
    _syncSub?.cancel();
    _syncSub = null;
    // Tear the mempool observer down at the same time. The sync
    // loop and the observer have independent Rust cancel flags
    // (SYNC_CANCEL / MEMPOOL_CANCEL), but Dart pairs them so the
    // UX invariant "no sync running → no mempool stream running"
    // holds.
    _stopMempoolObserver();
    _isSyncing = false;
    _stopPolling();
    final prev = state.value;
    final accountUuid = _getActiveAccountUuid();
    final scopedPrev = _previousScopedState(prev, accountUuid);
    final spendableDisplay = SyncState.preserveSpendableDisplay(scopedPrev);
    state = AsyncData(
      SyncState(
        accountUuid: accountUuid,
        hasBalanceData: scopedPrev?.hasBalanceData ?? false,
        hasCachedBalance: scopedPrev?.hasCachedBalance ?? false,
        hasRecentTransactionsData:
            scopedPrev?.hasRecentTransactionsData ?? false,
        hasRecentTransactionsError:
            scopedPrev?.hasRecentTransactionsError ?? false,
        isSyncing: false,
        isBackgroundMode: false,
        isSyncComplete: prev?.isSyncComplete ?? false,
        percentage: prev?.percentage ?? 0.0,
        checking: prev?.checking,
        scannedHeight: prev?.scannedHeight ?? 0,
        chainTipHeight: prev?.chainTipHeight ?? 0,
        transparentBalance: scopedPrev?.transparentBalance,
        saplingBalance: scopedPrev?.saplingBalance,
        orchardBalance: scopedPrev?.orchardBalance,
        ironwoodBalance: scopedPrev?.ironwoodBalance,
        orchardLockedBalance: scopedPrev?.orchardLockedBalance,
        transparentPendingBalance: scopedPrev?.transparentPendingBalance,
        transparentLockedBalance: scopedPrev?.transparentLockedBalance,
        transparentAuthority: scopedPrev?.transparentAuthority,
        transparentLastKnownBalance: scopedPrev?.transparentLastKnownBalance,
        transparentStop: scopedPrev?.transparentStop,
        transparentPrivate: scopedPrev?.transparentPrivate,
        saplingPendingBalance: scopedPrev?.saplingPendingBalance,
        orchardPendingBalance: scopedPrev?.orchardPendingBalance,
        ironwoodPendingBalance: scopedPrev?.ironwoodPendingBalance,
        canShieldTransparentBalance:
            scopedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: scopedPrev?.shieldTransparentFee,
        shieldTransparentAmount: scopedPrev?.shieldTransparentAmount,
        spendableBalance: scopedPrev?.spendableBalance,
        displaySpendableBalance: spendableDisplay.balance,
        displayIronwoodBalance: scopedPrev?.displayIronwoodBalance,
        displayIronwoodPendingBalance:
            scopedPrev?.displayIronwoodPendingBalance,
        displayOrchardBalance: scopedPrev?.displayOrchardBalance,
        displayOrchardPendingBalance: scopedPrev?.displayOrchardPendingBalance,
        displayOrchardLockedBalance: scopedPrev?.displayOrchardLockedBalance,
        displaySpendableFreshness: spendableDisplay.freshness,
        totalBalance: scopedPrev?.totalBalance,
        displayTotalBalance: scopedPrev?.displayTotalBalance,
        displayShieldedBalance: scopedPrev?.displayShieldedBalance,
        recentTransactions: scopedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: prev?.lastSyncStartedAt,
        lastSyncCompletedAt: prev?.lastSyncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
      ),
    );
  }

  WalletMutationSyncPause _walletMutationSyncPauseSnapshot() {
    return WalletMutationSyncPause(
      hadActiveSync: _isSyncing || rust_sync.isSyncRunning(),
      hadPolling: _pollTimer != null || _pollCheckInFlight,
      hadMempoolObserver: rust_sync.isMempoolObserverRunning(),
      resetEpoch: _walletResetEpoch,
    );
  }

  bool needsPauseForWalletMutation() =>
      _walletMutationSyncPauseSnapshot().hadWorkToPause ||
      _recoveryStatusReadCount > 0 ||
      _swapRecovery != null;

  void clearCachedWalletDbPath() {
    _cachedDbPath = null;
  }

  @visibleForTesting
  Future<String> resolveWalletDbPathForTesting() => _getDbPath();

  Future<rust_sync.EnhanceRecoveryStatus?> recoveryStatus() async {
    if (_requiresUnlock ||
        _getActiveAccountUuid() == null ||
        _walletMutationPauseCount > 0) {
      return null;
    }
    // Register before the first asynchronous step so account deletion/reset can
    // close admission and drain every reader before touching the wallet DB.
    _recoveryStatusReadCount++;
    try {
      final dbPath = await _getDbPath();
      if (_walletMutationPauseCount > 0) return null;
      return await rust_sync.getEnhanceRecoveryStatus(
        dbPath: dbPath,
        network: _endpointConfig.networkName,
      );
    } finally {
      _endTrackedWalletCall();
    }
  }

  /// Reads the wallet's saved swap recovery state without network access, or
  /// null without a wallet (see [_trackedWalletCall]). While a wallet mutation
  /// holds admission it throws rather than reporting idle state.
  Future<rust_swap.SwapRecoveryStatus?> swapRecoveryStatus() =>
      _trackedWalletCall(
        _existingWalletDbPathResolver,
        (path) => rust_swap.getSwapRecoveryStatus(
          dbPath: path,
          networkName: _endpointConfig.networkName,
        ),
      );

  /// Runs `call`, a native call on the wallet DB at the path `resolvePath`
  /// gives, or returns null when it gives none. Every native wallet call of the
  /// swap recovery code goes through here. It registers with the drain that
  /// wallet mutations wait on (see [pauseForWalletMutation]) before its first
  /// await, so deletion or reset can never remove the DB under it, and it
  /// throws a [StateError] instead of starting while a mutation holds
  /// admission.
  Future<T?> _trackedWalletCall<T>(
    Future<String?> Function() resolvePath,
    Future<T> Function(String path) call,
  ) async {
    const busy = 'The wallet is changing. Try again in a moment.';
    if (_walletMutationPauseCount > 0) throw StateError(busy);
    _recoveryStatusReadCount++;
    try {
      final path = await resolvePath();
      if (_walletMutationPauseCount > 0) throw StateError(busy);
      if (path == null) return null;
      return await call(path);
    } finally {
      _endTrackedWalletCall();
    }
  }

  /// Ends one registered wallet call and releases a drain waiting on the last
  /// one.
  void _endTrackedWalletCall() {
    _recoveryStatusReadCount--;
    if (_recoveryStatusReadCount == 0) {
      _recoveryStatusReadsDrained?.complete();
      _recoveryStatusReadsDrained = null;
    }
  }

  Future<void> _drainRecoveryStatusReads() {
    if (_recoveryStatusReadCount == 0) return Future.value();
    return (_recoveryStatusReadsDrained ??= Completer<void>()).future;
  }

  /// Exit a pause without resuming. Destructive callers use this when the
  /// wallet DB may already be gone, so it also discards any restart another
  /// pause deferred: nothing should sync a wallet that was just reset.
  ///
  /// That holds even when this is not the last pause to exit. The reset
  /// advances the epoch, so a pause taken before it (the recovery toggle,
  /// say) cannot restart sync from its pre-reset snapshot when it exits
  /// later. A start requested after the reset — a new wallet's first sync —
  /// is still deferred to the last exit as usual.
  void endWalletMutationPause() {
    _walletResetEpoch++;
    _swapRecoveryRefreshOwed = false;
    // A late round of the old wallet changes nothing.
    _swapRecoveryGeneration++;
    _swapRecoveryWorkDue = false;
    _swapFilterScanned = null;
    // The applied policy belonged to the wallet just reset; a replacement
    // wallet reports its own.
    _appliedTransparentPolicy = null;
    _pendingMutationRestartSync = false;
    _pendingMutationRestartPolling = false;
    _endWalletMutationPause(resume: false);
  }

  void _endWalletMutationPause({required bool resume}) {
    if (_walletMutationPauseCount > 0) {
      _walletMutationPauseCount--;
    }
    // Another wallet mutation still owns the DB — account deletion or a reset
    // is mid-flight. Restarting here would open and write the wallet DB
    // underneath it, so hand the restart to whichever pause exits last.
    if (_walletMutationPauseCount > 0) return;
    final restartSync = resume && _pendingMutationRestartSync;
    final restartPolling = resume && _pendingMutationRestartPolling;
    // A configuration fetch can finish after mobile hides. Keep its restart
    // pending until resume instead of starting foreground work while hidden.
    // Locked wallets still discard the request below, as before.
    if ((restartSync || restartPolling) &&
        !_requiresUnlock &&
        !canRunAppProcessWork(isInForeground: _isInForeground)) {
      return;
    }
    _pendingMutationRestartSync = false;
    _pendingMutationRestartPolling = false;
    // Check nothing else when there is nothing to restart: the opt-out exit
    // runs after a wallet reset, where reading providers is unsafe.
    if (!restartSync && !restartPolling) return;
    if (_requiresUnlock) return;
    if (restartSync) {
      log('SyncNotifier: resuming sync and mempool observation after pause');
      startSync();
    }
    if (restartPolling) {
      _startPolling();
    }
  }

  Future<void> withRecoverySettingPaused(Future<void> Function() action) async {
    if (_recoverySettingTransition) {
      throw StateError('Setting transition already running.');
    }
    _recoverySettingTransition = true;
    await IronwoodMigrationBackgroundLifecycle.runWithNewQuiescenceLease(
      () async {
        final lifecycle = _recoveryLifecycle;
        WalletMutationSyncPause? pause;
        try {
          await waitForRecoveryQuiescence(
            lifecycle.quiesce(),
            timeout: _recoveryTransitionTimeout,
          );
          pause = await pauseForWalletMutation();
          await action();
        } finally {
          try {
            await lifecycle.resumeAfterMutation().timeout(
              _recoveryTransitionTimeout,
            );
          } catch (error) {
            log('Could not resume native preparation: $error');
          }
          // The toggle changes which obligations are retryable at all, so
          // the previous attempt's backoff no longer describes this wallet.
          _recoveryRestartGate.reset();
          // Release only a pause this transition actually took. `quiesce()`
          // can fail before one exists, and a `pauseForWalletMutation` that
          // throws has already released its own. Decrementing the shared
          // counter here would consume an overlapping account deletion's
          // pause and start sync while it is still deleting.
          //
          // The transition guard is dropped only now, after native resume has
          // settled or timed out, so nothing can start sync in between. The
          // pause check in `startSync` still covers an overlapping deletion.
          _recoverySettingTransition = false;
          final acquired = pause;
          if (acquired != null) {
            resumeAfterWalletMutation(
              acquired,
              forceRestart:
                  !_requiresUnlock &&
                  _isInForeground &&
                  (ref.read(accountProvider).value?.hasAccounts ?? false),
            );
          }
        }
      },
    );
  }

  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    _walletMutationPauseCount++;
    final pause = _walletMutationSyncPauseSnapshot();

    try {
      await _stopSwapRecovery();
      if (pause.hadWorkToPause) {
        // The pause records whether to restart; a start queued behind the
        // stopped sync would otherwise outlive it.
        _queuedSyncStart = null;
        ++_syncGen;
        ++_progressEventVersion;
        ++_balanceReadVersion;
        _stopPolling();
        await onStoppingSync?.call();
        log('SyncNotifier: pausing sync for wallet DB mutation');
        _isSyncing = false;
        rust_sync.setSyncMode(mode: 0);
        rust_sync.cancelFullSync();
        _stopMempoolObserver();
        await _syncSub?.cancel();
        _syncSub = null;

        final prev = state.value;
        if (prev != null) {
          state = AsyncData(prev.withSyncActivityStopped());
        }

        final stopped = await _waitForRustTasksToStop(
          timeoutMs: 120000,
          onSyncTimeout:
              'SyncNotifier: timed out waiting for Rust sync to stop before '
              'wallet mutation',
          onMempoolTimeout:
              'SyncNotifier: timed out waiting for mempool observer to stop '
              'before wallet mutation',
        );
        if (!stopped) {
          throw StateError(
            'Sync did not stop before wallet database mutation.',
          );
        }
      }

      await _drainRecoveryStatusReads().timeout(_recoveryTransitionTimeout);
      return pause;
    } catch (_) {
      resumeAfterWalletMutation(pause);
      rethrow;
    }
  }

  /// [forceRestart] resumes sync and polling regardless of what the pause
  /// snapshot captured — the recovery toggle stops sync itself, so it must
  /// bring it back even when nothing was running when it took the pause.
  /// Mobile defers that request while hidden and consumes it on resume;
  /// locking or resetting the wallet discards the deferred request.
  ///
  /// A pause that outlived a wallet reset contributes neither its snapshot
  /// nor [forceRestart]: both describe the deleted wallet. It only releases
  /// its count, which still fires any start requested after the reset.
  void resumeAfterWalletMutation(
    WalletMutationSyncPause pause, {
    bool forceRestart = false,
  }) {
    if (pause.resetEpoch != _walletResetEpoch) {
      _endWalletMutationPause(resume: true);
      return;
    }
    _pendingMutationRestartSync |=
        forceRestart || pause.hadActiveSync || pause.hadMempoolObserver;
    _pendingMutationRestartPolling |=
        forceRestart || pause.hadPolling || pause.hadActiveSync;
    _endWalletMutationPause(resume: true);
  }

  Future<void> clearSensitiveStateForLock() async {
    // A public details load the user started stores nothing after a lock.
    ref.read(publicDetailsLoadsProvider).cancel();
    _resumeTipCheckPending = false;
    _queuedSyncStart = null;
    ref.read(pendingActivityEvidenceProvider.notifier).clear();
    _recoveryRestartGate.reset();
    _pendingMutationRestartSync = false;
    _pendingMutationRestartPolling = false;
    _syncStartDeferred = false;
    _deferredSyncLatestTipHeight = null;
    ++_syncGen;
    ++_sensitiveStateEpoch;
    ++_progressEventVersion;
    ++_balanceReadVersion;
    _isSyncing = false;
    _stopPolling();
    _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
    _mempoolRefreshInFlight = false;
    _mempoolRefreshQueued = false;
    // Drop any queued follow-up. Leave `_balanceRefreshInFlight` to the
    // running pass's `finally` so a new pass cannot start alongside it.
    _balanceRefreshQueued = false;
    _balanceRefreshQueuedReleaseSnapshot = false;
    _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable = false;
    _balanceRefreshQueuedRequireAuthoritativeBalance = false;
    _lastKnownByAccount.clear();
    final cacheStore = ref.read(walletBalanceCacheProvider);
    final cacheDrained = cacheStore.suspendAndDrain();
    state = AsyncData(SyncState());

    // Sign-out should cancel the current Rust run immediately so unlock
    // cannot race with a still-running old sync.
    rust_sync.setSyncMode(mode: 0);
    rust_sync.cancelFullSync();

    await _stopSwapRecovery();
    await cacheDrained;
    cacheStore.resume();
    await _waitForRustTasksToStop(
      timeoutMs: 5000,
      onSyncTimeout:
          'SyncNotifier: timed out waiting for Rust sync to stop during sign-out',
      onMempoolTimeout:
          'SyncNotifier: timed out waiting for mempool observer to stop during '
          'sign-out',
    );
  }

  /// Cancels the current sync (if any), waits for the Rust loop to
  /// finish its teardown so `isSyncRunning()` returns `false`, then
  /// starts a fresh sync and restarts the polling loop. This is the
  /// right entry point for settings that change the underlying
  /// transport (e.g. the Tor toggle) and need the next run to use
  /// the new value — a plain `stopSync()` alone leaves the wallet
  /// silent for the rest of the session if the toggle fires while
  /// sync is already idle.
  Future<void> restartSync() async {
    await restartSyncAfterTransportChange(
      () async {},
      failIfNotQuiescent: false,
    );
  }

  /// Quiesces every Rust network lane, applies one transport change, then
  /// starts sync and polling again. The callback runs only after existing
  /// direct or Tor channels have been asked to stop, which prevents a runtime
  /// route toggle from overlapping a newly configured connection.
  ///
  /// [failIfNotQuiescent] belongs to the route change alone: switching to Tor
  /// while a direct channel is still up would leak, so that caller must fail
  /// loudly. Callers that only want a fresh sync on the same transport
  /// (endpoint changes, post-broadcast refreshes) keep the older behaviour of
  /// starting anyway, because aborting there would leave the wallet with no
  /// sync and no polling for the rest of the session.
  Future<void> restartSyncAfterTransportChange(
    Future<void> Function() updateTransport, {
    bool failIfNotQuiescent = true,
  }) async {
    _swapRecoveryTransitions++;
    try {
      await _stopSwapRecovery();
      await _restartSyncWithTransport(
        updateTransport,
        failIfNotQuiescent: failIfNotQuiescent,
      );
    } finally {
      _swapRecoveryTransitions--;
    }
  }

  /// The body of [restartSyncAfterTransportChange], run once swap recovery has
  /// stopped and is held off.
  Future<void> _restartSyncWithTransport(
    Future<void> Function() updateTransport, {
    required bool failIfNotQuiescent,
  }) async {
    ++_syncGen;
    ++_progressEventVersion;
    ++_balanceReadVersion;
    rust_sync.cancelFullSync();
    await _syncSub?.cancel();
    _syncSub = null;
    _stopMempoolObserver();
    _isSyncing = false;
    _stopPolling();
    final prev = state.value;
    if (prev != null) {
      state = AsyncData(prev.withSyncActivityStopped());
    }
    // `cancelFullSync` / `stopMempoolObserver` set atomics that
    // the Rust loop and the mempool observer check at their own
    // cadence (batch boundaries for sync, the 100ms cancel-aware
    // sleep for the observer), so they take up to one batch /
    // one message worth of work to actually stop. We must wait
    // for BOTH of them to clear before starting a fresh session:
    //
    //   * `isSyncRunning()` — the next `startFullSync` will
    //     reject until the old single-run lock drops.
    //   * `isMempoolObserverRunning()` — the next
    //     `_startMempoolObserver` will log "already running" and
    //     skip without retry if the old observer is still
    //     winding down. Without waiting here the new sync
    //     session would silently lose mempool streaming for
    //     its entire run (Codex adversarial-review finding 1).
    //
    // 5s ceiling matches the original `restartSync` behaviour
    // and the `_resetWallet` path in `home_screen.dart`. Neither
    // the sync loop's post-batch cancel check nor the observer's
    // 100ms cancel slice should take anywhere near that long,
    // but a network stall mid-broadcast can extend it.
    final stopped = await _waitForRustTasksToStop(
      timeoutMs: 5000,
      onSyncTimeout: failIfNotQuiescent
          ? 'SyncNotifier: restartSync timed out waiting for Rust sync loop to '
                'stop after 5s; transport change blocked'
          : 'SyncNotifier: restartSync timed out waiting for Rust sync loop to '
                'stop after 5s; starting anyway (the startSync guard will log '
                'if the old run is still around)',
      onMempoolTimeout: failIfNotQuiescent
          ? 'SyncNotifier: restartSync timed out waiting for mempool observer '
                'to stop after 5s; transport change blocked'
          : 'SyncNotifier: restartSync timed out waiting for mempool observer '
                'to stop after 5s; the new observer start will skip and the '
                'new session runs without streaming',
    );
    if (shouldAbortRestartForBusyNetwork(
      quiescent: stopped,
      changesTransport: failIfNotQuiescent,
    )) {
      throw StateError(
        'Network tasks did not stop before the transport change. Direct '
        'traffic remains blocked; retry the Tor setting after sync stops.',
      );
    }
    await updateTransport();
    // Welcome can change Tor before a wallet exists. The transport is ready,
    // but there is no account to sync or poll yet.
    if (_getActiveAccountUuid() == null) return;
    startSync();
    _startPolling();
  }

  // ======================== Polling ========================

  bool _privateStatusCoverageNeedsSettings() {
    final failure = state.value?.failure;
    if (failure?.kind != SyncFailureKind.privateStatusCoverage) return false;
    return shouldPauseSyncForPrivateStatusCoverage(
      failure: failure,
      privateQueriesEnabled: ref.read(enhancePirProvider),
    );
  }

  void _handleAppResume() {
    if (_isShuttingDown) return;
    _isInForeground = true;
    ref.read(pendingActivityEvidenceProvider.notifier).setForeground(true);
    // A resume is public: the recovery restart schedule starts over. A swap
    // recovery round is owed, which the tip check below starts at the tip or
    // leaves to the sync it starts.
    _recoveryRestartGate.reset();
    _oweSwapRecovery(run: false);
    // Consume a restart deferred by a mutation that finished while hidden.
    // An ongoing mutation keeps ownership until its own last pause exits.
    if (_walletMutationPauseCount == 0 &&
        (_pendingMutationRestartSync || _pendingMutationRestartPolling)) {
      _endWalletMutationPause(resume: true);
    }
    unawaited(_refreshBalanceAfterResume());
    unawaited(_refreshOwedSwapRecovery());
    // Coalesce repeated focus/resume events. An old mobile check spanning
    // backgrounding cannot certify foreground freshness; follow it immediately.
    _resumeTipCheckPending = true;
    unawaited(_checkAndSync());
  }

  void _handleAppHide() {
    _isInForeground = false;
    ref.read(pendingActivityEvidenceProvider.notifier).setForeground(false);
    ++_foregroundEpoch;
    if (!canRunAppProcessWork(isInForeground: _isInForeground)) {
      _cancelSwapRecoveryRound();
      _stopPolling();
      _queuedSyncStart = null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_isShuttingDown) return;
    if (_privateStatusCoverageNeedsSettings()) {
      _pollTimer = null;
      return;
    }
    if (!canRunAppProcessWork(isInForeground: _isInForeground)) return;
    if (_resumeTipCheckPending &&
        !_pollCheckInFlight &&
        !_isSyncing &&
        !_requiresUnlock &&
        (ref.read(accountProvider).value?.hasAccounts ?? false)) {
      unawaited(_checkAndSync());
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        await _checkAndSync();
      } catch (e) {
        log('AutoSync: polling error: $e');
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkAndSync() async {
    if (_isShuttingDown) return;
    if (_recoverySettingTransition || _walletMutationPauseCount > 0) return;
    if (_privateStatusCoverageNeedsSettings()) {
      _stopPolling();
      return;
    }
    final gen = _syncGen;
    final epoch = _sensitiveStateEpoch;
    final foregroundEpoch = _foregroundEpoch;
    final hasAccounts = ref.read(accountProvider).value?.hasAccounts ?? false;
    if (_pollCheckInFlight ||
        _isSyncing ||
        _requiresUnlock ||
        !canRunAppProcessWork(isInForeground: _isInForeground) ||
        !hasAccounts) {
      return;
    }
    _pollCheckInFlight = true;
    _resumeTipCheckPending = false;
    _stopPolling();
    try {
      final tip = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .getLatestBlockHeight();
      await ref.read(chainUpgradeStatusProvider.notifier).refreshAtTip(tip);
      final current = state.value;
      final lastSynced = current?.chainTipHeight ?? 0;
      final syncComplete = current?.isSyncComplete ?? false;
      if (gen != _syncGen || epoch != _sensitiveStateEpoch || _requiresUnlock) {
        log('AutoSync: skipping restart after lock transition');
        return;
      }
      if (canRunAppProcessWork(isInForeground: false) ||
          (foregroundEpoch == _foregroundEpoch && _isInForeground)) {
        _resumeTipCheckPending = false;
        ref
            .read(pendingActivityEvidenceProvider.notifier)
            .networkChecked(
              tip.toInt(),
              allowBackground: canRunAppProcessWork(isInForeground: false),
            );
      }
      // A new chain tip is public: the restart schedule starts over.
      if (tip.toInt() > lastSynced) _recoveryRestartGate.reset();
      // Skip the status read entirely when the tip or an incomplete previous
      // sync already calls for a restart: that sync runs recovery anyway.
      var recoveryRestart = false;
      if (!shouldStartSyncForPolledTip(current, tip.toInt()) &&
          ref.read(enhancePirProvider)) {
        final recovery = await recoveryStatus();
        if (_recoverySettingTransition ||
            _requiresUnlock ||
            gen != _syncGen ||
            epoch != _sensitiveStateEpoch) {
          return;
        }
        // A null status means the read bailed out — locked, no active
        // account, or a wallet mutation pause — not that the queue drained.
        // Leave the gate's deadline alone rather than clearing it.
        recoveryRestart =
            recovery != null &&
            shouldRestartRecovery(recovery, _recoveryRestartGate);
      }
      if (shouldStartSyncForPolledTip(
        current,
        tip.toInt(),
        hasActiveRecovery: recoveryRestart,
      )) {
        log(
          'AutoSync: needs sync (tip=$tip, last=$lastSynced, complete=$syncComplete)',
        );
        startSync(latestTipHeight: tip.toInt());
      } else {
        _runOwedSwapRecovery(atTip: true);
      }
    } catch (e) {
      if (ref.mounted && gen == _syncGen && epoch == _sensitiveStateEpoch) {
        final kind = classifySyncFailure(e).kind;
        ref
            .read(pendingActivityEvidenceProvider.notifier)
            .invalidateNetwork(
              connectionFailed:
                  kind == SyncFailureKind.network ||
                  kind == SyncFailureKind.torUnavailable,
            );
      }
      log('AutoSync: tip check failed: $e');
    } finally {
      _pollCheckInFlight = false;
    }
    if (gen != _syncGen || _requiresUnlock) {
      return;
    }
    _startPolling();
  }

  Future<bool> _waitForRustTasksToStop({
    required int timeoutMs,
    required String onSyncTimeout,
    required String onMempoolTimeout,
  }) async {
    var waited = 0;
    while ((rust_sync.isSyncRunning() ||
            rust_sync.isMempoolObserverRunning()) &&
        waited < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    final syncRunning = rust_sync.isSyncRunning();
    final mempoolRunning = rust_sync.isMempoolObserverRunning();
    if (syncRunning) {
      log(onSyncTimeout);
    }
    if (mempoolRunning) {
      log(onMempoolTimeout);
    }
    return !syncRunning && !mempoolRunning;
  }

  // ======================== Mempool Observer ========================

  /// Fire up the Rust mempool observer for this sync session.
  ///
  /// Runs in parallel with the scan loop — matches
  /// zcash-android-wallet-sdk's `startObservingMempool` coroutine.
  /// The Rust side has its own reconnect loop with 1s / 30s
  /// backoff, so the Dart side only needs to:
  ///
  ///   1. Subscribe to the emitted stream.
  ///   2. On each `matched=true` event for the active account, trigger
  ///      the same balance refresh path sync uses for `hasNewTx`
  ///      events. Already-known outbound txs refresh as before; new
  ///      inbound shielded txs are first stored by Rust as unmined
  ///      wallet transactions.
  ///   3. Skip refresh for inactive-account events. The wallet-wide
  ///      observer has already stored the tx, so switching accounts can
  ///      surface it through the normal account-scoped history read.
  ///
  /// Reuses [_mempoolSub] as the single subscription handle. The
  /// `startMempoolObserver` FRB call is guarded on the Rust side
  /// by the MEMPOOL_RUNNING atomic, so a double-call just logs
  /// and returns an error; we catch and ignore it.
  void _startMempoolObserver(String dbPath, RpcEndpointConfig endpoint) {
    if (_isShuttingDown) return;
    if (rust_sync.isMempoolObserverRunning()) {
      // Already up — happens if startSync fires while a previous
      // observer is still winding down. The Rust side will
      // reject the second start, so skip rather than racing it.
      log('Mempool: observer already running, skipping start');
      return;
    }
    _mempoolSub?.cancel();
    final evidenceEpoch = ++_mempoolEvidenceEpoch;
    final stream = rust_sync.startMempoolObserver(
      dbPath: dbPath,
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
    );
    _mempoolSub = stream.listen(
      (event) {
        if (evidenceEpoch != _mempoolEvidenceEpoch ||
            _requiresUnlock ||
            _isShuttingDown ||
            !ref.mounted) {
          return;
        }
        if (!event.matched) return;
        final activeAccountUuid = _getActiveAccountUuid();
        final scopes = event.accountUuids.isEmpty
            ? [?activeAccountUuid]
            : event.accountUuids;
        for (final accountUuid in scopes) {
          ref
              .read(pendingActivityEvidenceProvider.notifier)
              .observe(accountUuid: accountUuid, txids: [event.txidHex]);
        }
        // Empty account scope means Rust knows the tx is wallet-relevant,
        // but cannot narrow it to an account yet; preserve the legacy
        // active-account refresh behavior in that case.
        if (event.accountUuids.isNotEmpty &&
            !event.accountUuids.contains(activeAccountUuid)) {
          log(
            'Mempool: matched ${event.txidHex} for inactive account, skipping active refresh',
          );
          return;
        }
        log('Mempool: matched ${event.txidHex}, refreshing balance');
        _scheduleMempoolRefresh();
        // The store commit can land in the account-scoped history view
        // a beat after the event arrives; delayed follow-ups close that
        // race (no-ops when the first refresh already saw it).
        // ref.mounted: the notifier can be disposed with these timers
        // pending (bootstrap reload swaps the ProviderScope).
        Timer(const Duration(seconds: 2), () {
          if (ref.mounted && !_requiresUnlock) _scheduleMempoolRefresh();
        });
        Timer(const Duration(seconds: 6), () {
          if (ref.mounted && !_requiresUnlock) _scheduleMempoolRefresh();
        });
      },
      onDone: () {
        log('Mempool: stream ended');
        _mempoolSub = null;
      },
      onError: (e) {
        // Observer-side errors are logged from the Rust side in
        // detail; here we just track that the Dart subscription
        // closed so a restart at the next startSync is safe.
        log('Mempool: stream error: $e');
        _mempoolSub = null;
      },
    );
  }

  void _scheduleMempoolRefresh() {
    if (_mempoolRefreshInFlight) {
      _mempoolRefreshQueued = true;
      return;
    }

    _mempoolRefreshInFlight = true;
    unawaited(_runMempoolRefreshLoop());
  }

  Future<void> _runMempoolRefreshLoop() async {
    try {
      do {
        _mempoolRefreshQueued = false;
        try {
          await _requestBalanceRefresh();
        } catch (e, st) {
          log('Mempool: refresh failed: $e\n$st');
        }
      } while (_mempoolRefreshQueued && !_requiresUnlock);
    } finally {
      _mempoolRefreshInFlight = false;
      _mempoolRefreshQueued = false;
    }
  }

  /// Cancel the running mempool observer (if any) and tear down
  /// the Dart subscription. Symmetric with [_startMempoolObserver]
  /// and called from [stopSync] as well as on dispose.
  void _stopMempoolObserver() {
    ++_mempoolEvidenceEpoch;
    ref.read(pendingActivityEvidenceProvider.notifier).invalidateNetwork();
    if (rust_sync.isMempoolObserverRunning()) {
      rust_sync.stopMempoolObserver();
    }
    _mempoolSub?.cancel();
    _mempoolSub = null;
  }

  double _clampProgress(double value) => value.clamp(0.0, 1.0).toDouble();

  // ======================== Progress Handling ========================

  /// A post-sync follow-up changed wallet data after this sync completed:
  /// open receipts and Activity feeds reload, and balances and recent history
  /// are re-read. The sync is not completed again.
  Future<void> _onSyncFollowupUpdated() async {
    if (!ref.mounted || _requiresUnlock) return;
    _swapRecoveryRefreshOwed = false;
    ref.read(syncFollowupProvider.notifier).updated();
    // Let the completion's own reads land first, so this refresh does not
    // supersede them.
    try {
      await _lastForegroundProgressHandling;
    } catch (_) {
      // The stream listener logs it.
    }
    if (!ref.mounted || _requiresUnlock) return;
    try {
      await _requestBalanceRefresh();
    } catch (e, st) {
      log('SyncNotifier: follow-up refresh failed: $e\n$st');
    }
  }

  Future<void> _onSyncProgress(SyncProgressEvent event) async {
    if (!ref.mounted || _requiresUnlock) {
      return;
    }
    final progressEventVersion = ++_progressEventVersion;
    final epoch = _sensitiveStateEpoch;
    if (event.scannedHeight != _lastLoggedHeight) {
      log(
        'Sync: ${(event.percentage * 100).toStringAsFixed(1)}% (${event.scannedHeight}/${event.chainTipHeight})',
      );
      _lastLoggedHeight = event.scannedHeight;
    }

    final prev = state.value;
    final dbPath = await _getDbPath();
    if (!ref.mounted) return;
    final network = _endpointConfig.networkName;
    final accountUuid = _getActiveAccountUuid();
    if (accountUuid == null) {
      log('SyncNotifier: no active account, skipping refresh');
      return;
    }
    final scopedPrev = _previousScopedState(prev, accountUuid);

    // Only fetch balance/history when there are new transactions or sync is complete.
    // Skipping intermediate batches avoids opening a new DB connection per batch.
    BigInt? transparent;
    BigInt? sapling;
    BigInt? orchard;
    BigInt? ironwood;
    BigInt? orchardLocked;
    BigInt? transparentPending;
    BigInt? transparentLocked;
    rust_sync.TransparentBalanceAuthority? transparentAuthority;
    BigInt? transparentLastKnown;
    rust_sync.TransparentStopReason? transparentStop;
    bool? transparentPrivate;
    BigInt? saplingPending;
    BigInt? orchardPending;
    BigInt? ironwoodPending;
    BigInt? spendable;
    BigInt? total;
    bool? canShieldTransparentBalance;
    BigInt? shieldTransparentFee;
    BigInt? shieldTransparentAmount;
    rust_sync.WalletBalance? fetchedBalance;
    var hasAuthoritativeBalance = false;
    var didFetchRecentTxs = false;
    int? balanceReadVersion;
    var recentTxs =
        scopedPrev?.recentTransactions ?? const <rust_sync.TransactionInfo>[];
    if (event.hasNewTx || event.isComplete) {
      balanceReadVersion = ++_balanceReadVersion;
      try {
        final balance = await readWalletBalance(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
        if (balance.availability ==
            rust_sync.WalletBalanceAvailability.available) {
          fetchedBalance = balance;
          transparent = balance.transparent;
          sapling = balance.sapling;
          orchard = balance.orchard;
          ironwood = balance.ironwood;
          orchardLocked = balance.orchardLocked;
          transparentPending = balance.transparentPending;
          transparentLocked = balance.transparentLocked;
          transparentAuthority = balance.transparentAuthority;
          transparentLastKnown = balance.transparentLastKnown;
          transparentStop = balance.transparentStop;
          transparentPrivate = balance.transparentPrivate;
          saplingPending = balance.saplingPending;
          orchardPending = balance.orchardPending;
          ironwoodPending = balance.ironwoodPending;
          spendable = balance.spendable;
          total = balance.total;
          hasAuthoritativeBalance = true;
          _logSpendableDropBreakdown(balance, scopedPrev);
        } else {
          _logUnavailableBalance(balance.availability, accountUuid);
        }
      } catch (e) {
        log('SyncNotifier: balance fetch failed: $e');
      }
      if (!ref.mounted) return;
      try {
        recentTxs = await readTransactionHistory(
          dbPath: dbPath,
          network: network,
          limit: 10,
          accountUuid: accountUuid,
        );
        didFetchRecentTxs = true;
      } catch (e) {
        log('SyncNotifier: tx history fetch failed: $e');
      }
      if (!ref.mounted) return;
      final shieldStatus = await _getShieldTransparentStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        transparentBalance:
            transparent ?? scopedPrev?.transparentBalance ?? BigInt.zero,
      );
      if (shieldStatus != null) {
        canShieldTransparentBalance = shieldStatus.canShield;
        shieldTransparentFee = shieldStatus.fee;
        shieldTransparentAmount = shieldStatus.amount;
      }
    }

    if (!ref.mounted || epoch != _sensitiveStateEpoch || _requiresUnlock) {
      log(
        'SyncNotifier: discarding sync progress update after lock transition',
      );
      return;
    }
    final stateAccountUuid = _getActiveAccountUuid();
    final useFetchedAccountData = accountUuid == stateAccountUuid;
    final balanceReadIsCurrent =
        balanceReadVersion == null || balanceReadVersion == _balanceReadVersion;
    final useFetchedBalance =
        useFetchedAccountData &&
        hasAuthoritativeBalance &&
        balanceReadIsCurrent;
    final useFetchedRecentTxs =
        useFetchedAccountData && didFetchRecentTxs && balanceReadIsCurrent;
    // A stream error can be recorded while this handler awaits DB reads. Its
    // stopped failure state must win over this older progress event.
    final currentState = state.value;
    final failureRecordedWhileAwaiting =
        currentState?.failure != null &&
        (!identical(currentState?.failure, prev?.failure) ||
            currentState?.lastSyncFailedAt != prev?.lastSyncFailedAt);
    if (progressEventVersion != _progressEventVersion ||
        failureRecordedWhileAwaiting) {
      _mergeFetchedAccountDataIntoLatestState(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        balance: useFetchedBalance ? fetchedBalance : null,
        recentTransactions: useFetchedRecentTxs ? recentTxs : null,
        canShieldTransparentBalance: canShieldTransparentBalance,
        shieldTransparentFee: shieldTransparentFee,
        shieldTransparentAmount: shieldTransparentAmount,
      );
      log(
        'SyncNotifier: discarded stale progress metadata'
        '${useFetchedBalance || useFetchedRecentTxs ? ', kept account data' : ''}',
      );
      return;
    }
    if ((event.hasNewTx || event.isComplete) &&
        useFetchedAccountData &&
        balanceReadIsCurrent) {
      ref
          .read(pendingActivityEvidenceProvider.notifier)
          .historyReadCompleted(accountUuid, available: didFetchRecentTxs);
    }
    if (useFetchedBalance) {
      ++_authoritativeBalanceVersion;
      _persistBalanceSnapshot(
        dbPath,
        network,
        accountUuid,
        fetchedBalance!,
        syncComplete: event.isComplete,
      );
    }
    final stateScopedPrev = _previousScopedState(
      currentState,
      stateAccountUuid,
    );
    final hasBalanceData =
        useFetchedBalance || (stateScopedPrev?.hasBalanceData ?? false);
    final hasRecentTransactionsData =
        useFetchedRecentTxs ||
        (stateScopedPrev?.hasRecentTransactionsData ?? false);
    if (!useFetchedAccountData) {
      log(
        'SyncNotifier: discarding account-scoped sync data after account transition',
      );
    }

    final syncStartedAt =
        prev?.lastSyncStartedAt ??
        (event.isSyncing || event.isComplete ? DateTime.now() : null);
    final syncCompletedAt = event.isComplete
        ? DateTime.now()
        : prev?.lastSyncCompletedAt;
    final isPreparationEvent = isSyncPreparationPhase(event.phase);
    final eventPercentage = _clampProgress(event.percentage);
    final actualPercentage = isPreparationEvent
        ? math.max(currentState?.percentage ?? 0, eventPercentage)
        : eventPercentage;
    final nextScannedHeight = isPreparationEvent
        ? currentState?.scannedHeight ?? event.scannedHeight
        : event.scannedHeight;
    final nextChainTipHeight = isPreparationEvent
        ? math.max(currentState?.chainTipHeight ?? 0, event.chainTipHeight)
        : event.chainTipHeight;
    // An amount carried without a fresh read past a tip the sync just moved
    // follows the carry rule; see [SyncState.carryingTransparentAuthority].
    final carriedPrev =
        useFetchedBalance ||
            stateScopedPrev == null ||
            nextChainTipHeight == stateScopedPrev.chainTipHeight
        ? stateScopedPrev
        : stateScopedPrev.carryingTransparentAuthority(
            privatePolicyMayApply: _privatePolicyMayApply,
            crossesTip: true,
          );
    final nextSpendableBalance = useFetchedBalance
        ? spendable ?? stateScopedPrev?.spendableBalance ?? BigInt.zero
        : stateScopedPrev?.spendableBalance ?? BigInt.zero;
    final spendableDisplay = SyncState.resolveSpendableDisplay(
      previous: stateScopedPrev,
      authoritativeSpendable: nextSpendableBalance,
      hasAuthoritativeBalance: useFetchedBalance,
      syncComplete: event.isComplete,
    );
    final preservePoolDisplay =
        spendableDisplay.freshness ==
        SpendableBalanceFreshness.lastCompletedSync;

    state = AsyncData(
      SyncState(
        accountUuid: stateAccountUuid,
        hasBalanceData: hasBalanceData,
        hasCachedBalance:
            !useFetchedBalance && (stateScopedPrev?.hasCachedBalance ?? false),
        hasRecentTransactionsData: hasRecentTransactionsData,
        hasRecentTransactionsError:
            !useFetchedRecentTxs &&
            (stateScopedPrev?.hasRecentTransactionsError ?? false),
        isSyncing: event.isSyncing && !event.isComplete,
        isBackgroundMode: false,
        isSyncComplete: event.isComplete,
        percentage: actualPercentage,
        displayTargetPercentage: isPreparationEvent
            ? currentState?.displayTargetPercentage ?? actualPercentage
            : event.displayTargetPercentage,
        checking: event.isComplete ? null : event.checking,
        displayTargetBlocks: isPreparationEvent && event.checking == null
            ? currentState?.displayTargetBlocks ?? 0
            : event.displayTargetBlocks,
        // Preparation on a retry invalidates the previous queue snapshot.
        remainingScanBlocks: event.remainingScanBlocks,
        pendingScanStartHeight: event.pendingScanStartHeight,
        phaseCompletedUnits: event.phaseCompletedUnits,
        phaseTotalUnits: event.phaseTotalUnits,
        scannedHeight: nextScannedHeight,
        chainTipHeight: nextChainTipHeight,
        transparentBalance: useFetchedBalance
            ? transparent
            : carriedPrev?.transparentBalance,
        saplingBalance: useFetchedBalance
            ? sapling
            : carriedPrev?.saplingBalance,
        orchardBalance: useFetchedBalance
            ? orchard
            : carriedPrev?.orchardBalance,
        ironwoodBalance: useFetchedBalance
            ? ironwood
            : carriedPrev?.ironwoodBalance,
        orchardLockedBalance: useFetchedBalance
            ? orchardLocked
            : carriedPrev?.orchardLockedBalance,
        transparentPendingBalance: useFetchedBalance
            ? transparentPending
            : carriedPrev?.transparentPendingBalance,
        transparentLockedBalance: useFetchedBalance
            ? transparentLocked
            : carriedPrev?.transparentLockedBalance,
        transparentAuthority: useFetchedBalance
            ? transparentAuthority
            : carriedPrev?.transparentAuthority,
        transparentLastKnownBalance: useFetchedBalance
            ? transparentLastKnown
            : carriedPrev?.transparentLastKnownBalance,
        transparentStop: useFetchedBalance
            ? transparentStop
            : carriedPrev?.transparentStop,
        transparentPrivate: useFetchedBalance
            ? transparentPrivate
            : carriedPrev?.transparentPrivate,
        saplingPendingBalance: useFetchedBalance
            ? saplingPending
            : carriedPrev?.saplingPendingBalance,
        orchardPendingBalance: useFetchedBalance
            ? orchardPending
            : carriedPrev?.orchardPendingBalance,
        ironwoodPendingBalance: useFetchedBalance
            ? ironwoodPending
            : carriedPrev?.ironwoodPendingBalance,
        canShieldTransparentBalance: useFetchedBalance
            ? canShieldTransparentBalance ??
                  carriedPrev?.canShieldTransparentBalance ??
                  false
            : carriedPrev?.canShieldTransparentBalance ?? false,
        shieldTransparentFee: useFetchedBalance
            ? shieldTransparentFee ?? carriedPrev?.shieldTransparentFee
            : carriedPrev?.shieldTransparentFee,
        shieldTransparentAmount: useFetchedBalance
            ? shieldTransparentAmount ?? carriedPrev?.shieldTransparentAmount
            : carriedPrev?.shieldTransparentAmount,
        spendableBalance: nextSpendableBalance,
        displaySpendableBalance: spendableDisplay.balance,
        displayIronwoodBalance: preservePoolDisplay
            ? carriedPrev?.displayIronwoodBalance
            : useFetchedBalance
            ? ironwood
            : carriedPrev?.ironwoodBalance,
        displayIronwoodPendingBalance: preservePoolDisplay
            ? carriedPrev?.displayIronwoodPendingBalance
            : useFetchedBalance
            ? ironwoodPending
            : carriedPrev?.ironwoodPendingBalance,
        displayOrchardBalance: preservePoolDisplay
            ? carriedPrev?.displayOrchardBalance
            : useFetchedBalance
            ? orchard
            : carriedPrev?.orchardBalance,
        displayOrchardPendingBalance: preservePoolDisplay
            ? carriedPrev?.displayOrchardPendingBalance
            : useFetchedBalance
            ? orchardPending
            : carriedPrev?.orchardPendingBalance,
        displayOrchardLockedBalance: preservePoolDisplay
            ? carriedPrev?.displayOrchardLockedBalance
            : useFetchedBalance
            ? orchardLocked
            : carriedPrev?.orchardLockedBalance,
        displaySpendableFreshness: spendableDisplay.freshness,
        totalBalance: useFetchedBalance ? total : carriedPrev?.totalBalance,
        displayTotalBalance: preservePoolDisplay
            ? carriedPrev?.displayTotalBalance
            : useFetchedBalance
            ? total
            : carriedPrev?.totalBalance,
        displayShieldedBalance: preservePoolDisplay
            ? carriedPrev?.displayShieldedBalance
            : useFetchedBalance
            ? (sapling ?? BigInt.zero) +
                  (orchard ?? BigInt.zero) +
                  (ironwood ?? BigInt.zero) +
                  (saplingPending ?? BigInt.zero) +
                  (orchardPending ?? BigInt.zero) +
                  (ironwoodPending ?? BigInt.zero)
            : carriedPrev?.displayShieldedBalance,
        recentTransactions: useFetchedRecentTxs
            ? recentTxs
            : carriedPrev?.recentTransactions ?? const [],
        lastSyncStartedAt: syncStartedAt,
        lastSyncCompletedAt: syncCompletedAt,
        lastSyncFailedAt: prev?.lastSyncFailedAt,
        phase: event.phase,
      ),
    );

    // Handle sync completion here (not in onDone) to avoid race with async state update.
    if (event.isComplete) {
      _isSyncing = false;
      _startPolling();
      if (!useFetchedBalance) {
        unawaited(_ensureAuthoritativeBalanceRecovery());
      }
    }
  }

  void _mergeFetchedAccountDataIntoLatestState({
    required String dbPath,
    required String network,
    required String accountUuid,
    rust_sync.WalletBalance? balance,
    List<rust_sync.TransactionInfo>? recentTransactions,
    bool? canShieldTransparentBalance,
    BigInt? shieldTransparentFee,
    BigInt? shieldTransparentAmount,
  }) {
    if (balance == null && recentTransactions == null) return;
    final current = _previousScopedState(state.value, accountUuid);
    if (current == null) return;

    final syncComplete = current.isSyncedToTip;
    if (balance != null) {
      ++_authoritativeBalanceVersion;
      _persistBalanceSnapshot(
        dbPath,
        network,
        accountUuid,
        balance,
        syncComplete: syncComplete,
      );
    }
    state = AsyncData(
      current.withFetchedAccountData(
        balance: balance,
        fetchedRecentTransactions: recentTransactions,
        canShieldTransparentBalance: canShieldTransparentBalance,
        shieldTransparentFee: shieldTransparentFee,
        shieldTransparentAmount: shieldTransparentAmount,
        syncComplete: syncComplete,
      ),
    );
  }

  // ======================== Balance Refresh ========================

  /// Public: refresh balance and recent transactions (e.g. after send).
  Future<void> refreshAfterSend() =>
      _requestBalanceRefresh(releaseSnapshotOnAuthoritativeBalance: true);

  /// Reconcile released inputs before a cancelled send can be retried.
  /// An outgoing account's locked snapshot must not be restored on switch-back.
  /// Never publish that account's balance over a different active account.
  Future<void> refreshAfterProposalRelease(String accountUuid) async {
    _lastKnownByAccount.remove(accountUuid);
    if (_requiresUnlock || _getActiveAccountUuid() != accountUuid) return;
    try {
      await _requestBalanceRefresh(
        releaseSnapshotOnAuthoritativeBalance: true,
        requireAuthoritativeBalance: true,
      );
    } finally {
      // A switch during the read may have cached the outgoing locked state.
      _lastKnownByAccount.remove(accountUuid);
    }
  }

  /// Reconciles the account selected by a switch or active-account removal.
  ///
  /// If its balance summary is temporarily unavailable, discard only the
  /// restored balance snapshot so it cannot remain visibly stale.
  Future<void> refreshAfterAccountSwitch() => _requestBalanceRefresh(
    releaseSnapshotOnAuthoritativeBalance: true,
    clearRestoredSnapshotIfUnavailable: true,
  );

  /// Unlock only waits for one small persisted snapshot, never a wallet summary
  /// or history. The caller starts live reads after starting sync and routing.
  Future<void> refreshAfterUnlock() async {
    final epoch = _sensitiveStateEpoch;
    final uuid = _getActiveAccountUuid();
    if (uuid == null || _requiresUnlock) return;
    try {
      final path = await _getDbPath();
      final cached = await ref
          .read(walletBalanceCacheProvider)
          .load(
            dbPath: path,
            network: _endpointConfig.networkName,
            accountUuid: uuid,
          );
      if (!ref.mounted ||
          epoch != _sensitiveStateEpoch ||
          _requiresUnlock ||
          uuid != _getActiveAccountUuid()) {
        return;
      }
      final current = (state.value ?? SyncState()).scopedToAccount(uuid);
      if (cached != null && !current.hasBalanceData) {
        state = AsyncData(current.withCachedBalance(cached));
      }
    } catch (error) {
      log('SyncNotifier: balance cache restore failed: $error');
    }
  }

  /// Starts the live reads after a cold start or unlock, including a swap
  /// recovery refresh that locking cancelled, and owes a swap recovery round,
  /// which runs once the wallet is at the tip.
  void refreshHomeInBackground() {
    _oweSwapRecovery();
    unawaited(_refreshOwedSwapRecovery());
    unawaited(_refreshBalanceAfterResume());
  }

  void _persistBalanceSnapshot(
    String dbPath,
    String network,
    String uuid,
    rust_sync.WalletBalance balance, {
    required bool syncComplete,
    bool releaseSnapshotOnAuthoritativeBalance = false,
  }) {
    // A successful live read can still contain an intermediate scan balance.
    // Leave the disk snapshot intact until the display may also be replaced.
    if (!syncComplete && !releaseSnapshotOnAuthoritativeBalance) return;
    ref
        .read(walletBalanceCacheProvider)
        .accept(
          dbPath: dbPath,
          network: network,
          accountUuid: uuid,
          balance: balance,
        );
  }

  Future<void> _refreshBalanceAfterResume() async {
    if (_isShuttingDown) return;
    try {
      await _requestBalanceRefresh();
    } catch (e, st) {
      log('SyncNotifier: resume balance refresh failed: $e\n$st');
    }
  }

  /// Coalesce concurrent refresh triggers into one running pass.
  ///
  /// Returns a future that completes once a pass that started *after*
  /// this call's trigger has finished, so awaiting it still yields data
  /// reflecting the caller's event.
  Future<void> _requestBalanceRefresh({
    bool releaseSnapshotOnAuthoritativeBalance = false,
    bool clearRestoredSnapshotIfUnavailable = false,
    bool requireAuthoritativeBalance = false,
  }) {
    if (releaseSnapshotOnAuthoritativeBalance) {
      _balanceRefreshQueuedReleaseSnapshot = true;
    }
    if (clearRestoredSnapshotIfUnavailable) {
      _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable = true;
    }
    if (requireAuthoritativeBalance) {
      _balanceRefreshQueuedRequireAuthoritativeBalance = true;
    }
    if (_balanceRefreshInFlight) {
      _balanceRefreshQueued = true;
      // Non-null whenever a pass is in flight; the fallback keeps this
      // total if the two ever drift.
      return _balanceRefreshChain ?? Future<void>.value();
    }

    _balanceRefreshInFlight = true;
    final chain = _runCoalescedBalanceRefresh();
    _balanceRefreshChain = chain;
    return chain;
  }

  Future<void> _runCoalescedBalanceRefresh() async {
    Object? terminalError;
    StackTrace? terminalStackTrace;
    var requireAuthoritativeBalance = false;
    try {
      do {
        _balanceRefreshQueued = false;
        final releaseSnapshot = _balanceRefreshQueuedReleaseSnapshot;
        _balanceRefreshQueuedReleaseSnapshot = false;
        final clearRestoredSnapshotIfUnavailable =
            _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable;
        _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable = false;
        // Keep this requirement for the whole chain: an ordinary trailing
        // refresh must not turn an unavailable cancellation balance into success.
        requireAuthoritativeBalance =
            requireAuthoritativeBalance ||
            _balanceRefreshQueuedRequireAuthoritativeBalance;
        _balanceRefreshQueuedRequireAuthoritativeBalance = false;
        try {
          await _refreshBalance(
            releaseSnapshotOnAuthoritativeBalance:
                releaseSnapshot || requireAuthoritativeBalance,
            clearRestoredSnapshotIfUnavailable:
                clearRestoredSnapshotIfUnavailable,
            requireAuthoritativeBalance: requireAuthoritativeBalance,
          );
          // A successful trailing pass satisfies every caller sharing this
          // chain, even if an earlier pass failed.
          terminalError = null;
          terminalStackTrace = null;
        } catch (e, st) {
          log('SyncNotifier: coalesced balance refresh failed: $e\n$st');
          terminalError = e;
          terminalStackTrace = st;
        }
      } while (_balanceRefreshQueued && !_requiresUnlock);

      final error = terminalError;
      final stackTrace = terminalStackTrace;
      if (error != null && stackTrace != null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      _balanceRefreshInFlight = false;
      _balanceRefreshQueued = false;
      _balanceRefreshQueuedReleaseSnapshot = false;
      _balanceRefreshQueuedClearRestoredSnapshotIfUnavailable = false;
      _balanceRefreshQueuedRequireAuthoritativeBalance = false;
      _balanceRefreshChain = null;
    }
  }

  Future<void> _ensureAuthoritativeBalanceRecovery() {
    final existing = _authoritativeBalanceRecovery;
    if (existing != null) return existing;

    final recovery = _runAuthoritativeBalanceRecovery();
    _authoritativeBalanceRecovery = recovery;
    unawaited(
      recovery.whenComplete(() {
        if (identical(_authoritativeBalanceRecovery, recovery)) {
          _authoritativeBalanceRecovery = null;
        }
      }),
    );
    return recovery;
  }

  Future<void> _runAuthoritativeBalanceRecovery() async {
    final gen = _syncGen;
    final epoch = _sensitiveStateEpoch;
    final accountUuid = _getActiveAccountUuid();
    final startingVersion = _authoritativeBalanceVersion;
    if (accountUuid == null) return;

    for (final delay in _authoritativeBalanceRecoveryDelays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (!ref.mounted ||
          gen != _syncGen ||
          epoch != _sensitiveStateEpoch ||
          _requiresUnlock ||
          accountUuid != _getActiveAccountUuid()) {
        return;
      }
      if (_authoritativeBalanceVersion > startingVersion) return;

      final current = _previousScopedState(state.value, accountUuid);
      final syncInProgress =
          (current?.isSyncing ?? false) ||
          (current?.isBackgroundMode ?? false) ||
          rust_sync.isSyncRunning();
      if (syncInProgress) continue;

      try {
        await _requestBalanceRefresh();
      } catch (e, st) {
        log('SyncNotifier: authoritative balance recovery failed: $e\n$st');
      }
      if (_authoritativeBalanceVersion > startingVersion) return;
    }

    log(
      'SyncNotifier: authoritative balance still unavailable after '
      'bounded recovery (account=$accountUuid)',
    );
  }

  /// Validates spend readiness without waiting for display history. A persisted
  /// or carried snapshot is never authority: after native scanning finishes,
  /// read a fresh account balance without publishing sync completion state.
  Future<void> waitForAuthoritativeSpendable({
    required String accountUuid,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    const pollInterval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(timeout);
    final initial = _previousScopedState(state.value, accountUuid);
    if (!(initial?.isUsingCompletedSpendableSnapshot ?? false)) return;
    final epoch = _sensitiveStateEpoch;

    void checkScope() {
      if (!ref.mounted || _requiresUnlock || epoch != _sensitiveStateEpoch) {
        throw StateError('Wallet changed while finishing sync.');
      }
      if (_getActiveAccountUuid() != accountUuid) {
        throw StateError('Active account changed while finishing sync.');
      }
      final scoped = _previousScopedState(state.value, accountUuid);
      if (scoped?.failure != null || scoped?.error != null) {
        throw StateError('Wallet sync failed before balance refresh.');
      }
    }

    bool nativeScanFinished() =>
        !rust_sync.isSyncRunning() &&
        (!_isSyncing || (_lastForegroundSyncProgress?.isComplete ?? false));

    while (true) {
      checkScope();
      final scoped = _previousScopedState(state.value, accountUuid);
      if (!(scoped?.isUsingCompletedSpendableSnapshot ?? false)) return;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw StateError('Wallet sync is still finishing. Try again.');
      }

      if (nativeScanFinished()) {
        final gen = _syncGen;
        final balance =
            await (() async {
              final dbPath = await _getDbPath();
              checkScope();
              return readWalletBalance(
                dbPath: dbPath,
                network: _endpointConfig.networkName,
                accountUuid: accountUuid,
              );
            })().timeout(
              remaining,
              onTimeout: () {
                throw StateError('Wallet sync is still finishing. Try again.');
              },
            );
        checkScope();
        // A foreground start may have raced the read. The operation's lease
        // prevents another start during the second check and native operation.
        if (gen == _syncGen &&
            nativeScanFinished() &&
            balance.availability ==
                rust_sync.WalletBalanceAvailability.available) {
          return;
        }
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Runs a balance-sensitive operation without allowing polling or other
  /// Dart foreground triggers to start a new sync between the authoritative
  /// balance check and the native operation.
  Future<T> runWithAuthoritativeSpendable<T>({
    required String accountUuid,
    required Future<T> Function() operation,
  }) async {
    await waitForAuthoritativeSpendable(accountUuid: accountUuid);
    _authoritativeSpendableOperationCount++;
    try {
      // A sync may have started after the first wait returned but before this
      // lease was acquired. Re-check while the lease prevents another start.
      await waitForAuthoritativeSpendable(accountUuid: accountUuid);
      return await operation();
    } finally {
      _authoritativeSpendableOperationCount--;
      if (_authoritativeSpendableOperationCount == 0 &&
          _syncStartDeferred &&
          ref.mounted &&
          !_requiresUnlock) {
        final latestTipHeight = _deferredSyncLatestTipHeight;
        _syncStartDeferred = false;
        _deferredSyncLatestTipHeight = null;
        startSync(latestTipHeight: latestTipHeight);
      }
    }
  }

  Future<void> _refreshBalance({
    bool releaseSnapshotOnAuthoritativeBalance = false,
    bool clearRestoredSnapshotIfUnavailable = false,
    bool requireAuthoritativeBalance = false,
  }) async {
    if (_requiresUnlock) {
      state = AsyncData(SyncState());
      return;
    }
    final version = ++_balanceReadVersion;
    final epoch = _sensitiveStateEpoch;
    final dbPath = await _getDbPath();
    final network = _endpointConfig.networkName;
    final uuid = _getActiveAccountUuid();
    if (uuid == null || !_acceptsAccountRead(uuid, epoch, version)) return;

    // Both reads start together, but each publishes as soon as it is ready.
    // Keep history's errors observed even when the balance read is superseded.
    final historyUpdate = _refreshAccountHistory(
      dbPath: dbPath,
      network: network,
      accountUuid: uuid,
      epoch: epoch,
      balanceReadVersion: version,
    );
    rust_sync.WalletBalance? balance;
    try {
      final result = await readWalletBalance(
        dbPath: dbPath,
        network: network,
        accountUuid: uuid,
      );
      if (result.availability ==
          rust_sync.WalletBalanceAvailability.available) {
        balance = result;
      } else {
        _logUnavailableBalance(result.availability, uuid);
      }
    } catch (error) {
      _logRefreshReadError(
        label: 'balance',
        fallback: 'keeping previous value',
        error: error,
      );
    }
    if (!_acceptsAccountRead(uuid, epoch, version)) {
      if (ref.mounted &&
          requireAuthoritativeBalance &&
          !_requiresUnlock &&
          uuid == _getActiveAccountUuid() &&
          epoch == _sensitiveStateEpoch) {
        _balanceRefreshQueued = true;
        _balanceRefreshQueuedReleaseSnapshot = true;
      }
      return;
    }
    if (requireAuthoritativeBalance && balance == null) {
      throw StateError('Balance unavailable after releasing send proposal');
    }
    final current = (state.value ?? SyncState()).scopedToAccount(uuid);
    if (SyncState.shouldClearUnavailableRestoredSnapshot(
      previous: current,
      hasAuthoritativeBalance: balance != null,
      clearRestoredSnapshotIfUnavailable: clearRestoredSnapshotIfUnavailable,
    )) {
      _lastKnownByAccount.remove(uuid);
      state = AsyncData(
        current
            .withoutAccountScopedData(accountUuid: uuid)
            .copyWith(
              hasRecentTransactionsData: current.hasRecentTransactionsData,
              hasRecentTransactionsError: current.hasRecentTransactionsError,
              recentTransactions: current.recentTransactions,
            ),
      );
      await historyUpdate;
      return;
    }
    if (balance != null) {
      _logSpendableDropBreakdown(balance, current);
      ++_authoritativeBalanceVersion;
    }
    final syncComplete = current.isSyncedToTip;
    state = AsyncData(
      current.withFetchedAccountData(
        balance: balance,
        canShieldTransparentBalance: balance == null ? null : false,
        shieldTransparentFee: balance == null ? null : BigInt.zero,
        shieldTransparentAmount: balance == null ? null : BigInt.zero,
        syncComplete: syncComplete,
        releaseSnapshotOnAuthoritativeBalance:
            releaseSnapshotOnAuthoritativeBalance,
      ),
    );
    if (balance != null) {
      _persistBalanceSnapshot(
        dbPath,
        network,
        uuid,
        balance,
        syncComplete: syncComplete,
        releaseSnapshotOnAuthoritativeBalance:
            releaseSnapshotOnAuthoritativeBalance,
      );
    }

    // Send/release callers can await the whole refresh, while Home sees the
    // accepted balance above before history and shielding checks finish.
    await Future.wait([
      historyUpdate,
      if (balance != null)
        _refreshShieldStatus(
          dbPath: dbPath,
          network: network,
          accountUuid: uuid,
          epoch: epoch,
          balanceReadVersion: version,
          transparentBalance: balance.transparent,
        ),
    ]);
  }

  bool _acceptsAccountRead(String uuid, int epoch, int version) =>
      ref.mounted &&
      epoch == _sensitiveStateEpoch &&
      !_requiresUnlock &&
      uuid == _getActiveAccountUuid() &&
      version == _balanceReadVersion;

  Future<void> _refreshAccountHistory({
    required String dbPath,
    required String network,
    required String accountUuid,
    required int epoch,
    required int balanceReadVersion,
  }) async {
    try {
      final history = await readTransactionHistory(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
        limit: 10,
      );
      if (!_acceptsAccountRead(accountUuid, epoch, balanceReadVersion)) return;
      final current = (state.value ?? SyncState()).scopedToAccount(accountUuid);
      state = AsyncData(
        current.copyWith(
          hasRecentTransactionsData: true,
          hasRecentTransactionsError: false,
          recentTransactions: history,
        ),
      );
      ref
          .read(pendingActivityEvidenceProvider.notifier)
          .historyReadCompleted(accountUuid, available: true);
    } catch (error) {
      if (_acceptsAccountRead(accountUuid, epoch, balanceReadVersion)) {
        state = AsyncData(
          (state.value ?? SyncState())
              .scopedToAccount(accountUuid)
              .copyWith(hasRecentTransactionsError: true),
        );
        ref
            .read(pendingActivityEvidenceProvider.notifier)
            .historyReadCompleted(accountUuid, available: false);
      }
      _logRefreshReadError(
        label: 'tx history',
        fallback: 'keeping previous list',
        error: error,
      );
    }
  }

  Future<void> _refreshShieldStatus({
    required String dbPath,
    required String network,
    required String accountUuid,
    required int epoch,
    required int balanceReadVersion,
    required BigInt transparentBalance,
  }) async {
    final status = await _getShieldTransparentStatus(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      transparentBalance: transparentBalance,
    );
    if (status == null ||
        !_acceptsAccountRead(accountUuid, epoch, balanceReadVersion)) {
      return;
    }
    final current = _previousScopedState(state.value, accountUuid);
    if (current == null || !current.hasBalanceData) return;
    state = AsyncData(
      current.copyWith(
        canShieldTransparentBalance: status.canShield,
        shieldTransparentFee: status.fee,
        shieldTransparentAmount: status.amount,
      ),
    );
  }

  String? _getActiveAccountUuid() {
    return ref.read(accountProvider).value?.activeAccountUuid;
  }

  @protected
  Future<rust_sync.WalletBalance> readWalletBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) => rust_sync.getBalance(
    dbPath: dbPath,
    network: network,
    accountUuid: accountUuid,
  );

  @protected
  Future<List<rust_sync.TransactionInfo>> readTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) => rust_sync.getTransactionHistory(
    dbPath: dbPath,
    network: network,
    limit: limit,
    accountUuid: accountUuid,
  );

  void _logSpendableDropBreakdown(
    rust_sync.WalletBalance balance,
    SyncState? previous,
  ) {
    if (!kDebugMode ||
        balance.spendable != BigInt.zero ||
        (previous?.displaySpendableBalance ?? BigInt.zero) <= BigInt.zero) {
      return;
    }
    log(
      'SyncNotifier: native spendable dropped to zero '
      '(changePending=${balance.changePendingConfirmation}, '
      'valuePending=${balance.valuePendingSpendability}, '
      'uneconomic=${balance.uneconomicValue}, '
      'ironwood=${balance.ironwood}, '
      'display=${previous?.displaySpendableBalance}, '
      'displayIronwood=${previous?.displayIronwoodBalance})',
    );
  }

  void _logUnavailableBalance(
    rust_sync.WalletBalanceAvailability availability,
    String accountUuid,
  ) {
    if (!kDebugMode) return;

    log(
      'SyncNotifier: wallet balance is temporarily unavailable '
      '(availability=${availability.name}, account=$accountUuid)',
    );
  }

  Future<({bool canShield, BigInt fee, BigInt amount})?>
  _getShieldTransparentStatus({
    required String dbPath,
    required String network,
    required String accountUuid,
    required BigInt transparentBalance,
  }) async {
    if (transparentBalance <= BigInt.zero) {
      return (canShield: false, fee: BigInt.zero, amount: BigInt.zero);
    }

    try {
      final status = await rust_sync.getShieldTransparentStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
      return (
        canShield: status.canShield,
        fee: status.feeZatoshi,
        amount: status.shieldedZatoshi,
      );
    } catch (e) {
      _logRefreshReadError(
        label: 'shield transparent status',
        fallback: 'keeping previous value',
        error: e,
      );
      return null;
    }
  }

  void _logRefreshReadError({
    required String label,
    required String fallback,
    required Object error,
  }) {
    if (_isDatabaseLockedError(error)) {
      log(
        'SyncNotifier: $label refresh skipped due to temporary DB lock; '
        '$fallback',
      );
      return;
    }
    log('SyncNotifier: $label refresh failed: $error');
  }

  bool _isDatabaseLockedError(Object error) {
    return error.toString().contains('database is locked');
  }

  /// Keeps the private transparent recovery companions of the wallet at
  /// [dbPath] out of device backups before a sync can write them. Best
  /// effort, as at startup: a failure is logged and the sync goes on.
  Future<void> _keepCompanionsOutOfBackups(String dbPath) async {
    try {
      await _excludeCompanionsFromBackup(dbPath);
    } catch (error) {
      log('Sync: could not keep recovery companions out of backups: $error');
    }
  }

  Future<String> _getDbPath() async {
    if (_cachedDbPath != null) return _cachedDbPath!;
    _cachedDbPath = await _walletDbPathResolver();
    return _cachedDbPath!;
  }

  @visibleForTesting
  void handleAppResumeForTesting() => _handleAppResume();

  @visibleForTesting
  void handleAppHideForTesting() => _handleAppHide();

  @visibleForTesting
  void stopTipChecksForTesting() => _stopPolling();

  @visibleForTesting
  Future<void> checkTipForTesting() => _checkAndSync();

  @visibleForTesting
  Future<void> handleSyncProgressForTesting(SyncProgressEvent event) =>
      _onSyncProgress(event);

  @visibleForTesting
  void handleAccountSwitchForTesting(String? accountUuid) =>
      _clearAccountScopedStateFor(accountUuid);

  bool get _requiresUnlock {
    return ref.read(appSecurityProvider).requiresUnlock;
  }

  RpcEndpointConfig get _endpointConfig =>
      ref.read(rpcEndpointFailoverProvider).current;
}

final syncProvider = AsyncNotifierProvider<SyncNotifier, SyncState>(
  () => SyncNotifier(),
);

/// Counts finished swap recovery rounds, so state the wallet keeps, such as a
/// saved history check, can be read again after each one.
final swapRecoveryRoundsProvider = NotifierProvider<SwapRecoveryRounds, int>(
  SwapRecoveryRounds.new,
);

/// See [swapRecoveryRoundsProvider].
class SwapRecoveryRounds extends Notifier<int> {
  @override
  int build() => 0;

  /// Records that a round finished.
  void ended() => state++;
}

/// Reads the wallet's saved swap recovery state without network access, or
/// null without a wallet (see [SyncNotifier.swapRecoveryStatus]). Overridable
/// in tests.
final swapRecoveryStatusReaderProvider =
    Provider<Future<rust_swap.SwapRecoveryStatus?> Function()>((ref) {
      return () => ref.read(syncProvider.notifier).swapRecoveryStatus();
    });

/// Whether the receiver service needs a newer app, as the wallet saved it. It is
/// read at startup and again after every swap recovery round, which is when it
/// can change. A read that fails keeps the last answer.
final swapRecoveryUpdateRequiredProvider = FutureProvider<bool>((ref) async {
  ref.watch(swapRecoveryRoundsProvider);
  final status = await ref.read(swapRecoveryStatusReaderProvider)();
  return status?.upgradeRequired ?? false;
});

/// Counts wallet data changes that do not complete a sync: post-sync
/// follow-ups published by [SyncNotifier], and a "Load publicly" result the
/// user asked for. Open receipts and Activity feeds reload on each: either
/// can change transactions outside the ten recent ones.
class SyncFollowupNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void updated() => state++;
}

final syncFollowupProvider = NotifierProvider<SyncFollowupNotifier, int>(
  SyncFollowupNotifier.new,
);

/// [SyncState.hasSettledSpendableBalance] for [accountUuid], from an unscoped
/// state.
///
/// The single spelling of "this balance is an answer" for everything that has
/// to decide whether a shortfall is real. Scoping first is not optional: an
/// unscoped read answers with another account's balance, or with the
/// wallet-wide sync fields of a state that has no balance at all.
bool spendableIsSettledForAccount(SyncState? sync, String? accountUuid) =>
    sync != null &&
    sync.scopedToAccount(accountUuid).hasSettledSpendableBalance;

/// [spendableIsSettledForAccount] for the active account, read live.
bool activeAccountSpendableIsSettled(Ref ref) => spendableIsSettledForAccount(
  ref.read(syncProvider).value,
  ref.read(accountProvider).value?.activeAccountUuid,
);

/// A foreground start waiting for the sync that holds the Rust guard.
class _QueuedSyncStart {
  const _QueuedSyncStart({required this.forced, this.latestTipHeight});

  /// Started through [SyncNotifier.startSyncAnyway].
  final bool forced;
  final int? latestTipHeight;
}
