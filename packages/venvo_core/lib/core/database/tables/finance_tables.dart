import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import 'master_tables.dart';
import 'payment_tables.dart';
import 'system_tables.dart';

/// Expenses, petty cash, salaries and the financial ledger.
///
/// [FinancialLedgerEntries] is a conventional double-entry journal: every
/// business event posts a *batch* of entries whose debits and credits sum to
/// zero. This is what prevents the same money being counted twice - a cheque
/// receipt, for example, debits `Cheques in Clearing` rather than `Cash`, and
/// only clearance moves it to the bank. Stock movements, invoices and payments
/// remain their own records; the ledger is the accounting projection of them,
/// linked by [FinancialLedgerEntries.sourceKind] and `sourceId`.

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Stable numeric code, see `AccountCodes`.
  TextColumn get code => text().withLength(min: 1, max: 16)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get type => textEnum<AccountType>()();

  /// System accounts are seeded and referenced by posting logic; they cannot
  /// be removed.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get description => text().nullable().withLength(max: 300)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
  ];
}

/// Append-only double-entry journal. Rows are never updated or deleted; a
/// mistake is corrected with a reversing batch.
@DataClassName('FinancialLedgerEntry')
@TableIndex(
  name: 'idx_fin_ledger_account_date',
  columns: {#accountId, #entryDate},
)
@TableIndex(name: 'idx_fin_ledger_batch', columns: {#batchId})
@TableIndex(name: 'idx_fin_ledger_source', columns: {#sourceKind, #sourceId})
class FinancialLedgerEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Groups the entries of one balanced posting. Debits and credits within a
  /// batch always sum to the same total.
  TextColumn get batchId => text().withLength(min: 1, max: 40)();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get entryDate => dateTime()();

  /// Exactly one of these is non-zero on any given row.
  IntColumn get debitCents => integer().withDefault(const Constant(0))();
  IntColumn get creditCents => integer().withDefault(const Constant(0))();

  /// What caused the posting, so the journal can always be traced back to the
  /// invoice, payment or expense that produced it.
  TextColumn get sourceKind => textEnum<EntityKind>()();
  IntColumn get sourceId => integer().nullable()();
  TextColumn get description => text().withLength(max: 300)();

  IntColumn get agentId => integer().nullable().references(
    Agents,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get shopId => integer().nullable().references(
    Shops,
    #id,
    onDelete: KeyAction.restrict,
  )();

  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();

  /// Set on a row that reverses an earlier batch.
  TextColumn get reversesBatchId => text().nullable().withLength(max: 40)();
}

@DataClassName('ExpenseCategory')
class ExpenseCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 24)();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// Expense account the category posts against.
  IntColumn get accountId => integer().nullable().references(
    Accounts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
    {name},
  ];
}

@DataClassName('Expense')
@TableIndex(name: 'idx_expenses_date', columns: {#expenseDate})
@TableIndex(name: 'idx_expenses_category', columns: {#categoryId})
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get voucherNumber => text().withLength(min: 1, max: 32)();
  DateTimeColumn get expenseDate => dateTime()();
  IntColumn get categoryId => integer().references(
    ExpenseCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get description => text().withLength(min: 1, max: 500)();
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();

  /// Employee who physically spent the money, when applicable.
  IntColumn get paidByEmployeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get referenceNumber => text().nullable().withLength(max: 64)();

  /// Set when the expense was settled out of petty cash, linking the two
  /// modules without double counting the cash movement.
  IntColumn get pettyCashEntryId => integer().nullable()();

  /// Set when the expense was paid by a recorded outbound payment.
  IntColumn get paymentId => integer().nullable().references(
    Payments,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get status => textEnum<InvoiceStatus>().withDefault(
    Constant(InvoiceStatus.draft.name),
  )();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get postedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get cancelReason => text().nullable().withLength(max: 500)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {voucherNumber},
  ];
}

/// Petty cash ledger. Each row carries the running balance after it was
/// applied, so the closing balance for any day is a single row read rather
/// than a full replay.
@DataClassName('PettyCashEntry')
@TableIndex(name: 'idx_petty_cash_date', columns: {#entryDate})
class PettyCashEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get voucherNumber => text().withLength(min: 1, max: 32)();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get kind => textEnum<PettyCashEntryKind>()();

  /// Always positive; [kind] determines the sign applied to the balance.
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();

  /// Signed effect on the float, derived from [kind] at insert time and kept
  /// so sums need no CASE expression.
  IntColumn get signedAmountCents => integer()();

  /// Float balance immediately after this entry.
  IntColumn get balanceAfterCents => integer()();

  TextColumn get description => text().withLength(min: 1, max: 500)();
  TextColumn get referenceNumber => text().nullable().withLength(max: 64)();
  IntColumn get expenseId => integer().nullable().references(
    Expenses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get handledByEmployeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {voucherNumber},
  ];
}

/// A cash advance given to an employee, recovered from later salaries.
@DataClassName('EmployeeAdvance')
@TableIndex(name: 'idx_advances_employee', columns: {#employeeId})
class EmployeeAdvances extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId =>
      integer().references(Employees, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get advanceDate => dateTime()();
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();

  /// Amount already deducted from salaries.
  IntColumn get recoveredCents => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => textEnum<PaymentMethod>()();
  IntColumn get paymentId => integer().nullable().references(
    Payments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get notes => text().nullable().withLength(max: 500)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
}

/// One salary computation per employee per month.
@DataClassName('Salary')
@TableIndex(name: 'idx_salaries_period', columns: {#periodYear, #periodMonth})
@TableIndex(name: 'idx_salaries_employee', columns: {#employeeId})
class Salaries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get voucherNumber => text().withLength(min: 1, max: 32)();
  IntColumn get employeeId =>
      integer().references(Employees, #id, onDelete: KeyAction.restrict)();
  IntColumn get periodYear => integer()();
  IntColumn get periodMonth => integer()();

  IntColumn get basicSalaryCents => integer().withDefault(const Constant(0))();
  IntColumn get allowancesCents => integer().withDefault(const Constant(0))();
  IntColumn get bonusCents => integer().withDefault(const Constant(0))();
  IntColumn get deductionsCents => integer().withDefault(const Constant(0))();

  /// Portion of outstanding advances recovered in this period.
  IntColumn get advanceDeductedCents =>
      integer().withDefault(const Constant(0))();

  /// `basic + allowances + bonus - deductions - advanceDeducted`.
  IntColumn get netSalaryCents => integer().withDefault(const Constant(0))();

  /// Cache of the sum of [SalaryPayments] for this salary.
  IntColumn get paidCents => integer().withDefault(const Constant(0))();

  TextColumn get status =>
      textEnum<SalaryStatus>().withDefault(Constant(SalaryStatus.draft.name))();
  TextColumn get notes => text().nullable().withLength(max: 1000)();
  IntColumn get approvedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {voucherNumber},
    {employeeId, periodYear, periodMonth},
  ];
}

/// Supports partial salary settlement: several payments against one salary,
/// with the outstanding balance derived from the difference.
@DataClassName('SalaryPayment')
@TableIndex(name: 'idx_salary_payments_salary', columns: {#salaryId})
class SalaryPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get salaryId =>
      integer().references(Salaries, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get paymentDate => dateTime()();
  IntColumn get amountCents =>
      integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get method => textEnum<PaymentMethod>()();
  TextColumn get referenceNumber => text().nullable().withLength(max: 64)();

  /// The outbound payment row, so salary cash shows up in the cash ledger
  /// exactly once.
  IntColumn get paymentId => integer().nullable().references(
    Payments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get notes => text().nullable().withLength(max: 500)();
  IntColumn get createdByUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime()();
}
