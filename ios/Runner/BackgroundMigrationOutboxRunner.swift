import Foundation

struct BackgroundMigrationOutboxRunnerDependencies {
  var latestBlockHeight:
    (
      String,
      BackgroundMigrationCancellation
    ) -> Result<UInt64, NativeLightwalletdError>
  var sendTransaction:
    (
      String,
      Data,
      BackgroundMigrationCancellation
    ) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError>

  static let live = BackgroundMigrationOutboxRunnerDependencies(
    latestBlockHeight: { endpoint, cancellation in
      NativeLightwalletdClient.latestBlockHeight(
        endpoint: endpoint,
        cancellation: cancellation
      )
    },
    sendTransaction: { endpoint, rawTransaction, cancellation in
      NativeLightwalletdClient.sendTransaction(
        endpoint: endpoint,
        rawTransaction: rawTransaction,
        cancellation: cancellation
      )
    }
  )
}

enum BackgroundMigrationOutboxRunner {
  static func runOnce(
    store: BackgroundMigrationOutboxStore = .shared,
    cancellation: BackgroundMigrationCancellation,
    now: Date = Date(),
    dependencies: BackgroundMigrationOutboxRunnerDependencies = .live
  ) -> BackgroundMigrationOutboxRunResult {
    if cancellation.isCancelled {
      return BackgroundMigrationOutboxRunResult(
        transport: .cancelled,
        proofReady: nil
      )
    }

    let endpoint: String
    do {
      var selectedEndpoint: String?
      _ = try store.update { snapshot in
        snapshot.recoverInterruptedSubmissions(at: now)
        selectedEndpoint = snapshot.nextEndpointForInspection()
      }
      guard let selectedEndpoint else {
        return BackgroundMigrationOutboxRunResult(
          transport: .noWork,
          proofReady: nil
        )
      }
      endpoint = selectedEndpoint
    } catch BackgroundMigrationOutboxStoreError.temporarilyUnavailable {
      return BackgroundMigrationOutboxRunResult(
        transport: .temporarilyUnavailable,
        proofReady: nil
      )
    } catch {
      return BackgroundMigrationOutboxRunResult(
        transport: .needsUserAction,
        proofReady: nil
      )
    }

    let remoteHeight: UInt64
    switch dependencies.latestBlockHeight(endpoint, cancellation) {
    case .success(let height):
      remoteHeight = height
    case .failure(.cancelled):
      return BackgroundMigrationOutboxRunResult(
        transport: .cancelled,
        proofReady: nil
      )
    case .failure:
      return BackgroundMigrationOutboxRunResult(
        transport: .temporarilyUnavailable,
        proofReady: nil
      )
    }
    if cancellation.isCancelled {
      return BackgroundMigrationOutboxRunResult(
        transport: .cancelled,
        proofReady: nil
      )
    }

    var proofReady: BackgroundMigrationProofReadyMetadata?
    let selection: BackgroundMigrationOutboxSelection
    do {
      var selected: BackgroundMigrationOutboxSelection?
      let snapshot = try store.update { snapshot in
        snapshot.expireItems(remoteHeight: remoteHeight, endpoint: endpoint, at: now)
        proofReady = snapshot.markProofReadyIfNeeded(
          remoteHeight: remoteHeight,
          endpoint: endpoint,
          at: now
        )
        selected = snapshot.selectDue(
          remoteHeight: remoteHeight,
          endpoint: endpoint,
          at: now
        )
      }
      guard let selected else {
        if snapshot.receipts.contains(where: {
          $0.outcome == .expired && $0.remoteHeight == remoteHeight
        }) {
          return BackgroundMigrationOutboxRunResult(
            transport: .needsUserAction,
            proofReady: proofReady
          )
        }
        let nextHeight = snapshot.nextActionHeight(endpoint: endpoint)
        let transport: BackgroundMigrationTransportOutcome
        if let nextHeight {
          transport = .waiting(
            nextHeight: nextHeight,
            observedHeight: remoteHeight,
            delay: BackgroundMigrationOutboxCadence.nextCheckDelay(
              remoteHeight: remoteHeight,
              nextScheduledHeight: nextHeight
            )
          )
        } else {
          transport = .noWork
        }
        return BackgroundMigrationOutboxRunResult(
          transport: transport,
          proofReady: proofReady
        )
      }
      selection = selected
      _ = try store.update { snapshot in
        try snapshot.beginSubmission(
          itemId: selection.item.itemId,
          attemptId: UUID().uuidString,
          at: now
        )
      }
    } catch BackgroundMigrationOutboxStoreError.temporarilyUnavailable {
      return BackgroundMigrationOutboxRunResult(
        transport: .temporarilyUnavailable,
        proofReady: proofReady
      )
    } catch {
      return BackgroundMigrationOutboxRunResult(
        transport: .needsUserAction,
        proofReady: proofReady
      )
    }

    if cancellation.isCancelled {
      recordUncertain(
        store: store,
        itemId: selection.item.itemId,
        error: "Background execution expired before submission.",
        at: now
      )
      return BackgroundMigrationOutboxRunResult(
        transport: .cancelled,
        proofReady: proofReady
      )
    }

    switch dependencies.sendTransaction(
      selection.lightwalletdUrl,
      selection.item.rawTransaction,
      cancellation
    ) {
    case .failure(let error):
      recordUncertain(
        store: store,
        itemId: selection.item.itemId,
        error: String(describing: error),
        at: now
      )
      return BackgroundMigrationOutboxRunResult(
        transport: error == .cancelled ? .cancelled : .temporarilyUnavailable,
        proofReady: proofReady
      )
    case .success(let response):
      do {
        if response.errorCode == 0 || isAcceptedEquivalent(response.errorMessage) {
          var random = SystemRandomNumberGenerator()
          let snapshot = try store.update { snapshot in
            try snapshot.recordAccepted(
              itemId: selection.item.itemId,
              equivalent: response.errorCode != 0,
              remoteHeight: remoteHeight,
              responseCode: response.errorCode,
              responseMessage: response.errorMessage,
              at: now,
              random: &random
            )
          }
          let nextHeight = snapshot.nextActionHeight(endpoint: endpoint)
          return BackgroundMigrationOutboxRunResult(
            transport: .accepted(
              nextHeight: nextHeight,
              observedHeight: remoteHeight,
              delay: BackgroundMigrationOutboxCadence.nextCheckDelay(
                remoteHeight: remoteHeight,
                nextScheduledHeight: nextHeight
              )
            ),
            proofReady: proofReady
          )
        }
        _ = try store.update { snapshot in
          try snapshot.recordRejected(
            itemId: selection.item.itemId,
            remoteHeight: remoteHeight,
            responseCode: response.errorCode,
            responseMessage: response.errorMessage,
            at: now
          )
        }
        return BackgroundMigrationOutboxRunResult(
          transport: .needsUserAction,
          proofReady: proofReady
        )
      } catch BackgroundMigrationOutboxStoreError.temporarilyUnavailable {
        return BackgroundMigrationOutboxRunResult(
          transport: .temporarilyUnavailable,
          proofReady: proofReady
        )
      } catch {
        return BackgroundMigrationOutboxRunResult(
          transport: .needsUserAction,
          proofReady: proofReady
        )
      }
    }
  }

  static func isAcceptedEquivalent(_ message: String) -> Bool {
    let message = message.lowercased()
    return message.contains("already in mempool")
      || message.contains("already have transaction")
      || message.contains("transaction already exists")
      || message.contains("txn-already-known")
      || message.contains("txn-already-in-mempool")
      || message.contains("already known")
  }

  private static func recordUncertain(
    store: BackgroundMigrationOutboxStore,
    itemId: String,
    error: String,
    at date: Date
  ) {
    _ = try? store.update { snapshot in
      try snapshot.recordUncertain(itemId: itemId, error: error, at: date)
    }
  }
}
