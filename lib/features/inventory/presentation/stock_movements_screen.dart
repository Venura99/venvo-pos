import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/inventory/domain/location_models.dart';
import 'package:venvo_core/features/inventory/domain/stock_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'stock_document_forms.dart';
import 'stock_providers.dart';

/// The stock ledger itself: every movement, in order, with the running
/// balance each one left behind.
///
/// This is the screen that answers "where did this stock go?", and it reads
/// the append-only ledger rather than any derived figure.
class StockMovementsScreen extends ConsumerWidget {
  const StockMovementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.stockView) ?? false)) {
      return const PageScaffold(
        title: 'Stock Movements',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to stock',
        ),
      );
    }

    final entries = ref.watch(stockLedgerProvider);
    final filter = ref.watch(stockLedgerFilterProvider);
    final locations = ref.watch(stockLocationsProvider);
    final products =
        ref.watch(allActiveProductsProvider).valueOrNull ?? const [];

    return PageScaffold(
      title: 'Stock Movements',
      description:
          'The stock ledger. Entries are written as part of the movement '
          'itself and are never edited or deleted; a mistake is corrected by '
          'a compensating document.',
      scrollable: false,
      actions: [
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () =>
                ref.read(stockLedgerFilterProvider.notifier).state =
                    const StockLedgerFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppSearchField(
                hintText: 'Search product, SKU or document number',
                width: 320,
                initialValue: filter.search,
                onChanged: (value) => ref
                    .read(stockLedgerFilterProvider.notifier)
                    .update((state) => state.copyWith(search: value)),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<int?>(
                  initialValue: filter.productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    const DropdownMenuItem<int?>(child: Text('All products')),
                    for (final product in products)
                      DropdownMenuItem<int?>(
                        value: product.id,
                        child: Text(product.name),
                      ),
                  ],
                  onChanged: (value) => ref
                      .read(stockLedgerFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearProduct: true)
                            : state.copyWith(productId: value),
                      ),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<int?>(
                  initialValue: filter.locationId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    const DropdownMenuItem<int?>(child: Text('All locations')),
                    for (final location in locations)
                      DropdownMenuItem<int?>(
                        value: location.id,
                        child: Text(location.name),
                      ),
                  ],
                  onChanged: (value) => ref
                      .read(stockLedgerFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearLocation: true)
                            : state.copyWith(locationId: value),
                      ),
                ),
              ),
              SizedBox(
                width: 170,
                child: AppDateField(
                  value: filter.from,
                  label: 'From',
                  onChanged: (value) => ref
                      .read(stockLedgerFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearFrom: true)
                            : state.copyWith(from: value),
                      ),
                ),
              ),
              SizedBox(
                width: 170,
                child: AppDateField(
                  value: filter.to,
                  label: 'To',
                  onChanged: (value) => ref
                      .read(stockLedgerFilterProvider.notifier)
                      .update(
                        (state) => value == null
                            ? state.copyWith(clearTo: true)
                            : state.copyWith(to: value),
                      ),
                ),
              ),
              FilterChip(
                selected: filter.includeVirtualLocations,
                label: const Text('Include counterparty legs'),
                avatar: const Icon(Icons.hub_outlined, size: 16),
                onSelected: (value) => ref
                    .read(stockLedgerFilterProvider.notifier)
                    .update(
                      (state) => state.copyWith(includeVirtualLocations: value),
                    ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Text(
            filter.includeVirtualLocations
                ? 'Showing both legs of every movement. Each movement writes a '
                      'balanced pair, so these rows sum to zero per product.'
                : 'Showing movements in and out of your own locations. Turn on '
                      'the counterparty legs to see the matching mirror rows.',
            style: context.text.bodySmall,
          ),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<StockLedgerRow>>(
              value: entries,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<StockLedgerRow>(
                  rows: rows,
                  minWidth: 1180,
                  onRowTap: (row) => _openDocument(context, ref, row),
                  empty: EmptyState(
                    icon: Icons.swap_vert_outlined,
                    title: filter.hasAnyFilter
                        ? 'No movements match these filters'
                        : 'No stock movements yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Every transfer, sale, return and adjustment will '
                              'appear here as it is posted.',
                  ),
                  columns: [
                    AppTableColumn<StockLedgerRow>(
                      label: 'When',
                      width: 140,
                      cell: (context, row) => TableTwoLineCell(
                        primary: DateFormat(
                          'd MMM yyyy',
                        ).format(row.occurredAt.toLocal()),
                        secondary: DateFormat(
                          'HH:mm',
                        ).format(row.occurredAt.toLocal()),
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Document',
                      width: 165,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.documentNumber,
                        secondary: stockDocumentTypeLabel(row.documentType),
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Product',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.productName,
                        secondary: row.sku,
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Location',
                      flex: 2,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.locationName,
                        secondary: locationKindLabel(row.locationKind),
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Counterparty',
                      flex: 2,
                      cell: (context, row) => TableTextCell(
                        row.counterpartyName ?? '—',
                        muted: true,
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Change',
                      width: 100,
                      numeric: true,
                      tooltip:
                          'Negative where goods left, positive where they '
                          'arrived',
                      cell: (context, row) => Text(
                        row.isInbound
                            ? '+${row.quantityDelta}'
                            : '${row.quantityDelta}',
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: row.isInbound
                              ? context.statusColors.success
                              : context.statusColors.danger,
                        ),
                      ),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Balance after',
                      width: 110,
                      numeric: true,
                      tooltip:
                          'The balance this entry left behind, recorded '
                          'at the time',
                      cell: (context, row) =>
                          TableTextCell('${row.balanceAfter}'),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'Status',
                      width: 100,
                      cell: (context, row) =>
                          StatusPill.document(row.documentStatus),
                    ),
                    AppTableColumn<StockLedgerRow>(
                      label: 'By',
                      flex: 2,
                      cell: (context, row) =>
                          TableTextCell(row.recordedBy, muted: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          _LedgerSummary(rows: entries.valueOrNull ?? const [], filter: filter),
        ],
      ),
    );
  }

  Future<void> _openDocument(
    BuildContext context,
    WidgetRef ref,
    StockLedgerRow row,
  ) async {
    final documents = ref.read(stockDocumentsProvider).valueOrNull ?? const [];
    final match = documents
        .where((document) => document.documentNumber == row.documentNumber)
        .toList();
    if (match.isEmpty) {
      showSuccessSnackBar(
        context,
        'Open the Stock Transfers register to view ${row.documentNumber}.',
      );
      return;
    }
    await showStockDocument(context, ref, match.first.id);
  }
}

class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({required this.rows, required this.filter});

  final List<StockLedgerRow> rows;
  final StockLedgerFilter filter;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final inbound = rows
        .where((row) => row.isInbound)
        .fold(0, (total, row) => total + row.quantityDelta);
    final outbound = rows
        .where((row) => !row.isInbound)
        .fold(0, (total, row) => total - row.quantityDelta);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            rows.length >= filter.limit
                ? 'Showing the latest ${rows.length} entries'
                : '${rows.length} entr${rows.length == 1 ? 'y' : 'ies'}',
            style: context.text.bodySmall,
          ),
          Text('$inbound unit(s) in', style: context.text.bodySmall),
          Text('$outbound unit(s) out', style: context.text.bodySmall),
        ],
      ),
    );
  }
}
