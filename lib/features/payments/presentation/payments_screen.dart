import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/data/payment_pdf.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../../../core/services/file_delivery.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import '../../invoices/presentation/invoice_providers.dart';
import 'payment_form.dart';
import 'payment_providers.dart';

/// Collections and payments made, with what each one was applied to.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.paymentView) ?? false)) {
      return const PageScaffold(
        title: 'Payments',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to payments',
        ),
      );
    }

    final canRecord = user?.can(Permissions.paymentRecord) ?? false;
    final payments = ref.watch(paymentsProvider);
    final filter = ref.watch(paymentFilterProvider);

    return PageScaffold(
      title: 'Payments',
      description:
          'Money received and paid out. A cheque appears here as soon as it '
          'is taken, but counts as settled only once it clears.',
      scrollable: false,
      actions: [
        if (canRecord)
          FilledButton.icon(
            onPressed: () => _record(context),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Record a payment'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(filter: filter),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<PaymentSummary>>(
              value: payments,
              builder: (context, rows) => SectionCard(
                padding: EdgeInsets.zero,
                fillHeight: true,
                child: AppDataTable<PaymentSummary>(
                  rows: rows,
                  minWidth: 1180,
                  empty: EmptyState(
                    icon: Icons.payments_outlined,
                    title: filter.hasAnyFilter
                        ? 'No payments match these filters'
                        : 'No payments yet',
                    message: filter.hasAnyFilter
                        ? null
                        : 'Record a collection against an invoice, or on '
                              'account for later.',
                  ),
                  columns: [
                    AppTableColumn<PaymentSummary>(
                      label: 'Receipt',
                      width: 160,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.receiptNumber,
                        secondary: paymentMethodLabel(row.method),
                      ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Date',
                      width: 110,
                      cell: (context, row) => TableTextCell(
                        DateFormat(
                          'd MMM yyyy',
                        ).format(row.paymentDate.toLocal()),
                      ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Party',
                      flex: 3,
                      cell: (context, row) => TableTwoLineCell(
                        primary: row.partyName,
                        secondary: row.chequeNumber == null
                            ? (row.referenceNumber ?? '—')
                            : 'cheque ${row.chequeNumber}'
                                  '${row.bankName == null ? '' : ' · ${row.bankName}'}',
                      ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Applied to',
                      flex: 3,
                      cell: (context, row) => row.invoiceNumbers.isEmpty
                          ? const StatusPill(
                              'On account',
                              tone: StatusTone.info,
                            )
                          : TableTextCell(
                              row.invoiceNumbers.join(', '),
                              muted: true,
                            ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Amount',
                      width: 120,
                      numeric: true,
                      cell: (context, row) => Text(
                        row.amount.plain,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: row.isCancelled || row.isBounced
                              ? TextDecoration.lineThrough
                              : null,
                          color: row.direction == PaymentDirection.outbound
                              ? context.statusColors.danger
                              : null,
                        ),
                      ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Unapplied',
                      width: 110,
                      numeric: true,
                      tooltip:
                          'Money received and not yet put against an '
                          'invoice',
                      cell: (context, row) => TableTextCell(
                        row.unallocated.isZero ? '—' : row.unallocated.plain,
                        muted: row.unallocated.isZero,
                      ),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: 'Status',
                      width: 130,
                      cell: (context, row) => _StatusCell(payment: row),
                    ),
                    AppTableColumn<PaymentSummary>(
                      label: '',
                      width: 56,
                      cell: (context, row) => _RowMenu(payment: row),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppSpacing.gapSm,
          const _SummaryBar(),
        ],
      ),
    );
  }

  Future<void> _record(BuildContext context) async {
    final recorded = await PaymentFormDialog.show(context);
    if (recorded && context.mounted) {
      showSuccessSnackBar(context, 'Payment recorded.');
    }
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.payment});

  final PaymentSummary payment;

  @override
  Widget build(BuildContext context) {
    if (payment.isCancelled) {
      return const StatusPill('Cancelled', tone: StatusTone.neutral);
    }
    if (payment.isBounced) {
      return const StatusPill('Bounced', tone: StatusTone.danger);
    }
    if (payment.isPending) {
      return const Tooltip(
        message:
            'Received but not cleared. It does not reduce any balance yet.',
        child: StatusPill('Pending', tone: StatusTone.warning),
      );
    }
    return const StatusPill('Cleared', tone: StatusTone.success);
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});

  final PaymentFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(paymentFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search receipt, cheque, reference or party',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<PaymentMethod?>(
            initialValue: filter.method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Method'),
            items: [
              const DropdownMenuItem<PaymentMethod?>(
                child: Text('All methods'),
              ),
              for (final method in PaymentMethod.values)
                DropdownMenuItem<PaymentMethod?>(
                  value: method,
                  child: Text(paymentMethodLabel(method)),
                ),
            ],
            onChanged: (value) => notifier.update(
              (state) => value == null
                  ? state.copyWith(clearMethod: true)
                  : state.copyWith(method: value),
            ),
          ),
        ),
        SizedBox(
          width: 165,
          child: DropdownButtonFormField<PaymentStatus?>(
            initialValue: filter.status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              const DropdownMenuItem<PaymentStatus?>(child: Text('Any')),
              for (final status in PaymentStatus.values)
                DropdownMenuItem<PaymentStatus?>(
                  value: status,
                  child: Text(paymentStatusLabel(status)),
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
          selected: filter.advancesOnly,
          label: const Text('On account only'),
          onSelected: (value) =>
              notifier.update((state) => state.copyWith(advancesOnly: value)),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const PaymentFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(paymentTotalsProvider).valueOrNull;
    if (totals == null || totals.count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${totals.count} payment(s)', style: context.text.bodySmall),
          Text(
            'Received (cleared) ${totals.clearedIn.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: context.statusColors.success,
            ),
          ),
          if (!totals.clearedOut.isZero)
            Text(
              'Paid out ${totals.clearedOut.formatted()}',
              style: context.text.bodySmall,
            ),
          if (!totals.pending.isZero)
            Text(
              'Pending clearance ${totals.pending.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          if (!totals.bounced.isZero)
            Text(
              'Bounced ${totals.bounced.formatted()}',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.danger,
              ),
            ),
          if (!totals.advances.isZero)
            Text(
              'Held on account ${totals.advances.formatted()}',
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
  const _RowMenu({required this.payment});

  final PaymentSummary payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canAllocate = user?.can(Permissions.paymentAllocate) ?? false;
    final canCancel = user?.can(Permissions.paymentCancel) ?? false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'receipt':
            await _printReceipt(context, ref);
          case 'allocate':
            await _allocateRemainder(context, ref);
          case 'cancel':
            await _cancel(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'receipt', child: Text('Save receipt PDF')),
        if (canAllocate && payment.isCleared && payment.unallocated.isPositive)
          const PopupMenuItem(
            value: 'allocate',
            child: Text('Apply to invoices'),
          ),
        if (canCancel && !payment.isCancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'cancel', child: Text('Cancel payment')),
        ],
      ],
    );
  }

  Future<void> _printReceipt(BuildContext context, WidgetRef ref) async {
    try {
      final pdf = await ref.read(documentPdfServiceProvider.future);
      final bytes = await pdf.build(buildReceiptPdfSpec(payment));
      await FileDelivery.printPdf(
        bytes: bytes,
        documentName: payment.receiptNumber,
      );
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }

  Future<void> _allocateRemainder(BuildContext context, WidgetRef ref) async {
    final selection = PaymentPartySelection(
      agentId: payment.agentId,
      shopId: payment.shopId,
    );
    final invoices = await ref.read(
      allocatableInvoicesProvider(selection).future,
    );
    if (!context.mounted) return;

    if (invoices.isEmpty) {
      showSuccessSnackBar(
        context,
        '${payment.partyName} has nothing outstanding to apply this to.',
      );
      return;
    }

    final controllers = <int, TextEditingController>{
      for (final invoice in invoices)
        invoice.invoiceId: TextEditingController(),
    };

    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: 'Apply ${payment.receiptNumber}',
        subtitle:
            '${payment.unallocated.formatted()} of this payment is unapplied.',
        submitLabel: 'Apply',
        width: 640,
        onSubmit: () {
          final allocations = <PaymentAllocationRequest>[];
          for (final entry in controllers.entries) {
            final value = Money.tryParse(entry.value.text);
            if (value == null || !value.isPositive) continue;
            allocations.add(
              PaymentAllocationRequest(invoiceId: entry.key, amount: value),
            );
          }
          return ref
              .read(paymentServiceProvider)
              .allocate(
                ref.read(requireCurrentUserProvider),
                paymentId: payment.id,
                allocations: allocations,
              );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final invoice in invoices)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            invoice.invoiceNumber,
                            style: context.text.bodyMedium,
                          ),
                          Text(
                            'Can apply up to '
                            '${invoice.allocatable.formatted()}',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: AppMoneyField(
                        controller: controllers[invoice.invoiceId]!,
                        label: 'Apply',
                        validator: (value) => value > invoice.allocatable
                            ? 'At most ${invoice.allocatable.plain}'
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    if ((applied ?? false) && context.mounted) {
      showSuccessSnackBar(context, 'Payment applied.');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();

    final cancelled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: 'Cancel ${payment.receiptNumber}?',
        subtitle:
            'The payment stays on record. Because every balance counts '
            'cleared payments only, cancelling it restores whatever it had '
            'settled.',
        submitLabel: 'Cancel the payment',
        width: 520,
        onSubmit: () => ref
            .read(paymentServiceProvider)
            .cancelPayment(
              ref.read(requireCurrentUserProvider),
              paymentId: payment.id,
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
      showSuccessSnackBar(context, 'Payment cancelled.');
    }
  }
}
