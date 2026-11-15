import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/invoices/data/invoice_pdf.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../../../core/services/file_delivery.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'invoice_providers.dart';

/// Shows an invoice: its lines, its discounts and every payment against it.
Future<void> showInvoiceDetail(
  BuildContext context,
  WidgetRef ref,
  int invoiceId,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, child) {
        final detail = ref.watch(invoiceDetailProvider(invoiceId));

        return AlertDialog(
          title: const Text('Invoice'),
          content: SizedBox(
            width: 820,
            child: AsyncValueView<InvoiceDetail>(
              value: detail,
              builder: (context, data) => _InvoiceView(detail: data),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => printInvoice(context, ref, invoiceId),
              child: const Text('Save as PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );
}

/// Renders the invoice to a PDF and sends it to the print dialog, which also
/// offers to save a copy.
Future<void> printInvoice(
  BuildContext context,
  WidgetRef ref,
  int invoiceId,
) async {
  try {
    final detail = await ref.read(invoiceDetailProvider(invoiceId).future);
    final pdf = await ref.read(documentPdfServiceProvider.future);
    final bytes = await pdf.build(buildInvoicePdfSpec(detail));
    await FileDelivery.printPdf(
      bytes: bytes,
      documentName: detail.summary.invoiceNumber,
    );
  } catch (error) {
    if (context.mounted) showFailureSnackBar(context, error);
  }
}

/// Confirms, then cancels an invoice.
Future<void> confirmAndCancelInvoice(
  BuildContext context,
  WidgetRef ref,
  InvoiceSummary invoice,
) async {
  final reasonController = TextEditingController();
  var reverseStock = invoice.stockTransactionId != null;

  final cancelled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AppFormDialog(
        title: 'Cancel ${invoice.invoiceNumber}?',
        subtitle:
            'The invoice and its lines are kept exactly as they are; only its '
            'status changes.',
        submitLabel: 'Cancel the invoice',
        width: 560,
        onSubmit: () => ref
            .read(invoiceServiceProvider)
            .cancelInvoice(
              ref.read(requireCurrentUserProvider),
              invoiceId: invoice.id,
              reason: reasonController.text,
              reverseStockMovement: reverseStock,
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: reasonController,
              label: 'Reason',
              isRequired: true,
              autofocus: true,
              maxLines: 2,
              maxLength: 500,
            ),
            if (invoice.stockTransactionId != null) ...[
              AppSpacing.gapLg,
              SwitchListTile(
                value: reverseStock,
                onChanged: (value) => setState(() => reverseStock = value),
                title: const Text('Also put the goods back'),
                subtitle: const Text(
                  'Posts a reversing stock document. Leave this off if the '
                  'goods stayed with the customer and only the bill was '
                  'wrong.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (!invoice.settled.isZero) ...[
              AppSpacing.gapLg,
              _Note(
                tone: _NoteTone.warning,
                message:
                    '${invoice.settled.formatted()} has already been received '
                    'against this invoice. That money is not taken back: it '
                    'becomes an unapplied advance for ${invoice.partyName}.',
              ),
            ],
          ],
        ),
      ),
    ),
  );

  reasonController.dispose();
  if ((cancelled ?? false) && context.mounted) {
    showSuccessSnackBar(context, '${invoice.invoiceNumber} cancelled.');
  }
}

class _InvoiceView extends StatelessWidget {
  const _InvoiceView({required this.detail});

  final InvoiceDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(summary.invoiceNumber, style: context.text.titleLarge),
                    Text(
                      '${invoiceKindLabel(summary.kind)} · '
                      '${DateFormat('d MMM yyyy').format(summary.invoiceDate.toLocal())}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (summary.isCancelled)
                const StatusPill('Cancelled', tone: StatusTone.danger)
              else
                StatusPill.settlement(summary.settlementStatus),
            ],
          ),
          AppSpacing.gapLg,
          _field(context, 'Billed to', summary.partyName),
          if (detail.partyAddress != null)
            _field(context, 'Address', detail.partyAddress!),
          if (detail.partyPhone != null)
            _field(context, 'Phone', detail.partyPhone!),
          if (summary.agentName != null &&
              summary.kind != InvoiceKind.agentInvoice)
            _field(context, 'Agent', summary.agentName!),
          if (summary.dueDate != null)
            _field(
              context,
              'Due',
              DateFormat('d MMM yyyy').format(summary.dueDate!.toLocal()),
            ),
          if (summary.stockDocumentNumber != null)
            _field(context, 'Delivery note', summary.stockDocumentNumber!),
          _field(context, 'Raised by', summary.createdBy),
          if (summary.discountReason != null)
            _field(context, 'Discount reason', summary.discountReason!),
          if (summary.discountApprovedBy != null)
            _field(
              context,
              'Discount authorised by',
              summary.discountApprovedBy!,
            ),
          if (detail.notes != null) _field(context, 'Notes', detail.notes!),
          if (detail.cancelReason != null)
            _field(
              context,
              'Cancellation reason',
              '${detail.cancelReason}'
                  '${detail.cancelledBy == null ? '' : ' (${detail.cancelledBy})'}',
            ),
          AppSpacing.gapLg,
          const Divider(),
          _linesHeader(context),
          const Divider(height: 1),
          for (final line in detail.lines) _lineRow(context, line),
          const Divider(),
          _totals(context, summary),
          if (detail.payments.isNotEmpty) ...[
            AppSpacing.gapXl,
            Text('Payments', style: context.text.titleSmall),
            AppSpacing.gapSm,
            for (final payment in detail.payments)
              _paymentRow(context, payment),
          ],
        ],
      ),
    );
  }

  Widget _linesHeader(BuildContext context) {
    final style = context.text.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: context.colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('PRODUCT', style: style)),
          SizedBox(
            width: 60,
            child: Text('QTY', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 95,
            child: Text('PRICE', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 85,
            child: Text('DISCOUNT', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(
            width: 100,
            child: Text('AMOUNT', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(BuildContext context, InvoiceLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(line.productName, style: context.text.bodyMedium),
                Text(
                  line.returnedQuantity > 0
                      ? '${line.sku} · ${line.returnedQuantity} returned'
                      : line.sku,
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${line.quantity}',
              textAlign: TextAlign.right,
              style: context.text.bodyMedium,
            ),
          ),
          SizedBox(
            width: 95,
            child: Text(
              line.unitPrice.plain,
              textAlign: TextAlign.right,
              style: context.text.bodyMedium,
            ),
          ),
          SizedBox(
            width: 85,
            child: Text(
              line.discount.isZero ? '—' : line.discountLabel,
              textAlign: TextAlign.right,
              style: context.text.bodySmall,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              line.net.plain,
              textAlign: TextAlign.right,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totals(BuildContext context, InvoiceSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _totalLine(context, 'Gross', summary.gross),
        if (!summary.itemDiscount.isZero)
          _totalLine(context, 'Line discounts', -summary.itemDiscount),
        if (!summary.invoiceDiscount.isZero)
          _totalLine(context, 'Invoice discount', -summary.invoiceDiscount),
        _totalLine(context, 'Net payable', summary.net, emphasise: true),
        if (!summary.settled.isZero)
          _totalLine(context, 'Received (cleared)', -summary.settled),
        if (!summary.creditApplied.isZero)
          _totalLine(context, 'Credit applied', -summary.creditApplied),
        if (summary.isPosted)
          _totalLine(
            context,
            'Outstanding',
            summary.outstanding,
            emphasise: true,
          ),
        if (summary.hasPendingCheques)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '${summary.pendingCheques.formatted()} received by cheque and '
              'awaiting clearance. It is not included above and does not '
              'reduce the outstanding balance until it clears.',
              style: context.text.bodySmall?.copyWith(
                color: context.statusColors.warning,
              ),
            ),
          ),
        if (summary.isPosted && !summary.cost.isZero)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Goods cost ${summary.cost.formatted()} · gross profit '
              '${summary.grossProfit.formatted()}',
              style: context.text.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _totalLine(
    BuildContext context,
    String label,
    Money amount, {
    bool emphasise = false,
  }) {
    final style = emphasise ? context.text.titleSmall : context.text.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount.formatted(), style: style),
        ],
      ),
    );
  }

  Widget _paymentRow(BuildContext context, InvoicePaymentLine payment) {
    final tone = payment.isEffective
        ? StatusTone.success
        : payment.status == PaymentStatus.pending
        ? StatusTone.warning
        : StatusTone.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(payment.receiptNumber, style: context.text.bodyMedium),
          ),
          SizedBox(
            width: 110,
            child: Text(
              DateFormat('d MMM yyyy').format(payment.paymentDate.toLocal()),
              style: context.text.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              payment.chequeNumber == null
                  ? paymentMethodLabel(payment.method)
                  : '${paymentMethodLabel(payment.method)} '
                        '${payment.chequeNumber}',
              style: context.text.bodySmall,
            ),
          ),
          StatusPill(paymentStatusLabel(payment.status), tone: tone),
          AppSpacing.hGapMd,
          SizedBox(
            width: 100,
            child: Text(
              payment.allocated.plain,
              textAlign: TextAlign.right,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: payment.isEffective
                    ? null
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 185,
            child: Text(label, style: context.text.bodySmall),
          ),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}

enum _NoteTone { info, warning }

class _Note extends StatelessWidget {
  const _Note({required this.message, this.tone = _NoteTone.info});

  final String message;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final isWarning = tone == _NoteTone.warning;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isWarning ? colors.warningContainer : colors.infoContainer,
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_outlined : Icons.info_outline,
            size: 16,
            color: isWarning
                ? colors.onWarningContainer
                : colors.onInfoContainer,
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: isWarning
                    ? colors.onWarningContainer
                    : colors.onInfoContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
