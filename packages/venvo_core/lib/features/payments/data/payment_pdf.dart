import '../../../core/enums/app_enums.dart';
import '../../../core/services/document_pdf_service.dart';
import '../domain/payment_models.dart';

/// Turns a payment into a printable receipt.
///
/// The wording is deliberately exact about cheques: a receipt for a cheque
/// acknowledges that the cheque was *received*, not that the debt is settled.
/// Handing a customer a receipt that says "paid" for a cheque that later
/// bounces is how disputes start.
PdfDocumentSpec buildReceiptPdfSpec(PaymentSummary payment) {
  final isPendingCheque = payment.isCheque && payment.isPending;

  final totals = <PdfTotalLine>[
    PdfTotalLine('Amount', payment.amount, emphasise: true),
    if (!payment.allocated.isZero)
      PdfTotalLine('Applied to invoices', payment.allocated),
    if (payment.unallocated.isPositive)
      PdfTotalLine('Held on account', payment.unallocated),
  ];

  const pendingNote =
      'This acknowledges receipt of the cheque above. The amount is credited '
      'only when the cheque clears.';
  const bouncedNote =
      'This cheque was returned unpaid. The amount is not credited and the '
      'balance it had covered remains owed.';
  const onAccountNote =
      'Received on account. It has not yet been applied to a specific '
      'invoice.';

  final footnotes = <String>[
    if (isPendingCheque) pendingNote,
    if (payment.isBounced) bouncedNote,
    if (payment.isCancelled) 'This receipt has been cancelled.',
    if (payment.invoiceNumbers.isEmpty && payment.isCleared) onAccountNote,
  ];

  return PdfDocumentSpec(
    title: payment.direction == PaymentDirection.inbound
        ? 'Payment receipt'
        : 'Payment voucher',
    documentNumber: payment.receiptNumber,
    documentDate: payment.paymentDate,
    partyBlockTitle: payment.direction == PaymentDirection.inbound
        ? 'Received from'
        : 'Paid to',
    partyName: payment.partyName,
    metaFields: [
      PdfField('Date', DocumentPdfService.formatDate(payment.paymentDate)),
      PdfField('Method', paymentMethodLabel(payment.method)),
      PdfField('Status', paymentStatusLabel(payment.status)),
      if (payment.chequeNumber != null)
        PdfField('Cheque no.', payment.chequeNumber!),
      if (payment.bankName != null) PdfField('Bank', payment.bankName!),
      if (payment.chequeDate != null)
        PdfField(
          'Cheque date',
          DocumentPdfService.formatDate(payment.chequeDate!),
        ),
      if (payment.referenceNumber != null)
        PdfField('Reference', payment.referenceNumber!),
      if (payment.invoiceNumbers.isNotEmpty)
        PdfField('Against', payment.invoiceNumbers.join(', ')),
      PdfField('Recorded by', payment.createdBy),
    ],
    totals: totals,
    watermark: payment.isCancelled
        ? 'CANCELLED'
        : payment.isBounced
        ? 'BOUNCED'
        : isPendingCheque
        ? 'SUBJECT TO CLEARANCE'
        : null,
    footnotes: footnotes,
    showUnitPrices: false,
  );
}
