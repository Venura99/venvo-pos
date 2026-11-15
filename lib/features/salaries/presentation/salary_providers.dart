import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/salaries/api/salary_api.dart';
import 'package:venvo_core/features/salaries/domain/salary_models.dart';

import '../../../core/providers/core_providers.dart';

final salaryServiceProvider = Provider<SalaryApi>(
  (ref) => SalaryApi(ref.watch(apiClientProvider)),
);

final salaryQueryRepositoryProvider = Provider<SalaryQueryApi>(
  (ref) => SalaryQueryApi(ref.watch(apiClientProvider)),
);

final salaryFilterProvider = StateProvider<SalaryFilter>(
  (ref) => const SalaryFilter(),
);

final salariesProvider = StreamProvider<List<SalarySummary>>((ref) {
  return ref
      .watch(salaryQueryRepositoryProvider)
      .watchSalaries(ref.watch(salaryFilterProvider));
});

final salaryTotalsProvider = FutureProvider<SalaryTotals>((ref) {
  ref.watch(salariesProvider);
  return ref
      .watch(salaryQueryRepositoryProvider)
      .totals(ref.watch(salaryFilterProvider));
});

final salaryDetailProvider = FutureProvider.family<SalaryDetail, int>((
  ref,
  salaryId,
) {
  // Re-read when the register changes, so approving or paying shows up
  // without the dialog being reopened.
  ref.watch(salariesProvider);
  return ref.watch(salaryQueryRepositoryProvider).salaryDetail(salaryId);
});

/// Advances still owed, across everybody or for one employee.
final outstandingAdvancesProvider =
    StreamProvider.family<List<EmployeeAdvanceRow>, int?>((ref, employeeId) {
      return ref
          .watch(salaryQueryRepositoryProvider)
          .watchAdvances(employeeId: employeeId);
    });

/// What one employee owes, for the salary form's live computation.
final employeeAdvanceBalanceProvider = FutureProvider.family<Money, int>((
  ref,
  employeeId,
) {
  ref.watch(outstandingAdvancesProvider(employeeId));
  ref.watch(salariesProvider);
  return ref.watch(salaryServiceProvider).outstandingAdvances(employeeId);
});

/// Periods that already have salaries, for the period picker.
final salaryPeriodsProvider =
    FutureProvider<List<({int year, int month, int count})>>((ref) {
      ref.watch(salariesProvider);
      return ref.watch(salaryQueryRepositoryProvider).periods();
    });
