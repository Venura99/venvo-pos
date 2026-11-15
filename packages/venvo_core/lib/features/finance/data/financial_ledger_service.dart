import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/sequence_service.dart';
import '../../../core/utils/money.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/finance_models.dart';

/// The double-entry journal behind every figure in the application.
///
/// Invoices, payments, returns, expenses and salaries are each their own
/// record; this is the accounting projection of them. Every business event
/// posts one **batch** whose debits and credits sum to the same total, and
/// [post] refuses a batch that does not balance - so an unbalanced journal is
/// not a thing that can exist, rather than a thing a report has to cope with.
///
/// Why it matters that this is separate from the operational records: it is
/// what stops the same money being counted twice. A cheque receipt debits
/// *Cheques in Clearing*, never *Cash*. Only clearance moves it to the bank.
/// Money received but not yet applied to an invoice sits in *Customer
/// Advances*, a liability, until an allocation moves it to the receivable.
///
/// Rows are append-only. A mistake is corrected with [reverse], which posts
/// the mirror image of a batch, never by editing or deleting what was there.
class FinancialLedgerService {
  FinancialLedgerService({
    required AppDatabase database,
    required Clock clock,
    required SequenceService sequences,
  }) : _db = database,
       _clock = clock,
       _sequences = sequences;

  final AppDatabase _db;
  final Clock _clock;
  final SequenceService _sequences;

  /// Account id per code. The chart of accounts is seeded and system accounts
  /// cannot be removed, so an id is safe to remember for the session.
  final Map<String, int> _accountIds = {};

  // --- Posting ------------------------------------------------------------

  /// Posts one balanced batch and returns its batch reference.
  ///
  /// Call this inside the transaction that writes the record it describes, so
  /// a business event and its accounting either both exist or neither does.
  /// Lines of zero are dropped before balancing, which lets callers hand over
  /// a discount or an advance recovery without first checking whether it
  /// happens to be nil.
  Future<String> post({
    required AuthenticatedUser actor,
    required EntityKind sourceKind,
    required DateTime entryDate,
    required String description,
    required List<JournalLine> lines,
    int? sourceId,
    int? agentId,
    int? shopId,
    String? reversesBatchId,
  }) async {
    final usable = lines
        .where((line) => !line.amount.isZero)
        .toList(growable: false);
    require(
      usable.isNotEmpty,
      'A journal batch needs at least one line with an amount.',
    );
    for (final line in usable) {
      require(
        line.amount.isPositive,
        'A journal line is always a positive amount; which side it lands on '
        'comes from whether it is a debit or a credit.',
      );
    }

    final debits = usable
        .where((line) => line.isDebit)
        .map((line) => line.amount)
        .sum;
    final credits = usable
        .where((line) => !line.isDebit)
        .map((line) => line.amount)
        .sum;
    requireRule(
      debits == credits,
      'This posting does not balance: debits ${debits.formatted()} against '
      'credits ${credits.formatted()}. ($description)',
      rule: 'finance.batch_must_balance',
    );

    final batchId = await _sequences.nextNumber(
      SequenceKeys.journalBatch,
      prefixOverride: SequenceKeys.journalBatch,
    );
    final now = _clock.nowUtc();

    for (final line in usable) {
      await _db
          .into(_db.financialLedgerEntries)
          .insert(
            FinancialLedgerEntriesCompanion.insert(
              batchId: batchId,
              accountId: await _accountId(line.accountCode),
              entryDate: entryDate,
              debitCents: Value(line.isDebit ? line.amount.cents : 0),
              creditCents: Value(line.isDebit ? 0 : line.amount.cents),
              sourceKind: sourceKind,
              sourceId: Value(sourceId),
              description: line.description ?? description,
              agentId: Value(line.agentId ?? agentId),
              shopId: Value(line.shopId ?? shopId),
              createdByUserId: actor.id,
              createdAt: now,
              reversesBatchId: Value(reversesBatchId),
            ),
          );
    }

    return batchId;
  }

  /// Posts the mirror image of an existing batch.
  ///
  /// Used when the event behind a posting is undone - an invoice cancelled, a
  /// cheque bounced, an expense withdrawn. The original rows stay exactly as
  /// they were, which is what keeps the journal auditable.
  Future<String> reverse({
    required AuthenticatedUser actor,
    required String batchId,
    required String reason,
    DateTime? entryDate,
  }) async {
    final rows = await (_db.select(
      _db.financialLedgerEntries,
    )..where((row) => row.batchId.equals(batchId))).get();
    requireFound(
      rows.isEmpty ? null : rows,
      'There is no journal batch "$batchId" to reverse.',
    );

    // A reversal has as many rows as the batch it mirrors, so this is a
    // list read rather than a single-row one.
    final already = await (_db.select(
      _db.financialLedgerEntries,
    )..where((row) => row.reversesBatchId.equals(batchId))).get();
    requireRule(
      already.isEmpty,
      'Journal batch $batchId has already been reversed.',
      rule: 'finance.reverse_once',
    );

    final first = rows.first;
    return post(
      actor: actor,
      sourceKind: first.sourceKind,
      sourceId: first.sourceId,
      entryDate: entryDate ?? _clock.nowUtc(),
      description: 'Reversal of $batchId: $reason',
      reversesBatchId: batchId,
      lines: [
        for (final row in rows)
          JournalLine(
            accountCode: await _accountCode(row.accountId),
            amount: Money(
              row.debitCents != 0 ? row.debitCents : row.creditCents,
            ),
            // Debits become credits and the other way about.
            isDebit: row.debitCents == 0,
            description: 'Reversal: ${row.description}',
            agentId: row.agentId,
            shopId: row.shopId,
          ),
      ],
    );
  }

  // --- Named postings -----------------------------------------------------
  //
  // One method per business event, so the accounts an event touches are
  // decided in one place rather than at each call site.

  /// Revenue and the cost of what was sold, when an invoice is posted.
  Future<String> postInvoice({
    required AuthenticatedUser actor,
    required int invoiceId,
    required String invoiceNumber,
    required InvoiceKind kind,
    required DateTime invoiceDate,
    required Money gross,
    required Money discount,
    required Money net,
    required Money cost,
    int? agentId,
    int? shopId,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.invoice,
      sourceId: invoiceId,
      entryDate: invoiceDate,
      description: 'Invoice $invoiceNumber',
      agentId: agentId,
      shopId: shopId,
      lines: [
        // What the party owes, at the discounted price.
        JournalLine.debit(_receivableFor(kind), net),
        // Revenue at the full price, with the discount shown as its own
        // contra-revenue line rather than hidden inside a smaller sale.
        JournalLine.credit(AccountCodes.salesRevenue, gross),
        JournalLine.debit(AccountCodes.salesDiscounts, discount),
        // The goods leave inventory and become an expense of this sale.
        JournalLine.debit(AccountCodes.costOfGoodsSold, cost),
        JournalLine.credit(AccountCodes.inventory, cost),
      ],
    );
  }

  /// Money in. Nothing touches a receivable yet: an unapplied receipt is a
  /// liability, because the business owes the party either goods or a refund
  /// until the money is pointed at an invoice.
  Future<String> postPaymentReceived({
    required AuthenticatedUser actor,
    required int paymentId,
    required String receiptNumber,
    required DateTime paymentDate,
    required Money amount,
    required PaymentMethod method,
    required bool isCleared,
    int? agentId,
    int? shopId,
  }) {
    final asset = isCleared
        ? _cashAccountFor(method)
        // A cheque in hand is not cash and not in the bank.
        : AccountCodes.chequesInClearing;

    return post(
      actor: actor,
      sourceKind: EntityKind.payment,
      sourceId: paymentId,
      entryDate: paymentDate,
      description: 'Receipt $receiptNumber',
      agentId: agentId,
      shopId: shopId,
      lines: [
        JournalLine.debit(asset, amount),
        JournalLine.credit(AccountCodes.customerAdvances, amount),
      ],
    );
  }

  /// A cheque clears: it stops being paper in a drawer and becomes bank money.
  Future<String> postChequeCleared({
    required AuthenticatedUser actor,
    required int paymentId,
    required String chequeNumber,
    required DateTime clearedOn,
    required Money amount,
    int? agentId,
    int? shopId,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.cheque,
      sourceId: paymentId,
      entryDate: clearedOn,
      description: 'Cheque $chequeNumber cleared',
      agentId: agentId,
      shopId: shopId,
      lines: [
        JournalLine.debit(AccountCodes.bank, amount),
        JournalLine.credit(AccountCodes.chequesInClearing, amount),
      ],
    );
  }

  /// A cheque bounces: the paper was worth nothing, so the receipt it
  /// represented is taken back out again.
  Future<String> postChequeBounced({
    required AuthenticatedUser actor,
    required int paymentId,
    required String chequeNumber,
    required DateTime bouncedOn,
    required Money amount,

    /// True when the cheque had already been cleared, so the money is being
    /// taken back out of the bank rather than out of clearing. Crediting the
    /// wrong one would leave clearing negative and the bank overstated.
    required bool wasCleared,
    Money charges = Money.zero,
    int? agentId,
    int? shopId,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.cheque,
      sourceId: paymentId,
      entryDate: bouncedOn,
      description: 'Cheque $chequeNumber bounced',
      agentId: agentId,
      shopId: shopId,
      lines: [
        JournalLine.debit(AccountCodes.customerAdvances, amount),
        JournalLine.credit(
          wasCleared ? AccountCodes.bank : AccountCodes.chequesInClearing,
          amount,
        ),
        // Any bank charge is the business's expense, paid out of the bank.
        JournalLine.debit(AccountCodes.chequeBounceCharges, charges),
        JournalLine.credit(AccountCodes.bank, charges),
      ],
    );
  }

  /// Money held for a party is applied to what they owe.
  Future<String> postAllocation({
    required AuthenticatedUser actor,
    required int paymentId,
    required String receiptNumber,
    required String invoiceNumber,
    required InvoiceKind invoiceKind,
    required DateTime entryDate,
    required Money amount,
    bool isWithdrawal = false,
    int? agentId,
    int? shopId,
  }) {
    const advance = AccountCodes.customerAdvances;
    final receivable = _receivableFor(invoiceKind);

    return post(
      actor: actor,
      sourceKind: EntityKind.payment,
      sourceId: paymentId,
      entryDate: entryDate,
      description: isWithdrawal
          ? 'Withdrew $receiptNumber from $invoiceNumber'
          : 'Applied $receiptNumber to $invoiceNumber',
      agentId: agentId,
      shopId: shopId,
      lines: isWithdrawal
          ? [
              JournalLine.debit(receivable, amount),
              JournalLine.credit(advance, amount),
            ]
          : [
              JournalLine.debit(advance, amount),
              JournalLine.credit(receivable, amount),
            ],
    );
  }

  /// A credit note is issued: a sales return, held to the party's account
  /// until it is applied to an invoice.
  Future<String> postCreditNoteIssued({
    required AuthenticatedUser actor,
    required int creditNoteId,
    required String creditNoteNumber,
    required DateTime issueDate,
    required Money amount,
    int? agentId,
    int? shopId,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.creditNote,
      sourceId: creditNoteId,
      entryDate: issueDate,
      description: 'Credit note $creditNoteNumber',
      agentId: agentId,
      shopId: shopId,
      lines: [
        JournalLine.debit(AccountCodes.salesReturns, amount),
        JournalLine.credit(AccountCodes.customerAdvances, amount),
      ],
    );
  }

  /// Credit is set against an invoice, or taken back off one.
  Future<String> postCreditApplied({
    required AuthenticatedUser actor,
    required int creditNoteId,
    required String creditNoteNumber,
    required String invoiceNumber,
    required InvoiceKind invoiceKind,
    required DateTime entryDate,
    required Money amount,
    bool isWithdrawal = false,
    int? agentId,
    int? shopId,
  }) {
    const advance = AccountCodes.customerAdvances;
    final receivable = _receivableFor(invoiceKind);

    return post(
      actor: actor,
      sourceKind: EntityKind.creditNote,
      sourceId: creditNoteId,
      entryDate: entryDate,
      description: isWithdrawal
          ? 'Withdrew $creditNoteNumber from $invoiceNumber'
          : 'Applied $creditNoteNumber to $invoiceNumber',
      agentId: agentId,
      shopId: shopId,
      lines: isWithdrawal
          ? [
              JournalLine.debit(receivable, amount),
              JournalLine.credit(advance, amount),
            ]
          : [
              JournalLine.debit(advance, amount),
              JournalLine.credit(receivable, amount),
            ],
    );
  }

  /// Goods arrive from a supplier, or leave as a write-off.
  Future<String> postStockMovement({
    required AuthenticatedUser actor,
    required int transactionId,
    required String documentNumber,
    required StockDocumentType documentType,
    required DateTime documentDate,
    required Money cost,
  }) {
    final (debit, credit) = switch (documentType) {
      // Opening stock is the owner putting goods into the business.
      StockDocumentType.openingStock => (
        AccountCodes.inventory,
        AccountCodes.ownersEquity,
      ),
      StockDocumentType.purchaseIn => (
        AccountCodes.inventory,
        AccountCodes.payableSuppliers,
      ),
      // Damaged, scrapped or counted short: inventory is worth less than it
      // was, and the difference is a loss.
      StockDocumentType.damageWriteOff ||
      StockDocumentType.adjustmentDecrease => (
        AccountCodes.stockWriteOff,
        AccountCodes.inventory,
      ),
      // Found in a count: inventory is worth more than the books said.
      StockDocumentType.adjustmentIncrease ||
      StockDocumentType.reconciliation => (
        AccountCodes.inventory,
        AccountCodes.stockWriteOff,
      ),
      // Moving your own goods between your own locations changes nothing in
      // the accounts, and selling them is accounted for by the invoice.
      _ => (null, null),
    };

    if (debit == null || credit == null || cost.isZero) {
      return Future.value('');
    }

    return post(
      actor: actor,
      sourceKind: EntityKind.stockDocument,
      sourceId: transactionId,
      entryDate: documentDate,
      description: '$documentNumber (${documentType.name})',
      lines: [JournalLine.debit(debit, cost), JournalLine.credit(credit, cost)],
    );
  }

  /// An expense is incurred and settled.
  Future<String> postExpense({
    required AuthenticatedUser actor,
    required int expenseId,
    required String voucherNumber,
    required DateTime expenseDate,
    required Money amount,
    required PaymentMethod method,
    String? expenseAccountCode,
    bool fromPettyCash = false,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.expense,
      sourceId: expenseId,
      entryDate: expenseDate,
      description: 'Expense $voucherNumber',
      lines: [
        JournalLine.debit(
          expenseAccountCode ?? AccountCodes.operatingExpenses,
          amount,
        ),
        JournalLine.credit(
          fromPettyCash ? AccountCodes.pettyCash : _cashAccountFor(method),
          amount,
        ),
      ],
    );
  }

  /// Cash moves between the main cash box and the petty cash float. Nothing is
  /// earned or spent here, so both sides are assets.
  Future<String> postPettyCashTransfer({
    required AuthenticatedUser actor,
    required int entryId,
    required String voucherNumber,
    required DateTime entryDate,
    required Money amount,
    required bool intoFloat,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.pettyCashEntry,
      sourceId: entryId,
      entryDate: entryDate,
      description: 'Petty cash $voucherNumber',
      lines: intoFloat
          ? [
              JournalLine.debit(AccountCodes.pettyCash, amount),
              JournalLine.credit(AccountCodes.cashOnHand, amount),
            ]
          : [
              JournalLine.debit(AccountCodes.cashOnHand, amount),
              JournalLine.credit(AccountCodes.pettyCash, amount),
            ],
    );
  }

  /// A correction to the float that is not a transfer: cash counted short or
  /// over. The difference is a loss or a gain, not a movement.
  Future<String> postPettyCashAdjustment({
    required AuthenticatedUser actor,
    required int entryId,
    required String voucherNumber,
    required DateTime entryDate,
    required Money amount,
    required bool isIncrease,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.pettyCashEntry,
      sourceId: entryId,
      entryDate: entryDate,
      description: 'Petty cash adjustment $voucherNumber',
      lines: isIncrease
          ? [
              JournalLine.debit(AccountCodes.pettyCash, amount),
              JournalLine.credit(AccountCodes.operatingExpenses, amount),
            ]
          : [
              JournalLine.debit(AccountCodes.operatingExpenses, amount),
              JournalLine.credit(AccountCodes.pettyCash, amount),
            ],
    );
  }

  /// An advance paid to an employee. It is an asset - money the employee owes
  /// back - not an expense, which is why paying it does not hit the salary
  /// line and recovering it later does not reduce wages twice.
  Future<String> postEmployeeAdvance({
    required AuthenticatedUser actor,
    required int advanceId,
    required DateTime advanceDate,
    required Money amount,
    required PaymentMethod method,
    required String employeeName,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.employeeAdvance,
      sourceId: advanceId,
      entryDate: advanceDate,
      description: 'Advance to $employeeName',
      lines: [
        JournalLine.debit(AccountCodes.receivableEmployees, amount),
        JournalLine.credit(_cashAccountFor(method), amount),
      ],
    );
  }

  /// A salary is approved: the wage becomes an expense and a debt to the
  /// employee, less whatever advance it recovers.
  Future<String> postSalaryApproved({
    required AuthenticatedUser actor,
    required int salaryId,
    required String voucherNumber,
    required DateTime entryDate,
    required Money earned,
    required Money advanceRecovered,
    required Money net,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.salary,
      sourceId: salaryId,
      entryDate: entryDate,
      description: 'Salary $voucherNumber',
      lines: [
        JournalLine.debit(AccountCodes.salaryExpense, earned),
        JournalLine.credit(AccountCodes.salariesPayable, net),
        // The advance is settled by deduction rather than repaid in cash.
        JournalLine.credit(AccountCodes.receivableEmployees, advanceRecovered),
      ],
    );
  }

  /// A salary, or part of one, is actually handed over.
  Future<String> postSalaryPaid({
    required AuthenticatedUser actor,
    required int salaryId,
    required String voucherNumber,
    required DateTime paymentDate,
    required Money amount,
    required PaymentMethod method,
  }) {
    return post(
      actor: actor,
      sourceKind: EntityKind.salaryPayment,
      sourceId: salaryId,
      entryDate: paymentDate,
      description: 'Salary payment $voucherNumber',
      lines: [
        JournalLine.debit(AccountCodes.salariesPayable, amount),
        JournalLine.credit(_cashAccountFor(method), amount),
      ],
    );
  }

  // --- Reading ------------------------------------------------------------

  /// Net movement on one account over a period. Debits positive.
  Future<Money> balanceOf(String accountCode, {DateTime? from, DateTime? to}) {
    return _netOf(
      'a.code = ?',
      [Variable<String>(accountCode)],
      from: from,
      to: to,
    );
  }

  /// Every account with a non-zero balance, which is the trial balance: the
  /// debit column and the credit column must come to the same total.
  Future<TrialBalance> trialBalance({DateTime? from, DateTime? to}) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT a.code, a.name, a.type,
             COALESCE(SUM(e.debit_cents), 0) AS debits,
             COALESCE(SUM(e.credit_cents), 0) AS credits
      FROM accounts a
      LEFT JOIN financial_ledger_entries e ON e.account_id = a.id
        AND (? IS NULL OR e.entry_date >= ?)
        AND (? IS NULL OR e.entry_date <= ?)
      GROUP BY a.id
      HAVING debits <> 0 OR credits <> 0
      ORDER BY a.code
      ''',
          variables: _periodVariables(from, to),
          readsFrom: {_db.accounts, _db.financialLedgerEntries},
        )
        .get();

    return TrialBalance(
      from: from,
      to: to,
      rows: rows
          .map(
            (row) => TrialBalanceRow(
              accountCode: row.read<String>('code'),
              accountName: row.read<String>('name'),
              accountType: AccountType.values.byName(row.read<String>('type')),
              debits: Money(row.read<int>('debits')),
              credits: Money(row.read<int>('credits')),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Profit and loss for a period, built from the journal rather than from the
  /// operational tables, so it agrees with the trial balance by construction.
  Future<ProfitAndLoss> profitAndLoss({DateTime? from, DateTime? to}) async {
    final balance = await trialBalance(from: from, to: to);

    Money netOf(AccountType type) {
      final rows = balance.rows.where((row) => row.accountType == type);
      return rows.map((row) => row.debits - row.credits).sum;
    }

    // Income accounts are credited by a sale and debited by a discount or a
    // return, so the natural balance is negative and revenue is its mirror.
    final revenue = -netOf(AccountType.income);
    final expenses = netOf(AccountType.expense);

    Money account(String code) {
      final row = balance.rows
          .where((row) => row.accountCode == code)
          .firstOrNull;
      return row == null ? Money.zero : row.debits - row.credits;
    }

    return ProfitAndLoss(
      from: from,
      to: to,
      grossSales: -account(AccountCodes.salesRevenue),
      discounts: account(AccountCodes.salesDiscounts),
      returns: account(AccountCodes.salesReturns),
      costOfGoodsSold: account(AccountCodes.costOfGoodsSold),
      operatingExpenses: account(AccountCodes.operatingExpenses),
      salaryExpense: account(AccountCodes.salaryExpense),
      stockWriteOff: account(AccountCodes.stockWriteOff),
      otherExpenses:
          expenses -
          account(AccountCodes.costOfGoodsSold) -
          account(AccountCodes.operatingExpenses) -
          account(AccountCodes.salaryExpense) -
          account(AccountCodes.stockWriteOff),
      revenue: revenue,
      expenses: expenses,
    );
  }

  /// The journal itself, newest first.
  Stream<List<JournalRow>> watchEntries(FinancialLedgerFilter filter) {
    final search = filter.search.trim().toLowerCase();
    final pattern = '%$search%';

    final query = _db.customSelect(
      '''
      SELECT e.*, a.code AS account_code, a.name AS account_name,
             a.type AS account_type, u.full_name AS created_by
      FROM financial_ledger_entries e
      JOIN accounts a ON a.id = e.account_id
      JOIN users u ON u.id = e.created_by_user_id
      WHERE 1 = 1
        AND (? IS NULL OR a.code = ?)
        AND (? IS NULL OR e.source_kind = ?)
        AND (? IS NULL OR e.entry_date >= ?)
        AND (? IS NULL OR e.entry_date <= ?)
        AND (? = '' OR LOWER(e.description) LIKE ?
             OR LOWER(e.batch_id) LIKE ?
             OR LOWER(a.name) LIKE ?)
      ORDER BY e.entry_date DESC, e.batch_id DESC, e.id
      LIMIT ?
      ''',
      variables: [
        Variable<String>(filter.accountCode),
        Variable<String>(filter.accountCode),
        Variable<String>(filter.sourceKind?.name),
        Variable<String>(filter.sourceKind?.name),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.from)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(_iso(filter.to)),
        Variable<String>(search),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<String>(pattern),
        Variable<int>(filter.limit),
      ],
      readsFrom: {_db.financialLedgerEntries, _db.accounts, _db.users},
    );

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => JournalRow(
              id: row.read<int>('id'),
              batchId: row.read<String>('batch_id'),
              entryDate: row.read<DateTime>('entry_date'),
              accountCode: row.read<String>('account_code'),
              accountName: row.read<String>('account_name'),
              accountType: AccountType.values.byName(
                row.read<String>('account_type'),
              ),
              debit: Money(row.read<int>('debit_cents')),
              credit: Money(row.read<int>('credit_cents')),
              sourceKind: EntityKind.values.byName(
                row.read<String>('source_kind'),
              ),
              sourceId: row.readNullable<int>('source_id'),
              description: row.read<String>('description'),
              createdBy: row.read<String>('created_by'),
              reversesBatchId: row.readNullable<String>('reverses_batch_id'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Batches whose debits and credits disagree.
  ///
  /// [post] makes this impossible, so a non-empty result means something wrote
  /// to the table without going through this service. It is checked by a test
  /// and surfaced on the ledger screen rather than trusted silently.
  Future<List<UnbalancedBatch>> findUnbalancedBatches() async {
    final rows = await _db
        .customSelect(
          '''
      SELECT batch_id,
             SUM(debit_cents) AS debits,
             SUM(credit_cents) AS credits
      FROM financial_ledger_entries
      GROUP BY batch_id
      HAVING SUM(debit_cents) <> SUM(credit_cents)
      ''',
          readsFrom: {_db.financialLedgerEntries},
        )
        .get();

    return rows
        .map(
          (row) => UnbalancedBatch(
            batchId: row.read<String>('batch_id'),
            debits: Money(row.read<int>('debits')),
            credits: Money(row.read<int>('credits')),
          ),
        )
        .toList(growable: false);
  }

  /// Journal batches raised by one record, for tracing a figure back.
  Future<List<JournalRow>> entriesForSource({
    required EntityKind sourceKind,
    required int sourceId,
  }) {
    return watchEntries(
      FinancialLedgerFilter(sourceKind: sourceKind, limit: 200),
    ).first.then(
      (rows) =>
          rows.where((row) => row.sourceId == sourceId).toList(growable: false),
    );
  }

  // --- Internals ----------------------------------------------------------

  Future<Money> _netOf(
    String where,
    List<Variable<Object>> whereVariables, {
    DateTime? from,
    DateTime? to,
  }) async {
    final row = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(e.debit_cents - e.credit_cents), 0) AS net
      FROM financial_ledger_entries e
      JOIN accounts a ON a.id = e.account_id
      WHERE $where
        AND (? IS NULL OR e.entry_date >= ?)
        AND (? IS NULL OR e.entry_date <= ?)
      ''',
          variables: [
            ...whereVariables,
            Variable<String>(_iso(from)),
            Variable<String>(_iso(from)),
            Variable<String>(_iso(to)),
            Variable<String>(_iso(to)),
          ],
          readsFrom: {_db.financialLedgerEntries, _db.accounts},
        )
        .getSingle();
    return Money(row.read<int>('net'));
  }

  List<Variable<Object>> _periodVariables(DateTime? from, DateTime? to) => [
    Variable<String>(_iso(from)),
    Variable<String>(_iso(from)),
    Variable<String>(_iso(to)),
    Variable<String>(_iso(to)),
  ];

  Future<int> _accountId(String code) async {
    final cached = _accountIds[code];
    if (cached != null) return cached;

    final row = await (_db.select(
      _db.accounts,
    )..where((a) => a.code.equals(code))).getSingleOrNull();
    final account = requireFound(
      row,
      'Account "$code" is missing from the chart of accounts.',
    );
    _accountIds[code] = account.id;
    return account.id;
  }

  Future<String> _accountCode(int id) async {
    final row = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    return requireFound(row, 'That account no longer exists.').code;
  }

  /// Which receivable an invoice lands on. Retail sales have their own, so a
  /// shop's wholesale debt is never mixed up with what its walk-in customers
  /// owe - the same separation the sales reports keep.
  static String _receivableFor(InvoiceKind kind) => switch (kind) {
    InvoiceKind.agentInvoice => AccountCodes.receivableAgents,
    InvoiceKind.shopInvoice => AccountCodes.receivableShops,
    InvoiceKind.retailSale => AccountCodes.receivableRetail,
  };

  static String _cashAccountFor(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => AccountCodes.cashOnHand,
    PaymentMethod.bankTransfer ||
    PaymentMethod.cardOrDigital ||
    PaymentMethod.cheque => AccountCodes.bank,
    PaymentMethod.creditNote => AccountCodes.customerAdvances,
    PaymentMethod.openingBalance => AccountCodes.ownersEquity,
  };

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();
}
