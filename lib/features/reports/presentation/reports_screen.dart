import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/reports/data/report_export_service.dart';
import 'package:venvo_core/features/reports/domain/report_models.dart';

import '../../../core/services/file_delivery.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../agents/presentation/agents_screen.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../employees/presentation/employees_screen.dart';
import '../../expenses/presentation/expense_providers.dart';
import '../../inventory/presentation/location_providers.dart';
import '../../products/presentation/products_screen.dart';
import '../../shops/presentation/shops_screen.dart';
import 'report_providers.dart';

/// The report set.
///
/// One screen for all eighteen: they share a period, a filter bar that shows
/// only the filters the open report actually uses, and the same export. The
/// caveats under each report are part of the report, not decoration - a figure
/// that counts only cleared money has to say so wherever it is read.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final visible = ref.watch(visibleReportsProvider);

    if (user == null || visible.isEmpty) {
      return const PageScaffold(
        title: 'Reports',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to any reports',
          message:
              'Each report needs the same permission as the module it reads.',
        ),
      );
    }

    return const PageScaffold(
      title: 'Reports',
      description:
          'Every report is built from the same definitions the screens use, '
          'so a figure here and the register it came from can never '
          'disagree. Each one carries its own caveats, and they print.',
      scrollable: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 290, child: _ReportList()),
          AppSpacing.hGapLg,
          Expanded(child: _ReportPane()),
        ],
      ),
    );
  }
}

class _ReportList extends ConsumerWidget {
  const _ReportList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleReportsProvider);
    final selected = ref.watch(selectedReportProvider);

    final grouped = <ReportGroup, List<ReportDefinition>>{};
    for (final report in visible) {
      grouped.putIfAbsent(report.group, () => []).add(report);
    }

    return SectionCard(
      title: '${visible.length} reports',
      padding: EdgeInsets.zero,
      fillHeight: true,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          for (final group in ReportGroup.values)
            if (grouped[group] != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Text(
                  reportGroupLabel(group).toUpperCase(),
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              for (final report in grouped[group]!)
                ListTile(
                  dense: true,
                  selected: report.id == selected?.id,
                  title: Text(report.title),
                  onTap: () =>
                      ref.read(selectedReportIdProvider.notifier).state =
                          report.id,
                ),
            ],
        ],
      ),
    );
  }
}

class _ReportPane extends ConsumerWidget {
  const _ReportPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final definition = ref.watch(selectedReportProvider);
    if (definition == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(definition: definition),
        AppSpacing.gapLg,
        _Filters(definition: definition),
        AppSpacing.gapLg,
        const Expanded(child: _ResultTable()),
        const _Notes(),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.definition});

  final ReportDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canExport =
        ref.watch(currentUserProvider)?.can(Permissions.reportsExport) ?? false;
    final result = ref.watch(reportResultProvider).valueOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(definition.title, style: context.text.titleLarge),
              Text(definition.description, style: context.text.bodySmall),
            ],
          ),
        ),
        if (canExport && result != null && !result.isEmpty) ...[
          AppSpacing.hGapMd,
          OutlinedButton.icon(
            onPressed: () => _export(context, ref, csv: true),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('CSV'),
          ),
          AppSpacing.hGapSm,
          FilledButton.icon(
            onPressed: () => _export(context, ref, csv: false),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF'),
          ),
        ],
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool csv,
  }) async {
    try {
      final result = ref.read(reportResultProvider).valueOrNull;
      if (result == null) return;
      final service = await ref.read(reportExportServiceProvider.future);
      final extension = csv ? 'csv' : 'pdf';
      final fileName = ReportExportService.fileNameFor(
        definition.id,
        result.generatedAt,
        extension: extension,
      );
      // Built in memory and handed over as a download or through the save
      // dialog, because a browser has no exports folder to write into.
      final savedTo = await FileDelivery.save(
        bytes: csv
            ? service.buildCsvBytes(result)
            : await service.buildPdf(result),
        fileName: fileName,
        mimeType: csv ? 'text/csv' : 'application/pdf',
      );

      // Null means the user closed the save dialog. That is a decision, not a
      // failure, so nothing is reported.
      if (savedTo == null || !context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ErrorView.describe(error))));
    }
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.definition});

  final ReportDefinition definition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final notifier = ref.read(reportFilterProvider.notifier);
    final now = DateTime.now();

    final fields = <Widget>[];

    if (definition.offers(ReportFilterField.period)) {
      fields.addAll([
        SizedBox(
          width: 165,
          child: AppDateField(
            value: filter.from,
            label: 'From',
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearFrom: true)
                  : state.copyWith(from: value),
            ),
          ),
        ),
        SizedBox(
          width: 165,
          child: AppDateField(
            value: filter.to,
            label: 'To',
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearTo: true)
                  : state.copyWith(to: value),
            ),
          ),
        ),
        OutlinedButton(
          onPressed: () => notifier.update(
            (state) => state.copyWith(
              from: DateTime(now.year, now.month),
              to: DateTime(
                now.year,
                now.month + 1,
              ).subtract(const Duration(days: 1)),
            ),
          ),
          child: const Text('This month'),
        ),
        OutlinedButton(
          onPressed: () => notifier.update(
            (state) => state.copyWith(
              from: DateTime(now.year),
              to: DateTime(now.year + 1).subtract(const Duration(days: 1)),
            ),
          ),
          child: const Text('This year'),
        ),
      ]);
    }

    if (definition.offers(ReportFilterField.agent)) {
      final agents =
          ref.watch(selectableAgentsProvider).valueOrNull ?? const [];
      fields.add(
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.agentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Agent'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All agents')),
              for (final agent in agents)
                DropdownMenuItem<int?>(
                  value: agent.id,
                  child: Text(agent.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearAgent: true)
                  : state.copyWith(agentId: value),
            ),
          ),
        ),
      );
    }

    if (definition.offers(ReportFilterField.shop)) {
      final shops = ref.watch(shopsProvider).valueOrNull ?? const [];
      fields.add(
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.shopId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Shop'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All shops')),
              for (final shop in shops)
                DropdownMenuItem<int?>(value: shop.id, child: Text(shop.name)),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearShop: true)
                  : state.copyWith(shopId: value),
            ),
          ),
        ),
      );
    }

    if (definition.offers(ReportFilterField.category)) {
      // Product categories for the stock and sales reports; expense
      // categories for the expense report, which is the only place the word
      // means something else.
      final isExpense = definition.group == ReportGroup.finance;
      final items = isExpense
          ? (ref.watch(expenseCategoriesProvider).valueOrNull ?? const [])
                .map((category) => (id: category.id, name: category.name))
                .toList()
          : (ref.watch(selectableCategoriesProvider).valueOrNull ?? const [])
                .map((category) => (id: category.id, name: category.name))
                .toList();

      fields.add(
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All categories')),
              for (final category in items)
                DropdownMenuItem<int?>(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearCategory: true)
                  : state.copyWith(categoryId: value),
            ),
          ),
        ),
      );
    }

    if (definition.offers(ReportFilterField.product)) {
      final products = ref.watch(productsProvider).valueOrNull ?? const [];
      fields.add(
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: [
              const DropdownMenuItem<int?>(child: Text('All products')),
              for (final product in products.take(300))
                DropdownMenuItem<int?>(
                  value: product.id,
                  child: Text(product.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearProduct: true)
                  : state.copyWith(productId: value),
            ),
          ),
        ),
      );
    }

    if (definition.offers(ReportFilterField.employee)) {
      final employees =
          ref.watch(selectableEmployeesProvider).valueOrNull ?? const [];
      fields.add(
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<int?>(
            initialValue: filter.employeeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Employee'),
            items: [
              const DropdownMenuItem<int?>(child: Text('Everybody')),
              for (final employee in employees)
                DropdownMenuItem<int?>(
                  value: employee.id,
                  child: Text(employee.name),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearEmployee: true)
                  : state.copyWith(employeeId: value),
            ),
          ),
        ),
      );
    }

    if (definition.offers(ReportFilterField.location)) {
      final locations = (ref.watch(locationsProvider).valueOrNull ?? const [])
          .where((location) => !location.isVirtual && location.isActive)
          .toList();
      fields.add(
        SizedBox(
          width: 210,
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
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearLocation: true)
                  : state.copyWith(locationId: value),
            ),
          ),
        ),
      );
    }

    if (fields.isEmpty) {
      return Text(
        'This report is a position as it stands now, so there is nothing to '
        'narrow it by.',
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    if (filter.hasAnyFilter) {
      fields.add(
        TextButton.icon(
          onPressed: () => notifier.state = const ReportFilter(),
          icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
          label: const Text('Clear'),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: fields,
    );
  }
}

class _ResultTable extends ConsumerWidget {
  const _ResultTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<ReportResult?>(
      value: ref.watch(reportResultProvider),
      onRetry: () => ref.invalidate(reportResultProvider),
      builder: (context, result) {
        if (result == null) return const SizedBox.shrink();

        final columns = [
          for (var index = 0; index < result.columns.length; index++)
            AppTableColumn<ReportRow>(
              label: result.columns[index].label,
              width: result.columns[index].width,
              flex: result.columns[index].flex,
              numeric: result.columns[index].isNumeric,
              cell: (context, row) => _Cell(
                value: index < row.values.length
                    ? row.values[index]
                    : ReportValue.empty,
                column: result.columns[index],
                emphasise: row.emphasise,
              ),
            ),
        ];

        return SectionCard(
          title: result.isEmpty
              ? null
              : '${result.rows.length} row(s)'
                    '${result.subtitle == null ? '' : ' · ${result.subtitle}'}',
          padding: EdgeInsets.zero,
          fillHeight: true,
          child: AppDataTable<ReportRow>(
            rows: result.rows,
            minWidth: _minWidthFor(result),
            empty: const EmptyState(
              icon: Icons.insert_chart_outlined,
              title: 'Nothing to report',
              message: 'No records match this report over the period selected.',
            ),
            trailingRowBuilder: result.totals == null
                ? null
                : (context) => _TotalsRow(result: result, columns: columns),
            columns: columns,
          ),
        );
      },
    );
  }

  /// Enough width that every column gets its declared size, so a wide report
  /// scrolls sideways rather than crushing its columns.
  ///
  /// The table's own gutters count towards it: leaving them out is what made
  /// an eighteen-column report overflow its row by exactly the space between
  /// the columns.
  static double _minWidthFor(ReportResult result) {
    var width = AppTableSummaryRow.guttersFor(result.columns.length);
    for (final column in result.columns) {
      width += column.width ?? (140.0 * column.flex);
    }
    return width < 720 ? 720 : width;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.column,
    this.emphasise = false,
  });

  final ReportValue value;
  final ReportColumn column;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final text = ReportExportService.formatForDisplay(value);

    return Text(
      text.isEmpty ? '—' : text,
      textAlign: column.isNumeric ? TextAlign.right : TextAlign.left,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.text.bodyMedium?.copyWith(
        fontWeight: emphasise ? FontWeight.w700 : null,
        color: value.isNegative ? context.statusColors.danger : null,
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.result, required this.columns});

  final ReportResult result;
  final List<AppTableColumn<ReportRow>> columns;

  @override
  Widget build(BuildContext context) {
    return AppTableSummaryRow<ReportRow>(
      columns: columns,
      cell: (context, column, index) => Text(
        index == 0
            ? 'Total'
            : ReportExportService.formatForDisplay(
                index < result.totals!.length
                    ? result.totals![index]
                    : ReportValue.empty,
              ),
        textAlign: column.numeric ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Notes extends ConsumerWidget {
  const _Notes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(reportResultProvider).valueOrNull;
    if (result == null || result.notes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in result.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 13,
                    color: context.colors.onSurfaceVariant,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      note.text,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
