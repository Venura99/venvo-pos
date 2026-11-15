import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'inspection_dialog.dart';
import 'return_detail_dialog.dart';
import 'return_form.dart';
import 'return_providers.dart';

/// The returns register.
///
/// The pile awaiting inspection is pulled out at the top, because goods
/// sitting in transit are neither the returning party's problem nor available
/// to sell: somebody has to look at them before either can be true.
class ReturnsScreen extends ConsumerWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.returnView) ?? false)) {
      return const PageScaffold(
        title: 'Returns',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to returns',
        ),
      );
    }

    final canCreate = user?.can(Permissions.returnCreate) ?? false;

    return PageScaffold(
      title: 'Returns',
      description:
          'Goods coming back up the chain. A return takes the goods out of '
          'the returning location straight away, but they wait in transit '
          'until somebody inspects them - nothing re-enters sellable stock '
          'unseen, and no credit is raised before then.',
      scrollable: false,
      actions: [
        if (canCreate)
          FilledButton.icon(
            onPressed: () => _newReturn(context),
            icon: const Icon(Icons.assignment_return_outlined, size: 18),
            label: const Text('New return'),
          ),
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AwaitingInspectionBanner(),
          _Filters(),
          AppSpacing.gapLg,
          Expanded(child: _ReturnTable()),
          AppSpacing.gapSm,
          _SummaryBar(),
        ],
      ),
    );
  }

  Future<void> _newReturn(BuildContext context) async {
    final posted = await ReturnFormDialog.show(context);
    if (posted && context.mounted) {
      showSuccessSnackBar(
        context,
        'Return posted. The goods are in transit until they are inspected.',
      );
    }
  }
}

class _AwaitingInspectionBanner extends ConsumerWidget {
  const _AwaitingInspectionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(returnsProvider).valueOrNull;
    if (rows == null) return const SizedBox.shrink();

    final waiting = rows.where((row) => row.awaitsInspection).toList();
    if (waiting.isEmpty) return const SizedBox.shrink();

    final units = waiting.fold(0, (total, row) => total + row.totalQuantity);
    final canInspect =
        ref.watch(currentUserProvider)?.can(Permissions.returnInspect) ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: SectionCard(
        title:
            '${waiting.length} return(s) awaiting inspection '
            '· $units unit(s) in transit',
        subtitle:
            'These goods have left the returning location but have not been '
            'put anywhere yet. They are not sellable and not creditable until '
            'they are inspected.',
        leading: Icon(
          Icons.pending_actions_outlined,
          color: context.statusColors.warning,
        ),
        actions: [
          if (canInspect)
            OutlinedButton(
              onPressed: () => _inspectOldest(context, ref, waiting),
              child: const Text('Inspect the oldest'),
            ),
          TextButton(
            onPressed: () => ref
                .read(returnFilterProvider.notifier)
                .update((state) => state.copyWith(pendingInspectionOnly: true)),
            child: const Text('Show only these'),
          ),
        ],
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            for (final row in waiting.take(6))
              Chip(
                label: Text(
                  '${row.returnNumber} · ${row.fromLocationName} · '
                  '${row.totalQuantity} unit(s)',
                ),
                visualDensity: VisualDensity.compact,
              ),
            if (waiting.length > 6)
              Chip(
                label: Text('and ${waiting.length - 6} more'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _inspectOldest(
    BuildContext context,
    WidgetRef ref,
    List<ReturnSummary> waiting,
  ) async {
    final oldest = waiting.reduce(
      (a, b) => a.returnDate.isBefore(b.returnDate) ? a : b,
    );
    await showInspectionDialog(context, ref, oldest);
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(returnFilterProvider);
    final notifier = ref.read(returnFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search number, invoice, agent or shop',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<ReturnRoute?>(
            initialValue: filter.routes.length == 1
                ? filter.routes.first
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Route'),
            items: [
              const DropdownMenuItem<ReturnRoute?>(child: Text('All routes')),
              for (final route in ReturnRoute.values)
                DropdownMenuItem<ReturnRoute?>(
                  value: route,
                  child: Text(returnRouteLabel(route)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => state.copyWith(routes: value == null ? {} : {value}),
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<ReturnStatus?>(
            initialValue: filter.status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem<ReturnStatus?>(child: Text('Any status')),
              for (final status in ReturnStatus.values)
                DropdownMenuItem<ReturnStatus?>(
                  value: status,
                  child: Text(returnStatusLabel(status)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearStatus: true)
                  : state.copyWith(status: value),
            ),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<ReturnReason?>(
            initialValue: filter.reason,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [
              const DropdownMenuItem<ReturnReason?>(child: Text('Any reason')),
              for (final reason in ReturnReason.values)
                DropdownMenuItem<ReturnReason?>(
                  value: reason,
                  child: Text(returnReasonLabel(reason)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearReason: true)
                  : state.copyWith(reason: value),
            ),
          ),
        ),
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
        FilterChip(
          selected: filter.pendingInspectionOnly,
          label: const Text('Awaiting inspection'),
          avatar: const Icon(Icons.pending_outlined, size: 16),
          onSelected: (value) => notifier.update(
            (state) => state.copyWith(pendingInspectionOnly: value),
          ),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const ReturnFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _ReturnTable extends ConsumerWidget {
  const _ReturnTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(returnsProvider);
    final filter = ref.watch(returnFilterProvider);

    return AsyncValueView<List<ReturnSummary>>(
      value: returns,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<ReturnSummary>(
          rows: rows,
          minWidth: 1260,
          onRowTap: (row) => showReturnDetail(context, ref, row.id),
          empty: EmptyState(
            icon: Icons.assignment_return_outlined,
            title: filter.hasAnyFilter
                ? 'No returns match these filters'
                : 'No returns yet',
            message: filter.hasAnyFilter
                ? null
                : 'Record a return when goods come back from a shop, an agent '
                      'or a customer.',
          ),
          columns: [
            AppTableColumn<ReturnSummary>(
              label: 'Return',
              width: 160,
              cell: (context, row) => TableTwoLineCell(
                primary: row.returnNumber,
                secondary: returnRouteLabel(row.route),
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Date',
              width: 110,
              cell: (context, row) => TableTextCell(
                DateFormat('d MMM yyyy').format(row.returnDate.toLocal()),
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'From',
              flex: 3,
              cell: (context, row) => TableTwoLineCell(
                primary: row.fromLocationName,
                secondary: 'to ${row.toLocationName}',
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Reason',
              flex: 2,
              cell: (context, row) => TableTwoLineCell(
                primary: returnReasonLabel(row.reason),
                secondary: row.originInvoiceNumber ?? 'not traced',
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Units',
              width: 80,
              numeric: true,
              cell: (context, row) => TableTextCell('${row.totalQuantity}'),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Value',
              width: 115,
              numeric: true,
              cell: (context, row) => TableTextCell(
                row.totalValue.isZero ? '—' : row.totalValue.plain,
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Credited',
              width: 115,
              numeric: true,
              cell: (context, row) => Text(
                row.creditedValue.isZero ? '—' : row.creditedValue.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  color: row.creditedValue.isZero
                      ? context.colors.onSurfaceVariant
                      : context.statusColors.info,
                ),
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: 'Status',
              width: 160,
              cell: (context, row) => StatusPill(
                row.awaitsInspection && row.pendingLineCount > 0
                    ? '${row.pendingLineCount} to inspect'
                    : returnStatusLabel(row.status),
                tone: _toneFor(row.status),
              ),
            ),
            AppTableColumn<ReturnSummary>(
              label: '',
              width: 56,
              cell: (context, row) => _RowMenu(document: row),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(returnTotalsProvider).valueOrNull;
    if (totals == null || totals.documentCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            '${totals.documentCount} return(s)',
            style: context.text.bodySmall,
          ),
          Text('${totals.totalUnits} unit(s)', style: context.text.bodySmall),
          Text(
            'Returned value ${totals.totalValue.formatted()}',
            style: context.text.bodySmall,
          ),
          if (totals.awaitingInspection > 0)
            Text(
              '${totals.awaitingInspection} awaiting inspection',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (!totals.creditedValue.isZero)
            Text(
              'Credited ${totals.creditedValue.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.info,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.document});

  final ReturnSummary document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canInspect = user?.can(Permissions.returnInspect) ?? false;
    final canCancel = user?.can(Permissions.returnCreate) ?? false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await showReturnDetail(context, ref, document.id);
          case 'inspect':
            await showInspectionDialog(context, ref, document);
          case 'cancel':
            await confirmAndCancelReturn(context, ref, document);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View return')),
        if (canInspect && document.awaitsInspection)
          const PopupMenuItem(value: 'inspect', child: Text('Inspect goods')),
        if (canCancel && document.canBeCancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'cancel', child: Text('Cancel return')),
        ],
      ],
    );
  }
}

/// Asks for a reason, then cancels the return by reversing its movements.
Future<void> confirmAndCancelReturn(
  BuildContext context,
  WidgetRef ref,
  ReturnSummary document,
) async {
  final reasonController = TextEditingController();

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Cancel ${document.returnNumber}?',
      subtitle:
          'The return and its lines are kept exactly as they are. The goods '
          'go back where they came from through opposing ledger entries, so '
          'the history stays intact.',
      submitLabel: 'Cancel the return',
      onSubmit: () => ref
          .read(returnServiceProvider)
          .cancelReturn(
            ref.read(requireCurrentUserProvider),
            returnId: document.id,
            reason: reasonController.text,
          ),
      child: AppTextField(
        controller: reasonController,
        label: 'Reason',
        isRequired: true,
        autofocus: true,
        maxLines: 2,
        maxLength: 500,
      ),
    ),
  );

  reasonController.dispose();
  if ((cancelled ?? false) && context.mounted) {
    showSuccessSnackBar(context, '${document.returnNumber} cancelled.');
  }
}

StatusTone _toneFor(ReturnStatus status) => switch (status) {
  ReturnStatus.draft => StatusTone.neutral,
  ReturnStatus.posted => StatusTone.warning,
  ReturnStatus.inspected => StatusTone.info,
  ReturnStatus.completed => StatusTone.success,
  ReturnStatus.cancelled => StatusTone.danger,
};
