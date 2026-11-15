import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/payments/api/payment_api.dart';
import 'package:venvo_core/features/payments/data/payment_query_repository.dart';
import 'package:venvo_core/features/payments/domain/payment_models.dart';

import '../../../core/providers/core_providers.dart';

final paymentServiceProvider = Provider<PaymentApi>(
  (ref) => PaymentApi(ref.watch(apiClientProvider)),
);

final paymentQueryRepositoryProvider = Provider<PaymentQueryApi>(
  (ref) => PaymentQueryApi(ref.watch(apiClientProvider)),
);

// --- Payment register ------------------------------------------------------

final paymentFilterProvider = StateProvider<PaymentFilter>(
  (ref) => const PaymentFilter(),
);

final paymentsProvider = StreamProvider<List<PaymentSummary>>((ref) {
  return ref
      .watch(paymentQueryRepositoryProvider)
      .watchPayments(ref.watch(paymentFilterProvider));
});

final paymentTotalsProvider = FutureProvider<PaymentTotalsSnapshot>((
  ref,
) async {
  ref.watch(paymentsProvider);
  return ref
      .watch(paymentQueryRepositoryProvider)
      .paymentTotals(ref.watch(paymentFilterProvider));
});

// --- Cheque register -------------------------------------------------------

final chequeFilterProvider = StateProvider<ChequeFilter>(
  (ref) => const ChequeFilter(),
);

final chequesProvider = StreamProvider<List<ChequeSummary>>((ref) {
  return ref
      .watch(paymentQueryRepositoryProvider)
      .watchCheques(ref.watch(chequeFilterProvider));
});

final chequeTotalsProvider = FutureProvider<ChequeTotalsSnapshot>((ref) async {
  ref.watch(chequesProvider);
  return ref
      .watch(paymentQueryRepositoryProvider)
      .chequeTotals(ref.watch(chequeFilterProvider));
});

/// Which party a payment is being recorded against, so the allocation picker
/// knows whose invoices to offer.
/// Used as a provider family key, so it compares by value: without this,
/// every rebuild would create a fresh provider and re-run the query.
class PaymentPartySelection {
  const PaymentPartySelection({this.agentId, this.shopId});

  final int? agentId;
  final int? shopId;

  bool get isChosen => agentId != null || shopId != null;

  @override
  bool operator ==(Object other) =>
      other is PaymentPartySelection &&
      other.agentId == agentId &&
      other.shopId == shopId;

  @override
  int get hashCode => Object.hash(agentId, shopId);
}

/// Invoices the chosen party can still have money applied to.
final allocatableInvoicesProvider =
    FutureProvider.family<List<AllocatableInvoice>, PaymentPartySelection>((
      ref,
      selection,
    ) async {
      if (!selection.isChosen) return const [];
      // Re-read when payments change, so allocating one payment updates what is
      // left on the others.
      ref.watch(paymentsProvider);
      return ref
          .watch(paymentServiceProvider)
          .allocatableInvoices(
            agentId: selection.agentId,
            shopId: selection.shopId,
          );
    });

/// Unapplied money held for the chosen party.
final advanceBalanceProvider =
    FutureProvider.family<Money?, PaymentPartySelection>((
      ref,
      selection,
    ) async {
      if (!selection.isChosen) return null;
      ref.watch(paymentsProvider);
      return ref
          .watch(paymentServiceProvider)
          .advanceBalance(agentId: selection.agentId, shopId: selection.shopId);
    });
