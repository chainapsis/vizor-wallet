import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/activity_row_data.dart';

const _activityFeedActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

/// Vertical gap between a row's two stacked lines (title/subtitle and
/// amount/timestamp). Mobile gets a touch more breathing room; desktop
/// keeps the lines tight as before. Const so the dead branch is
/// tree-shaken per form factor.
const _activityRowInnerLineGap = kAppFormFactor == AppFormFactor.mobile
    ? AppSpacing.xxs
    : 0.0;

/// Sub-line text style — the subtitle (Shielded / Transparent) and the
/// supporting amount line (timestamp / status). Mobile bumps these to the
/// 16px label token; desktop keeps the smaller label. Const-branched so
/// the unused form factor is tree-shaken.
const _activityRowSubLineStyle = kAppFormFactor == AppFormFactor.mobile
    ? AppTypography.labelLarge
    : AppTypography.labelMedium;

/// Sub-line leading icon (the shielded / transparent badge). Mobile uses
/// the 16px medium icon token; desktop keeps the previous 14px.
const _activityRowSubtitleIconSize = kAppFormFactor == AppFormFactor.mobile
    ? AppIconSize.medium
    : 14.0;

class ActivityFeedSectionData {
  const ActivityFeedSectionData({required this.title, required this.rows});

  final String title;
  final List<ActivityRowData> rows;
}

class ActivityFeed extends StatelessWidget {
  const ActivityFeed({
    required this.sections,
    this.isLoading = false,
    this.errorText,
    this.emptyText = 'No activity yet',
    this.rowKeyPrefix,
    this.cardWidth = 396,
    this.showHeader = true,
    super.key,
  });

  final List<ActivityFeedSectionData> sections;
  final bool isLoading;
  final String? errorText;
  final String emptyText;
  final String? rowKeyPrefix;

  /// Fixed card width. The 396px default matches the desktop pane;
  /// mobile passes null so cards stretch to the parent width.
  final double? cardWidth;

  /// Whether to render the desktop title row ("Activity" + filter).
  /// Mobile surfaces provide their own top nav title instead.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: _ActivityFeedTitleRow(),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: _ActivityFeedBody(
            sections: sections,
            isLoading: isLoading,
            errorText: errorText,
            emptyText: emptyText,
            rowKeyPrefix: rowKeyPrefix,
            cardWidth: cardWidth,
          ),
        ),
      ],
    );
  }
}

class _ActivityFeedTitleRow extends StatelessWidget {
  const _ActivityFeedTitleRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('activity_screen_title_row'),
      height: 33,
      child: Stack(
        children: [
          Center(
            child: Text(
              'Activity',
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
                letterSpacing: 0,
              ),
            ),
          ),
          const Positioned(right: 0, top: 8, child: _ActivityFilterButton()),
        ],
      ),
    );
  }
}

class _ActivityFilterButton extends StatelessWidget {
  const _ActivityFilterButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('activity_screen_filter_button'),
      width: 62,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 42,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  key: const ValueKey('activity_screen_filter_label'),
                  'Filter',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.disabled,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.filter,
            key: const ValueKey('activity_screen_filter_icon'),
            size: 16,
            color: colors.icon.disabled,
          ),
        ],
      ),
    );
  }
}

class _ActivityFeedBody extends StatelessWidget {
  const _ActivityFeedBody({
    required this.sections,
    required this.isLoading,
    required this.errorText,
    required this.emptyText,
    required this.rowKeyPrefix,
    required this.cardWidth,
  });

  final List<ActivityFeedSectionData> sections;
  final bool isLoading;
  final String? errorText;
  final String emptyText;
  final String? rowKeyPrefix;
  final double? cardWidth;

  @override
  Widget build(BuildContext context) {
    final message = errorText ?? (isLoading ? 'Loading activity...' : null);
    if (message != null && sections.isEmpty) {
      return _ActivityFeedMessageCard(
        text: message,
        isError: errorText != null,
        width: cardWidth,
      );
    }
    if (sections.isEmpty) {
      return _ActivityFeedMessageCard(text: emptyText, width: cardWidth);
    }

    var rowIndex = 0;
    return Column(
      children: [
        for (
          var sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) ...[
          if (sectionIndex > 0) const SizedBox(height: AppSpacing.md),
          _ActivityFeedCard(
            section: sections[sectionIndex],
            width: cardWidth,
            rowKeyBuilder: rowKeyPrefix == null
                ? null
                : () => ValueKey('${rowKeyPrefix}_row_${rowIndex++}'),
          ),
        ],
        const SizedBox(height: AppSpacing.base),
      ],
    );
  }
}

class _ActivityFeedMessageCard extends StatelessWidget {
  const _ActivityFeedMessageCard({
    required this.text,
    required this.width,
    this.isError = false,
  });

  final String text;
  final double? width;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      height: 160,
      child: _ActivityFeedCardShell(
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.labelLarge.copyWith(
              color: isError ? colors.text.destructive : colors.text.secondary,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedCard extends StatelessWidget {
  const _ActivityFeedCard({
    required this.section,
    required this.width,
    this.rowKeyBuilder,
  });

  final ActivityFeedSectionData section;
  final double? width;
  final ValueKey<String> Function()? rowKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: width,
      child: _ActivityFeedCardShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Text(
                    section.title,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.secondary,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              for (var index = 0; index < section.rows.length; index++) ...[
                if (index > 0) const SizedBox(height: AppSpacing.s),
                ActivityFeedRowGroup(
                  key: rowKeyBuilder?.call(),
                  row: section.rows[index],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedCardShell extends StatelessWidget {
  const _ActivityFeedCardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ActivityFeedRowGroup extends StatelessWidget {
  const ActivityFeedRowGroup({required this.row, super.key});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    if (row.childRows.isEmpty) {
      return ActivityFeedRow(row: row);
    }

    return Column(
      children: [
        ActivityFeedRow(row: row),
        for (final childRow in row.childRows)
          ActivityFeedRow(row: childRow, compact: true, childRow: true),
      ],
    );
  }
}

class ActivityFeedRow extends StatefulWidget {
  const ActivityFeedRow({
    required this.row,
    this.compact = false,
    this.childRow = false,
    super.key,
  });

  final ActivityRowData row;
  final bool compact;
  final bool childRow;

  @override
  State<ActivityFeedRow> createState() => _ActivityFeedRowState();
}

class _ActivityFeedRowState extends State<ActivityFeedRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant ActivityFeedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.title != widget.row.title ||
        oldWidget.row.amountText != widget.row.amountText ||
        oldWidget.row.statusText != widget.row.statusText ||
        oldWidget.row.timestampText != widget.row.timestampText) {
      _hovered = false;
      _focused = false;
    }
  }

  void _handleHoverChanged(bool value) {
    if (_hovered == value) return;
    setState(() {
      _hovered = value;
    });
  }

  void _handleFocusChanged(bool value) {
    if (_focused == value) return;
    setState(() {
      _focused = value;
    });
  }

  void _activate() {
    _handleHoverChanged(false);
    widget.row.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = widget.row;
    final isInteractive = row.onTap != null && !widget.childRow;
    final rowHeight = widget.compact ? 40.0 : 44.0;
    final showSelectedBorder = row.selected && !widget.childRow;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: rowHeight,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: isInteractive && _hovered
                ? colors.state.hoverOpacity
                : row.backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    widget.childRow
                        ? const _ActivityChildConnector()
                        : _ActivityRowIcon(row: row),
                    const SizedBox(width: AppSpacing.s),
                    Flexible(child: _ActivityRowTitle(row: row)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ActivityRowAmount(row: row, childRow: widget.childRow),
            ],
          ),
        ),
        if (showSelectedBorder || (isInteractive && _focused))
          Positioned(
            left: -1,
            top: -1,
            right: -1,
            bottom: -1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.state.focusRing, width: 2),
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                ),
              ),
            ),
          ),
      ],
    );

    if (!isInteractive) return content;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _handleHoverChanged(true),
        onExit: (_) => _handleHoverChanged(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _handleFocusChanged,
          shortcuts: _activityFeedActivationShortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _ActivityRowTitle extends StatelessWidget {
  const _ActivityRowTitle({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.accent,
            letterSpacing: 0,
          ),
        ),
        if (row.subtitle != null) ...[
          const SizedBox(height: _activityRowInnerLineGap),
          _ActivityRowSubtitle(
            text: row.subtitle!,
            iconName: row.subtitleIconName,
          ),
        ],
      ],
    );
  }
}

class _ActivityRowSubtitle extends StatelessWidget {
  const _ActivityRowSubtitle({required this.text, this.iconName});

  final String text;
  final String? iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconName != null) ...[
          AppIcon(
            iconName!,
            size: _activityRowSubtitleIconSize,
            color: iconName == AppIcons.shieldKeyholeOutline
                ? colors.icon.brandCrimson
                : colors.icon.muted,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _activityRowSubLineStyle.copyWith(
              color: colors.text.secondary,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRowAmount extends StatelessWidget {
  const _ActivityRowAmount({required this.row, required this.childRow});

  final ActivityRowData row;
  final bool childRow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountColor = row.amountColor ?? colors.text.primary;
    final supporting = _supportingAmountText(row);
    final supportingColor = _supportingAmountColor(row, colors);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 128),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ActivityAmountValue(row: row, color: amountColor),
          if (supporting != null) ...[
            const SizedBox(height: _activityRowInnerLineGap),
            _ActivitySupportingAmountText(
              row: row,
              text: supporting,
              color: supportingColor,
            ),
          ],
        ],
      ),
    );
  }

  String? _supportingAmountText(ActivityRowData row) {
    if (childRow) return null;
    if (row.amountSubtitle != null) return row.amountSubtitle;
    final status = row.statusText.trim();
    final routineStatus =
        status == 'Completed' ||
        status == 'In progress' ||
        RegExp(r'^\d+/\d+ In progress$').hasMatch(status);
    if (status.isNotEmpty && !routineStatus) return status;
    return row.timestampText == '--' ? null : row.timestampText;
  }

  Color _supportingAmountColor(ActivityRowData row, AppColors colors) {
    if (row.amountSubtitle != null) return colors.text.muted;
    final supporting = _supportingAmountText(row);
    if (supporting != null && supporting == row.statusText.trim()) {
      return row.statusColor ?? colors.text.secondary;
    }
    return colors.text.muted;
  }
}

class _ActivityAmountValue extends StatelessWidget {
  const _ActivityAmountValue({required this.row, required this.color});

  final ActivityRowData row;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      row.amountText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: AppTypography.labelLarge.copyWith(color: color, letterSpacing: 0),
    );
    final iconName = row.amountIconName;
    if (iconName == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(iconName, size: 14, color: row.amountIconColor ?? color),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: text),
      ],
    );
  }
}

class _ActivitySupportingAmountText extends StatelessWidget {
  const _ActivitySupportingAmountText({
    required this.row,
    required this.text,
    required this.color,
  });

  final ActivityRowData row;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final iconName = row.amountSubtitle == text
        ? row.amountSubtitleIconName
        : row.statusText.trim() == text
        ? row.statusIconName
        : null;
    final iconColor = row.amountSubtitle == text
        ? row.amountSubtitleIconColor
        : row.statusText.trim() == text
        ? row.statusColor
        : null;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: _activityRowSubLineStyle.copyWith(color: color, letterSpacing: 0),
    );
    if (iconName == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(iconName, size: 12, color: iconColor ?? color),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: label),
      ],
    );
  }
}

class _ActivityRowIcon extends StatelessWidget {
  const _ActivityRowIcon({required this.row});

  static const _avatarSize = AppAssetSize.size;
  static const _progressRingSize = AppAssetSize.size * (37.0 / 32.0);

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final progress = row.leadingProgressValue;
    if (progress != null) {
      return SizedBox.square(
        dimension: _avatarSize,
        child: OverflowBox(
          maxWidth: _progressRingSize,
          maxHeight: _progressRingSize,
          child: SizedBox.square(
            dimension: _progressRingSize,
            child: CustomPaint(
              painter: _ActivityProgressRingPainter(progress: progress),
              child: Center(
                child: AppIcon(
                  row.leadingIconName,
                  size: AppAssetSize.icon,
                  color: row.leadingIconColor,
                  animated: row.leadingIconName == AppIcons.loader,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: _avatarSize,
      child: _ActivityIconFallback(row: row),
    );
  }
}

class _ActivityIconFallback extends StatelessWidget {
  const _ActivityIconFallback({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: row.leadingBackgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          row.leadingIconName,
          size: AppAssetSize.icon,
          color: row.leadingIconColor,
          animated: row.leadingIconName == AppIcons.loader,
        ),
      ),
    );
  }
}

class _ActivityChildConnector extends StatelessWidget {
  const _ActivityChildConnector();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('activity_feed_child_connector'),
      width: AppAssetSize.size,
      height: AppAssetSize.size,
      child: Center(
        child: CustomPaint(
          size: const Size(
            AppAssetSize.size * (14 / 32),
            AppAssetSize.size * (14 / 32),
          ),
          painter: _ActivityChildConnectorPainter(
            color: context.colors.icon.disabled,
          ),
        ),
      ),
    );
  }
}

class _ActivityProgressRingPainter extends CustomPainter {
  const _ActivityProgressRingPainter({required this.progress});

  final double progress;

  static const _segmentCount = 4;
  static const _viewBoxSize = 37.0;
  static const _center = Offset(18.1836, 18.1842);
  static const _ringRadius = 17.0;
  static const _ringStrokeWidth = 2.5;
  static const _segmentGapAngle = 0.32;
  static const _trackColor = Color(0xFFD4D4D4);
  static const _progressColor = Color(0xFFC2546A);
  static const _innerFillColor = Color(0x339A9A9A);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBoxSize, size.height / _viewBoxSize);
    _paintProgressRing(canvas);
    _paintInnerCircle(canvas);
    canvas.restore();
  }

  void _paintProgressRing(Canvas canvas) {
    final trackPaint = Paint()
      ..color = _trackColor
      ..strokeWidth = _ringStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = _progressColor
      ..strokeWidth = _ringStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: _center, radius: _ringRadius);
    const segmentStep = math.pi * 2 / _segmentCount;
    const segmentSweep = segmentStep - _segmentGapAngle;
    const firstStartAngle = -math.pi + (_segmentGapAngle / 2);
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final filledSegments = normalizedProgress <= 0
        ? 0
        : math.max(
            1,
            math.min(
              _segmentCount,
              (normalizedProgress * _segmentCount).ceil(),
            ),
          );

    for (var index = 0; index < _segmentCount; index++) {
      final startAngle = firstStartAngle + (segmentStep * index);
      canvas.drawArc(rect, startAngle, segmentSweep, false, trackPaint);
    }
    for (var index = 0; index < filledSegments; index++) {
      final startAngle = firstStartAngle + (segmentStep * index);
      canvas.drawArc(rect, startAngle, segmentSweep, false, progressPaint);
    }
  }

  void _paintInnerCircle(Canvas canvas) {
    final fillPaint = Paint()
      ..color = _innerFillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(18.1836, 18.1841), 13, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _ActivityProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ActivityChildConnectorPainter extends CustomPainter {
  const _ActivityChildConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.15)
      ..lineTo(size.width * 0.25, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.86,
        size.width * 0.39,
        size.height * 0.86,
      )
      ..lineTo(size.width * 0.82, size.height * 0.86);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ActivityChildConnectorPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
