import StoreKit
import SwiftUI
import UIKit

struct GiftClipView: View {
  @ObservedObject var model: GiftClipModel
  @State private var showsInstallOverlay = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      switch model.state {
      case .waiting:
        header(
          title: "Claim a Vizor gift card",
          detail: "Open the gift card link you received to see your gift."
        )
      case .invalid:
        header(
          title: "This gift link can't be opened",
          detail: "Ask the sender to share the complete gift card link again."
        )
      case .gift(let preview, let saved):
        giftDetails(preview, saved: saved)
      }

      Spacer(minLength: 0)

      Button {
        showsInstallOverlay = true
      } label: {
        Text(installLabel)
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 52)
      }
      .buttonStyle(.borderedProminent)
      .tint(.primary)
      .foregroundStyle(Color(uiColor: .systemBackground))
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .appStoreOverlay(isPresented: $showsInstallOverlay) {
      SKOverlay.AppClipConfiguration(position: .bottom)
    }
  }

  private var installLabel: String {
    if case .gift = model.state {
      return "Get Vizor to claim"
    }
    return "Get Vizor"
  }

  private func header(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title.bold())
      Text(detail)
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .padding(.top, 24)
  }

  @ViewBuilder
  private func giftDetails(_ preview: GiftLinkPreview, saved: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("You received a gift")
        .font(.headline)
        .foregroundStyle(.secondary)
      if let zec = preview.zecAmountText {
        Text("\(zec) ZEC")
          .font(.system(size: 40, weight: .bold))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
      }
      if let usd = preview.fiatUsd {
        Text("About \(usd, format: .currency(code: "USD")) when sent")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.top, 24)

    if let message = preview.message {
      Text(message)
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    Label {
      Text(
        saved
          ? "Saved on this iPhone. Vizor opens this gift after you install it."
          : "Install Vizor, then open this gift card link again."
      )
    } icon: {
      Image(systemName: saved ? "lock" : "arrow.uturn.left")
    }
    .font(.footnote)
    .foregroundStyle(.secondary)

    Text("Vizor checks the gift before you claim it.")
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}
