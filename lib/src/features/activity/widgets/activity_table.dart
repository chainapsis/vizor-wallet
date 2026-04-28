import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/activity_row_data.dart';

class ActivityTable extends StatelessWidget {
  const ActivityTable({
    required this.rows,
    this.title,
    this.onTitleTap,
    this.isLoading = false,
    this.errorText,
    this.emptyText = 'No activity yet',
    this.currentPage = 1,
    this.totalPages = 1,
    this.onPageChanged,
    this.showPagination = false,
    super.key,
  });

  final List<ActivityRowData> rows;
  final String? title;
  final VoidCallback? onTitleTap;
  final bool isLoading;
  final String? errorText;
  final String emptyText;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onPageChanged;
  final bool showPagination;

  @override
  Widget build(BuildContext context) {
    final effectiveTotalPages = math.max(1, totalPages);
    final effectiveCurrentPage = math.min(
      math.max(currentPage, 1),
      effectiveTotalPages,
    );

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
            ActivityTableRow(row: rows[i]),
            if (i != rows.length - 1) ...[
              const SizedBox(height: AppSpacing.xs),
              const _ActivityTableDivider(),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
        if (showPagination) ...[
          const SizedBox(height: AppSpacing.lg),
          ActivityTablePagination(
            currentPage: effectiveCurrentPage,
            totalPages: effectiveTotalPages,
            onPageChanged: onPageChanged,
          ),
        ],
      ],
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
    final accentStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.accent,
    );
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: _ActivityColumnLayout(
          txType: Text('Tx Type', style: mutedStyle),
          amount: Text('Amount', style: mutedStyle),
          status: Text('Status', style: mutedStyle),
          timestamp: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Time Stamp', textAlign: TextAlign.end, style: accentStyle),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(AppIcons.arrowDown, size: 16, color: colors.icon.accent),
            ],
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
            style: AppTypography.labelMedium.copyWith(
              color: row.statusColor ?? colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

class ActivityTableRow extends StatelessWidget {
  const ActivityTableRow({required this.row, super.key});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Container(
      height: 48,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
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
        amount: Text(
          row.amountText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: row.amountColor ?? colors.text.accent,
          ),
        ),
        status: _StatusLabel(row: row),
        timestamp: Text(
          row.timestampText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );

    if (row.onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.onTap,
        child: content,
      ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PaginationIconButton(
          iconName: AppIcons.chevronBackward,
          enabled: currentPage > 1,
          onTap: () => onPageChanged?.call(currentPage - 1),
        ),
        for (final page in pages)
          page == null
              ? const _PaginationEllipsis()
              : _PaginationPageButton(
                  page: page,
                  selected: page == currentPage,
                  onTap: () => onPageChanged?.call(page),
                ),
        _PaginationIconButton(
          iconName: AppIcons.chevronForward,
          enabled: currentPage < totalPages,
          onTap: () => onPageChanged?.call(currentPage + 1),
        ),
      ],
    );
  }
}

class _PaginationIconButton extends StatelessWidget {
  const _PaginationIconButton({
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
    final child = SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: AppIcon(
          iconName,
          size: 16,
          color: enabled ? colors.icon.accent : colors.text.disabled,
        ),
      ),
    );

    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _PaginationPageButton extends StatelessWidget {
  const _PaginationPageButton({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Text(
          '$page',
          style: AppTypography.bodySmall.copyWith(
            color: selected ? colors.text.accent : colors.text.secondary,
          ),
        ),
      ),
    );

    if (selected) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
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
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
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
