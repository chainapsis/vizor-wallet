part of 'payment_links_screen.dart';

/// The desktop group flow: its form, quote and funding state.
///
/// A mixin rather than a widget, because the screen may switch pages under a
/// funding group (an incoming link opens Redeem directly) and the group's
/// state has to outlive the page.
mixin _PaymentLinksBatchCreation on ConsumerState<PaymentLinksScreen> {
  // What the group flow shares with the rest of the screen.
  PaymentLinksLocalPage get _page;
  set _page(PaymentLinksLocalPage value);
  bool get _operationInProgress;
  set _operationInProgress(bool value);
  set _showHelp(bool value);
  TextEditingController get _amountController;
  void _resetAmountInput();
  TextEditingController get _messageController;
  bool get _messageExceedsByteLimit;
  PaymentLinkCardArtwork get _selectedArtwork;
  set _selectedArtwork(PaymentLinkCardArtwork value);
  PaymentLinkFundingResult? get _pendingFundingMetadata;
  Timer? get _fundingQuoteDebounce;
  int get _fundingQuoteGeneration;
  set _fundingQuoteGeneration(int value);
  Map<String, PaymentLinkFundingProgress> get _fundingProgressByAddress;
  set _fundingProgressByAddress(Map<String, PaymentLinkFundingProgress> value);
  void _showPage(PaymentLinksLocalPage page);
  void _showError(String message);
  Future<void> _loadRecoveries({required bool showError});
  Future<void> _refreshFundingProgress();
  bool _canEstimateCardFee(SyncState? sync, String accountUuid);
  HardwareSignerKind? _signerFor(String? accountUuid);
  void _warnUnsettledHardwareFunding(PaymentLinkHardwareFundingResult result);

  // Captured once so cleanup still works after the screen is disposed.
  late final PaymentLinkBatchOperations _batchOperations;
  int _batchCount = 2;
  int _batchPreparationGeneration = 0;
  Timer? _batchQuoteDebounce;
  // Review and Create share one button, so the second press of a double-click
  // on Review must not fund the group unreviewed.
  Timer? _batchCreateArming;
  _BatchQuote _batchQuote = const _BatchQuoteEmpty();
  _BatchSubmission _batchSubmission = const _BatchNotSent();
  bool _batchReviewing = false;
  bool _batchPresentationDirty = false;
  // Each card's design in order while the group mixes designs; drawn once so
  // the preview and the created cards agree.
  List<PaymentLinkCardArtwork>? _batchMixedArtworks;
  String? _selectedBatchId;
  // The group just created here, whose detail plays the ready reveal.
  String? _justCreatedBatchId;

  /// A batch that is being signed or may already be on the network keeps its
  /// draft and state: nothing may requote it or start it over.
  bool get _batchLocked => _batchSubmission is! _BatchNotSent;

  /// Funding or saving is in flight; nothing may navigate away.
  bool get _batchBusy => switch (_batchSubmission) {
    _BatchSending() => true,
    _BatchUnsaved(:final saving) => saving,
    _ => false,
  };

  PaymentLinkBatchDraft? get _hardwareBatchSigning =>
      switch (_batchSubmission) {
        _BatchSending(:final hardwareDraft) => hardwareDraft,
        _ => null,
      };

  String? get _batchErrorText => switch (_batchSubmission) {
    _BatchUncertain() =>
      'Vizor couldn’t confirm the payment was sent. Check this group in Gift Cards before creating another.',
    _BatchUnsaved() =>
      'Funding was sent, but the cards could not be saved. Try again before closing Vizor.',
    _ => switch (_batchQuote) {
      _BatchQuoteReady(:final problem) => problem,
      _BatchQuoteFailed(:final message) => message,
      _ => null,
    },
  };

  void _clearPreparedBatch() {
    _batchPreparationGeneration++;
    if (_batchQuote case _BatchQuoteReady(
      :final draft,
    ) when _batchSubmission is _BatchNotSent) {
      unawaited(
        _batchOperations.abandonUnsubmittedBatch(draft.id).catchError((
          Object error,
        ) {
          log(
            'PaymentLinksScreen: could not discard unsubmitted batch: $error',
          );
        }),
      );
    }
    _batchQuote = const _BatchQuoteEmpty();
  }

  /// A quote prepared before the ZEC price loaded, now that it has.
  bool get _batchFiatSnapshotStale {
    final quote = _batchQuote;
    return quote is _BatchQuoteReady &&
        ref.read(swapFeatureEnabledProvider) &&
        quote.draft.links.first.presentation?.fiatSnapshot == null &&
        ref.read(zecHomeMarketDataStateProvider).displayData?.usdPrice != null;
  }

  /// Leaving the route drops the secrets of a group nothing was sent for.
  void _disposeBatchCreation() {
    _batchQuoteDebounce?.cancel();
    _batchCreateArming?.cancel();
    _clearPreparedBatch();
    // A hardware preparation that failed leaves its drafts for a retry. The
    // store refuses to remove anything that reached a signer.
    if (_batchSubmission case _BatchSending(:final hardwareDraft?)) {
      unawaited(
        _batchOperations.abandonUnsubmittedBatch(hardwareDraft.id).catchError((
          Object error,
        ) {
          log('PaymentLinksScreen: hardware batch cleanup deferred: $error');
        }),
      );
    }
  }

  void _startBulkCreate() {
    if (_operationInProgress || _pendingFundingMetadata != null) return;
    _fundingQuoteDebounce?.cancel();
    _fundingQuoteGeneration++;
    _resetAmountInput();
    _messageController.clear();
    _batchQuoteDebounce?.cancel();
    _clearPreparedBatch();
    setState(() {
      _batchCount = 2;
      _batchReviewing = false;
      _batchPresentationDirty = false;
      _batchMixedArtworks = null;
      _batchSubmission = const _BatchNotSent();
      _selectedArtwork = PaymentLinkCardArtwork
          .values[Random().nextInt(PaymentLinkCardArtwork.values.length)];
      _page = PaymentLinksLocalPage.bulk;
      _showHelp = false;
    });
  }

  /// Leaving the group flow drops its quote; the card list tracks an
  /// unsettled batch from here.
  void _leaveBatchCreation() {
    _batchQuoteDebounce?.cancel();
    _clearPreparedBatch();
    _batchSubmission = const _BatchNotSent();
  }

  void _requoteBatchForAccount() {
    // A batch that was sent, or may have been, keeps its outcome on screen.
    if (_batchLocked) return;
    _batchQuoteDebounce?.cancel();
    _clearPreparedBatch();
    setState(() {
      _batchReviewing = false;
      _batchCount = _batchCount.clamp(
        kPaymentLinkBatchMinCount,
        _batchMaxCount,
      );
    });
    _scheduleBatchQuote();
  }

  void _requoteBatchAfterSync() {
    // A finished sync that left the balance unchanged keeps the quote, so
    // new blocks do not regenerate every card.
    if (_batchQuote case _BatchQuoteReady(
      :final spendable,
    ) when ref.read(syncProvider).value?.spendableBalance == spendable) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page == PaymentLinksLocalPage.bulk) {
        _scheduleBatchQuote();
      }
    });
  }

  int get _batchMaxCount => paymentLinkBatchMaxCount(
    _signerFor(ref.read(accountProvider).value?.activeAccountUuid),
  );

  void _setBatchCount(int count) {
    if (_batchLocked ||
        count == _batchCount ||
        count < kPaymentLinkBatchMinCount ||
        count > _batchMaxCount) {
      return;
    }
    setState(() => _batchCount = count);
    _scheduleBatchQuote();
  }

  void _scheduleBatchQuote() {
    if (_batchLocked) return;
    _batchQuoteDebounce?.cancel();
    _clearPreparedBatch();
    _batchPresentationDirty = false;
    if (_page != PaymentLinksLocalPage.bulk) return;
    final amount = parseZecAmount(_amountController.text.trim());
    if (amount == null || amount <= BigInt.zero) {
      setState(() {});
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    final sync = ref.read(syncProvider).value;
    if (accountUuid == null || !_canEstimateCardFee(sync, accountUuid)) {
      // Pending, not an error: the sync gate requotes once it opens.
      setState(() => _batchQuote = const _BatchQuoteWaitingForSync());
      return;
    }
    final minimum =
        BigInt.from(_batchCount) *
        (amount + BigInt.from(kPaymentLinkClaimFeeReserveZatoshi));
    if (sync!.spendableBalance < minimum) {
      setState(
        () => _batchQuote = const _BatchQuoteFailed(_kBatchOverBalanceText),
      );
      return;
    }
    setState(() => _batchQuote = const _BatchQuotePreparing());
    _batchQuoteDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_prepareBatch());
    });
  }

  PaymentLinkPresentation _batchPresentation(BigInt amount) =>
      PaymentLinkPresentation(
        artworkId: _selectedArtwork.protocolId,
        message: _messageController.text,
        fiatSnapshot: ref.read(swapFeatureEnabledProvider)
            ? PaymentLinkFiatSnapshot.capture(
                amountZatoshi: amount,
                zecUsdUnitPrice: ref
                    .read(zecHomeMarketDataStateProvider)
                    .displayData
                    ?.usdPrice,
              )
            : null,
      );

  Future<void> _prepareBatch() async {
    final generation = ++_batchPreparationGeneration;
    final amount = parseZecAmount(_amountController.text.trim());
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (amount == null ||
        amount <= BigInt.zero ||
        accountUuid == null ||
        _batchCount < kPaymentLinkBatchMinCount ||
        _batchCount > _batchMaxCount) {
      setState(
        () => _batchQuote = const _BatchQuoteFailed(
          'No active account is available.',
        ),
      );
      return;
    }
    setState(() => _batchQuote = const _BatchQuotePreparing());
    try {
      final draft = await _batchOperations.prepareBatch(
        count: _batchCount,
        amountZatoshi: amount,
        sourceAccountUuid: accountUuid,
        presentation: _batchPresentation(amount),
        artworkIds: _batchMixedArtworks
            ?.take(_batchCount)
            .map((artwork) => artwork.protocolId)
            .toList(),
      );
      if (!mounted ||
          generation != _batchPreparationGeneration ||
          _page != PaymentLinksLocalPage.bulk ||
          ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        await _batchOperations.abandonUnsubmittedBatch(draft.id);
        return;
      }
      final spendable = ref.read(syncProvider).value?.spendableBalance;
      setState(
        () => _batchQuote = _BatchQuoteReady(
          draft,
          spendable: spendable,
          problem: spendable == null
              ? 'Available balance is still loading. Try again after wallet sync.'
              : draft.quote.totalDeductedZatoshi > spendable
              ? _kBatchOverBalanceText
              : null,
        ),
      );
    } catch (error) {
      if (!mounted || generation != _batchPreparationGeneration) return;
      setState(
        () => _batchQuote = error is PaymentLinkBatchRejected
            ? _BatchQuoteFailed(error.message)
            : const _BatchQuoteFailed(
                'These cards could not be prepared.',
                retryable: true,
              ),
      );
      log('PaymentLinksScreen: batch preparation failed: $error');
    }
  }

  Future<void> _createFundedBatch() async {
    final quote = _batchQuote;
    if (quote is! _BatchQuoteReady || quote.problem != null || _batchLocked) {
      return;
    }
    final draft = quote.draft;
    final hardware = ref
        .read(accountProvider.notifier)
        .isHardwareAccount(draft.quote.sourceAccountUuid);
    setState(() {
      // A hardware signer takes over from its overlay.
      _batchSubmission = _BatchSending(hardwareDraft: hardware ? draft : null);
      _operationInProgress = true;
    });
    if (hardware) return;
    try {
      final result = await _batchOperations.fundBatch(draft);
      if (!mounted) return;
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      _applyBatchFundingResult(result);
    } on PaymentLinkBatchQuoteChanged {
      _requoteBatch(_kBatchFeeChangedText);
    } on PaymentLinkBatchPreSubmissionFailure {
      _requoteBatch('No cards were funded. Review the amount and try again.');
    } on PaymentLinkBatchRejected catch (rejected) {
      // Rejected while proposing: nothing reached the network.
      if (!mounted) return;
      setState(() => _batchQuote = _BatchQuoteFailed(rejected.message));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _batchQuote = const _BatchQuoteEmpty();
        _batchSubmission = const _BatchUncertain();
      });
      await _loadRecoveries(showError: false);
      log('PaymentLinksScreen: batch funding needs checking: $error');
    } finally {
      if (mounted) {
        setState(() {
          if (_batchSubmission is _BatchSending) {
            _batchSubmission = const _BatchNotSent();
          }
          _operationInProgress = false;
        });
      }
      unawaited(_refreshFundingProgress());
    }
  }

  /// Quotes again for a batch nothing was sent for. The reason is a toast
  /// because a new quote clears the inline error.
  void _requoteBatch(String message) {
    if (!mounted) return;
    setState(() => _batchQuote = const _BatchQuoteEmpty());
    _showError(message);
    unawaited(_prepareBatch());
  }

  /// Records a funded group. Card details that failed to save keep the review,
  /// where saving is retried, whichever account is active.
  void _applyBatchFundingResult(PaymentLinkBatchFundingResult result) {
    setState(() {
      _batchQuote = const _BatchQuoteEmpty();
      _batchSubmission = result.fundingMetadataSaved
          ? const _BatchNotSent()
          : _BatchUnsaved(result);
      _operationInProgress = false;
      _fundingProgressByAddress = {
        ..._fundingProgressByAddress,
        for (final link in result.draft.links)
          link.address: PaymentLinkFundingProgress(
            confirmationCount: 0,
            broadcastAccepted: result.broadcastAccepted,
          ),
      };
    });
    if (result.fundingMetadataSaved) _showCreatedBatch(result.draft);
  }

  /// Opens the saved group, or returns home when the funding account is no
  /// longer active.
  void _showCreatedBatch(PaymentLinkBatchDraft draft) {
    final sourceStillActive =
        ref.read(accountProvider).value?.activeAccountUuid ==
        draft.quote.sourceAccountUuid;
    setState(() {
      _batchQuote = const _BatchQuoteEmpty();
      _batchSubmission = const _BatchNotSent();
      _selectedBatchId = draft.id;
      _justCreatedBatchId = draft.id;
      _page = sourceStillActive
          ? PaymentLinksLocalPage.batchDetail
          : PaymentLinksLocalPage.home;
    });
    if (!sourceStillActive) {
      _showError(
        'Cards were created under the previous account. Switch back to view them.',
      );
    }
  }

  Future<void> _retryBatchFundingMetadata() async {
    final submission = _batchSubmission;
    if (submission is! _BatchUnsaved || submission.saving) return;
    final result = submission.result;
    setState(() => _batchSubmission = _BatchUnsaved(result, saving: true));
    try {
      await _batchOperations.retryBatchFundingMetadata(
        batchId: result.draft.id,
        fundingTxids: result.txids,
      );
      await _loadRecoveries(showError: false);
      if (!mounted) return;
      _showCreatedBatch(result.draft);
    } catch (_) {
      if (!mounted) return;
      setState(() => _batchSubmission = _BatchUnsaved(result));
      _showError('Card details could not be saved. Try again.');
    }
  }

  Widget _buildHardwareBatchOverlay(PaymentLinkBatchDraft draft) {
    final accountUuid = draft.quote.sourceAccountUuid;
    Future<void> onBroadcast(
      VizorPaymentLink _,
      PaymentLinkHardwareFundingResult result,
    ) => _completeHardwareBatch(draft, result);
    Future<void> onCancel() => _cancelHardwareBatch(draft);
    Future<void> onRefused(Object refusal) =>
        _cancelHardwareBatch(draft, refusal: refusal);
    if (_signerFor(accountUuid) == HardwareSignerKind.ledger) {
      return PaymentLinkLedgerSigningOverlay(
        key: ValueKey('ledger-batch-${draft.id}'),
        amountZatoshi: draft.quote.recipientAmountZatoshi,
        sourceAccountUuid: accountUuid,
        batch: draft,
        onCancel: onCancel,
        onBatchRefused: onRefused,
        onFundingBroadcast: onBroadcast,
      );
    }
    return PaymentLinkKeystoneSigningOverlay(
      key: ValueKey('keystone-batch-${draft.id}'),
      amountZatoshi: draft.quote.recipientAmountZatoshi,
      sourceAccountUuid: accountUuid,
      batch: draft,
      onCancel: onCancel,
      onBatchRefused: onRefused,
      onFundingBroadcast: onBroadcast,
    );
  }

  Future<void> _cancelHardwareBatch(
    PaymentLinkBatchDraft draft, {
    Object? refusal,
  }) async {
    if (!mounted || _hardwareBatchSigning != draft) return;
    final recoveries = await ref.read(paymentLinkRecoveryStoreProvider).load();
    final retained = recoveries.where((record) => record.batchId == draft.id);
    final uncertain = retained.any(
      (record) =>
          record.submittedAtHeight != null ||
          (record.fundingTxids?.isNotEmpty ?? false),
    );
    if (!uncertain && retained.isNotEmpty) {
      // A failed preparation leaves the drafts for a retry; leaving drops them.
      try {
        await _batchOperations.abandonUnsubmittedBatch(draft.id);
      } catch (error) {
        log('PaymentLinksScreen: could not discard unsubmitted batch: $error');
      }
    }
    if (!mounted || _hardwareBatchSigning != draft) return;
    setState(() {
      _batchQuote = refusal is PaymentLinkBatchRejected
          ? _BatchQuoteFailed(refusal.message)
          : const _BatchQuoteEmpty();
      _batchSubmission = uncertain
          ? const _BatchUncertain()
          : const _BatchNotSent();
      _operationInProgress = false;
    });
    if (refusal is PaymentLinkBatchQuoteChanged) {
      _showError(_kBatchFeeChangedText);
    }
    await _loadRecoveries(showError: false);
    if (!uncertain &&
        refusal is! PaymentLinkBatchRejected &&
        mounted &&
        _page == PaymentLinksLocalPage.bulk &&
        _batchReviewing) {
      unawaited(_prepareBatch());
    }
  }

  Future<void> _completeHardwareBatch(
    PaymentLinkBatchDraft draft,
    PaymentLinkHardwareFundingResult funding,
  ) async {
    if (!mounted || _hardwareBatchSigning != draft) return;
    await _loadRecoveries(showError: false);
    if (!mounted || _hardwareBatchSigning != draft) return;
    _applyBatchFundingResult(
      PaymentLinkBatchFundingResult(
        draft: draft,
        txids: funding.txids,
        broadcastAccepted: isPaymentLinkFundingBroadcastAccepted(
          funding.status,
        ),
        fundingMetadataSaved: funding.fundingMetadataSaved,
      ),
    );
    _warnUnsettledHardwareFunding(funding);
    unawaited(_refreshFundingProgress());
  }

  Widget _buildBulk() {
    final sync = ref.watch(syncProvider).value;
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final signer = _signerFor(accountUuid);
    final batchQuote = _batchQuote;
    final submission = _batchSubmission;
    // Once Create is pressed the funding spends the quoted notes, so the live
    // balance would report the group's own cost as a shortfall.
    final spendable = switch ((submission, batchQuote)) {
      (_BatchNotSent(), _)
          when accountUuid != null &&
              sync?.accountUuid == accountUuid &&
              sync?.hasBalanceData == true =>
        sync!.spendableBalance,
      (_BatchNotSent(), _) => null,
      (_, _BatchQuoteReady(spendable: final quoted)) => quoted,
      _ => null,
    };
    final quote = switch ((submission, batchQuote)) {
      (_BatchUnsaved(:final result), _) => result.draft.quote,
      (_, _BatchQuoteReady(:final draft)) => draft.quote,
      _ => null,
    };
    final canProceed =
        submission is _BatchNotSent &&
        batchQuote is _BatchQuoteReady &&
        batchQuote.problem == null &&
        !_messageExceedsByteLimit &&
        spendable != null &&
        batchQuote.draft.quote.totalDeductedZatoshi <= spendable;
    return PaymentLinkBulkDesktopFlow(
      count: _batchCount,
      maxCount: paymentLinkBatchMaxCount(signer),
      isLedger: signer == HardwareSignerKind.ledger,
      amountController: _amountController,
      messageController: _messageController,
      artwork: _selectedArtwork,
      mixedArtworks: _batchMixedArtworks?.take(_batchCount).toList(),
      onMixChanged: (mixed) => setState(() {
        _batchMixedArtworks = mixed
            ? paymentLinkMixedArtworks(kPaymentLinkBatchMaxCount)
            : null;
        _batchPresentationDirty = true;
      }),
      spendable: spendable,
      quote: quote,
      preparing: batchQuote is _BatchQuotePreparing,
      waitingForSync: batchQuote is _BatchQuoteWaitingForSync,
      reviewing: _batchReviewing,
      submitting: _batchBusy,
      retrySaving: submission is _BatchUnsaved,
      error: _messageExceedsByteLimit
          ? kPaymentLinkMessageTooLargeText
          : _batchErrorText,
      onCountChanged: _setBatchCount,
      onAmountChanged: (_) => _scheduleBatchQuote(),
      onMessageChanged: (_) => setState(() => _batchPresentationDirty = true),
      onArtworkChanged: (artwork) {
        setState(() {
          _selectedArtwork = artwork;
          _batchMixedArtworks = null;
          _batchPresentationDirty = true;
        });
      },
      onReview: canProceed
          ? () {
              setState(() => _batchReviewing = true);
              _batchCreateArming?.cancel();
              _batchCreateArming = Timer(kDoubleTapTimeout, () {});
              if (_batchPresentationDirty || _batchFiatSnapshotStale) {
                _clearPreparedBatch();
                _batchPresentationDirty = false;
                unawaited(_prepareBatch());
              }
            }
          : null,
      onEdit: _batchLocked
          ? null
          : () => setState(() => _batchReviewing = false),
      onCreate: switch (submission) {
        _BatchUnsaved(saving: false) => _retryBatchFundingMetadata,
        _BatchNotSent() when canProceed => () {
          if (_batchCreateArming?.isActive ?? false) return;
          unawaited(_createFundedBatch());
        },
        _ => null,
      },
      onBack: () => _showPage(PaymentLinksLocalPage.home),
      onRetry: batchQuote is _BatchQuoteFailed && batchQuote.retryable
          ? _scheduleBatchQuote
          : null,
    );
  }
}

const _kBatchFeeChangedText = 'The network fee changed. Review the new total.';

const _kBatchOverBalanceText =
    'Reduce the amount or number of cards to fit your available balance.';

/// Where a group's quote stands.
sealed class _BatchQuote {
  const _BatchQuote();
}

/// No amount to quote yet.
final class _BatchQuoteEmpty extends _BatchQuote {
  const _BatchQuoteEmpty();
}

/// The network fee waits for wallet sync; the sync gate quotes again.
final class _BatchQuoteWaitingForSync extends _BatchQuote {
  const _BatchQuoteWaitingForSync();
}

final class _BatchQuotePreparing extends _BatchQuote {
  const _BatchQuotePreparing();
}

/// Prepared cards and the spendable balance they were quoted against.
/// [problem] says why they cannot be funded as quoted.
final class _BatchQuoteReady extends _BatchQuote {
  const _BatchQuoteReady(this.draft, {required this.spendable, this.problem});

  final PaymentLinkBatchDraft draft;
  final BigInt? spendable;
  final String? problem;
}

/// No cards could be prepared. [retryable] offers Try again.
final class _BatchQuoteFailed extends _BatchQuote {
  const _BatchQuoteFailed(this.message, {this.retryable = false});

  final String message;
  final bool retryable;
}

/// How far a group's funding has gone.
sealed class _BatchSubmission {
  const _BatchSubmission();
}

final class _BatchNotSent extends _BatchSubmission {
  const _BatchNotSent();
}

/// Funding is being sent, from this device or through [hardwareDraft]'s
/// signer.
final class _BatchSending extends _BatchSubmission {
  const _BatchSending({this.hardwareDraft});

  final PaymentLinkBatchDraft? hardwareDraft;
}

/// The broadcast result is unknown: the cards are kept and never sent again.
final class _BatchUncertain extends _BatchSubmission {
  const _BatchUncertain();
}

/// Funded, but the card details still need saving. [saving] while retrying.
final class _BatchUnsaved extends _BatchSubmission {
  const _BatchUnsaved(this.result, {this.saving = false});

  final PaymentLinkBatchFundingResult result;
  final bool saving;
}
