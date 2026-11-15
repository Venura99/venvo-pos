import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'finance_models.g.dart';

/// One side of one journal line.
///
/// The amount is always positive; [isDebit] decides which column it lands in.
/// Letting a line carry a negative amount would mean the same posting could be
/// written two ways, and a trial balance that nets to zero would no longer
/// prove anything.
@JsonSerializable()
class JournalLine {
  const JournalLine({
    required this.accountCode,
    required this.amount,
    required this.isDebit,
    this.description,
    this.agentId,
    this.shopId,
  });

  const JournalLine.debit(
    this.accountCode,
    this.amount, {
    this.description,
    this.agentId,
    this.shopId,
  }) : isDebit = true;

  const JournalLine.credit(
    this.accountCode,
    this.amount, {
    this.description,
    this.agentId,
    this.shopId,
  }) : isDebit = false;

  final String accountCode;
  final Money amount;
  final bool isDebit;

  /// Overrides the batch description for this line alone.
  final String? description;

  final int? agentId;
  final int? shopId;

  factory JournalLine.fromJson(Map<String, dynamic> json) =>
      _$JournalLineFromJson(json);

  Map<String, dynamic> toJson() => _$JournalLineToJson(this);
}

/// One row of the journal, as the ledger screen shows it.
@JsonSerializable()
class JournalRow {
  const JournalRow({
    required this.id,
    required this.batchId,
    required this.entryDate,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.debit,
    required this.credit,
    required this.sourceKind,
    required this.description,
    required this.createdBy,
    this.sourceId,
    this.reversesBatchId,
  });

  final int id;
  final String batchId;
  final DateTime entryDate;
  final String accountCode;
  final String accountName;
  final AccountType accountType;
  final Money debit;
  final Money credit;

  /// What caused the posting, so any figure can be traced back to the
  /// invoice, payment, expense or salary behind it.
  final EntityKind sourceKind;
  final int? sourceId;

  final String description;
  final String createdBy;
  final String? reversesBatchId;

  bool get isReversal => reversesBatchId != null;

  /// Signed movement, debits positive.
  Money get net => debit - credit;

  factory JournalRow.fromJson(Map<String, dynamic> json) =>
      _$JournalRowFromJson(json);

  Map<String, dynamic> toJson() => _$JournalRowToJson(this);
}

/// One account's totals over a period.
@JsonSerializable()
class TrialBalanceRow {
  const TrialBalanceRow({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.debits,
    required this.credits,
  });

  final String accountCode;
  final String accountName;
  final AccountType accountType;
  final Money debits;
  final Money credits;

  /// Debits positive. An asset or expense is normally positive, a liability,
  /// equity or income account normally negative.
  Money get net => debits - credits;

  /// The balance as an accountant would read it: positive on the side the
  /// account naturally sits.
  Money get naturalBalance => switch (accountType) {
    AccountType.asset || AccountType.expense => net,
    AccountType.liability || AccountType.equity || AccountType.income => -net,
  };

  factory TrialBalanceRow.fromJson(Map<String, dynamic> json) =>
      _$TrialBalanceRowFromJson(json);

  Map<String, dynamic> toJson() => _$TrialBalanceRowToJson(this);
}

/// The trial balance. Its two columns agreeing is the proof that every
/// posting balanced.
@JsonSerializable()
class TrialBalance {
  const TrialBalance({required this.rows, this.from, this.to});

  static const TrialBalance empty = TrialBalance(rows: []);

  final List<TrialBalanceRow> rows;
  final DateTime? from;
  final DateTime? to;

  Money get totalDebits => rows.map((row) => row.debits).sum;
  Money get totalCredits => rows.map((row) => row.credits).sum;

  bool get isBalanced => totalDebits == totalCredits;

  List<TrialBalanceRow> ofType(AccountType type) =>
      rows.where((row) => row.accountType == type).toList(growable: false);

  factory TrialBalance.fromJson(Map<String, dynamic> json) =>
      _$TrialBalanceFromJson(json);

  Map<String, dynamic> toJson() => _$TrialBalanceToJson(this);
}

/// Profit and loss for a period, read from the journal.
@JsonSerializable()
class ProfitAndLoss {
  const ProfitAndLoss({
    required this.grossSales,
    required this.discounts,
    required this.returns,
    required this.costOfGoodsSold,
    required this.operatingExpenses,
    required this.salaryExpense,
    required this.stockWriteOff,
    required this.otherExpenses,
    required this.revenue,
    required this.expenses,
    this.from,
    this.to,
  });

  static const ProfitAndLoss empty = ProfitAndLoss(
    grossSales: Money.zero,
    discounts: Money.zero,
    returns: Money.zero,
    costOfGoodsSold: Money.zero,
    operatingExpenses: Money.zero,
    salaryExpense: Money.zero,
    stockWriteOff: Money.zero,
    otherExpenses: Money.zero,
    revenue: Money.zero,
    expenses: Money.zero,
  );

  /// Sales at the full price, before any discount.
  final Money grossSales;

  /// Discounts given, which reduce revenue.
  final Money discounts;

  /// Credit notes raised for goods that came back.
  final Money returns;

  final Money costOfGoodsSold;
  final Money operatingExpenses;
  final Money salaryExpense;
  final Money stockWriteOff;
  final Money otherExpenses;

  /// `grossSales - discounts - returns`.
  final Money revenue;

  /// Every expense account added up.
  final Money expenses;

  final DateTime? from;
  final DateTime? to;

  /// What the business actually earned on the goods, before overheads.
  Money get grossProfit => revenue - costOfGoodsSold;

  Money get overheads => expenses - costOfGoodsSold;

  Money get netProfit => revenue - expenses;

  bool get isProfitable => netProfit.isPositive;

  /// Gross profit as a share of revenue, in basis points.
  int get grossMarginBps => revenue.isZero ? 0 : grossProfit.bpsOf(revenue);

  factory ProfitAndLoss.fromJson(Map<String, dynamic> json) =>
      _$ProfitAndLossFromJson(json);

  Map<String, dynamic> toJson() => _$ProfitAndLossToJson(this);
}

/// A batch whose two sides disagree. Posting makes this impossible, so one of
/// these means something bypassed the service.
@JsonSerializable()
class UnbalancedBatch {
  const UnbalancedBatch({
    required this.batchId,
    required this.debits,
    required this.credits,
  });

  final String batchId;
  final Money debits;
  final Money credits;

  Money get difference => debits - credits;

  factory UnbalancedBatch.fromJson(Map<String, dynamic> json) =>
      _$UnbalancedBatchFromJson(json);

  Map<String, dynamic> toJson() => _$UnbalancedBatchToJson(this);
}

/// How the journal view is narrowed.
@JsonSerializable()
class FinancialLedgerFilter {
  const FinancialLedgerFilter({
    this.search = '',
    this.accountCode,
    this.sourceKind,
    this.from,
    this.to,
    this.limit = 500,
  });

  final String search;
  final String? accountCode;
  final EntityKind? sourceKind;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      accountCode != null ||
      sourceKind != null ||
      from != null ||
      to != null;

  FinancialLedgerFilter copyWith({
    String? search,
    String? accountCode,
    bool clearAccount = false,
    EntityKind? sourceKind,
    bool clearSourceKind = false,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return FinancialLedgerFilter(
      search: search ?? this.search,
      accountCode: clearAccount ? null : (accountCode ?? this.accountCode),
      sourceKind: clearSourceKind ? null : (sourceKind ?? this.sourceKind),
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory FinancialLedgerFilter.fromJson(Map<String, dynamic> json) =>
      _$FinancialLedgerFilterFromJson(json);

  Map<String, dynamic> toJson() => _$FinancialLedgerFilterToJson(this);
}

String accountTypeLabel(AccountType type) => switch (type) {
  AccountType.asset => 'Assets',
  AccountType.liability => 'Liabilities',
  AccountType.equity => 'Equity',
  AccountType.income => 'Income',
  AccountType.expense => 'Expenses',
};

/// What produced a journal row, in words.
String journalSourceLabel(EntityKind kind) => switch (kind) {
  EntityKind.invoice => 'Invoice',
  EntityKind.payment => 'Payment',
  EntityKind.cheque => 'Cheque',
  EntityKind.creditNote => 'Credit note',
  EntityKind.returnDocument => 'Return',
  EntityKind.stockDocument => 'Stock document',
  EntityKind.expense => 'Expense',
  EntityKind.pettyCashEntry => 'Petty cash',
  EntityKind.salary => 'Salary',
  EntityKind.employeeAdvance => 'Employee advance',
  EntityKind.salaryPayment => 'Salary payment',
  _ => kind.name,
};
