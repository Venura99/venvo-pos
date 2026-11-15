import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
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
import '../../payments/presentation/payment_providers.dart';
import 'return_providers.dart';

/// The credit note register.
///
/// A credit note is money the business owes back. It is applied to invoices
/// the same way a payment is allocated, so credit never disappears into a
/// balance: whatever has not been applied is still owed to the party, and that
/// is the number this screen leads with.
class CreditNotesScreen extends ConsumerWidget {
  const CreditNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.returnView) ?? false)) {
      return const PageScaffold(
        title: 'Credit Notes',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to credit notes',
        ),
      );
    }

    return const PageScaffold(
      title: 'Credit Notes',
      description:
          'Credit raised when goods came back. Applying a credit note to an '
          'invoice reduces what is owed; the invoice itself is never altered. '
          'A credit note is only ever issued against an inspected return.',
      scrollable: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(),
          AppSpacing.gapLg,
          Expanded(child: _CreditNoteTable()),
          AppSpacing.gapSm,
          _SummaryBar(),
        ],
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(creditNoteFilterProvider);
    final notifier = ref.read(creditNoteFilterProvider.notifier);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppSearchField(
          hintText: 'Search number, return, invoice or party',
          width: 320,
          onChanged: (value) =>
              notifier.update((state) => state.copyWith(search: value)),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<InvoiceStatus?>(
            initialValue: filter.status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem<InvoiceStatus?>(child: Text('Any status')),
              DropdownMenuItem<InvoiceStatus?>(
                value: InvoiceStatus.posted,
                child: Text('Posted'),
              ),
              DropdownMenuItem<InvoiceStatus?>(
                value: InvoiceStatus.cancelled,
                child: Text('Cancelled'),
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
          selected: filter.withRemainingOnly,
          label: const Text('Still has credit left'),
          avatar: const Icon(Icons.savings_outlined, size: 16),
          onSelected: (value) => notifier.update(
            (state) => state.copyWith(withRemainingOnly: value),
          ),
        ),
        if (filter.hasAnyFilter)
          TextButton.icon(
            onPressed: () => notifier.state = const CreditNoteFilter(),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
            label: const Text('Clear filters'),
          ),
      ],
    );
  }
}

class _CreditNoteTable extends ConsumerWidget {
  const _CreditNoteTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(creditNotesProvider);
    final filter = ref.watch(creditNoteFilterProvider);

    return AsyncValueView<List<CreditNoteSummary>>(
      value: notes,
      builder: (context, rows) => SectionCard(
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<CreditNoteSummary>(
          rows: rows,
          minWidth: 1180,
          onRowTap: (row) => showCreditNoteDetail(context, ref, row.id),
          empty: EmptyState(
            icon: Icons.request_quote_outlined,
            title: filter.hasAnyFilter
                ? 'No credit notes match these filters'
                : 'No credit notes yet',
            message: filter.hasAnyFilter
                ? null
                : 'A credit note is issued from an inspected return.',
          ),
          columns: [
            AppTableColumn<CreditNoteSummary>(
              label: 'Credit note',
              width: 160,
              cell: (context, row) => TableTwoLineCell(
                primary: row.creditNoteNumber,
                secondary: row.returnNumber ?? 'no return',
              ),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Date',
              width: 110,
              cell: (context, row) => TableTextCell(
                DateFormat('d MMM yyyy').format(row.issueDate.toLocal()),
              ),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Owed to',
              flex: 3,
              cell: (context, row) => TableTwoLineCell(
                primary: row.partyName,
                secondary: row.originInvoiceNumber == null
                    ? row.partyType.name
                    : 'against ${row.originInvoiceNumber}',
              ),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Amount',
              width: 120,
              numeric: true,
              cell: (context, row) => TableTextCell(row.amount.plain),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Applied',
              width: 120,
              numeric: true,
              cell: (context, row) =>
                  TableTextCell(row.applied.isZero ? '—' : row.applied.plain),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Left',
              width: 120,
              numeric: true,
              cell: (context, row) => Text(
                row.remaining.plain,
                textAlign: TextAlign.right,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: row.remaining.isPositive
                      ? context.statusColors.info
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: 'Status',
              width: 130,
              cell: (context, row) => StatusPill(
                row.isCancelled
                    ? 'Cancelled'
                    : row.isFullyApplied
                    ? 'Used in full'
                    : row.applied.isZero
                    ? 'Unapplied'
                    : 'Part applied',
                tone: row.isCancelled
                    ? StatusTone.danger
                    : row.isFullyApplied
                    ? StatusTone.success
                    : StatusTone.info,
              ),
            ),
            AppTableColumn<CreditNoteSummary>(
              label: '',
              width: 56,
              cell: (context, row) => _RowMenu(note: row),
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
    final rows = ref.watch(creditNotesProvider).valueOrNull;
    if (rows == null || rows.isEmpty) return const SizedBox.shrink();

    final live = rows.where((row) => row.isPosted).toList();
    final issued = live.map((row) => row.amount).sum;
    final applied = live.map((row) => row.applied).sum;
    final remaining = live.map((row) => row.remaining).sum;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.xs,
        children: [
          Text('${live.length} posted', style: context.text.bodySmall),
          Text('Issued ${issued.formatted()}', style: context.text.bodySmall),
          Text('Applied ${applied.formatted()}', style: context.text.bodySmall),
          Text(
            'Still owed to parties ${remaining.formatted()}',
            style: context.text.bodySmall?.copyWith(
              color: remaining.isPositive ? context.statusColors.info : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.note});

  final CreditNoteSummary note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canIssue =
        ref.watch(currentUserProvider)?.can(Permissions.creditNoteIssue) ??
        false;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            await showCreditNoteDetail(context, ref, note.id);
          case 'apply':
            await showApplyCreditDialog(context, ref, note);
          case 'cancel':
            await confirmAndCancelCreditNote(context, ref, note);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'view', child: Text('View credit note')),
        if (canIssue && note.isPosted && note.remaining.isPositive)
          const PopupMenuItem(
            value: 'apply',
            child: Text('Apply to an invoice'),
          ),
        if (canIssue && note.canBeCancelled) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'cancel',
            child: Text('Cancel credit note'),
          ),
        ],
      ],
    );
  }
}

/// Shows one credit note and everything it has been used for.
Future<void> showCreditNoteDetail(
  BuildContext context,
  WidgetRef ref,
  int creditNoteId,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 720,
        child: Consumer(
          builder: (context, ref, _) => AsyncValueView<CreditNoteDetail>(
            value: ref.watch(creditNoteDetailProvider(creditNoteId)),
            onRetry: () =>
                ref.invalidate(creditNoteDetailProvider(creditNoteId)),
            builder: (context, detail) => _CreditNoteBody(detail: detail),
          ),
        ),
      ),
    ),
  );
}

class _CreditNoteBody extends ConsumerWidget {
  const _CreditNoteBody({required this.detail});

  final CreditNoteDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = detail.summary;
    final canIssue =
        ref.watch(currentUserProvider)?.can(Permissions.creditNoteIssue) ??
        false;

    return Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.creditNoteNumber, style: context.text.titleLarge),
                    Text(
                      '${note.partyName} · '
                      '${DateFormat('d MMM yyyy').format(note.issueDate.toLocal())} · '
                      'issued by ${note.createdBy}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                note.isCancelled ? 'Cancelled' : 'Posted',
                tone: note.isCancelled ? StatusTone.danger : StatusTone.success,
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          AppSpacing.gapLg,
          SectionCard(
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.md,
              children: [
                _fact(context, 'Amount', note.amount.formatted()),
                _fact(context, 'Applied', note.applied.formatted()),
                _fact(context, 'Left to use', note.remaining.formatted()),
                _fact(context, 'From return', note.returnNumber ?? '—'),
                _fact(
                  context,
                  'Original invoice',
                  note.originInvoiceNumber ?? '—',
                ),
                if (note.reason != null) _fact(context, 'Reason', note.reason!),
                if (note.cancelReason != null)
                  _fact(context, 'Cancelled because', note.cancelReason!),
              ],
            ),
          ),
          AppSpacing.gapLg,
          Flexible(
            child: SingleChildScrollView(
              child: SectionCard(
                title: 'Where it has been applied',
                subtitle:
                    'A withdrawal is recorded as an opposing row rather than '
                    'a deletion, so the trail stays intact.',
                child: detail.applications.isEmpty
                    ? Text(
                        'Not applied to anything yet. The party is holding '
                        '${note.remaining.formatted()} of credit.',
                        style: context.text.bodyMedium,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final row in detail.applications)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 150,
                                    child: Text(
                                      row.invoiceNumber,
                                      style: context.text.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${DateFormat('d MMM yyyy, HH:mm').format(row.appliedAt.toLocal())}'
                                      ' · ${row.appliedBy}',
                                      style: context.text.bodySmall,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      row.amount.plain,
                                      textAlign: TextAlign.right,
                                      style: context.text.bodyMedium?.copyWith(
                                        color: row.isWithdrawal
                                            ? context.statusColors.danger
                                            : null,
                                      ),
                                    ),
                                  ),
                                  AppSpacing.hGapMd,
                                  if (canIssue && !row.isWithdrawal)
                                    TextButton(
                                      onPressed: () =>
                                          _withdraw(context, ref, row),
                                      child: const Text('Withdraw'),
                                    )
                                  else
                                    const SizedBox(width: 90),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              if (canIssue && note.isPosted && note.remaining.isPositive)
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await showApplyCreditDialog(context, ref, note);
                  },
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: const Text('Apply to an invoice'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    CreditNoteApplicationView row,
  ) async {
    final reasonController = TextEditingController();

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: 'Withdraw ${row.amount.formatted()} from ${row.invoiceNumber}?',
        subtitle:
            'The invoice goes back to owing that much, and the credit returns '
            'to the party. The original application stays on the record.',
        submitLabel: 'Withdraw it',
        onSubmit: () => ref
            .read(returnServiceProvider)
            .withdrawApplication(
              ref.read(requireCurrentUserProvider),
              applicationId: row.id,
              reason: reasonController.text,
            ),
        child: AppTextField(
          controller: reasonController,
          label: 'Reason',
          isRequired: true,
          autofocus: true,
          maxLength: 300,
        ),
      ),
    );

    reasonController.dispose();
    if ((done ?? false) && context.mounted) {
      showSuccessSnackBar(
        context,
        'Credit withdrawn from ${row.invoiceNumber}.',
      );
    }
  }

  static Widget _fact(BuildContext context, String label, String value) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Text(value, style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

/// Offsets a credit note against one of the party's posted invoices.
Future<void> showApplyCreditDialog(
  BuildContext context,
  WidgetRef ref,
  CreditNoteSummary note,
) async {
  final amountController = TextEditingController();
  int? invoiceId;

  final applied = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AppFormDialog(
          title: 'Apply ${note.creditNoteNumber}',
          subtitle:
              '${note.remaining.formatted()} of credit is left on this note. '
              'An invoice can only take what is not already claimed by a '
              'payment or a cheque in clearing.',
          submitLabel: 'Apply the credit',
          onSubmit: () async {
            final chosen = invoiceId;
            if (chosen == null) {
              throw const FormatException('Choose an invoice to apply it to.');
            }
            final amount = Money.tryParse(amountController.text);
            if (amount == null || !amount.isPositive) {
              throw const FormatException('Enter the amount to apply.');
            }
            await ref
                .read(returnServiceProvider)
                .applyToInvoice(
                  ref.read(requireCurrentUserProvider),
                  creditNoteId: note.id,
                  invoiceId: chosen,
                  amount: amount,
                );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InvoiceChoices(
                note: note,
                selected: invoiceId,
                onChanged: (value, suggested) => setState(() {
                  invoiceId = value;
                  if (suggested != null) {
                    amountController.text =
                        (suggested.cents / Money.minorPerMajor).toStringAsFixed(
                          2,
                        );
                  }
                }),
              ),
              AppSpacing.gapLg,
              AppMoneyField(
                controller: amountController,
                label: 'Amount to apply',
                isRequired: true,
                allowZero: false,
              ),
            ],
          ),
        );
      },
    ),
  );

  amountController.dispose();
  if ((applied ?? false) && context.mounted) {
    showSuccessSnackBar(context, '${note.creditNoteNumber} applied.');
  }
}

/// The party's invoices that still have room for credit.
class _InvoiceChoices extends ConsumerWidget {
  const _InvoiceChoices({
    required this.note,
    required this.selected,
    required this.onChanged,
  });

  final CreditNoteSummary note;
  final int? selected;
  final void Function(int? invoiceId, Money? suggestedAmount) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrowed to whichever party actually owns the balance. A shop's note
    // carries its agent's id too, and filtering on both would miss invoices
    // raised before the shop was reassigned.
    final selection = note.partyType == PartyType.shop
        ? PaymentPartySelection(shopId: note.shopId)
        : PaymentPartySelection(agentId: note.agentId);

    final invoices = ref
        .watch(allocatableInvoicesProvider(selection))
        .valueOrNull;
    if (invoices == null) return const LinearProgressIndicator(minHeight: 2);

    final rows = invoices
        .where((invoice) => invoice.allocatable.isPositive)
        .toList();
    if (rows.isEmpty) {
      return Text(
        'This party has no invoice with room left on it. The credit stays in '
        'hand until one is raised.',
        style: context.text.bodySmall,
      );
    }

    return AppDropdownField<int>(
      label: 'Invoice',
      isRequired: true,
      value: selected,
      items: [
        for (final invoice in rows)
          DropdownMenuItem(
            value: invoice.invoiceId,
            child: Text(
              '${invoice.invoiceNumber} · '
              '${invoice.allocatable.formatted()} can still be applied',
            ),
          ),
      ],
      onChanged: (value) {
        final invoice = rows.where((r) => r.invoiceId == value).firstOrNull;
        final room = invoice?.allocatable;
        final suggested = room == null
            ? null
            : (room < note.remaining ? room : note.remaining);
        onChanged(value, suggested);
      },
    );
  }
}

/// Withdraws a credit note that has not been used.
Future<void> confirmAndCancelCreditNote(
  BuildContext context,
  WidgetRef ref,
  CreditNoteSummary note,
) async {
  final reasonController = TextEditingController();

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Cancel ${note.creditNoteNumber}?',
      subtitle:
          'The note is kept and marked cancelled, and the return it came from '
          'becomes creditable again.',
      submitLabel: 'Cancel the credit note',
      onSubmit: () => ref
          .read(returnServiceProvider)
          .cancelCreditNote(
            ref.read(requireCurrentUserProvider),
            creditNoteId: note.id,
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
    showSuccessSnackBar(context, '${note.creditNoteNumber} cancelled.');
  }
}
