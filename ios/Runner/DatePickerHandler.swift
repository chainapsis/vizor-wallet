import Flutter
import UIKit

/// Presents the native iOS date picker as a sheet over the Flutter view.
/// Channel: `com.zcash.wallet/date_picker` (Dart side:
/// `lib/src/services/native_date_picker.dart`).
///
/// Uses `UICalendarView` (iOS 16+) rather than an inline `UIDatePicker`
/// because only the calendar view distinguishes "tapped a day" from
/// "browsed to another month" — the date picker fires `.valueChanged`
/// for both, which would auto-dismiss while the user is still
/// navigating. Below iOS 16 the channel reports `unavailable` and the
/// Dart caller falls back to the Flutter calendar sheet.
final class DatePickerHandler: NSObject {
  static let shared = DatePickerHandler()
  private override init() { super.init() }

  /// Pending Dart result — exactly one resolution per pickDate call.
  private var pendingResult: FlutterResult?
  private weak var presentedSheet: UIViewController?

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    // Local midnight on both sides: Dart sends DateTime(y, m, d)
    // components, so the calendar day — not an instant — is the unit.
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickDate":
      pickDate(call, result: result)
    case "cancel":
      dismissPresentedSheet()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pickDate(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(FlutterError(
        code: "unavailable",
        message: "Native date picker requires iOS 16",
        details: nil
      ))
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let minDate = (args["min"] as? String).flatMap(Self.dayFormatter.date(from:)),
      let maxDate = (args["max"] as? String).flatMap(Self.dayFormatter.date(from:)),
      minDate <= maxDate
    else {
      result(FlutterError(
        code: "badArgs",
        message: "pickDate needs min/max as yyyy-MM-dd with min <= max",
        details: nil
      ))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(
        code: "noViewController",
        message: "No view controller to present from",
        details: nil
      ))
      return
    }

    // A second pickDate while one is showing replaces it; the first
    // call resolves as cancelled.
    dismissPresentedSheet()
    pendingResult = result

    let initialDate = (args["initial"] as? String).flatMap(Self.dayFormatter.date(from:))
    let sheet = DatePickerSheetViewController(
      initialDate: initialDate,
      minDate: minDate,
      maxDate: maxDate,
      isDarkTheme: args["isDarkTheme"] as? Bool ?? false,
      accentColor: (args["accentColorHex"] as? String).flatMap(Self.color(fromHex:))
    )
    sheet.onFinish = { [weak self] date in
      self?.finish(with: date)
    }
    presentedSheet = sheet
    presenter.present(sheet, animated: true)
  }

  /// Resolves the pending Dart future. The sheet controller guarantees
  /// a single `onFinish`, but guard anyway — a second resolution of a
  /// FlutterResult is a crash.
  private func finish(with date: Date?) {
    guard let result = pendingResult else { return }
    pendingResult = nil
    presentedSheet = nil
    result(date.map(Self.dayFormatter.string(from:)))
  }

  private func dismissPresentedSheet() {
    guard let sheet = presentedSheet else { return }
    presentedSheet = nil
    // viewDidDisappear fires onFinish(nil) for the cancelled call.
    sheet.dismiss(animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  /// `RRGGBB` (no leading #) → UIColor.
  private static func color(fromHex hex: String) -> UIColor? {
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    return UIColor(
      red: CGFloat((value >> 16) & 0xFF) / 255.0,
      green: CGFloat((value >> 8) & 0xFF) / 255.0,
      blue: CGFloat(value & 0xFF) / 255.0,
      alpha: 1.0
    )
  }
}

/// Sheet hosting a `UICalendarView` in a detent sized to the calendar's
/// fitting height (capped at the large-detent maximum), so the sheet
/// hugs its content instead of covering the screen.
@available(iOS 16.0, *)
private final class DatePickerSheetViewController: UIViewController,
  UICalendarSelectionSingleDateDelegate
{
  /// Fired exactly once, after the sheet is fully gone: the picked day,
  /// or nil for swipe-down / programmatic dismissal.
  var onFinish: ((Date?) -> Void)?

  private let calendarView = UICalendarView()
  private let initialDate: Date?
  private let minDate: Date
  private let maxDate: Date
  private var pickedDate: Date?
  private var finished = false

  init(
    initialDate: Date?,
    minDate: Date,
    maxDate: Date,
    isDarkTheme: Bool,
    accentColor: UIColor?
  ) {
    self.initialDate = initialDate
    self.minDate = minDate
    self.maxDate = maxDate
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = isDarkTheme ? .dark : .light
    if let accentColor {
      calendarView.tintColor = accentColor
    }
    modalPresentationStyle = .pageSheet
    if let sheet = sheetPresentationController {
      sheet.prefersGrabberVisible = true
      sheet.detents = [
        .custom(identifier: .init("calendarFit")) { [weak self] context in
          guard let self else { return context.maximumDetentValue }
          let fit = self.calendarView
            .systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            .height
          // Grabber + vertical padding + home-indicator safe area; the
          // floor covers the pre-layout pass where the fitting height
          // is still zero (Apple's minimum calendar size is 320x371).
          return min(max(fit + 56, 380), context.maximumDetentValue)
        }
      ]
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone.current
    calendarView.calendar = gregorian
    calendarView.availableDateRange = DateInterval(start: minDate, end: maxDate)

    let selection = UICalendarSelectionSingleDate(delegate: self)
    if let initialDate {
      selection.setSelected(
        gregorian.dateComponents([.year, .month, .day], from: initialDate),
        animated: false
      )
    }
    calendarView.selectionBehavior = selection
    calendarView.visibleDateComponents = gregorian.dateComponents(
      [.year, .month],
      from: initialDate ?? maxDate
    )

    calendarView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(calendarView)
    NSLayoutConstraint.activate([
      calendarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
      calendarView.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      calendarView.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      calendarView.bottomAnchor.constraint(
        lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The custom detent resolves before the calendar has a width; once
    // laid out, re-resolve so the sheet settles at the true fit height.
    sheetPresentationController?.invalidateDetents()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    finishIfNeeded()
  }

  func dateSelection(
    _ selection: UICalendarSelectionSingleDate,
    didSelectDate dateComponents: DateComponents?
  ) {
    guard let dateComponents, let date = calendarView.calendar.date(from: dateComponents)
    else { return }
    pickedDate = date
    // Brief beat so the selection circle is visible before the sheet goes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self else { return }
      self.dismiss(animated: true) { self.finishIfNeeded() }
    }
  }

  private func finishIfNeeded() {
    guard !finished else { return }
    finished = true
    onFinish?(pickedDate)
  }
}
