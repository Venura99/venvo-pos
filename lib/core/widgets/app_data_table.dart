import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';

/// One column of an [AppDataTable].
///
/// A column is either fixed width or flexible. Fixed widths are honoured
/// first and the remaining space is divided between the flexible columns in
/// proportion to their flex, which is what keeps a name column wide and an
/// amount column exactly as wide as an amount needs.
class AppTableColumn<T> {
  const AppTableColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex = 1,
    this.numeric = false,
    this.sortKey,
    this.tooltip,
  });

  final String label;

  /// Builds the cell content for one row.
  final Widget Function(BuildContext context, T row) cell;

  /// Fixed width in logical pixels. When null the column is flexible.
  final double? width;
  final int flex;

  /// Right-aligns the column and applies tabular figures, so a column of
  /// money or quantities can be scanned vertically.
  final bool numeric;

  /// Set to make the header clickable; reported back through
  /// [AppDataTable.onSort].
  final String? sortKey;
  final String? tooltip;
}

/// A compact, virtualised data table for desktop.
///
/// Built on a header row plus a `ListView.builder` rather than Material's
/// `DataTable`, because `DataTable` lays out every row at once: a product
/// catalogue of a few thousand rows would cost a frame to scroll. Here only
/// the visible rows are built.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.sortKey,
    this.sortAscending = true,
    this.onSort,
    this.empty,
    this.minWidth = 720,
    this.rowKey,
    this.selectedRowKey,
    this.trailingRowBuilder,
  });

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final ValueChanged<T>? onRowTap;

  /// The [AppTableColumn.sortKey] currently sorted on, if any.
  final String? sortKey;
  final bool sortAscending;

  /// Called with a column's sort key when its header is clicked.
  final ValueChanged<String>? onSort;

  /// Shown in place of the body when [rows] is empty.
  final Widget? empty;

  /// Below this width the table scrolls horizontally rather than crushing
  /// columns into unreadable slivers.
  final double minWidth;

  /// Identifies a row for selection highlighting.
  final Object? Function(T row)? rowKey;
  final Object? selectedRowKey;

  /// Appended after the last row, for a totals line.
  final Widget Function(BuildContext context)? trailingRowBuilder;

  @override
  Widget build(BuildContext context) {
    // The empty state goes through the same layout as the data, rather than
    // taking a shortcut past it. A table whose columns are wider than the
    // pane needs its header laid out at [minWidth] and scrolled, and a
    // shortcut that laid the header out at the available width instead made
    // any wide table overflow its own heading the moment it had no rows.
    final isEmpty = rows.isEmpty && empty != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final needsHorizontalScroll = available < minWidth;
        final tableWidth = needsHorizontalScroll ? minWidth : available;

        final table = SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _buildHeaderRow(context, tableWidth: tableWidth),
              const Divider(height: 1),
              if (isEmpty)
                Expanded(child: empty!)
              else
                Expanded(
                  child: ListView.separated(
                    primary: false,
                    itemCount:
                        rows.length + (trailingRowBuilder == null ? 0 : 1),
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        return trailingRowBuilder!(context);
                      }
                      return _TableRow<T>(
                        row: rows[index],
                        columns: columns,
                        tableWidth: tableWidth,
                        onTap: onRowTap,
                        isSelected:
                            rowKey != null &&
                            selectedRowKey != null &&
                            rowKey!(rows[index]) == selectedRowKey,
                        isAlternate: index.isOdd,
                      );
                    },
                  ),
                ),
            ],
          ),
        );

        if (!needsHorizontalScroll) return table;
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(BuildContext context, {double? tableWidth}) {
    return Container(
      height: AppLayout.tableHeaderHeight,
      width: tableWidth,
      color: context.colors.surfaceContainerHighest.withValues(alpha: 0.45),
      child: _CellRow(
        columns: columns,
        tableWidth: tableWidth,
        builder: (context, column, index) {
          final isSorted = column.sortKey != null && column.sortKey == sortKey;
          final label = Text(
            column.label,
            style: context.text.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isSorted
                  ? context.colors.primary
                  : context.colors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          );

          final content = Row(
            mainAxisAlignment: column.numeric
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (column.numeric && isSorted) _sortIcon(context, isSorted),
              Flexible(child: label),
              if (!column.numeric && isSorted) _sortIcon(context, isSorted),
            ],
          );

          if (column.sortKey == null || onSort == null) {
            return column.tooltip == null
                ? content
                : Tooltip(message: column.tooltip!, child: content);
          }

          return InkWell(
            onTap: () => onSort!(column.sortKey!),
            child: column.tooltip == null
                ? content
                : Tooltip(message: column.tooltip!, child: content),
          );
        },
      ),
    );
  }

  Widget _sortIcon(BuildContext context, bool isSorted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Icon(
        sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
        size: 13,
        color: context.colors.primary,
      ),
    );
  }
}

class _TableRow<T> extends StatelessWidget {
  const _TableRow({
    required this.row,
    required this.columns,
    required this.onTap,
    required this.isSelected,
    required this.isAlternate,
    this.tableWidth,
  });

  final T row;
  final List<AppTableColumn<T>> columns;
  final ValueChanged<T>? onTap;
  final bool isSelected;
  final bool isAlternate;
  final double? tableWidth;

  @override
  Widget build(BuildContext context) {
    final background = isSelected
        ? context.colors.secondaryContainer
        : isAlternate
        ? context.colors.surfaceContainerHighest.withValues(alpha: 0.18)
        : null;

    final content = Container(
      height: AppLayout.tableRowHeight,
      width: tableWidth,
      color: background,
      child: _CellRow<T>(
        columns: columns,
        tableWidth: tableWidth,
        builder: (context, column, index) {
          final cell = column.cell(context, row);
          return Align(
            alignment: column.numeric
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: column.numeric
                ? DefaultTextStyle.merge(
                    style: AppTheme.monospacedNumbers(context.text.bodyMedium),
                    child: cell,
                  )
                : cell,
          );
        },
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: () => onTap!(row), child: content);
  }
}

/// Lays columns out once, shared by the header and every body row so the two
/// can never drift apart.
class _CellRow<T> extends StatelessWidget {
  const _CellRow({
    required this.columns,
    required this.builder,
    this.tableWidth,
  });

  final List<AppTableColumn<T>> columns;
  final Widget Function(
    BuildContext context,
    AppTableColumn<T> column,
    int index,
  )
  builder;
  final double? tableWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < columns.length; index++) ...[
          if (index == 0) const SizedBox(width: AppSpacing.lg),
          if (columns[index].width != null)
            SizedBox(
              width: columns[index].width,
              child: builder(context, columns[index], index),
            )
          else
            Expanded(
              flex: columns[index].flex,
              child: builder(context, columns[index], index),
            ),
          SizedBox(
            width: index == columns.length - 1 ? AppSpacing.lg : AppSpacing.md,
          ),
        ],
      ],
    );
  }
}

/// A row under the data that lines up with the columns: a totals or summary
/// line.
///
/// Public so that a caller handing [AppDataTable.trailingRowBuilder] a totals
/// row gets the table's own column layout, gutters and all, rather than a
/// hand-built [Row] that lines up until somebody changes the spacing.
class AppTableSummaryRow<T> extends StatelessWidget {
  const AppTableSummaryRow({
    super.key,
    required this.columns,
    required this.cell,
  });

  final List<AppTableColumn<T>> columns;

  /// Builds the content of one column's cell.
  final Widget Function(
    BuildContext context,
    AppTableColumn<T> column,
    int index,
  )
  cell;

  /// The horizontal space the table adds around and between its columns, which
  /// a caller computing a minimum width has to allow for.
  static double guttersFor(int columnCount) =>
      AppSpacing.lg * 2 + AppSpacing.md * (columnCount - 1);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppLayout.tableRowHeight),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        border: Border(top: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: _CellRow<T>(columns: columns, builder: cell),
    );
  }
}

/// A plain text cell, the common case. Truncates rather than wrapping, so
/// every row stays one line high.
class TableTextCell extends StatelessWidget {
  const TableTextCell(
    this.text, {
    super.key,
    this.muted = false,
    this.bold = false,
    this.maxLines = 1,
  });

  final String text;
  final bool muted;
  final bool bold;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: context.text.bodyMedium?.copyWith(
        color: muted ? context.colors.onSurfaceVariant : null,
        fontWeight: bold ? FontWeight.w600 : null,
      ),
    );
  }
}

/// Two lines in one cell: a value with a quieter qualifier underneath. Used
/// where a name needs its code or a product needs its SKU without spending a
/// whole column on it.
class TableTwoLineCell extends StatelessWidget {
  const TableTwoLineCell({
    super.key,
    required this.primary,
    required this.secondary,
  });

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}
