import 'package:flutter/widgets.dart';

class ActivityRowData {
  const ActivityRowData({
    this.stableId,
    required this.title,
    required this.leadingIconName,
    required this.leadingBackgroundColor,
    required this.leadingIconColor,
    this.leadingProgressValue,
    this.subtitle,
    this.subtitleIconName,
    required this.amountText,
    this.amountIconName,
    this.amountIconColor,
    this.amountColor,
    this.amountSubtitle,
    this.amountSubtitleIconName,
    this.amountSubtitleIconColor,
    required this.statusText,
    this.statusIsRoutine = false,
    required this.timestampText,
    this.statusIconName,
    this.statusColor,
    this.backgroundColor,
    this.selected = false,
    this.childRows = const [],
    this.onTap,
  });

  final String? stableId;
  final String title;
  final String leadingIconName;
  final Color leadingBackgroundColor;
  final Color leadingIconColor;
  final double? leadingProgressValue;
  final String? subtitle;
  final String? subtitleIconName;
  final String amountText;
  final String? amountIconName;
  final Color? amountIconColor;
  final Color? amountColor;
  final String? amountSubtitle;
  final String? amountSubtitleIconName;
  final Color? amountSubtitleIconColor;
  final String statusText;

  /// Whether [statusText] is a routine state (completed or in progress), so
  /// the feed shows the timestamp under the amount instead of the status.
  final bool statusIsRoutine;
  final String timestampText;
  final String? statusIconName;
  final Color? statusColor;
  final Color? backgroundColor;
  final bool selected;
  final List<ActivityRowData> childRows;
  final VoidCallback? onTap;
}
