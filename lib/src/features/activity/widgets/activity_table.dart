import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/activity_row_data.dart';

const _activityActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class ActivityTable extends StatelessWidget {
  const ActivityTable({
    required this.rows,
    this.title,
    this.onTitleTap,
    this.rowKeyPrefix,
    this.isLoading = false,
    this.errorText,
    this.emptyText = 'No activity yet',
    this.currentPage = 1,
    this.totalPages = 1,
    this.onPageChanged,
    this.showPagination = false,
    this.pinPaginationToBottom = false,
    super.key,
  });

  final List<ActivityRowData> rows;
  final String? title;
  final VoidCallback? onTitleTap;
  final String? rowKeyPrefix;
  final bool isLoading;
  final String? errorText;
  final String emptyText;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onPageChanged;
  final bool showPagination;
  final bool pinPaginationToBottom;

  @override
  Widget build(BuildContext context) {
    final effectiveTotalPages = math.max(1, totalPages);
    final effectiveCurrentPage = math.min(
      math.max(currentPage, 1),
      effectiveTotalPages,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldPinPagination =
            pinPaginationToBottom && constraints.hasBoundedHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              _ActivityTableTitle(title: title!, onTap: onTitleTap),
              const SizedBox(height: AppSpacing.xs),
            ],
            const _ActivityTableHeader(),
            const SizedBox(height: AppSpacing.s),
            if (errorText != null && rows.isEmpty)
              _ActivityTableMessage(text: errorText!, isError: true)
            else if (isLoading && rows.isEmpty)
              const _ActivityTableMessage(text: 'Loading activity...')
            else if (rows.isEmpty)
              _ActivityTableMessage(text: emptyText)
            else
              for (var i = 0; i < rows.length; i++) ...[
                ActivityTableRow(
                  key: rowKeyPrefix == null
                      ? null
                      : ValueKey('${rowKeyPrefix}_row_$i'),
                  row: rows[i],
                ),
                if (i != rows.length - 1) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const _ActivityTableDivider(),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            if (showPagination && effectiveTotalPages > 1) ...[
              if (shouldPinPagination) ...[
                const Spacer(),
                const SizedBox(height: AppSpacing.xs),
              ] else
                const SizedBox(height: AppSpacing.lg),
              ActivityTablePagination(
                currentPage: effectiveCurrentPage,
                totalPages: effectiveTotalPages,
                onPageChanged: onPageChanged,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ActivityTableTitle extends StatelessWidget {
  const _ActivityTableTitle({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(
              AppIcons.chevronForward,
              size: 16,
              color: colors.icon.accent,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Align(alignment: Alignment.centerLeft, child: child);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _ActivityTableHeader extends StatelessWidget {
  const _ActivityTableHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mutedStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.muted,
    );
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: _ActivityColumnLayout(
          txType: Text('Type', style: mutedStyle),
          amount: Text('Amount', style: mutedStyle),
          status: Text('Status', style: mutedStyle),
          timestamp: Text(
            'Date & time',
            textAlign: TextAlign.end,
            style: mutedStyle,
          ),
        ),
      ),
    );
  }
}

const double _activityLeftCellWidth = 190;
const double _activityMiddleCellWidth = 160;
const double _activityRightCellWidth = 140;
const double _activityFixedColumnsWidth =
    _activityLeftCellWidth +
    (_activityMiddleCellWidth * 2) +
    _activityRightCellWidth;

class _ActivityTableDivider extends StatelessWidget {
  const _ActivityTableDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.colors.border.subtle);
  }
}

class _ActivityColumnLayout extends StatelessWidget {
  const _ActivityColumnLayout({
    required this.txType,
    required this.amount,
    required this.status,
    required this.timestamp,
  });

  final Widget txType;
  final Widget amount;
  final Widget status;
  final Widget timestamp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useFixedColumns =
            constraints.maxWidth >= _activityFixedColumnsWidth;
        if (useFixedColumns) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ActivityCell(width: _activityLeftCellWidth, child: txType),
              _ActivityCell(width: _activityMiddleCellWidth, child: amount),
              _ActivityCell(width: _activityMiddleCellWidth, child: status),
              _ActivityCell(
                width: _activityRightCellWidth,
                alignEnd: true,
                child: timestamp,
              ),
            ],
          );
        }

        return Row(
          children: [
            _ActivityCell(flex: 190, child: txType),
            _ActivityCell(flex: 160, child: amount),
            _ActivityCell(flex: 160, child: status),
            _ActivityCell(flex: 140, alignEnd: true, child: timestamp),
          ],
        );
      },
    );
  }
}

class _ActivityCell extends StatelessWidget {
  const _ActivityCell({
    required this.child,
    this.width,
    this.flex,
    this.alignEnd = false,
  });

  final Widget child;
  final double? width;
  final int? flex;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    final width = this.width;
    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (row.statusIconName != null) ...[
          AppIcon(
            row.statusIconName!,
            size: 16,
            color: row.statusColor ?? colors.text.secondary,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Flexible(
          child: Text(
            row.statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: row.statusColor ?? colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class ActivityTableRow extends StatefulWidget {
  const ActivityTableRow({required this.row, super.key});

  final ActivityRowData row;

  @override
  State<ActivityTableRow> createState() => _ActivityTableRowState();
}

class _ActivityTableRowState extends State<ActivityTableRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant ActivityTableRow oldWidget) {
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
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.all(AppSpacing.xxs),
          decoration: BoxDecoration(
            color: isInteractive && _hovered
                ? _neutralHoverBackgroundColor(context)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: _ActivityColumnLayout(
            txType: Row(
              children: [
                _ActivityAvatar(row: row),
                const SizedBox(width: AppSpacing.s),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      if (row.subtitle != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (row.subtitleIconName != null) ...[
                              AppIcon(
                                row.subtitleIconName!,
                                size: 16,
                                color: colors.icon.brandCrimson,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                            ],
                            Flexible(
                              child: Text(
                                row.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.labelMedium.copyWith(
                                  color: row.subtitleIconName == null
                                      ? colors.text.secondary
                                      : colors.text.brandCrimson,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            amount: _AmountLabel(row: row),
            status: _StatusLabel(row: row),
            timestamp: Text(
              row.timestampText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ),
        if (isInteractive && _focused)
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
          shortcuts: _activityActivationShortcuts,
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

class _AmountLabel extends StatelessWidget {
  const _AmountLabel({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = row.amountColor ?? colors.text.accent;
    final text = Text(
      row.amountText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.labelLarge.copyWith(color: color),
    );

    final iconName = row.amountIconName;
    if (iconName == null) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -1),
          child: AppIcon(
            iconName,
            size: 16,
            color: row.amountIconColor ?? color,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: text),
      ],
    );
  }
}

class _ActivityAvatar extends StatelessWidget {
  const _ActivityAvatar({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: row.leadingBackgroundColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AppIcon(
            row.leadingIconName,
            size: 16,
            color: row.leadingIconColor,
          ),
        ),
      ),
    );
  }
}

class _ActivityTableMessage extends StatelessWidget {
  const _ActivityTableMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          text,
          style: AppTypography.labelLarge.copyWith(
            color: isError ? colors.text.destructive : colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

class ActivityTablePagination extends StatelessWidget {
  const ActivityTablePagination({
    required this.currentPage,
    required this.totalPages,
    this.onPageChanged,
    super.key,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onPageChanged;

  @override
  Widget build(BuildContext context) {
    final pages = _visiblePages(currentPage, totalPages);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PaginationIconButton(
            iconName: AppIcons.chevronBackward,
            enabled: currentPage > 1,
            onTap: () => onPageChanged?.call(currentPage - 1),
          ),
          for (final page in pages) ...[
            const SizedBox(width: AppSpacing.xxs),
            page == null
                ? const _PaginationEllipsis()
                : _PaginationPageButton(
                    key: ValueKey<int>(page),
                    page: page,
                    selected: page == currentPage,
                    onTap: () => onPageChanged?.call(page),
                  ),
          ],
          const SizedBox(width: AppSpacing.xxs),
          _PaginationIconButton(
            iconName: AppIcons.chevronForward,
            enabled: currentPage < totalPages,
            onTap: () => onPageChanged?.call(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _PaginationIconButton extends StatefulWidget {
  const _PaginationIconButton({
    required this.iconName,
    required this.enabled,
    required this.onTap,
  });

  final String iconName;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PaginationIconButton> createState() => _PaginationIconButtonState();
}

class _PaginationIconButtonState extends State<_PaginationIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant _PaginationIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.enabled;
    final border = enabled && _focused
        ? Border.all(color: colors.state.focusRing, width: 1.5)
        : null;

    return _PaginationItemShell(
      enabled: enabled,
      backgroundColor: enabled && _hovered
          ? _neutralHoverBackgroundColor(context)
          : null,
      border: border,
      onTap: widget.onTap,
      onHoverChanged: _handleHoverChanged,
      onFocusChanged: _handleFocusChanged,
      child: Center(
        child: AppIcon(
          widget.iconName,
          size: 14,
          color: enabled ? colors.icon.accent : colors.icon.disabled,
        ),
      ),
    );
  }
}

class _PaginationPageButton extends StatefulWidget {
  const _PaginationPageButton({
    required this.page,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaginationPageButton> createState() => _PaginationPageButtonState();
}

class _PaginationPageButtonState extends State<_PaginationPageButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant _PaginationPageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page ||
        oldWidget.selected != widget.selected) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final backgroundColor = selected
        ? colors.background.brandCrimsonStrong
        : _hovered
        ? _neutralHoverBackgroundColor(context)
        : null;
    final textColor = selected ? colors.text.inverse : colors.text.accent;
    final border = !selected && _focused
        ? Border.all(color: colors.state.focusRing, width: 1.5)
        : null;

    return _PaginationItemShell(
      selected: selected,
      backgroundColor: backgroundColor,
      border: border,
      onTap: selected ? null : widget.onTap,
      onHoverChanged: _handleHoverChanged,
      onFocusChanged: _handleFocusChanged,
      child: Center(
        child: Text(
          '${widget.page}',
          style: AppTypography.labelMedium.copyWith(color: textColor),
        ),
      ),
    );
  }
}

class _PaginationItemShell extends StatelessWidget {
  const _PaginationItemShell({
    required this.child,
    this.selected = false,
    this.enabled = true,
    this.backgroundColor,
    this.border,
    this.onTap,
    this.onHoverChanged,
    this.onFocusChanged,
  });

  final Widget child;
  final bool selected;
  final bool enabled;
  final Color? backgroundColor;
  final Border? border;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: border,
      ),
      child: child,
    );

    final tracksPointer = enabled && onHoverChanged != null;
    final canActivate = enabled && onTap != null;
    final canFocus = enabled && onFocusChanged != null;

    if (!tracksPointer && !canActivate && !canFocus) return content;

    void activate() {
      onHoverChanged?.call(false);
      onTap?.call();
    }

    final gestureContent = canActivate
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: activate,
            child: content,
          )
        : content;

    final focusableContent = canFocus
        ? FocusableActionDetector(
            mouseCursor: canActivate
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            onShowFocusHighlight: onFocusChanged,
            includeFocusSemantics: false,
            shortcuts: canActivate ? _activityActivationShortcuts : null,
            actions: canActivate
                ? <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<Intent>(
                      onInvoke: (_) {
                        activate();
                        return null;
                      },
                    ),
                  }
                : null,
            child: gestureContent,
          )
        : gestureContent;

    return Semantics(
      button: canActivate,
      selected: selected,
      child: MouseRegion(
        cursor: canActivate ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => onHoverChanged?.call(true),
        onExit: (_) => onHoverChanged?.call(false),
        child: focusableContent,
      ),
    );
  }
}

class _PaginationEllipsis extends StatelessWidget {
  const _PaginationEllipsis();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Text(
          '...',
          style: AppTypography.labelMedium.copyWith(
            color: context.colors.text.accent,
          ),
        ),
      ),
    );
  }
}

Color _neutralHoverBackgroundColor(BuildContext context) {
  final colors = context.colors;
  final isDark = AppTheme.of(context) == AppThemeData.dark;
  return isDark ? colors.background.raised : colors.background.base;
}

List<int?> _visiblePages(int currentPage, int totalPages) {
  if (totalPages <= 7) {
    return [for (var i = 1; i <= totalPages; i++) i];
  }

  final pages = <int?>[1];
  final start = math.max(2, currentPage - 1);
  final end = math.min(totalPages - 1, currentPage + 1);

  if (start > 2) pages.add(null);
  for (var page = start; page <= end; page++) {
    pages.add(page);
  }
  if (end < totalPages - 1) pages.add(null);
  pages.add(totalPages);

  return pages;
}
