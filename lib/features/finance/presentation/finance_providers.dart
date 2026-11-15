import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/features/finance/api/finance_api.dart';
import 'package:venvo_core/features/finance/domain/finance_models.dart';

import '../../../core/providers/core_providers.dart';

/// The journal. Shared by every service that posts to it, so the account-id
/// cache is built once per session rather than per posting.
final financialLedgerServiceProvider = Provider<FinanceApi>(
  (ref) => FinanceApi(ref.watch(apiClientProvider)),
);

final financialLedgerFilterProvider = StateProvider<FinancialLedgerFilter>(
  (ref) => const FinancialLedgerFilter(),
);

final journalProvider = StreamProvider<List<JournalRow>>((ref) {
  return ref
      .watch(financialLedgerServiceProvider)
      .watchEntries(ref.watch(financialLedgerFilterProvider));
});

/// The reporting period the ledger screen is looking at.
class FinancePeriod {
  const FinancePeriod({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      other is FinancePeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

final financePeriodProvider = StateProvider<FinancePeriod>(
  (ref) => const FinancePeriod(),
);

final trialBalanceProvider = FutureProvider<TrialBalance>((ref) {
  // Re-read whenever anything is posted, which the journal stream reflects.
  ref.watch(journalProvider);
  final period = ref.watch(financePeriodProvider);
  return ref
      .watch(financialLedgerServiceProvider)
      .trialBalance(from: period.from, to: period.to);
});

final profitAndLossProvider = FutureProvider<ProfitAndLoss>((ref) {
  ref.watch(journalProvider);
  final period = ref.watch(financePeriodProvider);
  return ref
      .watch(financialLedgerServiceProvider)
      .profitAndLoss(from: period.from, to: period.to);
});

/// Batches whose two sides disagree. Always empty unless something wrote to
/// the journal without going through the service, and surfaced rather than
/// assumed.
final unbalancedBatchesProvider = FutureProvider<List<UnbalancedBatch>>((ref) {
  ref.watch(journalProvider);
  return ref.watch(financialLedgerServiceProvider).findUnbalancedBatches();
});
