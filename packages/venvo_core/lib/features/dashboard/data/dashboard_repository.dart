import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/services/clock.dart';
import '../../../core/utils/money.dart';
import '../domain/dashboard_snapshot.dart';

/// Reads the dashboard figures.
///
/// Written as explicit SQL rather than through the query builder because these
/// are aggregate reports over several tables, and the SQL states the business
/// definition of each number plainly - in particular which rows count as
/// settled money.
///
/// Dates are stored as ISO-8601 UTC text, so a day range is a plain string
/// comparison, which lets SQLite use the date indexes.
class DashboardRepository {
  const DashboardRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  Future<DashboardSnapshot> load() async {
    final now = _clock.nowUtc();
    final dayStart = _clock.startOfLocalDay(now);
    final dayEnd = _clock.endOfLocalDay(now);
    final local = now.toLocal();
    final monthStart = DateTime(local.year, local.month).toUtc();
    final monthEnd = DateTime(
      local.year,
      local.month + 1,
    ).subtract(const Duration(milliseconds: 1)).toUtc();

    final posted = InvoiceStatus.posted.name;
    final cleared = PaymentStatus.cleared.name;

    // --- Sales -----------------------------------------------------------
    final todaysSales = await _money(
      '''
      SELECT COALESCE(SUM(net_total_cents), 0) AS v
      FROM invoices
      WHERE status = ? AND invoice_date BETWEEN ? AND ?
    ''',
      [posted, _iso(dayStart), _iso(dayEnd)],
    );

    final monthSales = await _money(
      '''
      SELECT COALESCE(SUM(net_total_cents), 0) AS v
      FROM invoices
      WHERE status = ? AND invoice_date BETWEEN ? AND ?
    ''',
      [posted, _iso(monthStart), _iso(monthEnd)],
    );

    final monthGrossProfit = await _money(
      '''
      SELECT COALESCE(SUM(net_total_cents - cost_total_cents), 0) AS v
      FROM invoices
      WHERE status = ? AND invoice_date BETWEEN ? AND ?
    ''',
      [posted, _iso(monthStart), _iso(monthEnd)],
    );

    // --- Collections ------------------------------------------------------
    // Only cleared inbound money. A pending cheque is excluded on purpose.
    final todaysCollections = await _money(
      '''
      SELECT COALESCE(SUM(amount_cents), 0) AS v
      FROM payments
      WHERE direction = ? AND status = ? AND payment_date BETWEEN ? AND ?
    ''',
      [PaymentDirection.inbound.name, cleared, _iso(dayStart), _iso(dayEnd)],
    );

    // --- Receivables ------------------------------------------------------
    // Billed, less what cleared payments settled, less applied credit notes,
    // plus balances carried in from before the system went live.
    final agentReceivable = await _receivable(
      partyType: PartyType.agent,
      postedStatus: posted,
      clearedStatus: cleared,
    );
    final shopReceivable = await _receivable(
      partyType: PartyType.shop,
      postedStatus: posted,
      clearedStatus: cleared,
    );

    final unallocated = await _money(
      '''
      SELECT COALESCE(SUM(amount_cents - allocated_cents), 0) AS v
      FROM payments
      WHERE direction = ? AND status = ? AND amount_cents > allocated_cents
    ''',
      [PaymentDirection.inbound.name, cleared],
    );

    // --- Stock value ------------------------------------------------------
    // Valued at the weighted average cost held on each balance row.
    final warehouseValue = await _stockValue(LocationKind.warehouse);
    final agentValue = await _stockValue(LocationKind.agent);
    final shopValue = await _stockValue(LocationKind.shop);
    final damagedValue = await _stockValue(LocationKind.damaged);

    // --- Cheques ----------------------------------------------------------
    final chequeRow = await _row(
      '''
      SELECT COALESCE(SUM(p.amount_cents), 0) AS total, COUNT(*) AS count
      FROM cheques c
      JOIN payments p ON p.id = c.payment_id
      WHERE c.status IN (?, ?) AND p.status = ?
    ''',
      [
        ChequeStatus.pending.name,
        ChequeStatus.deposited.name,
        PaymentStatus.pending.name,
      ],
    );

    // --- Expenses ---------------------------------------------------------
    final todaysExpenses = await _money(
      '''
      SELECT COALESCE(SUM(amount_cents), 0) AS v
      FROM expenses
      WHERE status = ? AND expense_date BETWEEN ? AND ?
    ''',
      [posted, _iso(dayStart), _iso(dayEnd)],
    );

    final monthExpenses = await _money(
      '''
      SELECT COALESCE(SUM(amount_cents), 0) AS v
      FROM expenses
      WHERE status = ? AND expense_date BETWEEN ? AND ?
    ''',
      [posted, _iso(monthStart), _iso(monthEnd)],
    );

    // --- Counts -----------------------------------------------------------
    final lowStock = await _int(
      '''
      SELECT COUNT(*) AS v FROM (
        SELECT p.id
        FROM products p
        LEFT JOIN stock_balances sb ON sb.product_id = p.id
        LEFT JOIN inventory_locations l ON l.id = sb.location_id
              AND l.kind IN (?, ?, ?)
        WHERE p.status = ? AND p.reorder_level > 0
        GROUP BY p.id
        HAVING COALESCE(SUM(CASE WHEN l.id IS NULL THEN 0 ELSE sb.quantity END), 0)
               <= p.reorder_level
      )
    ''',
      [
        LocationKind.warehouse.name,
        LocationKind.agent.name,
        LocationKind.shop.name,
        EntityStatus.active.name,
      ],
    );

    final activeProducts = await _int(
      'SELECT COUNT(*) AS v FROM products WHERE status = ?',
      [EntityStatus.active.name],
    );
    final activeAgents = await _int(
      'SELECT COUNT(*) AS v FROM agents WHERE status = ?',
      [EntityStatus.active.name],
    );
    final activeShops = await _int(
      'SELECT COUNT(*) AS v FROM shops WHERE status = ?',
      [EntityStatus.active.name],
    );

    // --- Returns ----------------------------------------------------------
    // Goods that have left the returning party and have not been inspected:
    // they are not sellable stock and not creditable, so they are a queue
    // somebody has to work through rather than a figure to admire.
    final awaitingRow = await _row(
      '''
      SELECT COUNT(*) AS count, COALESCE(SUM(total_quantity), 0) AS units
      FROM returns WHERE status = ?
    ''',
      [ReturnStatus.posted.name],
    );

    final unappliedCredit = await _money(
      '''
      SELECT COALESCE(SUM(amount_cents - applied_cents), 0) AS v
      FROM credit_notes WHERE status = ?
    ''',
      [posted],
    );

    // --- Petty cash, salaries and advances --------------------------------
    final pettyCash = await _money(
      'SELECT COALESCE(SUM(signed_amount_cents), 0) AS v '
      'FROM petty_cash_entries',
      const [],
    );

    final unpaidSalaries = await _money(
      '''
      SELECT COALESCE(SUM(net_salary_cents - paid_cents), 0) AS v
      FROM salaries
      WHERE status IN (?, ?) AND net_salary_cents > paid_cents
    ''',
      [SalaryStatus.approved.name, SalaryStatus.partiallyPaid.name],
    );

    final employeeAdvances = await _money(
      'SELECT COALESCE(SUM(amount_cents - recovered_cents), 0) AS v '
      'FROM employee_advances',
      const [],
    );

    // --- Retail, kept apart from wholesale --------------------------------
    final monthRetail = await _money(
      '''
      SELECT COALESCE(SUM(net_total_cents), 0) AS v
      FROM invoices
      WHERE status = ? AND kind = ? AND invoice_date BETWEEN ? AND ?
    ''',
      [posted, InvoiceKind.retailSale.name, _iso(monthStart), _iso(monthEnd)],
    );

    // --- Profit, from the journal -----------------------------------------
    // Income accounts are credited by a sale and debited by a discount or a
    // return, so revenue is the negative of their net movement; expenses are
    // the positive of theirs.
    final profitRow = await _row(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN a.type = ?
                     THEN e.credit_cents - e.debit_cents ELSE 0 END), 0)
          AS revenue,
        COALESCE(SUM(CASE WHEN a.type = ?
                     THEN e.debit_cents - e.credit_cents ELSE 0 END), 0)
          AS expenses
      FROM financial_ledger_entries e
      JOIN accounts a ON a.id = e.account_id
      WHERE e.entry_date BETWEEN ? AND ?
    ''',
      [
        AccountType.income.name,
        AccountType.expense.name,
        _iso(monthStart),
        _iso(monthEnd),
      ],
    );

    return DashboardSnapshot(
      generatedAt: now,
      todaysSales: todaysSales,
      todaysCollections: todaysCollections,
      todaysExpenses: todaysExpenses,
      monthSales: monthSales,
      monthExpenses: monthExpenses,
      monthGrossProfit: monthGrossProfit,
      receivableFromAgents: agentReceivable,
      receivableFromShops: shopReceivable,
      warehouseStockValue: warehouseValue,
      agentStockValue: agentValue,
      shopStockValue: shopValue,
      damagedStockValue: damagedValue,
      pendingChequeTotal: Money(_readInt(chequeRow, 'total')),
      pendingChequeCount: _readInt(chequeRow, 'count'),
      lowStockCount: lowStock,
      activeProductCount: activeProducts,
      activeAgentCount: activeAgents,
      activeShopCount: activeShops,
      unallocatedAdvances: unallocated,
      returnsAwaitingInspection: _readInt(awaitingRow, 'count'),
      returnsAwaitingInspectionUnits: _readInt(awaitingRow, 'units'),
      unappliedCreditNotes: unappliedCredit,
      pettyCashFloat: pettyCash,
      unpaidSalaries: unpaidSalaries,
      outstandingEmployeeAdvances: employeeAdvances,
      monthNetProfit:
          Money(_readInt(profitRow, 'revenue')) -
          Money(_readInt(profitRow, 'expenses')),
      monthRetailSales: monthRetail,
    );
  }

  /// Outstanding receivable for one party type.
  ///
  /// Settlement counts only allocations whose payment has cleared, which is
  /// what keeps an uncleared cheque out of the collected figure while still
  /// recording that it was received.
  Future<Money> _receivable({
    required PartyType partyType,
    required String postedStatus,
    required String clearedStatus,
  }) async {
    final billed = await _money(
      '''
      SELECT COALESCE(SUM(net_total_cents), 0) AS v
      FROM invoices
      WHERE status = ? AND party_type = ?
    ''',
      [postedStatus, partyType.name],
    );

    final settled = await _money(
      '''
      SELECT COALESCE(SUM(pa.amount_cents), 0) AS v
      FROM payment_allocations pa
      JOIN payments p ON p.id = pa.payment_id
      JOIN invoices i ON i.id = pa.invoice_id
      WHERE p.status = ? AND i.status = ? AND i.party_type = ?
    ''',
      [clearedStatus, postedStatus, partyType.name],
    );

    final credited = await _money(
      '''
      SELECT COALESCE(SUM(cna.amount_cents), 0) AS v
      FROM credit_note_applications cna
      JOIN credit_notes cn ON cn.id = cna.credit_note_id
      JOIN invoices i ON i.id = cna.invoice_id
      WHERE cn.status = ? AND i.status = ? AND i.party_type = ?
    ''',
      [postedStatus, postedStatus, partyType.name],
    );

    final openingTable = partyType == PartyType.agent ? 'agents' : 'shops';
    final opening = await _money(
      '''
      SELECT COALESCE(SUM(opening_balance_cents), 0) AS v
      FROM $openingTable WHERE status <> ?
    ''',
      [EntityStatus.archived.name],
    );

    return billed + opening - settled - credited;
  }

  Future<Money> _stockValue(LocationKind kind) async {
    return _money(
      '''
      SELECT COALESCE(SUM(sb.quantity * sb.average_cost_cents), 0) AS v
      FROM stock_balances sb
      JOIN inventory_locations l ON l.id = sb.location_id
      WHERE l.kind = ? AND sb.quantity > 0
    ''',
      [kind.name],
    );
  }

  // --- Query helpers ------------------------------------------------------

  Future<QueryRow> _row(String sql, List<Object?> args) async {
    final rows = await _db
        .customSelect(sql, variables: args.map(_variable).toList())
        .get();
    return rows.first;
  }

  Future<Money> _money(String sql, List<Object?> args) async {
    final row = await _row(sql, args);
    return Money(_readInt(row, 'v'));
  }

  Future<int> _int(String sql, List<Object?> args) async {
    final row = await _row(sql, args);
    return _readInt(row, 'v');
  }

  static int _readInt(QueryRow row, String column) {
    final value = row.data[column];
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  static Variable<Object> _variable(Object? value) => switch (value) {
    final String text => Variable<String>(text),
    final int number => Variable<int>(number),
    _ => Variable<String>(value.toString()),
  };

  static String _iso(DateTime value) => value.toUtc().toIso8601String();
}
