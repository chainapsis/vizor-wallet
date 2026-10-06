import Foundation

/// Display-only summary of a Gift Card link for the App Clip.
///
/// Reads the amount, USD snapshot, and message from the link fragment
/// (`docs/compact-gift-links.md`). It never decodes or exposes the gift
/// secret, and it is not a validator: the full app's Dart parser decides
/// whether the link can be claimed. Unreadable fields come back `nil`.
struct GiftLinkPreview: Equatable {
  /// Whole zatoshi as an unsigned decimal string, for example `"1000000"`.
  let amountZatoshi: String?
  let fiatUsd: Double?
  let message: String?

  init(amountZatoshi: String?, fiatUsd: Double?, message: String?) {
    self.amountZatoshi = amountZatoshi
    self.fiatUsd = fiatUsd
    self.message = message
  }

  init(url: URL) {
    guard let fragment = url.fragment else {
      self.init(amountZatoshi: nil, fiatUsd: nil, message: nil)
      return
    }
    if fragment.hasPrefix("v3="),
      let json = Self.decodeJson(String(fragment.dropFirst(3))) as? [Any]
    {
      self.init(
        amountZatoshi: Self.validAmount(json.count > 3 ? json[3] : nil),
        fiatUsd: Self.validFiat(json.count > 5 ? json[5] : nil),
        message: Self.validMessage(json.count > 6 ? json[6] : nil)
      )
    } else if fragment.hasPrefix("v2=") || fragment.hasPrefix("v1="),
      let json = Self.decodeJson(String(fragment.dropFirst(3))) as? [String: Any]
    {
      let presentation = json["presentation"] as? [String: Any]
      let fiat = presentation?["fiat"] as? [String: Any]
      self.init(
        amountZatoshi: Self.validAmount(json["amountZatoshi"]),
        fiatUsd: Self.validFiat(fiat?["amount"]),
        message: Self.validMessage(presentation?["message"])
      )
    } else {
      self.init(amountZatoshi: nil, fiatUsd: nil, message: nil)
    }
  }

  /// The amount in ZEC without trailing zeroes, for example `"0.01"`.
  /// Integer math only, so no floating-point rounding.
  var zecAmountText: String? {
    guard let amountZatoshi else { return nil }
    let padded = String(repeating: "0", count: max(0, 9 - amountZatoshi.count))
      + amountZatoshi
    let whole = String(padded.dropLast(8))
    var fraction = String(padded.suffix(8))
    while fraction.hasSuffix("0") {
      fraction.removeLast()
    }
    return fraction.isEmpty ? whole : "\(whole).\(fraction)"
  }

  private static func decodeJson(_ base64Url: String) -> Any? {
    var base64 = base64Url
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 = base64.trimmingCharacters(in: CharacterSet(charactersIn: "="))
    let remainder = base64.count % 4
    if remainder == 1 { return nil }
    if remainder > 0 {
      base64 += String(repeating: "=", count: 4 - remainder)
    }
    guard let data = Data(base64Encoded: base64) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }

  private static func validAmount(_ value: Any?) -> String? {
    guard
      let text = value as? String,
      (1...16).contains(text.count),
      text.first != "0",
      text.allSatisfy({ $0.isASCII && $0.isNumber })
    else {
      return nil
    }
    return text
  }

  private static func validFiat(_ value: Any?) -> Double? {
    guard
      let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else {
      return nil
    }
    let amount = number.doubleValue
    return amount.isFinite && amount >= 0 ? amount : nil
  }

  private static func validMessage(_ value: Any?) -> String? {
    guard let text = (value as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      return nil
    }
    // Dart caps messages at 128 grapheme clusters; never show more.
    return String(text.prefix(128))
  }
}
