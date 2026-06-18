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
/// amount/timestamp).
const _activityRowInnerLineGap = AppSpacing.xxs;

/// Subtitle line (Shielded / Transparent). Desktop keeps main's 14px
/// label; mobile bumps to the 16px label.
const _activityRowSubtitleStyle = AppTypography.labelLarge;

/// Supporting amount line (timestamp / status). Desktop keeps main's 13px
/// label; mobile bumps to the 16px label.
const _activitySupportingStyle = kAppFormFactor == AppFormFactor.mobile
    ? AppTypography.labelLarge
    : AppTypography.labelSmall;

/// Sub-line leading icon (the shielded / transparent badge).
const _activityRowSubtitleIconSize = kAppFormFactor == AppFormFactor.mobile
    ? AppIconSize.medium
    : 16.0;

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
          SizedBox(
            height: kAppFormFactor == AppFormFactor.mobile
                ? AppSpacing.lg
                : AppSpacing.base,
          ),
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

class ActivityFeedSliver extends StatelessWidget {
  const ActivityFeedSliver({
    required this.sections,
    this.isLoading = false,
    this.errorText,
    this.emptyText = 'No activity yet',
    this.rowKeyPrefix,
    super.key,
  });

  final List<ActivityFeedSectionData> sections;
  final bool isLoading;
  final String? errorText;
  final String emptyText;
  final String? rowKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final items = _activityFeedSliverItems(
      sections: sections,
      isLoading: isLoading,
      errorText: errorText,
      emptyText: emptyText,
      rowKeyPrefix: rowKeyPrefix,
    );
    final childIndexByKey = <Key, int>{
      for (var index = 0; index < items.length; index++)
        if (items[index].rowKey != null) items[index].rowKey!: index,
    };
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return _ActivityFeedSliverItemView(key: item.rowKey, item: item);
        },
        childCount: items.length,
        findChildIndexCallback: (key) => childIndexByKey[key],
      ),
    );
  }
}

List<_ActivityFeedSliverItem> _activityFeedSliverItems({
  required List<ActivityFeedSectionData> sections,
  required bool isLoading,
  required String? errorText,
  required String emptyText,
  required String? rowKeyPrefix,
}) {
  final message = errorText ?? (isLoading ? 'Loading activity...' : null);
  final items = <_ActivityFeedSliverItem>[
    _ActivityFeedSliverItem.title(),
    _ActivityFeedSliverItem.gap(AppSpacing.base),
  ];

  if (message != null && sections.isEmpty) {
    items.add(
      _ActivityFeedSliverItem.message(message, isError: errorText != null),
    );
    return items;
  }
  if (sections.isEmpty) {
    items.add(_ActivityFeedSliverItem.message(emptyText));
    return items;
  }

  var rowIndex = 0;
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    final rows = section.rows;
    if (sectionIndex > 0) {
      items.add(_ActivityFeedSliverItem.gap(AppSpacing.md));
    }
    items.add(
      _ActivityFeedSliverItem.sectionHeader(
        section.title,
        segmentPosition: rows.isEmpty
            ? _ActivityFeedCardSegmentPosition.single
            : _ActivityFeedCardSegmentPosition.first,
        hasRows: rows.isNotEmpty,
      ),
    );
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final stableKey = _stableRowKey(row);
      final rowKey = stableKey ?? _fallbackRowKey(rowKeyPrefix, rowIndex);
      if (stableKey == null && rowKeyPrefix != null) {
        rowIndex += 1;
      }
      items.add(
        _ActivityFeedSliverItem.row(
          row,
          rowKey: rowKey,
          segmentPosition: index == rows.length - 1
              ? _ActivityFeedCardSegmentPosition.last
              : _ActivityFeedCardSegmentPosition.middle,
          hasTopGap: index > 0,
        ),
      );
    }
  }
  items.add(_ActivityFeedSliverItem.gap(AppSpacing.base));
  return items;
}

ValueKey<String>? _fallbackRowKey(String? rowKeyPrefix, int rowIndex) {
  if (rowKeyPrefix == null) return null;
  return ValueKey('${rowKeyPrefix}_row_$rowIndex');
}

enum _ActivityFeedSliverItemType { title, gap, message, sectionHeader, row }

enum _ActivityFeedCardSegmentPosition { single, first, middle, last }

class _ActivityFeedSliverItem {
  const _ActivityFeedSliverItem._({
    required this.type,
    this.height,
    this.text,
    this.isError = false,
    this.row,
    this.rowKey,
    this.segmentPosition,
    this.hasRows = false,
    this.hasTopGap = false,
  });

  factory _ActivityFeedSliverItem.title() {
    return const _ActivityFeedSliverItem._(
      type: _ActivityFeedSliverItemType.title,
    );
  }

  factory _ActivityFeedSliverItem.gap(double height) {
    return _ActivityFeedSliverItem._(
      type: _ActivityFeedSliverItemType.gap,
      height: height,
    );
  }

  factory _ActivityFeedSliverItem.message(String text, {bool isError = false}) {
    return _ActivityFeedSliverItem._(
      type: _ActivityFeedSliverItemType.message,
      text: text,
      isError: isError,
    );
  }

  factory _ActivityFeedSliverItem.sectionHeader(
    String title, {
    required _ActivityFeedCardSegmentPosition segmentPosition,
    required bool hasRows,
  }) {
    return _ActivityFeedSliverItem._(
      type: _ActivityFeedSliverItemType.sectionHeader,
      text: title,
      segmentPosition: segmentPosition,
      hasRows: hasRows,
    );
  }

  factory _ActivityFeedSliverItem.row(
    ActivityRowData row, {
    required _ActivityFeedCardSegmentPosition segmentPosition,
    required bool hasTopGap,
    ValueKey<String>? rowKey,
  }) {
    return _ActivityFeedSliverItem._(
      type: _ActivityFeedSliverItemType.row,
      row: row,
      rowKey: rowKey,
      segmentPosition: segmentPosition,
      hasTopGap: hasTopGap,
    );
  }

  final _ActivityFeedSliverItemType type;
  final double? height;
  final String? text;
  final bool isError;
  final ActivityRowData? row;
  final ValueKey<String>? rowKey;
  final _ActivityFeedCardSegmentPosition? segmentPosition;
  final bool hasRows;
  final bool hasTopGap;
}

class _ActivityFeedSliverItemView extends StatelessWidget {
  const _ActivityFeedSliverItemView({required this.item, super.key});

  final _ActivityFeedSliverItem item;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      _ActivityFeedSliverItemType.title => const _ActivityFeedCentered(
        width: 420,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: _ActivityFeedTitleRow(),
        ),
      ),
      _ActivityFeedSliverItemType.gap => SizedBox(height: item.height),
      _ActivityFeedSliverItemType.message => _ActivityFeedCentered(
        width: 396,
        child: _ActivityFeedMessageCard(
          text: item.text!,
          width: 396,
          isError: item.isError,
        ),
      ),
      _ActivityFeedSliverItemType.sectionHeader =>
        _ActivityFeedSectionHeaderSegment(
          title: item.text!,
          position: item.segmentPosition!,
          hasRows: item.hasRows,
        ),
      _ActivityFeedSliverItemType.row => _ActivityFeedRowSegment(
        row: item.row!,
        position: item.segmentPosition!,
        hasTopGap: item.hasTopGap,
      ),
    };
  }
}

class _ActivityFeedCentered extends StatelessWidget {
  const _ActivityFeedCentered({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: width, child: child),
    );
  }
}

class _ActivityFeedSectionHeaderSegment extends StatelessWidget {
  const _ActivityFeedSectionHeaderSegment({
    required this.title,
    required this.position,
    required this.hasRows,
  });

  final String title;
  final _ActivityFeedCardSegmentPosition position;
  final bool hasRows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ActivityFeedCardSegment(
      position: position,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, hasRows ? AppSpacing.s : 24),
        child: SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              title,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityFeedRowSegment extends StatelessWidget {
  const _ActivityFeedRowSegment({
    required this.row,
    required this.position,
    required this.hasTopGap,
  });

  final ActivityRowData row;
  final _ActivityFeedCardSegmentPosition position;
  final bool hasTopGap;

  @override
  Widget build(BuildContext context) {
    return _ActivityFeedCardSegment(
      position: position,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          hasTopGap ? 12 : 0,
          16,
          position == _ActivityFeedCardSegmentPosition.last ? 24 : 0,
        ),
        child: ActivityFeedRowGroup(row: row),
      ),
    );
  }
}

class _ActivityFeedCardSegment extends StatelessWidget {
  const _ActivityFeedCardSegment({required this.position, required this.child});

  final _ActivityFeedCardSegmentPosition position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _ActivityFeedCentered(
      width: 396,
      child: CustomPaint(
        painter: _ActivityFeedCardSegmentShadowPainter(
          position: position,
          shadows: _activityFeedCardShadow(colors),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: _activityFeedSegmentRadius(position),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActivityFeedCardSegmentShadowPainter extends CustomPainter {
  const _ActivityFeedCardSegmentShadowPainter({
    required this.position,
    required this.shadows,
  });

  static const _shadowPaintExtent = 24.0;

  final _ActivityFeedCardSegmentPosition position;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final clipPath = _shadowClipPath(size);
    canvas.save();
    canvas.clipPath(clipPath);
    final radius = _activityFeedSegmentRadius(position);
    final baseRect = Offset.zero & size;
    for (final shadow in shadows) {
      final rect = baseRect.inflate(shadow.spreadRadius).shift(shadow.offset);
      canvas.drawRRect(radius.toRRect(rect), shadow.toPaint());
    }
    canvas.restore();
  }

  Path _shadowClipPath(Size size) {
    const extent = _shadowPaintExtent;
    final width = size.width;
    final height = size.height;
    final path = Path();
    switch (position) {
      case _ActivityFeedCardSegmentPosition.single:
        path.addRect(
          Rect.fromLTRB(-extent, -extent, width + extent, height + extent),
        );
      case _ActivityFeedCardSegmentPosition.first:
        path.addRect(Rect.fromLTRB(-extent, -extent, width + extent, height));
      case _ActivityFeedCardSegmentPosition.middle:
        path
          ..addRect(Rect.fromLTRB(-extent, 0, 0, height))
          ..addRect(Rect.fromLTRB(width, 0, width + extent, height));
      case _ActivityFeedCardSegmentPosition.last:
        path.addRect(
          Rect.fromLTRB(-extent, 0, width + extent, height + extent),
        );
    }
    return path;
  }

  @override
  bool shouldRepaint(
    covariant _ActivityFeedCardSegmentShadowPainter oldDelegate,
  ) {
    if (oldDelegate.position != position) return true;
    if (oldDelegate.shadows.length != shadows.length) return true;
    for (var index = 0; index < shadows.length; index++) {
      if (oldDelegate.shadows[index] != shadows[index]) return true;
    }
    return false;
  }
}

BorderRadius _activityFeedSegmentRadius(
  _ActivityFeedCardSegmentPosition position,
) {
  const radius = Radius.circular(AppRadii.large);
  return switch (position) {
    _ActivityFeedCardSegmentPosition.single => const BorderRadius.all(radius),
    _ActivityFeedCardSegmentPosition.first => const BorderRadius.vertical(
      top: radius,
    ),
    _ActivityFeedCardSegmentPosition.middle => BorderRadius.zero,
    _ActivityFeedCardSegmentPosition.last => const BorderRadius.vertical(
      bottom: radius,
    ),
  };
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

ValueKey<String>? _stableRowKey(ActivityRowData row) {
  final stableId = row.stableId;
  if (stableId == null || stableId.isEmpty) return null;
  return ValueKey(stableId);
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
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              for (var index = 0; index < section.rows.length; index++) ...[
                if (index > 0) const SizedBox(height: AppSpacing.s),
                ActivityFeedRowGroup(
                  key:
                      _stableRowKey(section.rows[index]) ??
                      rowKeyBuilder?.call(),
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
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: _activityFeedCardShadow(colors),
      ),
      child: child,
    );
  }
}

/// Activity cards drop their drop shadow on mobile (flat full-width cards on a
/// tinted background) and keep the surface shadow on desktop. Form-factor
/// branching is the compile-time [kAppFormFactor] const so the unused branch is
/// tree-shaken.
List<BoxShadow> _activityFeedCardShadow(AppColors colors) =>
    kAppFormFactor == AppFormFactor.mobile
    ? const <BoxShadow>[]
    : appSurfaceShadow(colors);

class ActivityFeedRowGroup extends StatelessWidget {
  const ActivityFeedRowGroup({required this.row, super.key});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    // The child slot is always present so a sub row appearing later (e.g. an
    // absorbed swap payout) eases in instead of popping.
    return Column(
      children: [
        ActivityFeedRow(row: row),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final childRow in row.childRows)
                TweenAnimationBuilder<double>(
                  key: ValueKey(
                    'activity_child_${childRow.stableId ?? childRow.title}',
                  ),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * -6),
                      child: child,
                    ),
                  ),
                  child: ActivityFeedRow(
                    row: childRow,
                    compact: true,
                    childRow: true,
                  ),
                ),
            ],
          ),
        ),
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
    final isInteractive = row.onTap != null;
    final rowHeight = widget.compact ? 40.0 : 44.0;
    final showSelectedBorder = row.selected && !widget.childRow;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          decoration: BoxDecoration(
            color: isInteractive && _hovered
                ? colors.state.hoverOpacity
                : row.backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    widget.childRow
                        ? const _ActivityChildConnector()
                        : _ActivityRowIcon(row: row),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(child: _ActivityRowTitle(row: row)),
                  ],
                ),
              ),
              // Content Line separates its left and right blocks by 10px.
              const SizedBox(width: 10),
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
                  borderRadius: BorderRadius.circular(AppRadii.small + 1),
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
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
        if (row.subtitle != null) ...[
          // Mobile-only extra gap; desktop keeps subtitle flush as on main.
          if (kAppFormFactor == AppFormFactor.mobile)
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
            style: _activityRowSubtitleStyle.copyWith(
              color: colors.text.secondary,
              fontWeight: FontWeight.w400,
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
      style: AppTypography.labelLarge.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
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
      style: _activitySupportingStyle.copyWith(color: color, letterSpacing: 0),
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
