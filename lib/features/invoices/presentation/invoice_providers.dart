import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/services/document_pdf_service.dart';
import 'package:venvo_core/features/invoices/api/invoice_api.dart';
import 'package:venvo_core/features/invoices/data/invoice_query_repository.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';

import '../../../core/providers/core_providers.dart';

final invoiceServiceProvider = Provider<InvoiceApi>(
  (ref) => InvoiceApi(ref.watch(apiClientProvider)),
);

final invoiceQueryRepositoryProvider = Provider<InvoiceQueryApi>(
  (ref) => InvoiceQueryApi(ref.watch(apiClientProvider)),
);

final invoiceFilterProvider = StateProvider<InvoiceFilter>(
  (ref) => const InvoiceFilter(),
);

final invoicesProvider = StreamProvider<List<InvoiceSummary>>((ref) {
  return ref
      .watch(invoiceQueryRepositoryProvider)
      .watchInvoices(ref.watch(invoiceFilterProvider));
});

final invoiceDetailProvider = FutureProvider.family<InvoiceDetail, int>((
  ref,
  invoiceId,
) {
  // Re-read when the register changes, so a payment or a cancellation shows
  // up without the dialog being reopened.
  ref.watch(invoicesProvider);
  return ref.watch(invoiceQueryRepositoryProvider).invoiceDetail(invoiceId);
});

/// Posted deliveries with no invoice against them: revenue waiting to be
/// recognised.
final unbilledDeliveriesProvider = StreamProvider<List<UnbilledDelivery>>((
  ref,
) {
  return ref.watch(invoiceQueryRepositoryProvider).watchUnbilledDeliveries();
});

final invoiceTotalsProvider = FutureProvider<InvoiceTotalsSnapshot>((
  ref,
) async {
  ref.watch(invoicesProvider);
  return ref
      .watch(invoiceQueryRepositoryProvider)
      .totals(ref.watch(invoiceFilterProvider));
});

/// The business's own details, as they print on a document.
final businessIdentityProvider = FutureProvider<BusinessIdentity>((ref) {
  return ref.watch(settingsServiceProvider).businessIdentity();
});

/// Renders printable documents.
///
/// Built without a folder to save into: the PDF is produced in memory and
/// handed to the print dialog, which is the one thing a browser, a phone and
/// a desktop all have.
final documentPdfServiceProvider = FutureProvider<DocumentPdfService>((
  ref,
) async {
  return DocumentPdfService(
    business: await ref.watch(businessIdentityProvider.future),
  );
});
