import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/invoices/domain/invoice_models.dart';
import 'package:venvo_core/features/returns/api/return_api.dart';
import 'package:venvo_core/features/returns/data/return_query_repository.dart';
import 'package:venvo_core/features/returns/domain/return_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../inventory/presentation/location_providers.dart';
import '../../invoices/presentation/invoice_providers.dart';

final returnServiceProvider = Provider<ReturnApi>(
  (ref) => ReturnApi(ref.watch(apiClientProvider)),
);

final returnQueryRepositoryProvider = Provider<ReturnQueryApi>(
  (ref) => ReturnQueryApi(ref.watch(apiClientProvider)),
);

final returnFilterProvider = StateProvider<ReturnFilter>(
  (ref) => const ReturnFilter(),
);

final returnsProvider = StreamProvider<List<ReturnSummary>>((ref) {
  return ref
      .watch(returnQueryRepositoryProvider)
      .watchReturns(ref.watch(returnFilterProvider));
});

final returnTotalsProvider = FutureProvider<ReturnTotals>((ref) async {
  ref.watch(returnsProvider);
  return ref
      .watch(returnQueryRepositoryProvider)
      .returnTotals(ref.watch(returnFilterProvider));
});

final returnDetailProvider = FutureProvider.family<ReturnDetail, int>((
  ref,
  returnId,
) {
  // Re-read when the register changes, so an inspection or a credit note
  // shows up without the dialog being reopened.
  ref.watch(returnsProvider);
  ref.watch(creditNotesProvider);
  return ref.watch(returnQueryRepositoryProvider).returnDetail(returnId);
});

/// The lines of an invoice with how much of each is still returnable.
final returnableLinesProvider =
    FutureProvider.family<List<ReturnableInvoiceLine>, int>((ref, invoiceId) {
      ref.watch(returnsProvider);
      return ref.watch(returnServiceProvider).returnableLines(invoiceId);
    });

// --- Credit notes ----------------------------------------------------------

final creditNoteFilterProvider = StateProvider<CreditNoteFilter>(
  (ref) => const CreditNoteFilter(),
);

final creditNotesProvider = StreamProvider<List<CreditNoteSummary>>((ref) {
  return ref
      .watch(returnQueryRepositoryProvider)
      .watchCreditNotes(ref.watch(creditNoteFilterProvider));
});

final creditNoteDetailProvider = FutureProvider.family<CreditNoteDetail, int>((
  ref,
  creditNoteId,
) {
  ref.watch(creditNotesProvider);
  return ref
      .watch(returnQueryRepositoryProvider)
      .creditNoteDetail(creditNoteId);
});

/// Unapplied credit held for a party.
final availableCreditProvider = FutureProvider.family<Money, CreditParty>((
  ref,
  party,
) async {
  if (!party.isChosen) return Money.zero;
  ref.watch(creditNotesProvider);
  return ref
      .watch(returnQueryRepositoryProvider)
      .availableCredit(agentId: party.agentId, shopId: party.shopId);
});

/// Which party a credit question is being asked about.
class CreditParty {
  const CreditParty({this.agentId, this.shopId});

  final int? agentId;
  final int? shopId;

  bool get isChosen => agentId != null || shopId != null;

  @override
  bool operator ==(Object other) =>
      other is CreditParty &&
      other.agentId == agentId &&
      other.shopId == shopId;

  @override
  int get hashCode => Object.hash(agentId, shopId);
}

// --- Pickers used by the return form --------------------------------------

/// A well-known virtual location, by its seeded code.
final returnVirtualLocationProvider =
    FutureProvider.family<InventoryLocation, String>((ref, code) {
      return ref.watch(locationRepositoryProvider).byCode(code);
    });

/// Posted invoices for a party, newest first, as candidates for a traced
/// return. Kept apart from the invoice register's own filter so opening this
/// picker does not disturb what the user had on screen there.
final partyInvoicesProvider =
    FutureProvider.family<List<InvoiceSummary>, CreditParty>((
      ref,
      party,
    ) async {
      if (!party.isChosen) return const [];
      // Re-read when a return is posted, so a fully returned invoice drops
      // out of the list.
      ref.watch(returnsProvider);
      return ref
          .watch(invoiceQueryRepositoryProvider)
          .watchInvoices(
            InvoiceFilter(
              agentId: party.agentId,
              shopId: party.shopId,
              status: InvoiceStatus.posted,
              limit: 60,
            ),
          )
          .first;
    });
