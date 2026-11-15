import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../products/presentation/products_screen.dart';
import 'stock_providers.dart';

/// Live stock by product, split across the warehouse, the agents and the
/// shops, with damaged goods shown separately because they are not sellable.
class StockOverviewScreen extends ConsumerWidget {
  const StockOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.stockView) ?? false)) {
      return const PageScaffold(
        title: 'Stock Overview',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to stock',
        ),
      );
    }

    final stock = ref.watch(productStockProvider);
    final filter = ref.watch(stockOverviewFilterProvider);
    final categories =
        ref.watch(selectableCategoriesProvider).valueOrNull ??
        const <CategoryListItem>[];

    return PageScaffold(
      title: 'Stock Overview',
      description:
          'Every balance here is a cache of the stock ledger and can be '
          'rebuilt from it. Damaged stock is listed apart from sellable '
          'stock.',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSearchField(
                hintText: 'Search product name or SKU',
                width: 320,
                onChanged: (value) => ref
                    .read(stockOverviewFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  initialValue: filter.categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<int?>(child: Text('All categories')),
                    for (final category in categories)
                      DropdownMenuItem<int?>(
                        value: category.id,
                        child: Text(category.qualifiedName),
                      ),
                  ],
                  onChanged: (value) => ref
                      .read(stockOverviewFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearCategory: true)
                            : state.copyWith(categoryId: value),
                      ),
                ),
              ),
              FilterChip(
                selected: filter.lowStockOnly,
                label: const Text('Low stock only'),
                avatar: const Icon(Icons.warning_amber_outlined, size: 16),
                onSelected: (value) => ref
                    .read(stockOverviewFilterProvider.notifier)
                    .update((state) => state.copyWith(lowStockOnly: value)),
              ),
              FilterChip(
                selected: !filter.hideZeroStock,
                label: const Text('Show products with no stock'),
                onSelected: (value) => ref
                    .read(stockOverviewFilterProvider.notifier)
                    .update((state) => state.copyWith(hideZeroStock: !value)),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<ProductStockRow>>(
              value: stock,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<ProductStockRow>(
                  rows: rows,
                  minWidth: 1120,
                  onRowTap: (row) => _openMovements(context, ref, row),
                  empty: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: filter.hasAnyFilter
                        ? 'No products match these filters'
                        : 'No stock anywhere yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Enter your opening stock to get started. It is '
                              'posted as a document so the ledger balances from '
                              'the first day.',
                  ),
                  columns: [
                    AppTableColumn<ProductStockRow>(
                      label: 'Product',
                      flex: 4,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.productName,
                        secondary: '${row.sku} · ${row.categoryName}',
                      ),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Warehouse',
                      width: 100,
                      numeric: true,
                      cell: (context, row) =>
                          _QuantityCell(quantity: row.warehouseQuantity),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Agents',
                      width: 90,
                      numeric: true,
                      cell: (context, row) =>
                          _QuantityCell(quantity: row.agentQuantity),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Shops',
                      width: 90,
                      numeric: true,
                      cell: (context, row) =>
                          _QuantityCell(quantity: row.shopQuantity),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'In transit',
                      width: 95,
                      numeric: true,
                      tooltip: 'Dispatched but not yet received',
                      cell: (context, row) => _QuantityCell(
                        quantity: row.inTransitQuantity,
                        muteZero: true,
                      ),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Damaged',
                      width: 95,
                      numeric: true,
                      tooltip: 'In quarantine, not available to sell',
                      cell: (context, row) => Text(
                        row.damagedQuantity == 0
                            ? '—'
                            : '${row.damagedQuantity}',
                        style: context.text.bodyMedium?.copyWith(
                          color: row.damagedQuantity == 0
                              ? context.colors.onSurfaceVariant
                              : context.statusColors.danger,
                        ),
                      ),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Sellable',
                      width: 100,
                      numeric: true,
                      tooltip: 'Warehouse plus agents plus shops',
                      cell: (context, row) => Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (row.isLowStock) ...[
                            Tooltip(
                              message:
                                  'At or below the reorder level of '
                                  '${row.reorderLevel}',
                              child: Icon(
                                Icons.warning_amber_outlined,
                                size: 15,
                                color: context.statusColors.warning,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          Text(
                            '${row.sellableQuantity}',
                            style: context.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Avg cost',
                      width: 100,
                      numeric: true,
                      tooltip:
                          'Weighted average across the locations holding '
                          'the product',
                      cell: (context, row) =>
                          TableTextCell(row.averageCost.plain),
                    ),
                    AppTableColumn<ProductStockRow>(
                      label: 'Value',
                      width: 120,
                      numeric: true,
                      cell: (context, row) =>
                          TableTextCell(row.sellableValue.plain, bold: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(rows: stock.valueOrNull ?? const []),
        ],
      ),
    );
  }

  void _openMovements(
    BuildContext context,
    WidgetRef ref,
    ProductStockRow row,
  ) {
    // Clicking a product narrows the movement history to it, which is the
    // question somebody asks next: where did this stock come from?
    ref
        .read(stockLedgerFilterProvider.notifier)
        .update((state) => state.copyWith(productId: row.productId));
    showSuccessSnackBar(
      context,
      'Movement history filtered to ${row.productName}. '
      'Open Stock Movements to see it.',
    );
  }
}

class _QuantityCell extends StatelessWidget {
  const _QuantityCell({required this.quantity, this.muteZero = false});

  final int quantity;
  final bool muteZero;

  @override
  Widget build(BuildContext context) {
    if (quantity == 0 && muteZero) {
      return const TableTextCell('—', muted: true);
    }
    return Text(
      '$quantity',
      style: context.text.bodyMedium?.copyWith(
        // A real location below zero means something was posted that should
        // not have been; it is surfaced rather than hidden.
        color: quantity < 0 ? context.statusColors.danger : null,
        fontWeight: quantity < 0 ? FontWeight.w700 : null,
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.rows});

  final List<ProductStockRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final sellableValue = rows.map((row) => row.sellableValue).sum;
    final damagedUnits = rows.fold(
      0,
      (total, row) => total + row.damagedQuantity,
    );
    final lowStock = rows.where((row) => row.isLowStock).length;
    final negative = rows
        .where(
          (row) =>
              row.warehouseQuantity < 0 ||
              row.agentQuantity < 0 ||
              row.shopQuantity < 0,
        )
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${rows.length} product(s)', style: context.text.bodySmall),
          Text(
            'Sellable stock value ${sellableValue.formatted()}',
            style: context.text.bodySmall,
          ),
          if (damagedUnits != 0)
            Text(
              '$damagedUnits unit(s) in quarantine',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
          if (lowStock > 0)
            Text(
              '$lowStock at or below reorder level',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (negative > 0)
            Text(
              '$negative with a negative balance — investigate these',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}
