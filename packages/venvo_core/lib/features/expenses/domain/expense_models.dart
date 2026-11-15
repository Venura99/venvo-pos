import '../../../core/enums/app_enums.dart';
import '../../../core/utils/money.dart';
import 'package:json_annotation/json_annotation.dart';

part 'expense_models.g.dart';

/// An expense being recorded.
@JsonSerializable()
class ExpenseDraft {
  const ExpenseDraft({
    required this.categoryId,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    this.id,
    this.expenseDate,
    this.paidByEmployeeId,
    this.referenceNumber,
    this.fromPettyCash = false,
    this.notes,
  });

  final int? id;
  final int categoryId;
  final String description;
  final Money amount;
  final PaymentMethod paymentMethod;
  final DateTime? expenseDate;

  /// Who physically spent the money, when somebody did.
  final int? paidByEmployeeId;

  final String? referenceNumber;

  /// Settled out of the petty cash float rather than from the cash box or the
  /// bank. The float is reduced by one linked entry, so the cash movement is
  /// recorded once and not twice.
  final bool fromPettyCash;

  final String? notes;

  factory ExpenseDraft.fromJson(Map<String, dynamic> json) =>
      _$ExpenseDraftFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseDraftToJson(this);
}

/// An expense as the register lists it.
@JsonSerializable()
class ExpenseSummary {
  const ExpenseSummary({
    required this.id,
    required this.voucherNumber,
    required this.expenseDate,
    required this.categoryId,
    required this.categoryName,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.createdBy,
    this.paidByEmployeeName,
    this.referenceNumber,
    this.pettyCashVoucherNumber,
    this.notes,
    this.cancelReason,
  });

  final int id;
  final String voucherNumber;
  final DateTime expenseDate;
  final int categoryId;
  final String categoryName;
  final String description;
  final Money amount;
  final PaymentMethod paymentMethod;
  final InvoiceStatus status;
  final String createdBy;
  final String? paidByEmployeeName;
  final String? referenceNumber;

  /// Set when the money came out of the petty cash float.
  final String? pettyCashVoucherNumber;

  final String? notes;
  final String? cancelReason;

  bool get isPosted => status == InvoiceStatus.posted;
  bool get isCancelled => status == InvoiceStatus.cancelled;
  bool get fromPettyCash => pettyCashVoucherNumber != null;
  bool get canBeCancelled => isPosted;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) =>
      _$ExpenseSummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseSummaryToJson(this);
}

/// One expense category, with what has been spent against it.
@JsonSerializable()
class ExpenseCategorySummary {
  const ExpenseCategorySummary({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.isSystem,
    required this.expenseCount,
    required this.total,
    this.accountCode,
  });

  final int id;
  final String code;
  final String name;
  final EntityStatus status;
  final bool isSystem;
  final int expenseCount;
  final Money total;

  /// The expense account this category posts against. Null falls back to
  /// Operating Expenses.
  final String? accountCode;

  bool get isArchived => status == EntityStatus.archived;
  bool get isInUse => expenseCount > 0;

  factory ExpenseCategorySummary.fromJson(Map<String, dynamic> json) =>
      _$ExpenseCategorySummaryFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseCategorySummaryToJson(this);
}

/// Spend in one category over the filtered period, for the breakdown.
@JsonSerializable()
class ExpenseCategoryTotal {
  const ExpenseCategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.total,
    required this.count,
  });

  final int categoryId;
  final String categoryName;
  final Money total;
  final int count;

  /// Share of the period's total spend, in basis points.
  int shareOf(Money periodTotal) => total.bpsOf(periodTotal);

  factory ExpenseCategoryTotal.fromJson(Map<String, dynamic> json) =>
      _$ExpenseCategoryTotalFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseCategoryTotalToJson(this);
}

/// Headline figures over the expense register.
@JsonSerializable()
class ExpenseTotals {
  const ExpenseTotals({
    required this.count,
    required this.total,
    required this.fromPettyCash,
    required this.cancelledCount,
    required this.byCategory,
  });

  static const ExpenseTotals empty = ExpenseTotals(
    count: 0,
    total: Money.zero,
    fromPettyCash: Money.zero,
    cancelledCount: 0,
    byCategory: [],
  );

  final int count;
  final Money total;
  final Money fromPettyCash;
  final int cancelledCount;
  final List<ExpenseCategoryTotal> byCategory;

  factory ExpenseTotals.fromJson(Map<String, dynamic> json) =>
      _$ExpenseTotalsFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseTotalsToJson(this);
}

/// How the expense register is narrowed.
@JsonSerializable()
class ExpenseFilter {
  const ExpenseFilter({
    this.search = '',
    this.categoryId,
    this.paymentMethod,
    this.status,
    this.pettyCashOnly = false,
    this.from,
    this.to,
    this.limit = 300,
  });

  final String search;
  final int? categoryId;
  final PaymentMethod? paymentMethod;
  final InvoiceStatus? status;
  final bool pettyCashOnly;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  bool get hasAnyFilter =>
      search.trim().isNotEmpty ||
      categoryId != null ||
      paymentMethod != null ||
      status != null ||
      pettyCashOnly ||
      from != null ||
      to != null;

  ExpenseFilter copyWith({
    String? search,
    int? categoryId,
    bool clearCategory = false,
    PaymentMethod? paymentMethod,
    bool clearMethod = false,
    InvoiceStatus? status,
    bool clearStatus = false,
    bool? pettyCashOnly,
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    int? limit,
  }) {
    return ExpenseFilter(
      search: search ?? this.search,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      paymentMethod: clearMethod ? null : (paymentMethod ?? this.paymentMethod),
      status: clearStatus ? null : (status ?? this.status),
      pettyCashOnly: pettyCashOnly ?? this.pettyCashOnly,
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      limit: limit ?? this.limit,
    );
  }

  factory ExpenseFilter.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFilterFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseFilterToJson(this);
}
