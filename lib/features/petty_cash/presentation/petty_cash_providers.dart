import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/petty_cash/api/petty_cash_api.dart';
import 'package:venvo_core/features/petty_cash/domain/petty_cash_models.dart';

import '../../../core/providers/core_providers.dart';

final pettyCashServiceProvider = Provider<PettyCashApi>(
  (ref) => PettyCashApi(ref.watch(apiClientProvider)),
);

final pettyCashFilterProvider = StateProvider<PettyCashFilter>(
  (ref) => const PettyCashFilter(),
);

final pettyCashEntriesProvider = StreamProvider<List<PettyCashRow>>((ref) {
  return ref
      .watch(pettyCashServiceProvider)
      .watchEntries(ref.watch(pettyCashFilterProvider));
});

final pettyCashSnapshotProvider = FutureProvider<PettyCashSnapshot>((ref) {
  ref.watch(pettyCashEntriesProvider);
  return ref
      .watch(pettyCashServiceProvider)
      .snapshot(ref.watch(pettyCashFilterProvider));
});

/// The float as it stands, independent of whatever period is being viewed.
final pettyCashBalanceProvider = FutureProvider<Money>((ref) {
  ref.watch(pettyCashEntriesProvider);
  return ref.watch(pettyCashServiceProvider).floatBalance();
});

/// Rows whose stored running balance disagrees with a replay of the book.
/// Always empty; surfaced rather than assumed.
final pettyCashDiscrepanciesProvider =
    FutureProvider<
      List<({String voucherNumber, Money stored, Money replayed})>
    >((ref) {
      ref.watch(pettyCashEntriesProvider);
      return ref.watch(pettyCashServiceProvider).findBalanceDiscrepancies();
    });
