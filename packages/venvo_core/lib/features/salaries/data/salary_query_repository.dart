import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/utils/money.dart';
import '../domain/salary_models.dart';

/// Read-only views over salaries and advances.
///
/// A draft salary is listed but is not a liability: every total here counts
/// approved salaries only, which is the same line the employee screen draws.
class SalaryQueryRepository {
  const SalaryQueryRepository(this._db);

  final AppDatabase _db;

  /// The salary register, newest period first.
  Stream<List<SalarySummary>> watchSalaries(SalaryFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT s.*, e.name AS employee_name, e.code AS employee_code,
             e.designation,
             u.full_name AS created_by,
             approver.full_name AS approved_by
      FROM salaries s
      JOIN employees e ON e.id = s.employee_id
      JOIN users u ON u.id = s.created_by_user_id
      LEFT JOIN users approver ON approver.id = s.approved_by_user_id
      WHERE 1 = 1
        AND (? IS NULL OR s.employee_id = ?)
        AND (? IS NULL OR s.period_year = ?)
        AND (? IS NULL OR s.period_month = ?)
        AND (? IS NULL OR s.status = ?)
        AND (? = 0 OR (s.status IN (?, ?)
             AND s.net_salary_cents - s.paid_cents > 0))
        AND (? = '' OR LOWER(s.voucher_number) LIKE ?
             OR LOWER(e.name) LIKE ?
             OR LOWER(e.code) LIKE ?)
      ORDER BY s.period_year DESC, s.period_month DESC, e.name
      LIMIT ?
      ''',
      variables: [
        Variable<int>(filter.employeeId),
        Variable<int>(filter.employeeId),
        Variable<int>(filter.periodYear),
        Variable<int>(filter.periodYear),
        Variable<int>(filter.periodMonth),
        Variable<int>(filter.periodMonth),
        Variable<String>(filter.status?.name),
        Variable<String>(filter.status?.name),
        Variable<int>(filter.unpaidOnly ? 1 : 0),
        Variable<String>(SalaryStatus.approved.name),
        Variable<String>(SalaryStatus.partiallyPaid.name),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {_db.salaries, _db.employees, _db.users},
    );

    return query.watch().map((rows) => rows.map(_map).toList(growable: false));
  }

  /// One salary with its payments, for viewing or printing a slip.
  Future<SalaryDetail> salaryDetail(int salaryId) async {
    final header = requireFound(
      await (_db.select(
        _db.salaries,
      )..where((s) => s.id.equals(salaryId))).getSingleOrNull(),
      'That salary no longer exists.',
    );

    // Voucher numbers are unique, so this reuses the register's own query
    // rather than repeating the joins.
    final summary = (await watchSalaries(
      SalaryFilter(search: header.voucherNumber, limit: 1),
    ).first).single;

    final rows = await _db
        .customSelect(
          '''
      SELECT p.*, u.full_name AS created_by
      FROM salary_payments p
      JOIN users u ON u.id = p.created_by_user_id
      WHERE p.salary_id = ?
      ORDER BY p.payment_date DESC, p.id DESC
      ''',
          variables: [Variable<int>(salaryId)],
          readsFrom: {_db.salaryPayments, _db.users},
        )
        .get();

    final owed = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents - recovered_cents), 0) AS owed '
          'FROM employee_advances WHERE employee_id = ?',
          variables: [Variable<int>(header.employeeId)],
          readsFrom: {_db.employeeAdvances},
        )
        .getSingle();

    return SalaryDetail(
      summary: summary,
      outstandingAdvances: Money(owed.read<int>('owed')),
      payments: rows
          .map(
            (row) => SalaryPaymentRow(
              id: row.read<int>('id'),
              paymentDate: row.read<DateTime>('payment_date'),
              amount: Money(row.read<int>('amount_cents')),
              method: PaymentMethod.values.byName(row.read<String>('method')),
              createdBy: row.read<String>('created_by'),
              referenceNumber: row.readNullable<String>('reference_number'),
              notes: row.readNullable<String>('notes'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Headline figures over the filtered register.
  Future<SalaryTotals> totals(SalaryFilter filter) async {
    final rows = await watchSalaries(filter).first;
    final live = rows.where((row) => row.isApproved).toList();

    return SalaryTotals(
      count: live.length,
      earned: live.map((row) => row.earned).sum,
      advanceRecovered: live.map((row) => row.advanceDeducted).sum,
      net: live.map((row) => row.netSalary).sum,
      paid: live.map((row) => row.paid).sum,
      outstanding: live.map((row) => row.outstanding).sum,
      draftCount: rows.where((row) => row.isDraft).length,
    );
  }

  /// Advances, newest first; by default only the ones still owed.
  Stream<List<EmployeeAdvanceRow>> watchAdvances({
    int? employeeId,
    bool outstandingOnly = true,
  }) {
    final query = _db.customSelect(
      '''
      SELECT a.*, e.name AS employee_name, u.full_name AS created_by
      FROM employee_advances a
      JOIN employees e ON e.id = a.employee_id
      JOIN users u ON u.id = a.created_by_user_id
      WHERE (? IS NULL OR a.employee_id = ?)
        AND (? = 0 OR a.amount_cents - a.recovered_cents > 0)
      ORDER BY a.advance_date DESC, a.id DESC
      ''',
      variables: [
        Variable<int>(employeeId),
        Variable<int>(employeeId),
        Variable<int>(outstandingOnly ? 1 : 0),
      ],
      readsFrom: {_db.employeeAdvances, _db.employees, _db.users},
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => EmployeeAdvanceRow(
              id: row.read<int>('id'),
              employeeId: row.read<int>('employee_id'),
              employeeName: row.read<String>('employee_name'),
              advanceDate: row.read<DateTime>('advance_date'),
              amount: Money(row.read<int>('amount_cents')),
              recovered: Money(row.read<int>('recovered_cents')),
              method: PaymentMethod.values.byName(
                row.read<String>('payment_method'),
              ),
              createdBy: row.read<String>('created_by'),
              notes: row.readNullable<String>('notes'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Periods that already have salaries, newest first, for the period picker.
  Future<List<({int year, int month, int count})>> periods() async {
    final rows = await _db
        .customSelect(
          'SELECT period_year, period_month, COUNT(*) AS count '
          'FROM salaries GROUP BY period_year, period_month '
          'ORDER BY period_year DESC, period_month DESC',
          readsFrom: {_db.salaries},
        )
        .get();

    return rows
        .map(
          (row) => (
            year: row.read<int>('period_year'),
            month: row.read<int>('period_month'),
            count: row.read<int>('count'),
          ),
        )
        .toList(growable: false);
  }

  static SalarySummary _map(QueryRow row) {
    return SalarySummary(
      id: row.read<int>('id'),
      voucherNumber: row.read<String>('voucher_number'),
      employeeId: row.read<int>('employee_id'),
      employeeName: row.read<String>('employee_name'),
      employeeCode: row.read<String>('employee_code'),
      periodYear: row.read<int>('period_year'),
      periodMonth: row.read<int>('period_month'),
      basicSalary: Money(row.read<int>('basic_salary_cents')),
      allowances: Money(row.read<int>('allowances_cents')),
      bonus: Money(row.read<int>('bonus_cents')),
      deductions: Money(row.read<int>('deductions_cents')),
      advanceDeducted: Money(row.read<int>('advance_deducted_cents')),
      netSalary: Money(row.read<int>('net_salary_cents')),
      paid: Money(row.read<int>('paid_cents')),
      status: SalaryStatus.values.byName(row.read<String>('status')),
      createdBy: row.read<String>('created_by'),
      designation: row.readNullable<String>('designation'),
      approvedBy: row.readNullable<String>('approved_by'),
      notes: row.readNullable<String>('notes'),
    );
  }
}
