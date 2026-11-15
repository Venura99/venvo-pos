import '../../../core/services/document_pdf_service.dart';
import '../domain/stock_models.dart';

/// Turns a stock document into a printable delivery note.
///
/// A delivery note records goods moved. It carries prices when the document
/// did, because the agent receiving the goods needs to see what they are
/// expected to be billed - but it says plainly that it is not an invoice, so
/// nobody treats it as one.
PdfDocumentSpec buildDeliveryNotePdfSpec(StockDocumentDetail detail) {
  final summary = detail.summary;
  final hasPrices = !summary.total.isZero;

  return PdfDocumentSpec(
    title: 'Delivery note',
    documentNumber: summary.documentNumber,
    documentDate: summary.documentDate,
    partyBlockTitle: 'Deliver to',
    partyName: summary.shopName ?? summary.agentName ?? summary.destinationName,
    partyFields: [PdfField('Destination', summary.destinationName)],
    metaFields: [
      PdfField('Date', DocumentPdfService.formatDate(summary.documentDate)),
      PdfField('Movement', stockDocumentTypeLabel(summary.documentType)),
      PdfField('From', summary.sourceName),
      if (summary.referenceNote != null)
        PdfField('Reference', summary.referenceNote!),
      PdfField('Raised by', summary.createdBy),
      PdfField('Units', '${summary.totalQuantity}'),
    ],
    lines: detail.lines
        .map(
          (line) => PdfDocumentLine(
            description: line.productName,
            reference: line.sku,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            lineTotal: line.lineTotal,
            discountLabel: line.discount.isZero ? null : line.discount.plain,
          ),
        )
        .toList(growable: false),
    totals: hasPrices
        ? [PdfTotalLine('Goods value', summary.total, emphasise: true)]
        : const [],
    notes: detail.notes,
    watermark: summary.isCancelled ? 'CANCELLED' : null,
    footnotes: [
      DocumentPdfService.deliveryNoteFootnote,
      if (hasPrices) _indicativeValueNote,
      if (summary.reversesDocumentNumber != null)
        'This document reverses ${summary.reversesDocumentNumber}.',
      if (summary.reversedByDocumentNumber != null)
        'This document has been reversed by ${summary.reversedByDocumentNumber}.',
    ],
    showUnitPrices: hasPrices,
  );
}

/// Printed when a delivery note carries prices, so nobody mistakes it for the
/// document that creates the amount payable.
const String _indicativeValueNote =
    'Values shown are indicative. The invoice, when raised, is the document '
    'that creates the amount payable.';
