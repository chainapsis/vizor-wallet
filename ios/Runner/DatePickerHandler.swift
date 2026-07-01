import Flutter
import UIKit

/// Presents native iOS date/month pickers as sheets over the Flutter view.
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
    case "pickMonthYear":
      pickMonthYear(call, result: result)
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

  private func pickMonthYear(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let minDate = (args["min"] as? String).flatMap(Self.dayFormatter.date(from:)),
      let maxDate = (args["max"] as? String).flatMap(Self.dayFormatter.date(from:)),
      minDate <= maxDate
    else {
      result(FlutterError(
        code: "badArgs",
        message: "pickMonthYear needs min/max as yyyy-MM-dd with min <= max",
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

    // A second picker while one is showing replaces it; the first call
    // resolves as cancelled.
    dismissPresentedSheet()
    pendingResult = result

    let initialDate = (args["initial"] as? String).flatMap(Self.dayFormatter.date(from:))
    let sheet = MonthYearPickerSheetViewController(
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
  private let interfaceStyle: UIUserInterfaceStyle
  private var pickedDate: Date?
  private var finished = false
  /// Largest calendar fitting height seen so far. The detent is
  /// monotonic — it grows for 6-week months and never shrinks back for
  /// 5-week ones — so browsing months doesn't bounce the sheet
  /// (VZR-75).
  private var maxCalendarFitHeight: CGFloat = 0

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
    self.interfaceStyle = isDarkTheme ? .dark : .light
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = interfaceStyle
    calendarView.overrideUserInterfaceStyle = interfaceStyle
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
          self.maxCalendarFitHeight = max(self.maxCalendarFitHeight, fit)
          // Grabber + vertical padding + home-indicator safe area; the
          // floor covers the pre-layout pass where the fitting height
          // is still zero (Apple's minimum calendar size is 320x371).
          return min(
            max(self.maxCalendarFitHeight + 56, 380),
            context.maximumDetentValue
          )
        }
      ]
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.overrideUserInterfaceStyle = interfaceStyle
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
    // The custom detent resolves before the calendar has a width, and
    // 6-week months fit taller than 5-week ones. Re-resolve only when
    // the calendar outgrows the tallest height seen so far — never on
    // shrink — so month navigation doesn't bounce the sheet (VZR-75).
    let fit = calendarView
      .systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      .height
    if fit > maxCalendarFitHeight, let sheet = sheetPresentationController {
      sheet.animateChanges { sheet.invalidateDetents() }
    }
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

/// Sheet for approximate wallet birthdays. iOS 17.4+ gets the native
/// `UIDatePicker.Mode.yearAndMonth` wheels; earlier iOS versions use a
/// two-column `UIPickerView` with the same month/year semantics.
private final class MonthYearPickerSheetViewController: UIViewController,
  UIPickerViewDataSource,
  UIPickerViewDelegate
{
  /// Fired exactly once, after the sheet is fully gone: a day inside the
  /// picked month, or nil for Cancel / swipe-down / programmatic dismissal.
  var onFinish: ((Date?) -> Void)?

  private let datePicker = UIDatePicker()
  private let pickerView = UIPickerView()
  private let minDate: Date
  private let maxDate: Date
  private let accentColor: UIColor?
  private let interfaceStyle: UIUserInterfaceStyle
  private weak var contentStack: UIStackView?
  private var calendar: Calendar
  private var selectedYear: Int
  private var selectedMonth: Int
  private var selectedDate: Date
  private var usesNativeMonthYearPicker = false
  private var pickedDate: Date?
  private var finished = false

  private lazy var monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("MMMM")
    formatter.timeZone = TimeZone.current
    return formatter
  }()

  init(
    initialDate: Date?,
    minDate: Date,
    maxDate: Date,
    isDarkTheme: Bool,
    accentColor: UIColor?
  ) {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = TimeZone.current
    let clampedInitial = Self.clamp(
      initialDate ?? maxDate,
      minDate: minDate,
      maxDate: maxDate
    )
    let components = gregorian.dateComponents([.year, .month], from: clampedInitial)
    let year = components.year ?? gregorian.component(.year, from: maxDate)
    let month = components.month ?? gregorian.component(.month, from: maxDate)

    self.minDate = minDate
    self.maxDate = maxDate
    self.accentColor = accentColor
    self.interfaceStyle = isDarkTheme ? .dark : .light
    self.calendar = gregorian
    self.selectedYear = year
    self.selectedMonth = month
    self.selectedDate = Self.selectionDate(
      year: year,
      month: month,
      minDate: minDate,
      maxDate: maxDate,
      calendar: gregorian
    )
    super.init(nibName: nil, bundle: nil)
    overrideUserInterfaceStyle = interfaceStyle
    modalPresentationStyle = .pageSheet
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.overrideUserInterfaceStyle = interfaceStyle
    view.backgroundColor = .systemBackground
    if let accentColor {
      view.tintColor = accentColor
    }

    let picker = makePicker()
    let separator = UIView()
    separator.backgroundColor = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

    let cancelButton = UIButton(type: .system)
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    let doneButton = UIButton(type: .system)
    doneButton.setTitle("Done", for: .normal)
    doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

    let spacer = UIView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let buttonRow = UIStackView(arrangedSubviews: [cancelButton, spacer, doneButton])
    buttonRow.axis = .horizontal
    buttonRow.alignment = .center
    buttonRow.spacing = 16

    let stack = UIStackView(arrangedSubviews: [picker, separator, buttonRow])
    stack.axis = .vertical
    stack.spacing = 12
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 20,
      leading: 20,
      bottom: 12,
      trailing: 20
    )
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentStack = stack
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
    configureSheet()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    finishIfNeeded()
  }

  private func makePicker() -> UIView {
    if #available(iOS 17.4, *) {
      usesNativeMonthYearPicker = true
      datePicker.datePickerMode = .yearAndMonth
      datePicker.preferredDatePickerStyle = .wheels
      datePicker.calendar = calendar
      datePicker.timeZone = TimeZone.current
      datePicker.minimumDate = minDate
      datePicker.maximumDate = maxDate
      datePicker.date = selectedDate
      datePicker.overrideUserInterfaceStyle = interfaceStyle
      if let accentColor {
        datePicker.tintColor = accentColor
      }
      datePicker.addTarget(
        self,
        action: #selector(datePickerChanged),
        for: .valueChanged
      )
      datePicker.translatesAutoresizingMaskIntoConstraints = false
      return datePicker
    }

    pickerView.dataSource = self
    pickerView.delegate = self
    pickerView.overrideUserInterfaceStyle = interfaceStyle
    pickerView.translatesAutoresizingMaskIntoConstraints = false
    selectFallbackRows(animated: false)
    return pickerView
  }

  private func configureSheet() {
    guard let sheet = sheetPresentationController else { return }
    sheet.prefersGrabberVisible = true
    if #available(iOS 16.0, *) {
      sheet.detents = [
        .custom(identifier: .init("monthYearContentFit")) { [weak self] context in
          guard let self, let contentStack = self.contentStack else {
            return context.maximumDetentValue
          }
          self.view.layoutIfNeeded()
          let targetWidth = max(
            0,
            self.view.bounds.width
              - self.view.safeAreaInsets.left
              - self.view.safeAreaInsets.right
          )
          let fittingSize = CGSize(
            width: targetWidth > 0
              ? targetWidth
              : UIView.layoutFittingCompressedSize.width,
            height: UIView.layoutFittingCompressedSize.height
          )
          return min(
            contentStack.systemLayoutSizeFitting(
              fittingSize,
              withHorizontalFittingPriority: targetWidth > 0
                ? .required
                : .fittingSizeLevel,
              verticalFittingPriority: .fittingSizeLevel
            ).height,
            context.maximumDetentValue
          )
        }
      ]
    } else {
      sheet.detents = [.medium()]
    }
  }

  @objc private func datePickerChanged() {
    selectedDate = Self.selectionDate(
      for: datePicker.date,
      minDate: minDate,
      maxDate: maxDate,
      calendar: calendar
    )
  }

  @objc private func cancelTapped() {
    dismiss(animated: true) { [weak self] in self?.finishIfNeeded() }
  }

  @objc private func doneTapped() {
    if usesNativeMonthYearPicker {
      datePickerChanged()
    }
    pickedDate = selectedDate
    dismiss(animated: true) { [weak self] in self?.finishIfNeeded() }
  }

  func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

  func pickerView(
    _ pickerView: UIPickerView,
    numberOfRowsInComponent component: Int
  ) -> Int {
    if component == 0 {
      return availableMonths(for: selectedYear).count
    }
    return availableYears.count
  }

  func pickerView(
    _ pickerView: UIPickerView,
    titleForRow row: Int,
    forComponent component: Int
  ) -> String? {
    if component == 0 {
      let months = availableMonths(for: selectedYear)
      guard months.indices.contains(row) else { return nil }
      return monthName(months[row])
    }
    let years = availableYears
    guard years.indices.contains(row) else { return nil }
    return "\(years[row])"
  }

  func pickerView(
    _ pickerView: UIPickerView,
    didSelectRow row: Int,
    inComponent component: Int
  ) {
    if component == 1 {
      let years = availableYears
      guard years.indices.contains(row) else { return }
      selectedYear = years[row]
      let months = availableMonths(for: selectedYear)
      if !months.contains(selectedMonth) {
        selectedMonth = min(
          max(selectedMonth, months.first ?? 1),
          months.last ?? 12
        )
      }
      pickerView.reloadComponent(0)
      if let monthIndex = months.firstIndex(of: selectedMonth) {
        pickerView.selectRow(monthIndex, inComponent: 0, animated: true)
      }
    } else {
      let months = availableMonths(for: selectedYear)
      guard months.indices.contains(row) else { return }
      selectedMonth = months[row]
    }

    selectedDate = Self.selectionDate(
      year: selectedYear,
      month: selectedMonth,
      minDate: minDate,
      maxDate: maxDate,
      calendar: calendar
    )
  }

  private var minYear: Int { calendar.component(.year, from: minDate) }
  private var maxYear: Int { calendar.component(.year, from: maxDate) }
  private var availableYears: [Int] { Array(minYear...maxYear) }

  private func availableMonths(for year: Int) -> [Int] {
    let minMonth = calendar.component(.month, from: minDate)
    let maxMonth = calendar.component(.month, from: maxDate)
    let start = year == minYear ? minMonth : 1
    let end = year == maxYear ? maxMonth : 12
    return Array(start...end)
  }

  private func selectFallbackRows(animated: Bool) {
    let years = availableYears
    if let yearIndex = years.firstIndex(of: selectedYear) {
      pickerView.selectRow(yearIndex, inComponent: 1, animated: animated)
    }
    let months = availableMonths(for: selectedYear)
    if let monthIndex = months.firstIndex(of: selectedMonth) {
      pickerView.selectRow(monthIndex, inComponent: 0, animated: animated)
    }
  }

  private func monthName(_ month: Int) -> String {
    var components = DateComponents()
    components.calendar = calendar
    components.year = 2000
    components.month = month
    components.day = 1
    guard let date = calendar.date(from: components) else { return "\(month)" }
    return monthFormatter.string(from: date)
  }

  private func finishIfNeeded() {
    guard !finished else { return }
    finished = true
    onFinish?(pickedDate)
  }

  private static func clamp(_ date: Date, minDate: Date, maxDate: Date) -> Date {
    min(max(date, minDate), maxDate)
  }

  private static func selectionDate(
    for date: Date,
    minDate: Date,
    maxDate: Date,
    calendar: Calendar
  ) -> Date {
    let components = calendar.dateComponents([.year, .month], from: date)
    return selectionDate(
      year: components.year ?? calendar.component(.year, from: maxDate),
      month: components.month ?? calendar.component(.month, from: maxDate),
      minDate: minDate,
      maxDate: maxDate,
      calendar: calendar
    )
  }

  private static func selectionDate(
    year: Int,
    month: Int,
    minDate: Date,
    maxDate: Date,
    calendar: Calendar
  ) -> Date {
    var components = DateComponents()
    components.calendar = calendar
    components.year = year
    components.month = month
    components.day = 1
    let monthStart = calendar.date(from: components) ?? minDate
    return clamp(monthStart, minDate: minDate, maxDate: maxDate)
  }
}
