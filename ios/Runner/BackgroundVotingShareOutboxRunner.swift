import Foundation

struct BackgroundVotingShareOutboxRunnerDependencies {
  var getShareStatus:
    (
      String,
      String,
      String,
      BackgroundVotingShareCancellation
    ) -> Result<VotingShareStatusResponse, VotingShareHelperClientError>
  var postShare:
    (
      String,
      Data,
      BackgroundVotingShareCancellation
    ) -> Result<Void, VotingShareHelperClientError>

  static let live = BackgroundVotingShareOutboxRunnerDependencies(
    getShareStatus: { baseUrl, roundId, shareIdHex, cancellation in
      VotingShareHelperClient.shared.getShareStatus(
        baseUrl: baseUrl,
        roundId: roundId,
        shareIdHex: shareIdHex,
        cancellation: cancellation
      )
    },
    postShare: { baseUrl, bodyJson, cancellation in
      VotingShareHelperClient.shared.postShare(
        baseUrl: baseUrl,
        bodyJson: bodyJson,
        cancellation: cancellation
      )
    }
  )
}

enum BackgroundVotingShareOutboxRunner {
  private static let runLock = NSLock()

  static func runOnce(
    store: BackgroundVotingShareOutboxStore = .shared,
    cancellation: BackgroundVotingShareCancellation,
    clock: () -> Date = Date.init,
    dependencies: BackgroundVotingShareOutboxRunnerDependencies = .live
  ) -> BackgroundVotingShareOutboxRunResult {
    var random = SystemRandomNumberGenerator()
    return runOnce(
      store: store,
      cancellation: cancellation,
      clock: clock,
      random: &random,
      dependencies: dependencies
    )
  }

  /// One pass over the voting share outbox.
  ///
  /// Unlike the Ironwood migration outbox, which deliberately broadcasts one
  /// transaction per wake to space submissions out on its timing schedule,
  /// this pass processes EVERY due share. Voting shares have no inter-share
  /// timing requirement — the per-share schedule was already applied by the
  /// foreground submission — and BGProcessingTask wakes are scarce, so leaving
  /// due work for the next wake would routinely leave shares unconfirmed past
  /// the vote end.
  static func runOnce<R: RandomNumberGenerator>(
    store: BackgroundVotingShareOutboxStore = .shared,
    cancellation: BackgroundVotingShareCancellation,
    clock: () -> Date = Date.init,
    random: inout R,
    dependencies: BackgroundVotingShareOutboxRunnerDependencies = .live
  ) -> BackgroundVotingShareOutboxRunResult {
    guard runLock.try() else {
      return BackgroundVotingShareOutboxRunResult(
        transport: .temporarilyUnavailable,
        nextActionableDate: nil,
        hasArmedUnconfirmedWork: false
      )
    }
    defer { runLock.unlock() }

    if cancellation.isCancelled {
      return finish(.cancelled, store: store, clock: clock)
    }

    var expiredCount = 0
    let workItems: [BackgroundVotingShareWorkItem]
    do {
      let snapshot = try store.update { snapshot in
        snapshot.recoverInterruptedSubmissions(at: clock())
        expiredCount += snapshot.expireEndedRounds(at: clock())
      }
      workItems = snapshot.dueShareWorkItems(at: clock())
    } catch BackgroundVotingShareOutboxStoreError.temporarilyUnavailable {
      return BackgroundVotingShareOutboxRunResult(
        transport: .temporarilyUnavailable,
        nextActionableDate: nil,
        hasArmedUnconfirmedWork: false
      )
    } catch {
      return BackgroundVotingShareOutboxRunResult(
        transport: .failed(String(describing: error)),
        nextActionableDate: nil,
        hasArmedUnconfirmedWork: false
      )
    }

    var confirmedCount = 0
    var resubmittedCount = 0
    var failedCount = 0
    var cancelled = false

    do {
      itemLoop: for item in workItems {
        if cancellation.isCancelled {
          cancelled = true
          break
        }
        // Re-read: a foreground stage or an earlier step of this pass may have
        // changed the share since the due list was computed.
        guard let current = try refreshedShare(item, store: store) else { continue }

        // Status poll: the first helper that reports the share confirmed
        // settles it; confirmation is recorded for foreground reconciliation.
        var confirmedUrl: String?
        if clock() >= current.statusCheckAt, !current.sentToUrls.isEmpty {
          for url in current.sentToUrls {
            if cancellation.isCancelled {
              cancelled = true
              break itemLoop
            }
            switch dependencies.getShareStatus(
              url,
              item.roundId,
              current.shareIdHex,
              cancellation
            ) {
            case .success(let response) where response.isConfirmed:
              confirmedUrl = url
            case .success:
              continue
            case .failure(.cancelled):
              cancelled = true
              break itemLoop
            case .failure:
              // A helper that cannot answer does not block the others.
              continue
            }
            if confirmedUrl != nil { break }
          }
        }
        if let confirmedUrl {
          _ = try store.update { snapshot in
            try snapshot.recordConfirmed(
              roundKey: item.roundKey,
              shareKey: item.shareKey,
              url: confirmedUrl,
              at: clock()
            )
          }
          confirmedCount += 1
          continue
        }

        // Resubmission: only once the share is overdue, its retry gate has
        // passed, and the vote end is far enough away to accept a resubmit.
        let resubmitNow = clock()
        let resubmitNowSeconds = UInt64(max(0, resubmitNow.timeIntervalSince1970))
        guard resubmitNow >= current.overdueAt(voteEndSeconds: item.voteEndSeconds),
          current.nextAttemptAt == nil || resubmitNow >= current.nextAttemptAt!,
          BackgroundVotingSharePolicy.allowsResubmission(
            voteEndSeconds: item.voteEndSeconds,
            nowSeconds: resubmitNowSeconds
          )
        else { continue }

        _ = try store.update { snapshot in
          try snapshot.beginSubmission(
            roundKey: item.roundKey,
            shareKey: item.shareKey,
            at: resubmitNow
          )
        }
        let order = BackgroundVotingSharePolicy.resubmissionServerOrder(
          helperUrls: item.helperUrls,
          sentToUrls: current.sentToUrls,
          random: &random
        )
        var acceptedUrl: String?
        var attemptedAnyPost = false
        var sawUncertainPost = false
        var lastFailure: String?
        for url in order {
          if cancellation.isCancelled { break }
          switch dependencies.postShare(url, current.recoveryBodyJson, cancellation) {
          case .success:
            attemptedAnyPost = true
            acceptedUrl = url
          case .failure(.cancelled):
            // The interrupted POST's outcome is unknown; treat like an
            // uncertain attempt so the retry ladder applies.
            attemptedAnyPost = true
            sawUncertainPost = true
            lastFailure = "The resubmission was interrupted; its outcome is unknown."
          case .failure(let error):
            attemptedAnyPost = true
            lastFailure = String(describing: error)
          }
          if acceptedUrl != nil || sawUncertainPost { break }
        }
        if let acceptedUrl {
          _ = try store.update { snapshot in
            try snapshot.recordResubmitted(
              roundKey: item.roundKey,
              shareKey: item.shareKey,
              url: acceptedUrl,
              at: clock()
            )
          }
          resubmittedCount += 1
          continue
        }
        if !attemptedAnyPost && cancellation.isCancelled {
          // Definite non-attempt: restore without a retry penalty, so stop
          // reconciliation is not delayed by an attempt that never happened.
          _ = try store.update { snapshot in
            try snapshot.recordCancelledBeforeSubmission(
              roundKey: item.roundKey,
              shareKey: item.shareKey,
              error: "Background execution expired before resubmission."
            )
          }
          cancelled = true
          break
        }
        _ = try store.update { snapshot in
          try snapshot.recordResubmitFailure(
            roundKey: item.roundKey,
            shareKey: item.shareKey,
            error: lastFailure ?? "Every helper refused the resubmission.",
            at: clock()
          )
        }
        failedCount += 1
        if cancellation.isCancelled {
          cancelled = true
          break
        }
      }
    } catch BackgroundVotingShareOutboxStoreError.temporarilyUnavailable {
      return BackgroundVotingShareOutboxRunResult(
        transport: .temporarilyUnavailable,
        nextActionableDate: nil,
        hasArmedUnconfirmedWork: false
      )
    } catch {
      return finishWithTransport(
        .failed(String(describing: error)),
        store: store,
        clock: clock
      )
    }

    let transport: BackgroundVotingShareTransportOutcome
    if cancelled {
      transport = .cancelled
    } else if expiredCount == 0 && workItems.isEmpty {
      let hasWork = (try? store.read())?.hasArmedUnconfirmedWork ?? true
      transport =
        hasWork
        ? .processed(confirmed: 0, resubmitted: 0, expired: 0, failed: 0)
        : .noWork
    } else {
      transport = .processed(
        confirmed: confirmedCount,
        resubmitted: resubmittedCount,
        expired: expiredCount,
        failed: failedCount
      )
    }
    return finishWithTransport(transport, store: store, clock: clock)
  }

  private static func finish(
    _ transport: BackgroundVotingShareTransportOutcome,
    store: BackgroundVotingShareOutboxStore,
    clock: () -> Date
  ) -> BackgroundVotingShareOutboxRunResult {
    finishWithTransport(transport, store: store, clock: clock)
  }

  private static func finishWithTransport(
    _ transport: BackgroundVotingShareTransportOutcome,
    store: BackgroundVotingShareOutboxStore,
    clock: () -> Date
  ) -> BackgroundVotingShareOutboxRunResult {
    guard let snapshot = try? store.read() else {
      // An unreadable store must not silently retire the schedule; assume
      // work remains so the manager re-arms and a later wake can recover.
      return BackgroundVotingShareOutboxRunResult(
        transport: transport,
        nextActionableDate: nil,
        hasArmedUnconfirmedWork: true
      )
    }
    return BackgroundVotingShareOutboxRunResult(
      transport: transport,
      nextActionableDate: snapshot.nextActionableDate(at: clock()),
      hasArmedUnconfirmedWork: snapshot.hasArmedUnconfirmedWork
    )
  }

  private static func refreshedShare(
    _ item: BackgroundVotingShareWorkItem,
    store: BackgroundVotingShareOutboxStore
  ) throws -> BackgroundVotingShare? {
    let snapshot = try store.read()
    guard
      let round = snapshot.rounds.first(where: { $0.roundKey == item.roundKey }),
      round.armedAt != nil,
      let share = round.shares.first(where: { $0.shareKey == item.shareKey }),
      share.status == .armed
    else {
      return nil
    }
    return share
  }
}
