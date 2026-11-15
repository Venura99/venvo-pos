import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/categories/domain/category_models.dart';
import 'package:venvo_core/features/products/api/product_api.dart';
import 'package:venvo_core/features/products/domain/product_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../categories/presentation/categories_screen.dart';
import 'product_form.dart';

final productRepositoryProvider = Provider<ProductApi>(
  (ref) => ProductApi(ref.watch(apiClientProvider)),
);

final productFilterProvider = StateProvider<ProductFilter>(
  (ref) => const ProductFilter(),
);

/// Live, filtered catalogue. Filtering happens in SQL so the product indexes
/// are used rather than loading everything and sifting it in memory.
final productsProvider = StreamProvider<List<ProductListItem>>((ref) {
  return ref
      .watch(productRepositoryProvider)
      .watchProducts(ref.watch(productFilterProvider));
});

final productBrandsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(productRepositoryProvider).watchBrands();
});

/// Active categories, for the filter and the form's category picker.
final selectableCategoriesProvider = FutureProvider<List<CategoryListItem>>((
  ref,
) {
  // Depends on the live category list so adding a category while the product
  // form is open is picked up next time it opens.
  ref.watch(categoriesProvider);
  return ref.watch(categoryRepositoryProvider).selectableCategories();
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.productsView) ?? false)) {
      return const PageScaffold(
        title: 'Products',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to the product catalogue',
        ),
      );
    }

    final canManage = user?.can(Permissions.productsManage) ?? false;
    final products = ref.watch(productsProvider);
    final filter = ref.watch(productFilterProvider);

    return PageScaffold(
      title: 'Products',
      description:
          'The catalogue. Prices here are the defaults offered on new '
          'documents; a posted invoice keeps the price it was raised with.',
      scrollable: false,
      actions: [
        if (canManage)
          FilledButton.icon(
            onPressed: () => _openForm(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add product'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(filter: filter),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<ProductListItem>>(
              value: products,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: _ProductTable(
                  rows: rows,
                  filter: filter,
                  canManage: canManage,
                  onRowTap: canManage
                      ? (product) => _openForm(context, ref, product)
                      : null,
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _SummaryBar(products: products.valueOrNull ?? const []),
        ],
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    ProductListItem? existing,
  ) async {
    final categories = await ref.read(selectableCategoriesProvider.future);
    if (!context.mounted) return;

    if (categories.isEmpty) {
      final goToCategories = await ConfirmDialog.show(
        context,
        title: 'Add a category first',
        message:
            'Every product belongs to a category, and there are no active '
            'categories yet. Add one such as Chargers or Cables, then come '
            'back here.',
        confirmLabel: 'Open categories',
        icon: Icons.folder_outlined,
      );
      if (goToCategories && context.mounted) {
        showSuccessSnackBar(
          context,
          'Open Master Data, then Categories, to add one.',
        );
      }
      return;
    }

    final saved = await ProductFormDialog.show(
      context,
      categories: categories,
      existing: existing,
    );
    if (saved && context.mounted) {
      showSuccessSnackBar(
        context,
        existing == null ? 'Product added.' : 'Product saved.',
      );
    }
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});

  final ProductFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(selectableCategoriesProvider).valueOrNull ??
        const <CategoryListItem>[];
    final brands = ref.watch(productBrandsProvider).valueOrNull ?? const [];
    final notifier = ref.read(productFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search name, SKU, barcode or brand',
          width: 340,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 210,
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
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearCategory: true)
                  : state.copyWith(categoryId: value),
            ),
          ),
        ),
        if (brands.isNotEmpty)
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              initialValue: filter.brand,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Brand'),
              items: [
                const DropdownMenuItem<String?>(child: Text('All brands')),
                for (final brand in brands)
                  DropdownMenuItem<String?>(value: brand, child: Text(brand)),
              ],
              onChanged: (value) => notifier.update(
                (state) => value == null
                    ? state.copyWith(clearBrand: true)
                    : state.copyWith(brand: value),
              ),
            ),
          ),
        FilterChip(
          selected: filter.lowStockOnly,
          label: const Text('Low stock only'),
          avatar: const Icon(Icons.warning_amber_outlined, size: 16),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(lowStockOnly: value)),
        ),
        FilterChip(
          selected: filter.includeInactive,
          label: const Text('Include inactive'),
          onSelected: (value) => notifier.update(
            (state) => state.copyWith(includeInactive: value),
          ),
        ),
        FilterChip(
          selected: filter.includeArchived,
          label: const Text('Include archived'),
          onSelected: (value) => notifier.update(
            (state) => state.copyWith(includeArchived: value),
          ),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const ProductFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _ProductTable extends ConsumerWidget {
  const _ProductTable({
    required this.rows,
    required this.filter,
    required this.canManage,
    required this.onRowTap,
  });

  final List<ProductListItem> rows;
  final ProductFilter filter;
  final bool canManage;
  final ValueChanged<ProductListItem>? onRowTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppDataTable<ProductListItem>(
      rows: rows,
      minWidth: 1180,
      onRowTap: onRowTap,
      sortKey: filter.sortKey.id,
      sortAscending: filter.sortAscending,
      onSort: (key) {
        final sortKey = ProductSortKey.fromId(key);
        if (sortKey == null) return;
        ref
            .read(productFilterProvider.notifier)
            .update((state) => state.withSort(sortKey));
      },
      empty: EmptyState(
        icon: Icons.inventory_2_outlined,
        title: filter.hasAnyFilter
            ? 'No products match these filters'
            : 'No products yet',
        message: filter.hasAnyFilter
            ? 'Try clearing the filters, or widen the search.'
            : 'Add the products you distribute: chargers, cables, earbuds, '
                  'power banks.',
      ),
      columns: [
        AppTableColumn<ProductListItem>(
          label: 'Product',
          flex: 4,
          sortKey: ProductSortKey.name.id,
          cell: (context, row) => TableTwoLineCell(
            primary: row.name,
            secondary: row.brand == null
                ? row.sku
                : '${row.sku} · ${row.brand}',
          ),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Category',
          flex: 2,
          sortKey: ProductSortKey.category.id,
          cell: (context, row) => TableTextCell(row.categoryName, muted: true),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Cost',
          width: 100,
          numeric: true,
          sortKey: ProductSortKey.costPrice.id,
          cell: (context, row) => TableTextCell(row.costPrice.plain),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Wholesale',
          width: 110,
          numeric: true,
          sortKey: ProductSortKey.wholesalePrice.id,
          cell: (context, row) => Text(
            row.wholesalePrice.plain,
            style: context.text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: row.sellsBelowCost ? context.statusColors.danger : null,
            ),
          ),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Retail',
          width: 100,
          numeric: true,
          sortKey: ProductSortKey.retailPrice.id,
          cell: (context, row) => TableTextCell(row.retailPrice.plain),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Warehouse',
          width: 95,
          numeric: true,
          tooltip: 'Units in the main warehouse',
          cell: (context, row) => TableTextCell('${row.warehouseQuantity}'),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Agents',
          width: 80,
          numeric: true,
          tooltip: 'Units held by agents',
          cell: (context, row) => TableTextCell('${row.agentQuantity}'),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Shops',
          width: 80,
          numeric: true,
          tooltip: 'Units held by shops',
          cell: (context, row) => TableTextCell('${row.shopQuantity}'),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Total',
          width: 90,
          numeric: true,
          sortKey: ProductSortKey.stock.id,
          tooltip:
              'Sellable units across every location. Damaged stock is '
              'excluded.',
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        AppTableColumn<ProductListItem>(
          label: 'Status',
          width: 100,
          cell: (context, row) => StatusPill.entity(row.status),
        ),
        AppTableColumn<ProductListItem>(
          label: '',
          width: 56,
          cell: (context, row) =>
              canManage ? _RowMenu(product: row) : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Totals under the table, so the catalogue's size and value are visible
/// without opening a report.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.products});

  final List<ProductListItem> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    final lowStock = products.where((p) => p.isLowStock).length;
    final belowCost = products.where((p) => p.sellsBelowCost).length;
    final stockValue = products.map((p) => p.stockValueAtCost).sum;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            products.length == 1 ? '1 product' : '${products.length} products',
            style: context.text.bodySmall,
          ),
          Text(
            'Stock value at cost ${stockValue.formatted()}',
            style: context.text.bodySmall,
          ),
          if (lowStock > 0)
            Text(
              '$lowStock at or below reorder level',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (belowCost > 0)
            Text(
              '$belowCost priced below cost',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.product});

  final ProductListItem product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'stock', child: Text('Where is the stock?')),
        const PopupMenuDivider(),
        if (product.isArchived)
          const PopupMenuItem(value: 'restore', child: Text('Restore'))
        else
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repository = ref.read(productRepositoryProvider);
    final actor = ref.read(requireCurrentUserProvider);

    try {
      switch (action) {
        case 'edit':
          final categories = await ref.read(
            selectableCategoriesProvider.future,
          );
          if (!context.mounted) return;
          await ProductFormDialog.show(
            context,
            categories: categories,
            existing: product,
          );
        case 'stock':
          final holdings = await repository.stockByLocation(product.id);
          if (!context.mounted) return;
          await _showStockBreakdown(context, holdings);
        case 'archive':
          final confirmed = await ConfirmDialog.show(
            context,
            title: 'Archive "${product.name}"?',
            message:
                'It will not be offered on new documents. Every past invoice '
                'and stock movement keeps it exactly as it is.',
            details: [
              'SKU ${product.sku}',
              'Stock on hand: ${product.sellableQuantity} unit(s)',
            ],
            confirmLabel: 'Archive',
            icon: Icons.archive_outlined,
          );
          if (!confirmed) return;
          await repository.archive(actor, product.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Product archived.');
          }
        case 'restore':
          await repository.restore(actor, product.id);
          if (context.mounted) {
            showSuccessSnackBar(context, 'Product restored.');
          }
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _showStockBreakdown(
    BuildContext context,
    List<ProductStockAtLocation> holdings,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: SizedBox(
          width: 420,
          child: holdings.isEmpty
              ? const Text('This product has no stock anywhere.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final holding in holdings)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(holding.locationName),
                        subtitle: Text(holding.locationKind.name),
                        trailing: Text(
                          '${holding.quantity}',
                          style: context.text.titleSmall,
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
