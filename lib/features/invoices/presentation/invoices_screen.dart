import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'invoice_detail_dialog.dart';
import 'invoice_form.dart';
import 'invoice_providers.dart';

/// The invoice register, plus the deliveries still waiting to be billed.
///
/// The second list is the point where a transfer becomes revenue, and it is on
/// this screen because "what have we delivered but not charged for?" is a
/// question somebody has to answer every day.
class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({
    super.key,
    this.title = 'Invoices',
    this.description =
        'An invoice is what makes money owed. Amounts shown as received count '
        'cleared payments only; cheques awaiting clearance are listed '
        'separately.',
    this.presetKinds = const {},
    this.presetMode,
    this.showUnbilledDeliveries = true,
    this.newInvoiceLabel = 'New invoice',
  });

  /// The retail-sales register: what shops sold to end customers, reported
  /// apart from the wholesale supply that stocked them.
  const InvoicesScreen.retailSales({super.key})
    : title = 'Retail Sales',
      description =
          'What each shop sold to end customers. Recorded separately from '
          'the wholesale supply that stocked it, so the same goods are '
          'never counted as revenue twice.',
      presetKinds = const {InvoiceKind.retailSale},
      presetMode = InvoiceMode.retailSale,
      showUnbilledDeliveries = false,
      newInvoiceLabel = 'New retail sale';

  final String title;
  final String description;

  /// Narrows the register when this screen is opened.
  final Set<InvoiceKind> presetKinds;

  /// Which flow the "new" button opens.
  final InvoiceMode? presetMode;
  final bool showUnbilledDeliveries;
  final String newInvoiceLabel;

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  @override
  void initState() {
    super.initState();
    // Apply this screen's preset once, after the first frame, so the shared
    // filter reflects which register was opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(invoiceFilterProvider.notifier).state = InvoiceFilter(
        kinds: widget.presetKinds,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.invoiceView) ?? false)) {
      return PageScaffold(
        title: widget.title,
        child: const EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to invoices',
        ),
      );
    }

    final canCreate = user?.can(Permissions.invoiceCreate) ?? false;
    final unbilled =
        ref.watch(unbilledDeliveriesProvider).valueOrNull ??
        const <UnbilledDelivery>[];

    return PageScaffold(
      title: widget.title,
      description: widget.description,
      scrollable: false,
      actions: [
        if (canCreate)
          FilledButton.icon(
            onPressed: () => _newInvoice(context),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(widget.newInvoiceLabel),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showUnbilledDeliveries && unbilled.isNotEmpty) ...[
            _UnbilledDeliveriesCard(deliveries: unbilled),
            AppSpacing.gapLg,
          ],
          const _Filters(),
          AppSpacing.gapLg,
          const Expanded(child: _InvoiceTable()),
          AppSpacing.gapSm,
          const _SummaryBar(),
        ],
      ),
    );
  }

  Future<void> _newInvoice(BuildContext context) async {
    final posted = await InvoiceFormDialog.show(
      context,
      initialMode: widget.presetMode,
    );
    if (posted && context.mounted) {
      showSuccessSnackBar(context, 'Invoice posted.');
    }
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(invoiceFilterProvider);
    final notifier = ref.read(invoiceFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search number, agent, shop or customer',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<InvoiceKind?>(
            initialValue: filter.kinds.length == 1 ? filter.kinds.first : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              const DropdownMenuItem<InvoiceKind?>(child: Text('All kinds')),
              for (final kind in InvoiceKind.values)
                DropdownMenuItem<InvoiceKind?>(
                  value: kind,
                  child: Text(invoiceKindLabel(kind)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => state.copyWith(kinds: value == null ? {} : {value}),
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<PaymentSettlementStatus?>(
            initialValue: filter.settlement,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Settlement'),
            items: [
              const DropdownMenuItem<PaymentSettlementStatus?>(
                child: Text('Any'),
              ),
              for (final status in PaymentSettlementStatus.values)
                DropdownMenuItem<PaymentSettlementStatus?>(
                  value: status,
                  child: Text(settlementLabel(status)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearSettlement: true)
                  : state.copyWith(settlement: value),
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
          selected: filter.unpaidOnly,
          label: const Text('Unpaid only'),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(unpaidOnly: value)),
        ),
        FilterChip(
          selected: filter.overdueOnly,
          label: const Text('Overdue'),
          avatar: const Icon(Icons.schedule, size: 16),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(overdueOnly: value)),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const InvoiceFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _InvoiceTable extends ConsumerWidget {
  const _InvoiceTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final now = ref.watch(clockProvider).nowUtc();

    return AsyncValueView<List<InvoiceSummary>>(
      value: invoices,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<InvoiceSummary>(
          rows: rows,
          minWidth: 1220,
          onRowTap: (row) => showInvoiceDetail(context, ref, row.id),
          empty: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: filter.hasAnyFilter
                ? 'No invoices match these filters'
                : 'No invoices yet',
            message: filter.hasAnyFilter
                ? null
                : 'Raise an invoice, or bill a delivery that has already gone '
                      'out.',
          ),
          columns: [
            AppTableColumn<InvoiceSummary>(
              label: 'Invoice',
              width: 165,
              cell: (context, row) => TableTwoLineCell(
                primary: row.invoiceNumber,
                secondary: invoiceKindLabel(row.kind),
              ),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Date',
              width: 115,
              cell: (context, row) => row.dueDate == null
                  ? TableTextCell(
                      DateFormat(
                        'd MMM yyyy',
                      ).format(row.invoiceDate.toLocal()),
                    )
                  : TableTwoLineCell(
                      primary: DateFormat(
                        'd MMM yyyy',
                      ).format(row.invoiceDate.toLocal()),
                      secondary: row.isOverdue(now)
                          ? 'overdue'
                          : 'due ${DateFormat('d MMM').format(row.dueDate!.toLocal())}',
                    ),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Billed to',
              flex: 3,
              cell: (context, row) => TableTwoLineCell(
                primary: row.partyName,
                secondary:
                    row.agentName == null ||
                        row.kind == InvoiceKind.agentInvoice
                    ? (row.stockDocumentNumber ?? '—')
                    : 'via ${row.agentName}',
              ),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Gross',
              width: 110,
              numeric: true,
              cell: (context, row) => TableTextCell(row.gross.plain),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Discount',
              width: 100,
              numeric: true,
              cell: (context, row) {
                final discount = row.itemDiscount + row.invoiceDiscount;
                return Text(
                  discount.isZero ? '—' : discount.plain,
                  style: context.text.bodyMedium?.copyWith(
                    color: discount.isZero
                        ? context.colors.onSurfaceVariant
                        : context.statusColors.warning,
                  ),
                );
              },
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Net',
              width: 115,
              numeric: true,
              cell: (context, row) => TableTextCell(row.net.plain, bold: true),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Received',
              width: 110,
              numeric: true,
              tooltip: 'Cleared money and applied credit notes only',
              cell: (context, row) => TableTextCell(
                (row.settled + row.creditApplied).isZero
                    ? '—'
                    : (row.settled + row.creditApplied).plain,
                muted: (row.settled + row.creditApplied).isZero,
              ),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Outstanding',
              width: 125,
              numeric: true,
              cell: (context, row) => Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (row.hasPendingCheques) ...[
                    Tooltip(
                      message:
                          '${row.pendingCheques.formatted()} received by '
                          'cheque, awaiting clearance. It does not reduce '
                          'this balance yet.',
                      child: Icon(
                        Icons.hourglass_empty,
                        size: 14,
                        color: context.statusColors.warning,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Text(
                    row.outstanding.isZero ? '—' : row.outstanding.plain,
                    style: context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: row.outstanding.isPositive
                          ? context.statusColors.danger
                          : context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AppTableColumn<InvoiceSummary>(
              label: 'Status',
              width: 135,
              cell: (context, row) => row.isCancelled
                  ? const StatusPill('Cancelled', tone: StatusTone.danger)
                  : StatusPill.settlement(row.settlementStatus),
            ),
            AppTableColumn<InvoiceSummary>(
              label: '',
              width: 56,
              cell: (context, row) => _RowMenu(invoice: row),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnbilledDeliveriesCard extends ConsumerWidget {
  const _UnbilledDeliveriesCard({required this.deliveries});

  final List<UnbilledDelivery> deliveries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate =
        ref.watch(currentUserProvider)?.can(Permissions.invoiceCreate) ?? false;
    final total = deliveries.map((d) => d.documentValue).sum;

    return SectionCard(
      title: '${deliveries.length} delivery(s) not yet billed',
      subtitle:
          'Goods have gone out on these documents. Until an invoice is '
          'raised they are not revenue and nobody owes for them.',
      leading: Icon(
        Icons.assignment_late_outlined,
        color: context.statusColors.warning,
      ),
      actions: [
        if (!total.isZero)
          Text(
            'Delivery value ${total.formatted()}',
            style: context.text.bodySmall,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final delivery in deliveries.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      delivery.documentNumber,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${delivery.partyName} · '
                      '${delivery.totalQuantity} unit(s) · '
                      '${DateFormat('d MMM yyyy').format(delivery.documentDate.toLocal())}',
                      style: context.text.bodySmall,
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: Text(
                      delivery.needsPrices
                          ? 'no prices'
                          : delivery.documentValue.plain,
                      textAlign: TextAlign.right,
                      style: context.text.bodySmall,
                    ),
                  ),
                  AppSpacing.hGapMd,
                  if (canCreate)
                    OutlinedButton(
                      onPressed: () => _bill(context, delivery),
                      child: const Text('Bill it'),
                    ),
                ],
              ),
            ),
          if (deliveries.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'and ${deliveries.length - 5} more.',
                style: context.text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _bill(BuildContext context, UnbilledDelivery delivery) async {
    final posted = await BillDeliveryDialog.show(context, delivery: delivery);
    if (posted && context.mounted) {
      showSuccessSnackBar(
        context,
        'Invoice raised for ${delivery.documentNumber}.',
      );
    }
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(invoiceTotalsProvider).valueOrNull;
    if (totals == null || totals.count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${totals.count} invoice(s)', style: context.text.bodySmall),
          Text('Net ${totals.net.formatted()}', style: context.text.bodySmall),
          if (!totals.discount.isZero)
            Text(
              'Discounts ${totals.discount.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          Text(
            'Gross profit ${totals.grossProfit.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: totals.grossProfit.isNegative
                  ? context.statusColors.danger
                  : context.statusColors.success,
            ),
          ),
          Text(
            'Outstanding ${totals.outstanding.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: totals.outstanding.isPositive
                  ? context.statusColors.danger
                  : null,
            ),
          ),
          if (!totals.pendingCheques.isZero)
            Text(
              'Cheques pending ${totals.pendingCheques.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (totals.cancelledCount > 0)
            Text(
              '${totals.cancelledCount} cancelled',
              style: context.text.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.invoice});

  final InvoiceSummary invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canCancel = user?.can(Permissions.invoiceCancel) ?? false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await showInvoiceDetail(context, ref, invoice.id);
          case 'print':
            await printInvoice(context, ref, invoice.id);
          case 'cancel':
            await confirmAndCancelInvoice(context, ref, invoice);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View invoice')),
        const PopupMenuItem(value: 'print', child: Text('Save as PDF')),
        if (canCancel && invoice.isPosted) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'cancel', child: Text('Cancel invoice')),
        ],
      ],
    );
  }
}
