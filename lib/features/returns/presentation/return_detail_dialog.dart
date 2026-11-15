import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'inspection_dialog.dart';
import 'return_providers.dart';

/// Shows one return: what came back, what was decided about it, and what
/// credit has been raised.
Future<void> showReturnDetail(
  BuildContext context,
  WidgetRef ref,
  int returnId,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _ReturnDetailDialog(returnId: returnId),
  );
}

class _ReturnDetailDialog extends ConsumerWidget {
  const _ReturnDetailDialog({required this.returnId});

  final int returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(returnDetailProvider(returnId));

    return Dialog(
      child: SizedBox(
        width: 860,
        child: AsyncValueView<ReturnDetail>(
          value: detail,
          onRetry: () => ref.invalidate(returnDetailProvider(returnId)),
          builder: (context, data) => _Body(detail: data),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final summary = detail.summary;

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
                    Text(summary.returnNumber, style: context.text.titleLarge),
                    Text(
                      '${returnRouteLabel(summary.route)} · '
                      '${DateFormat('d MMM yyyy').format(summary.returnDate.toLocal())} · '
                      'recorded by ${summary.createdBy}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                returnStatusLabel(summary.status),
                tone: switch (summary.status) {
                  ReturnStatus.cancelled => StatusTone.danger,
                  ReturnStatus.posted => StatusTone.warning,
                  ReturnStatus.completed => StatusTone.success,
                  _ => StatusTone.info,
                },
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          AppSpacing.gapLg,
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Facts(detail: detail),
                  AppSpacing.gapLg,
                  _Lines(detail: detail),
                  if (detail.creditNotes.isNotEmpty) ...[
                    AppSpacing.gapLg,
                    _CreditNotes(notes: detail.creditNotes),
                  ],
                  if (detail.notes != null) ...[
                    AppSpacing.gapLg,
                    SectionCard(
                      title: 'Notes',
                      child: Text(
                        detail.notes!,
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ],
                  if (detail.cancelReason != null) ...[
                    AppSpacing.gapLg,
                    SectionCard(
                      title: 'Why it was cancelled',
                      leading: Icon(
                        Icons.cancel_outlined,
                        color: context.statusColors.danger,
                      ),
                      child: Text(
                        detail.cancelReason!,
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AppSpacing.gapLg,
          Row(
            children: [
              if (summary.awaitsInspection &&
                  (user?.can(Permissions.returnInspect) ?? false))
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await showInspectionDialog(context, ref, summary);
                  },
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Inspect goods'),
                ),
              if (detail.canIssueCredit &&
                  (user?.can(Permissions.creditNoteIssue) ?? false))
                FilledButton.icon(
                  onPressed: () => _issueCredit(context, ref),
                  icon: const Icon(Icons.request_quote_outlined, size: 18),
                  label: Text(
                    'Issue credit ${detail.uncreditedValue.formatted()}',
                  ),
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

  Future<void> _issueCredit(BuildContext context, WidgetRef ref) async {
    final issued = await showCreditNoteDialog(context, ref, detail);
    if (issued && context.mounted) {
      showSuccessSnackBar(context, 'Credit note issued.');
    }
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;

    Widget fact(String label, String value) => SizedBox(
      width: 240,
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

    return SectionCard(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          fact('Came from', summary.fromLocationName),
          fact('Goes to', summary.toLocationName),
          fact('Reason', returnReasonLabel(summary.reason)),
          if (summary.reasonNote != null)
            fact('Reason note', summary.reasonNote!),
          fact(
            'Original invoice',
            summary.originInvoiceNumber ?? 'not traced to one',
          ),
          fact('Units', '${summary.totalQuantity}'),
          fact('Returned value', summary.totalValue.formatted()),
          fact(
            'Creditable',
            summary.isInspected
                ? detail.creditableValue.formatted()
                : 'after inspection',
          ),
          fact('Credited so far', summary.creditedValue.formatted()),
          if (detail.receiptDocumentNumber != null)
            fact('Receipt movement', detail.receiptDocumentNumber!),
          if (detail.dispositionDocumentNumber != null)
            fact('Disposition movement', detail.dispositionDocumentNumber!),
          if (detail.authorisedBy != null)
            fact('Authorised by', detail.authorisedBy!),
        ],
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.detail});

  final ReturnDetail detail;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '${detail.lines.length} line(s)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in detail.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.productName,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${line.sku} · ${line.quantity} unit(s) at '
                          '${line.unitPrice.formatted()} = '
                          '${line.lineValue.formatted()}',
                          style: context.text.bodySmall,
                        ),
                        if (line.inspectionNote != null)
                          Text(
                            line.inspectionNote!,
                            style: context.text.bodySmall?.copyWith(
                              color: context.statusColors.warning,
                            ),
                          ),
                        if (line.inspectedBy != null)
                          Text(
                            'Inspected by ${line.inspectedBy}'
                            '${line.inspectedAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(line.inspectedAt!.toLocal())}'}',
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AppSpacing.hGapMd,
                  if (line.isPending)
                    const StatusPill(
                      'Awaiting inspection',
                      tone: StatusTone.warning,
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        if (line.acceptedQuantity > 0)
                          StatusPill(
                            '${line.acceptedQuantity} accepted',
                            tone: StatusTone.success,
                          ),
                        if (line.damagedQuantity > 0)
                          StatusPill(
                            '${line.damagedQuantity} damaged',
                            tone: StatusTone.warning,
                          ),
                        if (line.scrappedQuantity > 0)
                          StatusPill(
                            '${line.scrappedQuantity} scrapped',
                            tone: StatusTone.danger,
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CreditNotes extends StatelessWidget {
  const _CreditNotes({required this.notes});

  final List<CreditNoteSummary> notes;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Credit raised against this return',
      subtitle:
          'A credit note reduces what the party owes. The original invoice is '
          'never changed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      note.creditNoteNumber,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${note.amount.formatted()} · '
                      '${note.applied.isZero ? 'not yet applied' : '${note.applied.formatted()} applied'}',
                      style: context.text.bodySmall,
                    ),
                  ),
                  StatusPill(
                    note.isCancelled
                        ? 'Cancelled'
                        : note.isFullyApplied
                        ? 'Used in full'
                        : '${note.remaining.formatted()} left',
                    tone: note.isCancelled
                        ? StatusTone.danger
                        : note.isFullyApplied
                        ? StatusTone.neutral
                        : StatusTone.info,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks how much to credit, then issues the note.
///
/// It is capped at what the inspection accepted, so the amount offered is
/// never more than the goods that actually came back.
Future<bool> showCreditNoteDialog(
  BuildContext context,
  WidgetRef ref,
  ReturnDetail detail,
) async {
  final amountController = TextEditingController(
    text: (detail.uncreditedValue.cents / Money.minorPerMajor).toStringAsFixed(
      2,
    ),
  );
  final reasonController = TextEditingController();

  final issued = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppFormDialog(
      title: 'Credit note for ${detail.summary.returnNumber}',
      subtitle:
          'Up to ${detail.uncreditedValue.formatted()} can be credited: what '
          'the inspection accepted or sent to quarantine, less anything '
          'already credited. Scrapped goods are written off, not credited.',
      submitLabel: 'Issue the credit note',
      onSubmit: () async {
        final amount = Money.tryParse(amountController.text);
        if (amount == null || !amount.isPositive) {
          throw const FormatException('Enter the amount to credit.');
        }
        await ref
            .read(returnServiceProvider)
            .issueCreditNote(
              ref.read(requireCurrentUserProvider),
              returnId: detail.summary.id,
              amount: amount,
              reason: reasonController.text,
            );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppMoneyField(
            controller: amountController,
            label: 'Amount',
            isRequired: true,
            allowZero: false,
            autofocus: true,
          ),
          AppSpacing.gapLg,
          AppTextField(
            controller: reasonController,
            label: 'Reason',
            maxLength: 300,
            helperText: 'Defaults to a reference to the return if left blank.',
          ),
        ],
      ),
    ),
  );

  amountController.dispose();
  reasonController.dispose();
  return issued ?? false;
}
