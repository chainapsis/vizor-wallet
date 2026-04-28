import 'package:flutter/widgets.dart';

class ActivityRowData {
  const ActivityRowData({
    required this.title,
    required this.leadingIconName,
    required this.leadingBackgroundColor,
    required this.leadingIconColor,
    this.subtitle,
    this.subtitleIconName,
    required this.amountText,
    this.amountIconName,
    this.amountIconColor,
    this.amountColor,
    required this.statusText,
    required this.timestampText,
    this.statusIconName,
    this.statusColor,
    this.onTap,
  });

  final String title;
  final String leadingIconName;
  final Color leadingBackgroundColor;
  final Color leadingIconColor;
  final String? subtitle;
  final String? subtitleIconName;
  final String amountText;
  final String? amountIconName;
  final Color? amountIconColor;
  final Color? amountColor;
  final String statusText;
  final String timestampText;
  final String? statusIconName;
  final Color? statusColor;
  final VoidCallback? onTap;
}
