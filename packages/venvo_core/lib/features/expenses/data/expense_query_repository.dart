import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import '../domain/expense_models.dart';

/// Read-only views over expenses.
///
/// Cancelled vouchers are listed but never counted: they stay visible so the
/// trail is intact, and every total here ignores them.
class ExpenseQueryRepository {
  const ExpenseQueryRepository(this._db);

  final AppDatabase _db;

  /// The expense register, newest first.
  Stream<List<ExpenseSummary>> watchExpenses(ExpenseFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT x.*, c.name AS category_name,
             u.full_name AS created_by,
             e.name AS paid_by,
             p.voucher_number AS petty_cash_voucher
      FROM expenses x
      JOIN expense_categories c ON c.id = x.category_id
      JOIN users u ON u.id = x.created_by_user_id
      LEFT JOIN employees e ON e.id = x.paid_by_employee_id
      LEFT JOIN petty_cash_entries p ON p.id = x.petty_cash_entry_id
      WHERE 1 = 1
        AND (? IS NULL OR x.category_id = ?)
        AND (? IS NULL OR x.payment_method = ?)
        AND (? IS NULL OR x.status = ?)
        AND (? IS NULL OR x.expense_date >= ?)
        AND (? IS NULL OR x.expense_date <= ?)
        AND (? = 0 OR x.petty_cash_entry_id IS NOT NULL)
        AND (? = '' OR LOWER(x.description) LIKE ?
             OR LOWER(x.voucher_number) LIKE ?
             OR LOWER(c.name) LIKE ?
             OR LOWER(COALESCE(x.reference_number, '')) LIKE ?)
      ORDER BY x.expense_date DESC, x.id DESC
      LIMIT ?
      ''',
      variables: [
        Variable<int>(filter.categoryId),
        Variable<int>(filter.categoryId),
        Variable<String>(filter.paymentMethod?.name),
        Variable<String>(filter.paymentMethod?.name),
        Variable<String>(filter.status?.name),
        Variable<String>(filter.status?.name),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<int>(filter.pettyCashOnly ? 1 : 0),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {
        _db.expenses,
        _db.expenseCategories,
        _db.users,
        _db.employees,
        _db.pettyCashEntries,
      },
    );

    return query.watch().map((rows) => rows.map(_map).toList(growable: false));
  }

  /// Headline figures plus the per-category breakdown, over the same filter.
  Future<ExpenseTotals> totals(ExpenseFilter filter) async {
    final rows = await watchExpenses(filter).first;
    final live = rows.where((row) => row.isPosted).toList();

    final byCategory = <int, ExpenseCategoryTotal>{};
    for (final expense in live) {
      final existing = byCategory[expense.categoryId];
      byCategory[expense.categoryId] = ExpenseCategoryTotal(
        categoryId: expense.categoryId,
        categoryName: expense.categoryName,
        total: (existing?.total ?? Money.zero) + expense.amount,
        count: (existing?.count ?? 0) + 1,
      );
    }

    final ordered = byCategory.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return ExpenseTotals(
      count: live.length,
      total: live.map((row) => row.amount).sum,
      fromPettyCash: live
          .where((row) => row.fromPettyCash)
          .map((row) => row.amount)
          .sum,
      cancelledCount: rows.where((row) => row.isCancelled).length,
      byCategory: ordered,
    );
  }

  /// Every category, with what has been spent against it.
  Stream<List<ExpenseCategorySummary>> watchCategories({
    bool includeArchived = false,
  }) {
    final query = _db.customSelect(
      '''
      SELECT c.*, a.code AS account_code,
             COALESCE(spend.count, 0) AS expense_count,
             COALESCE(spend.total, 0) AS total
      FROM expense_categories c
      LEFT JOIN accounts a ON a.id = c.account_id
      LEFT JOIN (
        SELECT category_id, COUNT(*) AS count, SUM(amount_cents) AS total
        FROM expenses WHERE status = ?
        GROUP BY category_id
      ) spend ON spend.category_id = c.id
      WHERE (? = 1 OR c.status <> ?)
      ORDER BY c.name
      ''',
      variables: [
        Variable<String>(InvoiceStatus.posted.name),
        Variable<int>(includeArchived ? 1 : 0),
        Variable<String>(EntityStatus.archived.name),
      ],
      readsFrom: {_db.expenseCategories, _db.expenses, _db.accounts},
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ExpenseCategorySummary(
              id: row.read<int>('id'),
              code: row.read<String>('code'),
              name: row.read<String>('name'),
              status: EntityStatus.values.byName(row.read<String>('status')),
              isSystem: row.read<bool>('is_system'),
              expenseCount: row.read<int>('expense_count'),
              total: Money(row.read<int>('total')),
              accountCode: row.readNullable<String>('account_code'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Spend per day over a period, for the daily expense report.
  Future<List<({DateTime day, Money total, int count})>> dailyTotals({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT DATE(expense_date) AS day,
             SUM(amount_cents) AS total,
             COUNT(*) AS count
      FROM expenses
      WHERE status = ?
        AND (? IS NULL OR expense_date >= ?)
        AND (? IS NULL OR expense_date <= ?)
      GROUP BY DATE(expense_date)
      ORDER BY day DESC
      ''',
          variables: [
            Variable<String>(InvoiceStatus.posted.name),
            Variable<String>(_iso(from)),
            Variable<String>(_iso(from)),
            Variable<String>(_iso(to)),
            Variable<String>(_iso(to)),
          ],
          readsFrom: {_db.expenses},
        )
        .get();

    return rows
        .map(
          (row) => (
            day: DateTime.parse(row.read<String>('day')),
            total: Money(row.read<int>('total')),
            count: row.read<int>('count'),
          ),
        )
        .toList(growable: false);
  }

  static ExpenseSummary _map(QueryRow row) {
    return ExpenseSummary(
      id: row.read<int>('id'),
      voucherNumber: row.read<String>('voucher_number'),
      expenseDate: row.read<DateTime>('expense_date'),
      categoryId: row.read<int>('category_id'),
      categoryName: row.read<String>('category_name'),
      description: row.read<String>('description'),
      amount: Money(row.read<int>('amount_cents')),
      paymentMethod: PaymentMethod.values.byName(
        row.read<String>('payment_method'),
      ),
      status: InvoiceStatus.values.byName(row.read<String>('status')),
      createdBy: row.read<String>('created_by'),
      paidByEmployeeName: row.readNullable<String>('paid_by'),
      referenceNumber: row.readNullable<String>('reference_number'),
      pettyCashVoucherNumber: row.readNullable<String>('petty_cash_voucher'),
      notes: row.readNullable<String>('notes'),
      cancelReason: row.readNullable<String>('cancel_reason'),
    );
  }

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}
