import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';

class ImportBirthdayCalendarOverlay extends StatelessWidget {
  const ImportBirthdayCalendarOverlay({
    required this.initialMonth,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDismiss,
    required this.onDateSelected,
    super.key,
  });

  final DateTime initialMonth;
  final DateTime? selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final VoidCallback onDismiss;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return AppPaneModalOverlay(
      borderRadius: BorderRadius.circular(AppDesktopSidebarSurface.glassRadius),
      onDismiss: onDismiss,
      child: ImportBirthdayCalendarPanel(
        initialMonth: initialMonth,
        selectedDate: selectedDate,
        firstDate: firstDate,
        lastDate: lastDate,
        onDateSelected: onDateSelected,
      ),
    );
  }
}

/// The calendar body itself (month/year navigation + day grid), shared
/// by the desktop pane overlay above and the mobile birthday sheet.
class ImportBirthdayCalendarPanel extends StatefulWidget {
  const ImportBirthdayCalendarPanel({
    required this.initialMonth,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateSelected,
    super.key,
  });

  final DateTime initialMonth;
  final DateTime? selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  State<ImportBirthdayCalendarPanel> createState() =>
      _ImportBirthdayCalendarPanelState();
}

enum _CalendarSelectionMode { day, month, year }

class _ImportBirthdayCalendarPanelState
    extends State<ImportBirthdayCalendarPanel> {
  static const _panelWidth = 312.0;
  static const _calendarWidth = 280.0;
  static const _cellSize = 40.0;
  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  late DateTime _visibleMonth;
  late int _visibleYearPageStart;
  _CalendarSelectionMode _selectionMode = _CalendarSelectionMode.day;

  @override
  void initState() {
    super.initState();
    _visibleMonth = _monthStart(widget.initialMonth);
    _visibleYearPageStart = _yearPageStartFor(_visibleMonth.year);
  }

  DateTime get _firstMonth => _monthStart(widget.firstDate);
  DateTime get _lastMonth => _monthStart(widget.lastDate);

  bool get _canGoPrevious {
    return switch (_selectionMode) {
      _CalendarSelectionMode.day => _visibleMonth.isAfter(_firstMonth),
      _CalendarSelectionMode.month => _visibleMonth.year > _firstMonth.year,
      _CalendarSelectionMode.year =>
        _visibleYearPageStart > _yearPageStartFor(_firstMonth.year),
    };
  }

  bool get _canGoNext {
    return switch (_selectionMode) {
      _CalendarSelectionMode.day => _visibleMonth.isBefore(_lastMonth),
      _CalendarSelectionMode.month => _visibleMonth.year < _lastMonth.year,
      _CalendarSelectionMode.year =>
        _visibleYearPageStart < _yearPageStartFor(_lastMonth.year),
    };
  }

  String get _titleLabel {
    return switch (_selectionMode) {
      _CalendarSelectionMode.day => _formatMonth(_visibleMonth),
      _CalendarSelectionMode.month => '${_visibleMonth.year}',
      _CalendarSelectionMode.year =>
        '$_visibleYearPageStart - ${_visibleYearPageStart + 11}',
    };
  }

  void _showPreviousPeriod() {
    if (!_canGoPrevious) return;
    setState(() {
      switch (_selectionMode) {
        case _CalendarSelectionMode.day:
          _visibleMonth = _clampMonth(
            DateTime(_visibleMonth.year, _visibleMonth.month - 1),
            _firstMonth,
            _lastMonth,
          );
        case _CalendarSelectionMode.month:
          _visibleMonth = _clampMonth(
            DateTime(_visibleMonth.year - 1, _visibleMonth.month),
            _firstMonth,
            _lastMonth,
          );
          _visibleYearPageStart = _yearPageStartFor(_visibleMonth.year);
        case _CalendarSelectionMode.year:
          _visibleYearPageStart -= 12;
      }
    });
  }

  void _showNextPeriod() {
    if (!_canGoNext) return;
    setState(() {
      switch (_selectionMode) {
        case _CalendarSelectionMode.day:
          _visibleMonth = _clampMonth(
            DateTime(_visibleMonth.year, _visibleMonth.month + 1),
            _firstMonth,
            _lastMonth,
          );
        case _CalendarSelectionMode.month:
          _visibleMonth = _clampMonth(
            DateTime(_visibleMonth.year + 1, _visibleMonth.month),
            _firstMonth,
            _lastMonth,
          );
          _visibleYearPageStart = _yearPageStartFor(_visibleMonth.year);
        case _CalendarSelectionMode.year:
          _visibleYearPageStart += 12;
      }
    });
  }

  void _handleTitleTap() {
    setState(() {
      switch (_selectionMode) {
        case _CalendarSelectionMode.day:
          _selectionMode = _CalendarSelectionMode.month;
        case _CalendarSelectionMode.month:
          _visibleYearPageStart = _yearPageStartFor(_visibleMonth.year);
          _selectionMode = _CalendarSelectionMode.year;
        case _CalendarSelectionMode.year:
          _selectionMode = _CalendarSelectionMode.month;
      }
    });
  }

  void _selectMonth(int month) {
    setState(() {
      _visibleMonth = _clampMonth(
        DateTime(_visibleMonth.year, month),
        _firstMonth,
        _lastMonth,
      );
      _selectionMode = _CalendarSelectionMode.day;
    });
  }

  void _selectYear(int year) {
    setState(() {
      _visibleMonth = _clampMonth(
        DateTime(year, _visibleMonth.month),
        _firstMonth,
        _lastMonth,
      );
      _visibleYearPageStart = _yearPageStartFor(_visibleMonth.year);
      _selectionMode = _CalendarSelectionMode.month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: _calendarPanelShadow(colors),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          width: _panelWidth - AppSpacing.sm * 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    _CalendarTitle(label: _titleLabel, onTap: _handleTitleTap),
                    const Spacer(),
                    _CalendarNavButton(
                      iconName: AppIcons.chevronBackward,
                      enabled: _canGoPrevious,
                      onTap: _showPreviousPeriod,
                    ),
                    _CalendarNavButton(
                      iconName: AppIcons.chevronForward,
                      enabled: _canGoNext,
                      onTap: _showNextPeriod,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const AppDecorativeDivider(width: _calendarWidth),
              const SizedBox(height: AppSpacing.xs),
              ...switch (_selectionMode) {
                _CalendarSelectionMode.day => [
                  _WeekdayRow(weekdays: _weekdays),
                  _DayGrid(
                    visibleMonth: _visibleMonth,
                    selectedDate: widget.selectedDate,
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    cellSize: _cellSize,
                    onDateSelected: widget.onDateSelected,
                  ),
                ],
                _CalendarSelectionMode.month => [
                  _MonthGrid(
                    visibleYear: _visibleMonth.year,
                    selectedMonth: widget.selectedDate ?? _visibleMonth,
                    firstMonth: _firstMonth,
                    lastMonth: _lastMonth,
                    width: _calendarWidth,
                    onMonthSelected: _selectMonth,
                  ),
                ],
                _CalendarSelectionMode.year => [
                  _YearGrid(
                    pageStartYear: _visibleYearPageStart,
                    selectedYear: (widget.selectedDate ?? _visibleMonth).year,
                    firstYear: _firstMonth.year,
                    lastYear: _lastMonth.year,
                    width: _calendarWidth,
                    onYearSelected: _selectYear,
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarTitle extends StatelessWidget {
  const _CalendarTitle({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.button.ghost.label,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                AppIcons.expand,
                size: 16,
                color: colors.button.ghost.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarNavButton extends StatelessWidget {
  const _CalendarNavButton({
    required this.iconName,
    required this.enabled,
    required this.onTap,
  });

  final String iconName;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = enabled ? colors.button.ghost.label : colors.icon.disabled;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(child: AppIcon(iconName, size: 16, color: color)),
        ),
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow({required this.weekdays});

  final List<String> weekdays;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (final weekday in weekdays)
          SizedBox(
            width: _ImportBirthdayCalendarPanelState._cellSize,
            height: _ImportBirthdayCalendarPanelState._cellSize,
            child: Center(
              child: Text(
                weekday,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleYear,
    required this.selectedMonth,
    required this.firstMonth,
    required this.lastMonth,
    required this.width,
    required this.onMonthSelected,
  });

  static const _monthLabels = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final int visibleYear;
  final DateTime selectedMonth;
  final DateTime firstMonth;
  final DateTime lastMonth;
  final double width;
  final ValueChanged<int> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    final cellWidth = width / 3;
    return SizedBox(
      width: width,
      child: Wrap(
        children: [
          for (var index = 0; index < _monthLabels.length; index++)
            _MonthCell(
              label: _monthLabels[index],
              month: DateTime(visibleYear, index + 1),
              selectedMonth: selectedMonth,
              firstMonth: firstMonth,
              lastMonth: lastMonth,
              width: cellWidth,
              onMonthSelected: onMonthSelected,
            ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.month,
    required this.selectedMonth,
    required this.firstMonth,
    required this.lastMonth,
    required this.width,
    required this.onMonthSelected,
  });

  final String label;
  final DateTime month;
  final DateTime selectedMonth;
  final DateTime firstMonth;
  final DateTime lastMonth;
  final double width;
  final ValueChanged<int> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = !month.isBefore(firstMonth) && !month.isAfter(lastMonth);
    final selected = _isSameMonth(month, selectedMonth);
    final textColor = selected
        ? colors.text.inverse
        : enabled
        ? colors.text.accent
        : colors.text.muted;

    final child = Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colors.background.inverse
              : colors.background.ground.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: SizedBox(
          width: 56,
          height: 32,
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onMonthSelected(month.month) : null,
        child: SizedBox(width: width, height: 48, child: child),
      ),
    );
  }
}

class _YearGrid extends StatelessWidget {
  const _YearGrid({
    required this.pageStartYear,
    required this.selectedYear,
    required this.firstYear,
    required this.lastYear,
    required this.width,
    required this.onYearSelected,
  });

  final int pageStartYear;
  final int selectedYear;
  final int firstYear;
  final int lastYear;
  final double width;
  final ValueChanged<int> onYearSelected;

  @override
  Widget build(BuildContext context) {
    final cellWidth = width / 3;
    return SizedBox(
      width: width,
      child: Wrap(
        children: [
          for (var index = 0; index < 12; index++)
            _YearCell(
              year: pageStartYear + index,
              selectedYear: selectedYear,
              firstYear: firstYear,
              lastYear: lastYear,
              width: cellWidth,
              onYearSelected: onYearSelected,
            ),
        ],
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.year,
    required this.selectedYear,
    required this.firstYear,
    required this.lastYear,
    required this.width,
    required this.onYearSelected,
  });

  final int year;
  final int selectedYear;
  final int firstYear;
  final int lastYear;
  final double width;
  final ValueChanged<int> onYearSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = year >= firstYear && year <= lastYear;
    final selected = year == selectedYear;
    final textColor = selected
        ? colors.text.inverse
        : enabled
        ? colors.text.accent
        : colors.text.muted;

    final child = Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colors.background.inverse
              : colors.background.ground.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: SizedBox(
          width: 64,
          height: 32,
          child: Center(
            child: Text(
              '$year',
              style: AppTypography.labelLarge.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onYearSelected(year) : null,
        child: SizedBox(width: width, height: 48, child: child),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.cellSize,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final double cellSize;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = _monthStart(visibleMonth);
    final leadingDays = firstOfMonth.weekday % DateTime.daysPerWeek;
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final minimumCells = leadingDays + daysInMonth;
    final neededRows = _ceilDiv(minimumCells, DateTime.daysPerWeek);
    final rowCount = neededRows < 5 ? 5 : neededRows;
    final cellCount = rowCount * DateTime.daysPerWeek;
    final firstCellDate = firstOfMonth.subtract(Duration(days: leadingDays));

    return SizedBox(
      width: cellSize * DateTime.daysPerWeek,
      child: Wrap(
        children: [
          for (var index = 0; index < cellCount; index++)
            _DayCell(
              date: firstCellDate.add(Duration(days: index)),
              visibleMonth: visibleMonth,
              selectedDate: selectedDate,
              firstDate: firstDate,
              lastDate: lastDate,
              size: cellSize,
              onDateSelected: onDateSelected,
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.visibleMonth,
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.size,
    required this.onDateSelected,
  });

  final DateTime date;
  final DateTime visibleMonth;
  final DateTime? selectedDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final double size;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final currentMonth = date.month == visibleMonth.month;
    final enabled =
        currentMonth &&
        !_isDateBefore(date, firstDate) &&
        !_isDateAfter(date, lastDate);
    final selected = selectedDate != null && _isSameDate(date, selectedDate!);
    final textColor = selected
        ? colors.text.inverse
        : enabled
        ? colors.text.accent
        : colors.text.muted;

    Widget child = Center(
      child: Text(
        '${date.day}',
        style: AppTypography.labelLarge.copyWith(color: textColor),
      ),
    );

    if (selected) {
      child = Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            shape: BoxShape.circle,
          ),
          child: SizedBox(width: size, height: size, child: child),
        ),
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onDateSelected(_dateOnly(date)) : null,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}

List<BoxShadow> _calendarPanelShadow(AppColors colors) {
  return [
    BoxShadow(
      color: colors.shadows.regular,
      offset: const Offset(0, 4),
      blurRadius: 16,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

DateTime _monthStart(DateTime value) {
  return DateTime(value.year, value.month);
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

bool _isDateBefore(DateTime value, DateTime boundary) {
  return _dateOnly(value).isBefore(_dateOnly(boundary));
}

bool _isDateAfter(DateTime value, DateTime boundary) {
  return _dateOnly(value).isAfter(_dateOnly(boundary));
}

int _ceilDiv(int value, int divisor) {
  return (value + divisor - 1) ~/ divisor;
}

DateTime _clampMonth(DateTime value, DateTime firstMonth, DateTime lastMonth) {
  final month = _monthStart(value);
  if (month.isBefore(firstMonth)) return firstMonth;
  if (month.isAfter(lastMonth)) return lastMonth;
  return month;
}

int _yearPageStartFor(int year) {
  const pageSize = 12;
  return year - ((year - 1) % pageSize);
}

String _formatMonth(DateTime date) {
  const monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${monthNames[date.month - 1]} ${date.year}';
}
