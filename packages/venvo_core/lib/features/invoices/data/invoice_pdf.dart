import '../../../core/enums/app_enums.dart';
import '../../../core/services/document_pdf_service.dart';
import '../domain/invoice_models.dart';

/// Turns an invoice into something printable.
///
/// Everything printed comes from what was stored when the invoice was posted -
/// the snapshotted product names, the prices charged and the discounts as they
/// were entered - so a reprint years later is the document the customer
/// actually received, not a re-derivation from today's prices.
PdfDocumentSpec buildInvoicePdfSpec(InvoiceDetail detail) {
  final summary = detail.summary;

  final totals = <PdfTotalLine>[
    PdfTotalLine('Gross', summary.gross),
    if (!summary.itemDiscount.isZero)
      PdfTotalLine('Line discounts', -summary.itemDiscount),
    if (!summary.invoiceDiscount.isZero)
      PdfTotalLine('Invoice discount', -summary.invoiceDiscount),
    PdfTotalLine('Net payable', summary.net, emphasise: true),
    if (!summary.settled.isZero) PdfTotalLine('Received', -summary.settled),
    if (!summary.creditApplied.isZero)
      PdfTotalLine('Credit applied', -summary.creditApplied),
    if (!summary.settled.isZero || !summary.creditApplied.isZero)
      PdfTotalLine('Outstanding', summary.outstanding, emphasise: true),
  ];

  final pendingChequeNote =
      'Cheques totalling ${summary.pendingCheques.formatted()} have been '
      'received and are awaiting clearance. They are not included in the '
      'amount received above.';
  const retailSaleNote =
      'Retail sale recorded at the shop. This is separate from the wholesale '
      'supply that stocked it.';

  final footnotes = <String>[
    if (summary.hasPendingCheques) pendingChequeNote,
    if (summary.hasPendingCheques) DocumentPdfService.pendingChequeFootnote,
    if (summary.discountReason != null)
      'Discount reason: ${summary.discountReason}',
    if (summary.kind == InvoiceKind.retailSale) retailSaleNote,
  ];

  return PdfDocumentSpec(
    title: switch (summary.kind) {
      InvoiceKind.agentInvoice => 'Agent invoice',
      InvoiceKind.shopInvoice => 'Invoice',
      InvoiceKind.retailSale => 'Sales receipt',
    },
    documentNumber: summary.invoiceNumber,
    documentDate: summary.invoiceDate,
    partyBlockTitle: 'Billed to',
    partyName: summary.partyName,
    partyFields: [
      if (detail.partyAddress != null)
        PdfField('Address', detail.partyAddress!),
      if (detail.partyPhone != null) PdfField('Phone', detail.partyPhone!),
    ],
    metaFields: [
      PdfField('Date', DocumentPdfService.formatDate(summary.invoiceDate)),
      if (summary.dueDate != null)
        PdfField('Due', DocumentPdfService.formatDate(summary.dueDate!)),
      if (summary.agentName != null && summary.kind != InvoiceKind.agentInvoice)
        PdfField('Agent', summary.agentName!),
      if (summary.stockDocumentNumber != null)
        PdfField('Delivery', summary.stockDocumentNumber!),
      PdfField('Raised by', summary.createdBy),
      PdfField('Status', settlementLabel(summary.settlementStatus)),
    ],
    lines: detail.lines
        .map(
          (line) => PdfDocumentLine(
            description: line.productName,
            reference: line.sku,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            lineTotal: line.net,
            discountLabel: line.discount.isZero ? null : line.discountLabel,
          ),
        )
        .toList(growable: false),
    totals: totals,
    notes: detail.notes,
    watermark: summary.isCancelled ? 'CANCELLED' : null,
    footnotes: footnotes,
  );
}
