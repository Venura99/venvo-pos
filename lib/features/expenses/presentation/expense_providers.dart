import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/expenses/api/expense_api.dart';
import 'package:venvo_core/features/expenses/domain/expense_models.dart';

import '../../../core/providers/core_providers.dart';

final expenseServiceProvider = Provider<ExpenseApi>(
  (ref) => ExpenseApi(ref.watch(apiClientProvider)),
);

final expenseQueryRepositoryProvider = Provider<ExpenseQueryApi>(
  (ref) => ExpenseQueryApi(ref.watch(apiClientProvider)),
);

final expenseFilterProvider = StateProvider<ExpenseFilter>(
  (ref) => const ExpenseFilter(),
);

final expensesProvider = StreamProvider<List<ExpenseSummary>>((ref) {
  return ref
      .watch(expenseQueryRepositoryProvider)
      .watchExpenses(ref.watch(expenseFilterProvider));
});

final expenseTotalsProvider = FutureProvider<ExpenseTotals>((ref) {
  ref.watch(expensesProvider);
  return ref
      .watch(expenseQueryRepositoryProvider)
      .totals(ref.watch(expenseFilterProvider));
});

/// Categories a new expense can be booked against.
final expenseCategoriesProvider = StreamProvider<List<ExpenseCategorySummary>>((
  ref,
) {
  return ref.watch(expenseQueryRepositoryProvider).watchCategories();
});

/// Every category, archived ones included, for the maintenance list.
final allExpenseCategoriesProvider =
    StreamProvider<List<ExpenseCategorySummary>>((ref) {
      return ref
          .watch(expenseQueryRepositoryProvider)
          .watchCategories(includeArchived: true);
    });

final dailyExpenseTotalsProvider =
    FutureProvider<List<({DateTime day, Money total, int count})>>((ref) {
      ref.watch(expensesProvider);
      final filter = ref.watch(expenseFilterProvider);
      return ref
          .watch(expenseQueryRepositoryProvider)
          .dailyTotals(from: filter.from, to: filter.to);
    });
